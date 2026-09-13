// auth/dev_login.dart
//
// नि:शुल्क testing को लागि — real Firebase Phone Auth (paid SMS) नचाहिने।
// जुनसुकै फोन नम्बर + code 123456 हाल्दा Anonymous sign-in हुन्छ, अनि त्यो फोन
// नम्बरलाई एउटै स्थिर profile सँग जोडिन्छ:
//   • पहिलोपटक        → नयाँ account (role selection → registration)
//   • फेरि उही नम्बर   → पुरानै profile मै login (Employer वा Worker), duplicate होइन
//
// कसरी: `phoneAccounts/{digitsOnly}` ले फोन → पछिल्लो uid track गर्छ। नयाँ session
// को anonymous uid फरक हुन्छ, त्यसैले पुरानो uid को `users`/`providers`/
// `registeredWorkers` data नयाँ uid मा सारिन्छ (uid-keyed model यथावत्; gate र
// queries अपरिवर्तित)।
//
// नोट: पूर्ण job-history/reviews persistence लाई Firebase Console मा real Phone
// sign-in enable गर्नुहोस् — त्यसपछि एउटै नम्बरले सधैँ एउटै uid पाउँछ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_globals.dart';

const String kTestPhone = '+9779800000000';
const String kTestCode = '123456';
const String kTestPhoneHint = '9800000000';

/// फोन नम्बरको अंक-मात्र key (index doc id)।
String phoneKey(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

/// पुरानो `isTestPhone` — अब जुनसुकै नम्बरमा test-mode चल्छ।
bool isTestPhone(String e164) => true;

/// यो फोन नम्बरसँग पहिले नै account छ? (OTP अघि login/signup छुट्याउन)
Future<bool> phoneAccountExists(String phone) async {
  try {
    final d = await FirebaseFirestore.instance
        .collection('phoneAccounts')
        .doc(phoneKey(phone))
        .get();
    return d.exists && (d.data()?['uid'] ?? '').toString().isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Test login — Anonymous sign-in + phone लाई स्थिर profile सँग जोड्ने।
Future<void> devTestSignIn(String phone) async {
  final cred = await FirebaseAuth.instance.signInAnonymously();
  final newUid = cred.user!.uid;
  activeTestPhone = phone;

  final db = FirebaseFirestore.instance;
  final key = phoneKey(phone);
  final idxRef = db.collection('phoneAccounts').doc(key);
  final idx = await idxRef.get();
  final oldUid = (idx.data()?['uid'] ?? '').toString();

  if (oldUid.isNotEmpty && oldUid != newUid) {
    await _migrateIdentity(oldUid, newUid, phone);
  }

  await db.collection('users').doc(newUid).set(
    {'testPhone': phone},
    SetOptions(merge: true),
  );
  await idxRef.set({
    'uid': newUid,
    'phone': phone,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// पुरानो uid को profile नयाँ session uid मा सार्ने।
/// rules ले `users`/`providers` (आफ्नै doc) र `registeredWorkers` (uid == self)
/// लेख्न दिन्छ। job-history (`serviceRequests`) real phone-auth बिना सर्दैन।
Future<void> _migrateIdentity(
    String oldUid, String newUid, String phone) async {
  final db = FirebaseFirestore.instance;

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
