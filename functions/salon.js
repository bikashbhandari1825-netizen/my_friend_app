// functions/salon.js
//
// Salon / Beauty Appointment Booking (Booksy-style) — Cloud Functions।
// index.js को अन्त्यबाट `Object.assign(exports, require("./salon"))` ले जोडिन्छ
// (admin.initializeApp() पहिले नै index.js मा भइसकेको हुन्छ)।
//
// चार callable: `salonAvailableSlots` (खाली समय-स्लट गणना), `bookSalonAppointment`
// (Firestore *transaction* भित्र double-booking-रहित लेखाइ), `salonCheckIn`
// (provider ले QR scan गर्दा), `submitSalonReview` (completed बुकिङ भएको
// ग्राहकको मात्र review + rating aggregate)।
//
// किन server-side: (१) बुकिङ-doc client ले सिधै लेख्न नसक्ने (rules मा
// `salon_appointments` create: false) — मूल्य/अवधि/staff/QR-token सबै यहीँ
// service-doc बाट गणना हुन्छ, client ले पठाएको मूल्य कहिल्यै मानिँदैन;
// (२) hotel module मा documented double-booking race (query atomically लक
// नहुने) यहाँ Admin SDK को transaction (pessimistic lock — transaction भित्र
// गरिएको query ले पनि सो range का doc लक गर्छ) ले ठीक गरिएको।
//
// समय: salon को स्थानीय समय (`tzOffsetMin`, Nepal = 345) मा `HH:MM` कामको
// समय र `YYYY-MM-DD` मिति; सबै गणना UTC epoch-ms मा रूपान्तरण गरेर हुन्छ।
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {enforceRateLimit} = require("./ratelimit");
const {ENFORCE_APP_CHECK} = require("./appcheck");
const crypto = require("crypto");

// lib/models/salon_models.dart::SalonAppointmentStatus.active सँग उस्तै।
const SALON_ACTIVE_STATUSES = ["confirmed", "checked_in"];
const SALON_MAX_DAYS_AHEAD = 60;
const SALON_MIN_LEAD_MS = 15 * 60 * 1000;
const SALON_MAX_SERVICES = 8;
const SALON_MAX_ACTIVE_PER_USER = 5;
const DAY_MS = 24 * 3600000;

function parseHm(s) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(s || ""));
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 24 || min > 59 || (h === 24 && min !== 0)) return null;
  return h * 60 + min;
}

// `YYYY-MM-DD` (salon स्थानीय) → {dayStartMs (UTC epoch), weekday 1=सोम…7=आइत}
function salonDay(dateStr, tzOffsetMin) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateStr || ""));
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const utc = Date.UTC(y, mo - 1, d);
  const check = new Date(utc);
  if (check.getUTCFullYear() !== y || check.getUTCMonth() !== mo - 1 ||
      check.getUTCDate() !== d) return null;
  const dow = check.getUTCDay(); // 0=आइत
  return {
    dayStartMs: utc - tzOffsetMin * 60000,
    weekday: dow === 0 ? 7 : dow,
  };
}

function cleanIds(raw) {
  if (!Array.isArray(raw)) return null;
  const ids = [...new Set(raw.filter((x) => typeof x === "string" && x))];
  if (ids.length === 0 || ids.length > SALON_MAX_SERVICES) return null;
  return ids;
}

// service doc हरू पढेर कुल अवधि/मूल्य — सबै active र यही salon का हुनुपर्छ।
// `reader` = `db` वा transaction (दुवैमा `.get(ref)` छ)।
async function loadServices(reader, db, salonId, serviceIds) {
  const refs = serviceIds.map((id) =>
    db.collection("salons").doc(salonId).collection("services").doc(id));
  const snaps = await Promise.all(refs.map((r) => reader.get(r)));
  let durationMin = 0;
  let totalPrice = 0;
  const names = [];
  for (const s of snaps) {
    if (!s.exists || s.get("active") === false) {
      throw new HttpsError("failed-precondition",
          "A selected service is no longer available.");
    }
    durationMin += Number(s.get("durationMin")) || 0;
    totalPrice += Number(s.get("price")) || 0;
    names.push(String(s.get("name") || ""));
  }
  if (durationMin < 5 || durationMin > 600) {
    throw new HttpsError("failed-precondition", "Invalid service duration.");
  }
  return {durationMin, totalPrice, names};
}

async function loadStaff(db, salonId, staffId, serviceIds) {
  const col = db.collection("salons").doc(salonId).collection("staff");
  let docs;
  if (staffId && staffId !== "any") {
    const s = await col.doc(String(staffId)).get();
    docs = s.exists ? [s] : [];
  } else {
    docs = (await col.get()).docs;
  }
  return docs
      .map((d) => ({id: d.id, ...d.data()}))
      .filter((s) => s.active !== false)
      .filter((s) => !Array.isArray(s.serviceIds) || s.serviceIds.length === 0 ||
          serviceIds.every((id) => s.serviceIds.includes(id)));
}

