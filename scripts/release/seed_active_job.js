// One-off, read+write: find our test Plumber worker (phone 9811119999) and
// the test employer (phone 9855554444) by their phoneAccounts index, then
// create a serviceRequests doc with status 'accepted' between them and set
// the worker's users/{uid}.activeJobId — simulating "worker has an active
// job" so the new Admin Dashboard "Cancel Task" feature can be tested live
// without needing to fight GPS/geo-matching (this device's real location
// resolves to Poland, not Kathmandu, so broadcast matching to a Kathmandu
// worker can't happen naturally on this box).
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function findUidByPhone(phoneDigits) {
  const doc = await db.collection('phoneAccounts').doc(phoneDigits).get();
  if (!doc.exists) return null;
  return (doc.data().uid || '').toString() || null;
}

(async () => {
  const workerUid = await findUidByPhone('9779811119999');
  const employerUid = await findUidByPhone('9779855554444');
  if (!workerUid || !employerUid) {
    console.log(JSON.stringify({ workerUid, employerUid, error: 'not found' }));
    process.exit(1);
  }

  const [workerDoc, employerDoc] = await Promise.all([
    db.collection('users').doc(workerUid).get(),
    db.collection('users').doc(employerUid).get(),
  ]);
  const workerData = workerDoc.data() || {};
  const employerData = employerDoc.data() || {};

  const reqRef = db.collection('serviceRequests').doc();
  await reqRef.set({
    employerUid,
    workerUid,
    employerName: `${employerData.firstName || ''} ${employerData.lastName || ''}`.trim() || 'TestEmployer',
    workerName: `${workerData.firstName || ''} ${workerData.lastName || ''}`.trim() || 'TestWorker',
    service: 'Plumber',
    status: 'accepted',
    address: 'Test seeded address',
    employerLat: 27.7172,
    employerLng: 85.3240,
    proposedPrice: 500,
    isRide: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection('users').doc(workerUid).set(
    { activeJobId: reqRef.id },
    { merge: true }
  );

  console.log(JSON.stringify({ requestId: reqRef.id, workerUid, employerUid }));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
