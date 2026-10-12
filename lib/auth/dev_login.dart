// auth/dev_login.dart
//
// फोन नम्बर ↔ Firebase uid जोड्ने/migrate गर्ने साझा utility — साँचो
// Firebase Phone Auth (OTP verify सफल भएपछि, otp_verification_page.dart)
// ले यहीं `linkPhoneToUid` बोलाउँछ ताकि एउटै नम्बरले सधैँ उही profile
// (role/verificationStatus/job-history) भेट्टाओस्, नयाँ/खाली account नबनोस्।
//
// कसरी: `phoneAccounts/{digitsOnly}` ले फोन → पछिल्लो uid track गर्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_globals.dart';

/// फोन नम्बरको अंक-मात्र key (index doc id)।
String phoneKey(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

/// यो फोन नम्बरसँग पहिले नै account छ? (OTP अघि login/signup छुट्याउन)
///
/// [firestore] — दिइएमा (unit test मा `FakeFirebaseFirestore`) त्यही
/// प्रयोग हुन्छ, नदिए production कै `FirebaseFirestore.instance` — यो
/// optional param ले कुनै पनि हालको caller को व्यवहार बदल्दैन।
Future<bool> phoneAccountExists(String phone,
    {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  try {
    final d = await db.collection('phoneAccounts').doc(phoneKey(phone)).get();
    return d.exists && (d.data()?['uid'] ?? '').toString().isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// TEST-ONLY HARNESS — Anonymous sign-in + `linkPhoneToUid`, बिना कुनै
/// साँचो SMS/reCAPTCHA। कुनै पनि production UI (phone_input_page.dart/
/// otp_verification_page.dart) ले यो कहिल्यै बोलाउँदैन — केवल
/// `test/unit/phone_auth_sweep_test.dart` र `phone_identity_linking_test.dart`
/// ले `linkPhoneToUid`/`_migrateIdentity` को behaviour (real-device
/// credential/reCAPTCHA mock गर्न नसकिने भएकोले) छिटो/deterministic रूपमा
/// जाँच्नका लागि मात्र प्रयोग गर्छन्।
Future<void> devTestSignIn(String phone,
    {FirebaseAuth? auth, FirebaseFirestore? firestore}) async {
  final fbAuth = auth ?? FirebaseAuth.instance;
  final db = firestore ?? FirebaseFirestore.instance;
  final cred = await fbAuth.signInAnonymously();
  final newUid = cred.user!.uid;
  activeTestPhone = phone;

  await db.collection('users').doc(newUid).set(
    {'testPhone': phone},
    SetOptions(merge: true),
  );
  await linkPhoneToUid(phone, newUid, firestore: db);
}

/// यो फोन नम्बर `phoneAccounts` index मा पहिले फरक uid सँग जोडिएको भेटिए
/// त्यो पुरानो profile (`users`/`providers`/`registeredWorkers`) यो नयाँ
/// uid मा migrate गर्छ, अनि index लाई यही नयाँ uid तिर अद्यावधिक गर्छ।
///
/// पहिले test-mode (हटाइएको `devTestSignIn`, Anonymous sign-in) ले बनाएको
/// profile त्यही नम्बरले साँचो SMS मार्फत पहिलोपटक login गर्दा (सर्वथा फरक,
/// real-phone-auth uid पाउने भएकोले) कहिल्यै भेटिँदैनथ्यो — role/
/// verificationStatus null देखिएर नयाँ/duplicate account बन्ने गुनासोको
/// साँचो जड। अब `otp_verification_page.dart` ले साँचो sign-in सफल
/// भएपछि सधैँ यही function बोलाउँछ, ताकि कुनै पुरानो test-mode legacy uid
/// भेटिए त्यसको profile नयाँ real-phone-auth uid मा एकपटक migrate होस्।
Future<void> linkPhoneToUid(String phone, String newUid,
    {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final key = phoneKey(phone);
  final idxRef = db.collection('phoneAccounts').doc(key);
  final idx = await idxRef.get();
  final oldUid = (idx.data()?['uid'] ?? '').toString();

  if (oldUid.isNotEmpty && oldUid != newUid) {
    await _migrateIdentity(oldUid, newUid, phone, firestore: db);
    // Stale FCM Token Cross-Contamination Fix — माथिकै `_migrateIdentity`
    // ले oldUid को `users` doc पूरै (fcmToken सहित) newUid मा clone गर्छ,
    // तर oldUid आफ्नै doc मा त्यही token सधैँको लागि बाँकी रहन्थ्यो। FCM
    // token यही भौतिक डिभाइस/installation सँग बाँधिएको हुन्छ, कुनै एक
    // Firebase Auth uid सँग होइन — त्यसैले पुरानो (अब त्यागिएको) uid ले
    // पाएको जुनसुकै भविष्यको push (जस्तै त्यो uid ले अघि गरेको अर्को
    // booking को counter-offer/status-update) यही डिभाइसमा नै आइरहन्थ्यो,
    // भलै अहिले साइन-इन भएको खाता सर्वथा फरक भए पनि — ठ्याक्कै "पुरानो/
    // असम्बन्धित बुकिङको notification अहिले किन देखियो" गुनासोको जड। अब
    // migrate भइसकेपछि पुरानो uid को token खाली गर्ने, ताकि यो डिभाइसले
    // भविष्यमा नयाँ uid कै token मार्फत मात्र push पाओस्।
    try {
      await db
          .collection('users')
          .doc(oldUid)
          .update({'fcmToken': FieldValue.delete()});
    } catch (_) {}
  }

  await idxRef.set({
    'uid': newUid,
    'phone': phone,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// पुरानो uid को profile नयाँ session uid मा सार्ने।
/// rules ले `users`/`providers` (आफ्नै doc) र `registeredWorkers` (uid == self)
/// लेख्न दिन्छ। job-history (`serviceRequests`) real phone-auth बिना सर्दैन
/// — त्यसको participant जाँच (`firestore.rules`/`storage.rules` दुवैमा)
/// resource कै हालको `employerUid`/`workerUid` उमेर्नेलाई मात्र लेख्न दिन्छ,
/// नयाँ uid ले त्यो सर्त कहिल्यै पूरा गर्दैन (चिकन-एग: पुरानो uid बाहेक
/// कसैले पनि त्यो field आफैं बदल्न पाउँदैन) — client-side बाट सुरक्षित
/// रूपमा सम्भव छैन, admin-privileged Cloud Function मात्र यो गर्न सक्छ। यो
/// सीमा अहिले केवल एकपटकको legacy migration (पुरानो test-mode anonymous
/// uid → पहिलोपटकको real-phone-auth uid) मा मात्र लागू हुन्छ — त्यसपछि
/// उही फोनले फेरि login गर्दा uid कहिल्यै बदलिँदैन, यो केस दोहोरिँदैन।
Future<void> _migrateIdentity(String oldUid, String newUid, String phone,
    {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;

  Future<void> cloneDoc(String col) async {
    try {
      final s = await db.collection(col).doc(oldUid).get();
      if (!s.exists) return;
      final data = Map<String, dynamic>.from(s.data()!);
      data['uid'] = newUid;
      data['testPhone'] = phone;
      await db.collection(col).doc(newUid).set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  await cloneDoc('users');
  await cloneDoc('providers');

  // public worker listing — uid field आफैँतिर सार्ने
  try {
    final q = await db
        .collection('registeredWorkers')
        .where('uid', isEqualTo: oldUid)
        .get();
    for (final d in q.docs) {
      await d.reference.update({'uid': newUid});
    }
  } catch (_) {}
}

/// Session सफा गरेर logout — अर्को tester सजिलै आफ्नो नम्बरले login गर्न सकून्।
Future<void> signOutClean() async {
  sessionProfilePhoto = null;
  activeTestPhone = null;
  celebrationShownFor.clear();
  await FirebaseAuth.instance.signOut();
}

/// Account पूर्ण रूपमा मेटाउने — `users`/`providers` doc, तीनवटै cascade
/// collection (`registeredWorkers`/`pendingWorkers`/`notifications`),
/// `phoneAccounts` index, र Firebase Auth account आफैं। settings_page.dart
/// (Delete Account) र "रद्द भएको दर्ता पछि फेरि role छान्ने" (Worker/Driver
/// registration कै "Start Fresh") — दुवैले यही एउटा core logic साझा गर्छन्,
/// ताकि delete-cascade कहिल्यै दुई ठाउँमा छुट्टाछुट्टै (र समयसँगै
/// out-of-sync) नहोस्। कलरले आफैं confirm dialog/error snackbar देखाउनुपर्छ
/// — यो function ले केवल deletion गर्छ, कुनै UI छुँदैन। Firebase Auth
/// account मेटिनेबित्तिकै (phoneAccounts index सहित) यही फोन नम्बरले फेरि
/// login गर्दा सर्वथा नयाँ uid/role-selection पाउँछ।
Future<void> deleteAccountCascade(String uid, {String? phone}) async {
  final db = FirebaseFirestore.instance;

  for (final col in ['registeredWorkers', 'pendingWorkers', 'notifications']) {
    final snap = await db.collection(col).where('uid', isEqualTo: uid).get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  await db.collection('users').doc(uid).delete();
  await db.collection('providers').doc(uid).delete();

  if (phone != null && phone.isNotEmpty) {
    await db.collection('phoneAccounts').doc(phoneKey(phone)).delete();
  }

  await FirebaseAuth.instance.currentUser?.delete();

  sessionProfilePhoto = null;
  activeTestPhone = null;
  celebrationShownFor.clear();
}
