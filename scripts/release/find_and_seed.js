// One-off: find the approved Bike driver "nek" and re-seed a fresh active
// ride for them (previous one was cancelled during earlier testing), so we
// can verify Call/Video/Message unlock immediately on acceptance.
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('users')
    .where('service', 'in', ['Bike', 'Car'])
    .get();
  if (snap.empty) {
    console.log(JSON.stringify({ error: 'no drivers found' }));
    process.exit(1);
  }
  const driverDoc = snap.docs[0];
  const driverUid = driverDoc.id;
  const driverData = driverDoc.data();

  const reqRef = db.collection('serviceRequests').doc();
  await reqRef.set({
    employerUid: 'seed-employer-uid-2',
    workerUid: driverUid,
    employerName: 'TestRider2',
    employerPhone: '9800000000',
    workerName: `${driverData.firstName || ''} ${driverData.lastName || ''}`.trim() || 'Driver',
    service: driverData.service || 'Bike',
    status: 'accepted',
    address: 'Test seeded ride pickup 2',
    employerLat: 27.7172,
    employerLng: 85.3240,
    proposedPrice: 250,
    isRide: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection('users').doc(driverUid).set(
    { activeJobId: reqRef.id },
    { merge: true }
  );

  // print phone so we can log in as this driver
  console.log(JSON.stringify({
    requestId: reqRef.id,
    driverUid,
    name: driverData.firstName,
    phone: driverData.phone || driverData.testPhone || null,
  }));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