// त्यो दिनका सबै appointment — salonId + startAt range (composite index,
// firestore.indexes.json मा छ)। status filter memory मै गरिन्छ।
function dayQuery(db, salonId, dayStartMs) {
  return db.collection("salon_appointments")
      .where("salonId", "==", salonId)
      .where("startAt", ">=", admin.firestore.Timestamp.fromMillis(dayStartMs))
      .where("startAt", "<",
          admin.firestore.Timestamp.fromMillis(dayStartMs + DAY_MS));
}

// दिइएको दिन/अवधिमा हरेक staff को खाली स्टार्ट-समय — [{startMs, staffIds}]।
function computeSlots({salon, staffList, durationMin, day, appts, nowMs}) {
  const step = Math.max(5, Math.min(120, Number(salon.slotStepMin) || 30));
  const busy = {};
  for (const a of appts) {
    if (!SALON_ACTIVE_STATUSES.includes(a.status)) continue;
    (busy[a.staffId] = busy[a.staffId] || []).push([
      a.startAt.toMillis(), a.endAt.toMillis()]);
  }
  const bySlot = new Map();
  for (const st of staffList) {
    const h = st.hours && st.hours[String(day.weekday)];
    if (!h) continue;
    const open = parseHm(h.open);
    const close = parseHm(h.close);
    if (open === null || close === null || close <= open) continue;
    for (let m = open; m + durationMin <= close; m += step) {
      const s = day.dayStartMs + m * 60000;
      const e = s + durationMin * 60000;
      if (s < nowMs + SALON_MIN_LEAD_MS) continue;
      const clash = (busy[st.id] || []).some(([bs, be]) => s < be && e > bs);
      if (clash) continue;
      if (!bySlot.has(s)) bySlot.set(s, []);
      bySlot.get(s).push(st.id);
    }
  }
  return [...bySlot.entries()].sort((a, b) => a[0] - b[0])
      .map(([startMs, staffIds]) => ({startMs, staffIds}));
}

async function loadSalon(reader, db, salonId) {
  const snap = await reader.get(db.collection("salons").doc(salonId));
  if (!snap.exists || snap.get("status") !== "active") {
    throw new HttpsError("not-found", "This salon is not accepting bookings.");
  }
  return {id: snap.id, ...snap.data()};
}

function validateDay(salon, date, nowMs) {
  const day = salonDay(date, Number(salon.tzOffsetMin) || 345);
  if (!day) throw new HttpsError("invalid-argument", "Invalid date.");
  if (day.dayStartMs + DAY_MS < nowMs ||
      day.dayStartMs > nowMs + SALON_MAX_DAYS_AHEAD * DAY_MS) {
    throw new HttpsError("invalid-argument",
        `Bookings open up to ${SALON_MAX_DAYS_AHEAD} days ahead.`);
  }
  return day;
}

/**
 * Input:  {salonId, date: 'YYYY-MM-DD', serviceIds: [..], staffId: id|'any'}
 * Output: {slots: [{startMs, staffIds: [..]}], durationMin}
 */
exports.salonAvailableSlots = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  await enforceRateLimit(request.auth.uid, "salonAvailableSlots", 60);
  const data = request.data || {};
  const salonId = String(data.salonId || "");
  const serviceIds = cleanIds(data.serviceIds);
  if (!salonId || !serviceIds) {
    throw new HttpsError("invalid-argument", "salonId and serviceIds required.");
  }
  const db = admin.firestore();
  const nowMs = Date.now();
  const salon = await loadSalon(db, db, salonId);
  const day = validateDay(salon, data.date, nowMs);
  const {durationMin} = await loadServices(db, db, salonId, serviceIds);
  const staffList = await loadStaff(db, salonId, data.staffId, serviceIds);
  const apptSnap = await dayQuery(db, salonId, day.dayStartMs).get();
  const slots = computeSlots({
    salon, staffList, durationMin, day, nowMs,
    appts: apptSnap.docs.map((d) => d.data()),
  });
  return {slots, durationMin};
});

/**
 * Input: {salonId, serviceIds, staffId|'any', date, startMs, paymentType,
 *         paymentMethod?, paymentRef?, customerName, customerPhone}
 * Output: {appointmentId}
 *
 * मूल्य/अवधि/staff/QR-token सबै यहीँ बन्छ। Transaction भित्र त्यो दिनका सबै
 * बुकिङ पुनः पढेर (लक सहित) माग गरिएको स्लट अझै खाली छ कि जाँचिन्छ — दुई
 * ग्राहकले एकैचोटि एउटै स्लट थिचे एउटा मात्र सफल हुन्छ, अर्कोले Firestore
 * ले transaction retry गरेपछि `already-exists` पाउँछ।
 */
