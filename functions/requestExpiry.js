// functions/requestExpiry.js
//
// म्याद सकिएका खुला (broadcasting) अनुरोध सफा गर्ने — एप बन्द/क्र्यास भएको
// यात्रीको अनुरोध पनि कसैले नलिई अनिश्चित कालसम्म खुला नरहोस्।
//   • १० मिनेटभन्दा पुरानो (सिर्जना वा पछिल्लो भाडा-वृद्धि) `broadcasting`
//     → `no_provider` (यात्रीको स्क्रिनले यही स्थितिमा "कुनै driver भेटिएन"
//     देखाउँछ; driver को सूची `status == broadcasting` मात्र सुन्छ, त्यसैले हट्छ)।
//   • २ दिनभन्दा पुरानो `no_provider` → मेटिन्छ (उप-collection सहित)।
// `kRequestStaleSec` (lib/utils/request_timeout.dart) सँग उही मान।
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const STALE_MS = 600 * 1000;
const PURGE_MS = 2 * 24 * 3600 * 1000;

function sinceMs(d) {
  const t = [d.createdAt, d.fareRaisedAt]
      .filter((v) => v && typeof v.toMillis === "function")
      .map((v) => v.toMillis());
  return t.length ? Math.max(...t) : null;
}

exports.expireStaleRequests = onSchedule("every 5 minutes", async () => {
  const db = admin.firestore();
  const now = Date.now();

  // index नचाहिने गरी status मात्रले query, म्याद memory मा जाँच्ने।
  const open = await db.collection("serviceRequests")
      .where("status", "==", "broadcasting").limit(500).get();
  let expired = 0;
  const batch = db.batch();
  open.forEach((doc) => {
    const since = sinceMs(doc.data());
    if (since !== null && now - since > STALE_MS) {
      batch.update(doc.ref, {
        status: "no_provider",
        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      expired++;
    }
  });
  if (expired > 0) await batch.commit();

  const dead = await db.collection("serviceRequests")
      .where("status", "==", "no_provider").limit(200).get();
  let purged = 0;
  for (const doc of dead.docs) {
    const ts = doc.get("expiredAt");
    const t = ts && typeof ts.toMillis === "function" ? ts.toMillis() : null;
    if (t !== null && now - t > PURGE_MS) {
      await db.recursiveDelete(doc.ref);
      purged++;
    }
  }
  console.log(`expireStaleRequests: expired=${expired} purged=${purged}`);
});
