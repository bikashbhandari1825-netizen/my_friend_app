// functions/wallet.js
//
// Server-side job completion — रेटिङ, वालेट/कमिसन र बुकिङ-स्थिति अब ग्राहकको
// फोनले होइन, यही function (Admin SDK, transaction भित्र) ले मात्र लेख्छ।
// पहिले `widget/complete_job_sheet.dart` ले यी सबै क्लाइन्टबाट लेख्थ्यो, र
// firestore.rules ले अर्काको `walletBalance`/`ratingSum` आदि बदल्न दिनुपर्थ्यो —
// परिवर्तित एपले कमिसन शून्य गर्न, रेटिङ बढाउन वा अर्काको वालेट बदल्न सक्थ्यो।
// अब rules ले ती फिल्डमा क्लाइन्टको लेखाइ पूर्ण रूपमा बन्द गर्छ।
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const {enforceRateLimit} = require("./ratelimit");
const {ENFORCE_APP_CHECK} = require("./appcheck");

const ACTIVE = ["accepted", "confirmed", "in_progress"];
// एउटै काम/राइडको अधिकतम रकम र एउटै जोडीबीच दैनिक पूरा-कामको सीमा।
const MAX_JOB_AMOUNT = 200000;
// एउटै जोडीबीच दैनिक कति काम *रेटिङ/काउन्टमा गनिन्छ* (default; admin ले
// `config/limits.maxPairPerDay` बाट बदल्न सक्छ)। यो सीमा नाघेपछि पनि काम
// कहिल्यै रोकिँदैन — भुक्तानी/कमिसन/स्थिति सधैँ पूरा हुन्छ, केवल रेटिङ र
// "पूरा-काम" गन्ती थपिँदैन (रेटिङ-फार्मिङ रोक्न)।
const DEFAULT_MAX_PAIR_PER_DAY = 12;
// यो रकमभन्दा सानो (वा शून्य) कामले रेटिङ/पूरा-काम गन्ती बढाउँदैन।
const MIN_REPUTATION_AMOUNT = 50;

