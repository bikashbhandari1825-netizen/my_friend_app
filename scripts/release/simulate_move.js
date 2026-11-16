const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const ref = db.collection('serviceRequests').doc('yvebXDGUCSlN0WN4rXfR');
  const snap = await ref.get();
  const d = snap.data();
  let lat = d.workerLat;
  let lng = d.workerLng;
  console.log('start', lat, lng, 'status', d.status);

  // Diagonal NE-ish straight line, ~15m per step.
  const dLat = 0.00012;
  const dLng = 0.00018;

  for (let i = 0; i < 10; i++) {
    lat += dLat;
    lng += dLng;
    await ref.update({
      workerLat: lat,
      workerLng: lng,
      workerLocationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('step', i, lat.toFixed(6), lng.toFixed(6));
    await sleep(2000);
  }
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
