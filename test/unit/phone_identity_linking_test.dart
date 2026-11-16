// test/unit/phone_identity_linking_test.dart
// Covers the "duplicate account" bug: a phone number that already has a
// Firestore profile must load that existing profile (role, verification
// status, provider data) on a later login with a different Firebase Auth
// uid, instead of ever landing on a fresh/blank one.
//
// auth/dev_login.dart's linkPhoneToUid()/devTestSignIn()/phoneAccountExists()
// now take optional FirebaseAuth/FirebaseFirestore overrides for exactly
// this kind of test; production call sites are unaffected since the
// parameters default to the real singletons.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/auth/dev_login.dart';

void main() {
  const phone = '+9779748329291';

  group('phoneAccountExists', () {
    test('false for a phone number never seen before', () async {
      final firestore = FakeFirebaseFirestore();
      expect(await phoneAccountExists(phone, firestore: firestore), isFalse);
    });

    test('true once the phone has an indexed uid', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('phoneAccounts').doc(phoneKey(phone)).set({
        'uid': 'worker-old-uid',
        'phone': phone,
      });
      expect(await phoneAccountExists(phone, firestore: firestore), isTrue);
    });
  });

  group('linkPhoneToUid — the duplicate-account bug', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('first-ever login for a phone number just creates the index',
        () async {
      await linkPhoneToUid(phone, 'uid-1', firestore: firestore);

      final idx = await firestore
          .collection('phoneAccounts')
          .doc(phoneKey(phone))
          .get();
      expect(idx.data()!['uid'], 'uid-1');
      // No prior profile existed, so nothing should have been cloned.
      final freshUserDoc = await firestore.collection('users').doc('uid-1').get();
      expect(freshUserDoc.exists, isFalse);
    });

    test(
        'an approved worker profile under an old uid is found and loaded '
        'under the new uid, not replaced by a blank one', () async {
      // Simulate: this phone was previously approved as a worker under
      // uid-old (e.g. a debug-build test-mode session).
      await firestore.collection('users').doc('uid-old').set({
        'role': 'worker',
        'verificationStatus': 'approved',
        'profileComplete': true,
        'name': 'Bijay Budha',
      });
      await firestore.collection('providers').doc('uid-old').set({
        'selfieUrl': 'https://example.com/selfie.jpg',
        'vehiclePlate': '3456',
      });
      await firestore.collection('phoneAccounts').doc(phoneKey(phone)).set({
        'uid': 'uid-old',
        'phone': phone,
      });

      // The same phone number now signs in again, but Firebase Auth hands
      // back a different uid (exactly what happens crossing from a debug
      // test-mode anonymous session to a release build's real SMS uid).
      await linkPhoneToUid(phone, 'uid-new', firestore: firestore);

      final newUserDoc =
          await firestore.collection('users').doc('uid-new').get();
      expect(newUserDoc.exists, isTrue);
      expect(newUserDoc.data()!['role'], 'worker');
      expect(newUserDoc.data()!['verificationStatus'], 'approved');
      expect(newUserDoc.data()!['profileComplete'], isTrue);
      expect(newUserDoc.data()!['name'], 'Bijay Budha');

      final newProviderDoc =
          await firestore.collection('providers').doc('uid-new').get();
      expect(newProviderDoc.exists, isTrue);
      expect(newProviderDoc.data()!['vehiclePlate'], '3456');

      // The phone->uid index must now point at the new uid going forward.
      final idx = await firestore
          .collection('phoneAccounts')
          .doc(phoneKey(phone))
          .get();
      expect(idx.data()!['uid'], 'uid-new');
    });

    test('registeredWorkers listing docs get repointed to the new uid',
        () async {
      await firestore.collection('phoneAccounts').doc(phoneKey(phone)).set({
        'uid': 'uid-old',
        'phone': phone,
      });
      await firestore.collection('registeredWorkers').doc('listing-1').set({
        'uid': 'uid-old',
        'name': 'Bijay Budha',
        'service': 'Bike',
      });

      await linkPhoneToUid(phone, 'uid-new', firestore: firestore);

      final listing = await firestore
          .collection('registeredWorkers')
          .doc('listing-1')
          .get();
      expect(listing.data()!['uid'], 'uid-new');
    });

    test('logging in again with the SAME uid is a no-op migration',
        () async {
      await firestore.collection('users').doc('uid-1').set({
        'role': 'employer',
        'profileComplete': true,
      });
      await firestore.collection('phoneAccounts').doc(phoneKey(phone)).set({
        'uid': 'uid-1',
        'phone': phone,
      });

      await linkPhoneToUid(phone, 'uid-1', firestore: firestore);

      final userDoc = await firestore.collection('users').doc('uid-1').get();
      // Untouched — still exactly the original profile, no clone occurred.
      expect(userDoc.data()!['role'], 'employer');
      expect(userDoc.data()!['profileComplete'], isTrue);
    });
  });

  group('devTestSignIn end-to-end', () {
    test(
        'two sequential test-mode sign-ins for the same phone number '
        'converge on one profile, not two separate accounts', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(signedIn: false);

      // First session: brand-new anonymous uid, brand-new profile.
      await devTestSignIn(phone, auth: auth, firestore: firestore);
      final firstUid = auth.currentUser!.uid;
      await firestore.collection('users').doc(firstUid).set({
        'role': 'worker',
        'verificationStatus': 'approved',
      }, SetOptions(merge: true));

      // Sign out and back in with a fresh anonymous session (a second
      // MockFirebaseAuth simulates a different device/browser storage,
      // which is exactly the scenario that produced the duplicate-account
      // bug when the real-phone-auth path didn't call linkPhoneToUid).
      final secondAuth = MockFirebaseAuth(signedIn: false);
      await devTestSignIn(phone, auth: secondAuth, firestore: firestore);
      final secondUid = secondAuth.currentUser!.uid;

      expect(secondUid, isNot(equals(firstUid)));

      final secondProfile =
          await firestore.collection('users').doc(secondUid).get();
      expect(secondProfile.data()!['role'], 'worker');
      expect(secondProfile.data()!['verificationStatus'], 'approved');
    });
  });
}