exports.completeJob = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = request.auth.uid;
  const data = request.data || {};
  const requestId = typeof data.requestId === "string" ? data.requestId : "";
  const rating = Number(data.rating);
  const comment = String(data.comment || "").trim().slice(0, 500);
  if (!requestId || requestId.length > 200) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new HttpsError("invalid-argument", "rating must be 1-5.");
  }

  await enforceRateLimit(uid, "completeJob", 20);
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const reqRef = db.collection("serviceRequests").doc(requestId);

  // commission दर/सीमा — config/payments (admin ले मात्र लेख्ने)।
  const payCfg = (await db.collection("config").doc("payments").get()).data() || {};
  const rate = typeof payCfg.commissionRate === "number" ?
    payCfg.commissionRate : 0.10;
  const threshold = typeof payCfg.minimumWalletThreshold === "number" ?
    payCfg.minimumWalletThreshold : 100;
  if (!(rate >= 0 && rate <= 1)) {
    throw new HttpsError("failed-precondition", "Invalid commission config.");
  }

  // रेटिङ-गन्ती सीमा (admin-सम्पादनीय) — नपाए/अमान्य भए default।
  const limCfg = (await db.collection("config").doc("limits").get()).data() || {};
  const maxPair = Number.isInteger(limCfg.maxPairPerDay) &&
      limCfg.maxPairPerDay > 0 ? limCfg.maxPairPerDay :
      DEFAULT_MAX_PAIR_PER_DAY;

  const result = await db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "This booking no longer exists.");
    }
    const r = reqSnap.data();
    if (r.employerUid !== uid) {
      throw new HttpsError("permission-denied",
          "Only the customer can complete this job.");
    }
    const workerUid = r.workerUid;
    if (typeof workerUid !== "string" || !workerUid) {
      throw new HttpsError("failed-precondition", "No worker assigned.");
    }
    if (!ACTIVE.includes(r.status)) {
      throw new HttpsError("failed-precondition",
          "This job is not in progress.");
    }
    // Dual-confirmation (सामान्य काम — Carpenter/Painter/Mechanic आदि, ride
    // होइन): काम सुरु (`in_progress`) भइसकेको र कामदारले "Job Completed"
    // पुष्टि (`workerConfirmedComplete`) गरिसकेको हुनैपर्छ। पहिले यो गेट केवल
    // UI बटनमा थियो (परिवर्तित एपले बाइपास गर्न सक्थ्यो); अब सर्भरले लागू गर्छ।
    const isRide = r.isRide === true ||
        ["Bike", "Car", "Auto"].includes(String(r.service || ""));
    if (!isRide &&
        (r.status !== "in_progress" || r.workerConfirmedComplete !== true)) {
      throw new HttpsError("failed-precondition",
          "The worker must start and confirm the job as complete first.");
    }
    // आफ्नै काममा आफैं ग्राहक र कामदार हुन नपाइने (रेटिङ-फार्मिङ)।
    if (workerUid === uid) {
      throw new HttpsError("failed-precondition",
          "You cannot complete a job assigned to yourself.");
    }
    // एउटै ग्राहक–कामदार जोडीले २४ घण्टामा धेरै "पूरा" काम बनाएर रेटिङ/काउन्ट
    // बढाउन नपाउने — तर वैध काम/भुक्तानी कहिल्यै नरोक्ने: सीमा नाघे काम
    // पूरा हुन्छ, केवल रेटिङ/गन्ती थपिँदैन (तल `countsForReputation`)।
    const pairSnap = await tx.get(db.collection("serviceRequests")
        .where("employerUid", "==", uid).where("workerUid", "==", workerUid));
    const dayAgo = Date.now() - 24 * 3600 * 1000;
    const recent = pairSnap.docs.filter((d) => {
      const c = d.get("completedAt");
      return d.get("status") === "completed" && c && c.toMillis() > dayAgo;
    }).length;
    // (Rs ० / अति-सानो रकमका नक्कली राइडले रेटिङ फुलाउन नपाउने — तल `amount`
    // निर्धारण भएपछि जाँचिन्छ।)
    let countsForReputation = recent < maxPair;
    // कामदारले साँच्चै काम सुरु गरेको प्रमाण (`startedAt` — rules ले कामदारलाई
    // मात्र लेख्न दिन्छ) — नत्र ग्राहक एक्लैले नक्कली काम पूरा गर्न सक्थ्यो।
    if (!r.startedAt) {
      throw new HttpsError("failed-precondition",
          "The worker has not started this job.");
    }
    // रकम सधैँ सर्भरमा भएको मूल्यबाट — क्लाइन्टले पठाएको रकम विश्वास नगर्ने।
    // (rules ले काम सक्रिय भएपछि मूल्य बदल्न दिँदैन।)
    const price = [r.finalPrice, r.agreedAmount, r.employerCounterPrice,
      r.workerCounterPrice, r.proposedPrice]
        .find((v) => typeof v === "number" && v >= 0);
    let amount = typeof price === "number" ? price : 0;
    if (!Number.isFinite(amount) || amount > MAX_JOB_AMOUNT) {
      throw new HttpsError("failed-precondition",
          "This job amount needs admin review.");
    }
    amount = Math.round(amount * 100) / 100;
    // रेटिङ/पूरा-काम गन्ती केवल न्यूनतम रकमभन्दा माथिका कामले मात्र (मुफ्तमा
    // दुई खाताले रेटिङ-फार्मिङ गर्न नपाउने); भुक्तानी/स्थिति सधैं पूरा हुन्छ।
    if (amount < MIN_REPUTATION_AMOUNT) countsForReputation = false;

    const workerRef = db.collection("users").doc(workerUid);
    const workerSnap = await tx.get(workerRef);
    const w = workerSnap.data() || {};
    const owed = amount * rate;
    const currentBalance = typeof w.walletBalance === "number" ?
      w.walletBalance : 0;
    const newBalance = currentBalance - owed;
    const eligible = newBalance > -threshold;

    const employerSnap = await tx.get(db.collection("users").doc(uid));
    const e = employerSnap.data() || {};
    const employerName = String(
        e.name || `${e.firstName || ""} ${e.lastName || ""}`.trim() ||
        "Customer");

    if (countsForReputation) {
      tx.set(db.collection("reviews").doc(), {
        targetUid: workerUid,
        authorUid: uid,
        authorName: employerName,
        rating,
        comment,
        service: String(r.service || ""),
        requestId,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    tx.set(workerRef, {
      ...(countsForReputation ? {
        ratingSum: FieldValue.increment(rating),
        ratingCount: FieldValue.increment(1),
        completedRidesCount: FieldValue.increment(1),
      } : {}),
      walletBalance: FieldValue.increment(-owed),
      isEligibleForJobs: eligible,
      ...(w.activeJobId === requestId ? {activeJobId: FieldValue.delete()} : {}),
    }, {merge: true});
    tx.update(reqRef, {
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      paymentConfirmed: true,
      paymentMethod: "cash",
      paidAmount: amount,
      commissionAmount: 0,
      workerPayoutAmount: amount,
      commissionRate: 0,
      payerWalletId: "",
    });
    tx.set(db.collection("walletLedger").doc(), {
      workerUid,
      requestId,
      type: "cash_commission_due",
      amount: -owed,
      grossAmount: amount,
      commissionAmount: owed,
      workerPayoutAmount: amount - owed,
      commissionRate: rate,
      paymentMethod: "cash",
      payerWalletId: "",
      settled: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {workerUid, amount};
  });

  // registeredWorkers मा देखिने औसत रेटिङ (display copy) पनि ताजा — best-effort।
  try {
    const u = (await db.collection("users").doc(result.workerUid).get()).data() || {};
    const count = Number(u.ratingCount) || 0;
    const avg = count === 0 ? 0 : (Number(u.ratingSum) || 0) / count;
    const rw = await db.collection("registeredWorkers")
        .where("uid", "==", result.workerUid).get();
    const batch = db.batch();
    rw.forEach((d) => batch.update(d.ref, {
      rating: avg.toFixed(1),
      reviews: String(count),
    }));
    await batch.commit();
  } catch (err) {
    console.warn("rating sync failed", err);
  }
  return {ok: true, amount: result.amount};
});
