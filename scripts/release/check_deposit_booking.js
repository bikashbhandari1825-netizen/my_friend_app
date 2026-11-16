const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('hotel_bookings')
    .where('guestName', '==', 'Bikash Bhandari')
    .get();
  if (snap.empty) {
    console.log('No bookings found for Bikash Bhandari.');
    return;
  }
  const docs = snap.docs.sort((a, b) =>
    (b.data().createdAt?.toMillis?.() ?? 0) - (a.data().createdAt?.toMillis?.() ?? 0));
  docs.slice(0, 3).forEach(d => {
    const data = d.data();
    console.log('--- Booking', d.id, '---');
    console.log({
      hotelId: data.hotelId,
      roomId: data.roomId,
      status: data.status,
      paymentType: data.paymentType,
      totalPrice: data.totalPrice,
      depositAmount: data.depositAmount,
      depositReference: data.depositReference,
      createdAt: data.createdAt?.toDate?.(),
    });
  });
})().catch(e => { console.error(e); process.exit(1); });
