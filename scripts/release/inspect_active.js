const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('serviceRequests')
    .where('status', 'in', ['accepted', 'confirmed', 'in_progress'])
    .get();
  if (snap.empty) {
    console.log(JSON.stringify({ error: 'no active requests found' }));
    process.exit(0);
  }
  const out = snap.docs.map(d => {
    const v = d.data();
    return {
      id: d.id,
      service: v.service,
      status: v.status,
      rideStartCode: v.rideStartCode,
      arrivedAt: v.arrivedAt ? 'set' : null,
      acceptedAt: v.acceptedAt ? 'set' : null,
      address: v.address,
      dropAddress: v.dropAddress,
      pickupAddress: v.pickupAddress,
      employerUid: v.employerUid,
      workerUid: v.workerUid,
    };
  });
  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
