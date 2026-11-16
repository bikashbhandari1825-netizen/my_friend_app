// One-off: find driver "nek bhandari" (Bike) by scanning users where
// service in [Bike, Car], seed an accepted serviceRequests doc + activeJobId
// for them, to test the Admin Dashboard "Cancel Task" feature on the
// Drivers Control Dashboard specifically.
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
    employerUid: 'seed-employer-uid',
    workerUid: driverUid,
    employerName: 'TestRider',
    workerName: `${driverData.firstName || ''} ${driverData.lastName || ''}`.trim() || 'Driver',
    service: driverData.service || 'Bike',
    status: 'accepted',
    address: 'Test seeded ride pickup',
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

  console.log(JSON.stringify({ requestId: reqRef.id, driverUid, name: driverData.firstName }));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
