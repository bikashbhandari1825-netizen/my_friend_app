// One-off: list workers/drivers with a phone number that is NOT the admin
// secret gateway number, so we can actually log in as them for testing.
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const ADMIN_SECRET = '9848391825';

(async () => {
  const snap = await db.collection('users')
    .where('role', '==', 'worker')
    .get();
  const rows = [];
  snap.forEach((doc) => {
    const d = doc.data();
    const phone = (d.phone || d.testPhone || '').toString();
    const digits = phone.replace(/[^0-9]/g, '');
    if (!digits.endsWith(ADMIN_SECRET) && digits.length > 0) {
      rows.push({
        uid: doc.id,
        phone,
        service: d.service,
        profileComplete: d.profileComplete,
        verificationStatus: d.verificationStatus || d.workerVerificationStatus,
      });
    }
  });
  console.log(JSON.stringify(rows, null, 2));
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
