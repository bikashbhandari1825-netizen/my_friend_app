// functions/rideCode.js
//
// राइड सुरु गर्ने ४-अंकको OTP — अब सर्भरमा मात्र। पहिले कोड `serviceRequests`
// doc मै (`rideStartCode`) बस्थ्यो र नियुक्त driver ले त्यो doc पढ्न पाउँथ्यो,
// त्यसैले driver को एपले आफैं कोड पढेर "मिलाउँथ्यो" — यात्रु नभेटी पनि राइड
// सुरु गर्न सकिन्थ्यो। अब कोड `serviceRequests/{id}/private/startCode` मा
// (rules ले क्लाइन्टलाई पूर्ण बन्द) बस्छ:
//   • `getRideStartCode`   — यात्रु (employer) ले मात्र आफ्नो कोड पाउँछ।
//   • `verifyRideStartCode` — driver ले टाइप गरेको कोड सर्भरले जाँच्छ; मिले
//     मात्र status 'in_progress' + startedAt (सर्भर समय) लेखिन्छ।
// ४-अंक brute-force रोक्न: ५ गलतपछि ५ मिनेट लक।
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");

const {enforceRateLimit} = require("./ratelimit");
const {ENFORCE_APP_CHECK} = require("./appcheck");

const MAX_WRONG = 5;
const LOCK_MS = 5 * 60 * 1000;
const STARTABLE = ["accepted", "confirmed"];

function isRideDoc(r) {
  return r.isRide === true ||
      ["Bike", "Car", "Auto"].includes(String(r.service || ""));
}

function newCode() {
  return String(crypto.randomInt(1000, 10000));
}

function reqIdFrom(data) {
  const id = data && typeof data.requestId === "string" ? data.requestId : "";
  if (!id || id.length > 200) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  return id;
}

// कोड नभए (वा पुरानो राइडमा दस्तावेजमै रहेको legacy कोड) बाट private doc बनाउने।
function ensureCode(tx, privRef, privSnap, r) {
  if (privSnap.exists && /^\d{4}$/.test(String(privSnap.get("code")))) {
    return String(privSnap.get("code"));
  }
  const legacy = String(r.rideStartCode || "");
  const code = /^\d{4}$/.test(legacy) ? legacy : newCode();
  tx.set(privRef, {code, wrong: 0, lockedUntil: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp()});
  return code;
}

exports.getRideStartCode = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = request.auth.uid;
  const requestId = reqIdFrom(request.data);
  await enforceRateLimit(uid, "getRideStartCode", 30);
  const db = admin.firestore();
  const reqRef = db.collection("serviceRequests").doc(requestId);
  const privRef = reqRef.collection("private").doc("startCode");
  const code = await db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) throw new HttpsError("not-found", "No such ride.");
    const r = reqSnap.data();
    if (r.employerUid !== uid) {
      throw new HttpsError("permission-denied", "Only the passenger can see this code.");
    }
    if (!isRideDoc(r) || !STARTABLE.includes(r.status)) {
      throw new HttpsError("failed-precondition", "No start code needed now.");
    }
    return ensureCode(tx, privRef, await tx.get(privRef), r);
  });
  return {code};
});

exports.verifyRideStartCode = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = request.auth.uid;
  const requestId = reqIdFrom(request.data);
  const entered = String((request.data || {}).code || "").trim();
  if (!/^\d{4}$/.test(entered)) {
    throw new HttpsError("invalid-argument", "Enter the 4-digit code.");
  }
  await enforceRateLimit(uid, "verifyRideStartCode", 20);
  const db = admin.firestore();
  const reqRef = db.collection("serviceRequests").doc(requestId);
  const privRef = reqRef.collection("private").doc("startCode");
  return db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) throw new HttpsError("not-found", "No such ride.");
    const r = reqSnap.data();
    if (r.workerUid !== uid) {
      throw new HttpsError("permission-denied", "Only the assigned driver can start this ride.");
    }
    if (!isRideDoc(r) || !STARTABLE.includes(r.status)) {
      throw new HttpsError("failed-precondition", "This ride cannot be started now.");
    }
    const privRef2 = privRef;
    const privSnap = await tx.get(privRef2);
    const now = Date.now();
    const lockedUntil = Number(privSnap.get("lockedUntil")) || 0;
    if (lockedUntil > now) {
      throw new HttpsError("resource-exhausted",
          "Too many wrong codes. Try again in a few minutes.");
    }
    const code = ensureCode(tx, privRef2, privSnap, r);
    const a = Buffer.from(entered);
    const b = Buffer.from(code);
    const match = a.length === b.length && crypto.timingSafeEqual(a, b);
    if (!match) {
      const wrong = (Number(privSnap.get("wrong")) || 0) + 1;
      tx.set(privRef2, {
        code,
        wrong: wrong >= MAX_WRONG ? 0 : wrong,
        lockedUntil: wrong >= MAX_WRONG ? now + LOCK_MS : 0,
      }, {merge: true});
      return {ok: false};
    }
    tx.update(reqRef, {
      status: "in_progress",
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      rideStartCode: admin.firestore.FieldValue.delete(),
    });
    tx.set(privRef2, {wrong: 0, lockedUntil: 0}, {merge: true});
    return {ok: true};
  });
});
