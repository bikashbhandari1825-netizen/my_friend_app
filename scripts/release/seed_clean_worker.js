const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const WORKER_UID = 'cZH88WV49CTPz0OKI1xZbWcAtdE3';

(async () => {
  const workerDoc = await db.collection('users').doc(WORKER_UID).get();
  const workerData = workerDoc.data() || {};

  const reqRef = db.collection('serviceRequests').doc();
  await reqRef.set({
    employerUid: 'seed-employer-uid-3',
    workerUid: WORKER_UID,
    employerName: 'TestCustomer3',
    employerPhone: '9800000003',
    workerName: `${workerData.firstName || ''} ${workerData.lastName || ''}`.trim() || 'Worker',
    service: workerData.service || 'Plumber',
    status: 'accepted',
    address: 'Test seeded job address 3',
    employerLat: 27.7172,
    employerLng: 85.3240,
    proposedPrice: 600,
    isRide: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection('users').doc(WORKER_UID).set(
    { activeJobId: reqRef.id },
    { merge: true }
  );

  console.log(JSON.stringify({ requestId: reqRef.id, workerUid: WORKER_UID }));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
