const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const ref = db.collection('serviceRequests').doc('NIdzmU0CECNvqS6rUHdr');
  await ref.update({
    status: 'accepted',
    arrivedAt: admin.firestore.FieldValue.delete(),
    startedAt: admin.firestore.FieldValue.delete(),
  });
  const snap = await ref.get();
  const d = snap.data();
  console.log(JSON.stringify({ status: d.status, rideStartCode: d.rideStartCode, service: d.service, arrivedAt: d.arrivedAt ?? null }, null, 2));
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