exports.bookSalonAppointment = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  await enforceRateLimit(request.auth.uid, "bookSalonAppointment", 10);
  const uid = request.auth.uid;
  const data = request.data || {};
  const salonId = String(data.salonId || "");
  const serviceIds = cleanIds(data.serviceIds);
  const startMs = Number(data.startMs);
  const customerName = String(data.customerName || "").trim().slice(0, 80);
  const customerPhone = String(data.customerPhone || "").trim().slice(0, 20);
  const paymentType = String(data.paymentType || "");
  const paymentMethod = String(data.paymentMethod || "");
  const paymentRef = String(data.paymentRef || "").trim().slice(0, 64);
  if (!salonId || !serviceIds || !Number.isFinite(startMs)) {
    throw new HttpsError("invalid-argument", "Missing booking details.");
  }
  if (!customerName || !customerPhone) {
    throw new HttpsError("invalid-argument", "Name and phone are required.");
  }
  if (!["pay_at_salon", "online_paid"].includes(paymentType)) {
    throw new HttpsError("invalid-argument", "Invalid payment type.");
  }
  if (paymentType === "online_paid" &&
      (!["esewa", "khalti", "qr"].includes(paymentMethod) || !paymentRef)) {
    throw new HttpsError("invalid-argument",
        "Enter your payment method and reference for online payment.");
  }
  const db = admin.firestore();

  // Slot-hoarding रोक — एउटै user सँग धेरै आउँदा-बुकिङ नहोस्।
  const mine = await db.collection("salon_appointments")
      .where("userId", "==", uid)
      .where("status", "in", SALON_ACTIVE_STATUSES).get();
  const upcoming = mine.docs.filter(
      (d) => d.get("endAt").toMillis() > Date.now());
  if (upcoming.length >= SALON_MAX_ACTIVE_PER_USER) {
    throw new HttpsError("resource-exhausted",
        `You can hold at most ${SALON_MAX_ACTIVE_PER_USER} upcoming appointments.`);
  }

  const apptRef = db.collection("salon_appointments").doc();
  let ownerId = "";
  let salonName = "";
  try {
    await db.runTransaction(async (tx) => {
      const nowMs = Date.now();
      const salon = await loadSalon(tx, db, salonId);
      if (salon.ownerId === uid) {
        throw new HttpsError("failed-precondition",
            "You cannot book your own salon.");
      }
      const day = validateDay(salon, data.date, nowMs);
      if (startMs < day.dayStartMs || startMs >= day.dayStartMs + DAY_MS) {
        throw new HttpsError("invalid-argument", "Time is outside that date.");
      }
      const {durationMin, totalPrice, names} =
          await loadServices(tx, db, salonId, serviceIds);
      const staffList = await loadStaff(db, salonId, data.staffId, serviceIds);
      // लक सहितको query — यही नै race-fix को मुख्य भाग।
      const apptSnap = await tx.get(dayQuery(db, salonId, day.dayStartMs));
      const appts = apptSnap.docs.map((d) => d.data());
      const slots = computeSlots({
        salon, staffList, durationMin, day, nowMs, appts});
      const slot = slots.find((s) => s.startMs === startMs);
      if (!slot) {
        throw new HttpsError("already-exists",
            "That time was just taken. Please pick another slot.");
      }
      // "Any available" — त्यो दिन सबैभन्दा कम बुकिङ भएको staff छान्ने।
      const load = (id) => appts.filter((a) => a.staffId === id &&
          SALON_ACTIVE_STATUSES.includes(a.status)).length;
      const staffId = [...slot.staffIds].sort((a, b) => load(a) - load(b))[0];
      const staff = staffList.find((s) => s.id === staffId);
      ownerId = salon.ownerId;
      salonName = salon.name;
      tx.set(apptRef, {
        userId: uid,
        salonId,
        ownerId,
        salonName,
        staffId,
        staffName: String(staff.name || ""),
        serviceIds,
        serviceNames: names,
        totalPrice,
        durationMin,
        startAt: admin.firestore.Timestamp.fromMillis(startMs),
        endAt: admin.firestore.Timestamp.fromMillis(
            startMs + durationMin * 60000),
        status: "confirmed",
        paymentType,
        paymentMethod: paymentType === "online_paid" ? paymentMethod : "",
        // declare-your-reference sandbox — साँचो gateway verify होइन; provider
        // ले आफैं "paid" मा बदल्छ।
        paymentRef: paymentType === "online_paid" ? paymentRef : "",
        paymentStatus: paymentType === "online_paid" ? "declared" : "unpaid",
        customerName,
        customerPhone,
        qrToken: crypto.randomBytes(12).toString("hex"),
        reviewed: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("bookSalonAppointment failed:", e);
    throw new HttpsError("internal", "Could not complete the booking.");
  }

  // best-effort — मालिकलाई notification (मौजुदा `notifications` → FCM function)।
  db.collection("notifications").add({
    uid: ownerId,
    title: `New appointment — ${salonName}`,
    body: `${customerName} booked ${serviceIds.length} service(s)`,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }).catch(() => {});
  return {appointmentId: apptRef.id};
});

/**
 * Provider ले ग्राहकको QR scan गर्दा — payload `KAAMMITRA-SALON:<id>:<token>`।
 * Output: बुकिङको सार (provider screen मा देखाउन) + `alreadyCheckedIn`।
 */
exports.salonCheckIn = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  await enforceRateLimit(request.auth.uid, "salonCheckIn", 30);
  const parts = String((request.data || {}).payload || "").split(":");
  if (parts.length !== 3 || parts[0] !== "KAAMMITRA-SALON") {
    throw new HttpsError("invalid-argument", "This is not a salon booking pass.");
  }
  const [, apptId, token] = parts;
  const db = admin.firestore();
  const ref = db.collection("salon_appointments").doc(apptId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found.");
    const a = snap.data();
    if (a.ownerId !== request.auth.uid) {
      throw new HttpsError("permission-denied",
          "This booking belongs to a different salon.");
    }
    const given = Buffer.from(token);
    const real = Buffer.from(String(a.qrToken || ""));
    if (given.length !== real.length || !crypto.timingSafeEqual(given, real)) {
      throw new HttpsError("permission-denied", "Invalid booking pass.");
    }
    if (a.status === "cancelled" || a.status === "no_show") {
      throw new HttpsError("failed-precondition",
          `This booking is ${a.status.replace("_", " ")}.`);
    }
    if (a.status === "completed") {
      throw new HttpsError("failed-precondition",
          "This booking is already completed.");
    }
    const now = Date.now();
    if (now < a.startAt.toMillis() - 2 * 3600000 ||
        now > a.endAt.toMillis() + 6 * 3600000) {
      throw new HttpsError("failed-precondition",
          "This pass is not valid at this time.");
    }
    const already = a.status === "checked_in";
    if (!already) {
      tx.update(ref, {
        status: "checked_in",
        checkedInAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return {
      alreadyCheckedIn: already,
      appointmentId: apptId,
      customerName: a.customerName,
      staffName: a.staffName,
      serviceNames: a.serviceNames,
      startMs: a.startAt.toMillis(),
      totalPrice: a.totalPrice,
      paymentStatus: a.paymentStatus,
      paymentType: a.paymentType,
    };
  });
});

/**
 * Verified review — केवल त्यो बुकिङकै ग्राहक, बुकिङ `completed` भएपछि, एकपटक।
 * Input: {appointmentId, rating (1-5), comment?}
 * review doc id = appointmentId (त्यसैले दोहोरो review असम्भव), र salon को
 * ratingSum/ratingCount यहीँ atomic अपडेट हुन्छ (client ले लेख्न नसक्ने)।
 */
exports.submitSalonReview = onCall({enforceAppCheck: ENFORCE_APP_CHECK}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  await enforceRateLimit(request.auth.uid, "submitSalonReview", 10);
  const data = request.data || {};
  const apptId = String(data.appointmentId || "");
  const rating = Number(data.rating);
  const comment = String(data.comment || "").trim().slice(0, 500);
  if (!apptId || !Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new HttpsError("invalid-argument", "Rating must be 1 to 5.");
  }
  const db = admin.firestore();
  const apptRef = db.collection("salon_appointments").doc(apptId);
  const reviewRef = db.collection("salon_reviews").doc(apptId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(apptRef);
    if (!snap.exists || snap.get("userId") !== request.auth.uid) {
      throw new HttpsError("permission-denied", "This is not your booking.");
    }
    if (snap.get("status") !== "completed") {
      throw new HttpsError("failed-precondition",
          "You can review after the appointment is completed.");
    }
    if (snap.get("reviewed") === true) {
      throw new HttpsError("already-exists", "You already reviewed this visit.");
    }
    const salonRef = db.collection("salons").doc(snap.get("salonId"));
    tx.set(reviewRef, {
      salonId: snap.get("salonId"),
      userId: request.auth.uid,
      reviewerName:
          String(snap.get("customerName") || "Customer").split(" ")[0],
      rating,
      comment,
      serviceNames: snap.get("serviceNames") || [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(apptRef, {reviewed: true});
    tx.update(salonRef, {
      ratingSum: admin.firestore.FieldValue.increment(rating),
      ratingCount: admin.firestore.FieldValue.increment(1),
    });
  });
  return {ok: true};
});
