const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  // Clean up the accidental seed from find_and_seed.js
  await db.collection('serviceRequests').doc('RhzgG3TEZxeZ2ECoE3jy').delete().catch(() => {});

  const ref = db.collection('serviceRequests').doc();
  await ref.set({
    service: 'Bike',
    isRide: true,
    employerUid: 'D6iC6VPfOnOAqFF83wOiW77XqgZ2',
    employerName: 'Bikash Bhandari',
    employerPhone: '',
    employerLat: 27.7172,
    employerLng: 85.3240,
    address: 'Kathmandu test pickup',
    title: 'Ride request',
    proposedPrice: 150,
    status: 'broadcasting',
    broadcast: true,
    autoOffer: false,
    nearbyCount: 1,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    preferredDate: admin.firestore.FieldValue.serverTimestamp(),
    timeSlot: 'anytime',
    destinationLat: 27.7275,
    destinationLng: 85.3345,
    destinationAddress: 'Kathmandu test drop',
  });
  console.log(JSON.stringify({ requestId: ref.id }));
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
