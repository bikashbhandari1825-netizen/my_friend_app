// functions/ratelimit.js
//
// हरेक user को callable function प्रयोगमा प्रति-मिनेट सीमा (Google Maps बिल
// दुरुपयोग / DoS रोक्न)। Firestore `_rate/{uid}_{name}` मा एउटै doc, transaction
// भित्र गन्ती; rules ले `_rate` क्लाइन्टबाट पूर्ण बन्द (catch-all) राखेको छ,
// Admin SDK मात्र लेख्छ।
const {HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

async function enforceRateLimit(uid, name, maxPerMinute) {
  const db = admin.firestore();
  const ref = db.collection("_rate").doc(`${uid}_${name}`);
  const minute = Math.floor(Date.now() / 60000);
  const allowed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data() || {};
    const count = d.minute === minute ? (d.count || 0) : 0;
    if (count >= maxPerMinute) return false;
    // `expireAt` — Firestore TTL policy (Console → Firestore → TTL, collection
    // `_rate`, field `expireAt`) सक्रिय गरे पुराना गन्ती-doc आफैं मेटिन्छन्।
    tx.set(ref, {minute, count: count + 1,
      expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000)});
    return true;
  });
  if (!allowed) {
    throw new HttpsError("resource-exhausted",
        "Too many requests. Please slow down and try again shortly.");
  }
}

module.exports = {enforceRateLimit};
