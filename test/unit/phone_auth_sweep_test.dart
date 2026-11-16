// test/unit/phone_auth_sweep_test.dart
//
// Headless, programmatic sweep across every pre-registered test number —
// written because the physical test device (Realme/ColorOS) blocks `adb
// shell input tap/swipe` synthetic touch events unless "Disable permission
// monitoring" is enabled in Developer Options, so a scripted on-device UI
// sweep isn't reliable from this environment. This exercises the exact
// same functions phone_input_page.dart/otp_verification_page.dart/
// settings_page.dart call (resolveE164, devTestSignIn, linkPhoneToUid,
// phoneAccountExists), against FakeFirebaseFirestore/MockFirebaseAuth, for
// every number — no widget tree, no device, fully deterministic.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_friend_app/auth/dev_login.dart';
import 'package:my_friend_app/auth/phone_format.dart';

void main() {
  // हरेक test number — जसको country-selector (phone_input_page.dart मा
  // user ले छानेको) र फिल्डमा टाइप गरेको raw text (country code सहित वा
  // बिना, दुवै ढाँचा — वास्तविक प्रयोगकर्ताले दुवै तरिकाले टाइप गर्न सक्छन्)।
  final cases = <_PhoneCase>[
    const _PhoneCase(
      label: 'Poland #1',
      countryIso: 'PL',
      typedWithCountryCode: '+48 574 726 831',
      typedNationalOnly: '574726831',
      expectedE164: '+48574726831',
    ),
    const _PhoneCase(
      label: 'Nepal #1',
      countryIso: 'NP',
      typedWithCountryCode: '+977 984-9458279',
      typedNationalOnly: '9849458279',
      expectedE164: '+9779849458279',
    ),
    const _PhoneCase(
      label: 'Poland #2',
      countryIso: 'PL',
      typedWithCountryCode: '+48 506 994 366',
      typedNationalOnly: '506994366',
      expectedE164: '+48506994366',
    ),
    // नोट: यो national-digit (9848391825) `kAdminSecretPhoneDigits` सँग
    // मिल्छ — तर त्यो जाँच UI layer (`phone_input_page.dart::_continue()`)
    // मै मात्र हुन्छ, यहाँ प्रत्यक्ष कल गरिने data-layer function हरूले
    // त्यसको वास्ता गर्दैनन्, त्यसैले यो सामान्य test-case कै रूपमा मान्य।
    const _PhoneCase(
      label: 'Nepal #2',
      countryIso: 'NP',
      typedWithCountryCode: '+977 984-8391825',
      typedNationalOnly: '9848391825',
      expectedE164: '+9779848391825',
    ),
    const _PhoneCase(
      label: 'Malta',
      countryIso: 'MT',
      typedWithCountryCode: '+356 7775 6050',
      typedNationalOnly: '77756050',
      expectedE164: '+35677756050',
    ),
  ];

  group('resolveE164 — the "+48 combined with the number" parsing bug', () {
    for (final c in cases) {
      test('${c.label}: typed with its own country code (+ prefix) is used '
          'as-is, never double-prefixed by the selector', () {
        final country =
            CountryService().findByCode(c.countryIso) ?? CountryService().getAll().first;
        expect(resolveE164(country, c.typedWithCountryCode), c.expectedE164);
      });

      test('${c.label}: typed as national digits only uses the selected '
          "country's dial code", () {
        final country =
            CountryService().findByCode(c.countryIso) ?? CountryService().getAll().first;
        expect(resolveE164(country, c.typedNationalOnly), c.expectedE164);
      });

      test('${c.label}: resolved number is still a plausible phone number '
          '(_canSubmit never blocks it)', () {
        final digits = digitsOnly(c.typedWithCountryCode);
        expect(isPlausiblePhoneDigits(digits.length >= 4 ? digits : '0000'),
            isTrue,
            reason: 'typed digits: $digits');
      });
    }
  });

  group('devTestSignIn + linkPhoneToUid — full test-mode sweep', () {
    for (final c in cases) {
      test('${c.label} (${c.expectedE164}) signs in cleanly, gets its own '
          'phoneAccounts index, zero network/captcha dependency', () async {
        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(signedIn: false);

        expect(await phoneAccountExists(c.expectedE164, firestore: firestore),
            isFalse);

        await devTestSignIn(c.expectedE164, auth: auth, firestore: firestore);
        final uid = auth.currentUser!.uid;
        expect(uid, isNotEmpty);

        expect(await phoneAccountExists(c.expectedE164, firestore: firestore),
            isTrue);

        final idx = await firestore
            .collection('phoneAccounts')
            .doc(phoneKey(c.expectedE164))
            .get();
        expect(idx.data()!['uid'], uid);
        expect(idx.data()!['phone'], c.expectedE164);
      });
    }
  });

  group('Account deletion → re-registration — stale-state regression guard',
      () {
    for (final c in cases) {
      test(
          '${c.label}: deleting users/providers/phoneAccounts docs (what '
          'settings_page.dart now does) means the next devTestSignIn for '
          'the SAME number gets a 100% clean profile — no resurrected role/'
          'verificationStatus from the deleted account', () async {
        final firestore = FakeFirebaseFirestore();
        final firstAuth = MockFirebaseAuth(signedIn: false);

        // 1) First account for this number — becomes an approved worker.
        await devTestSignIn(c.expectedE164,
            auth: firstAuth, firestore: firestore);
        final firstUid = firstAuth.currentUser!.uid;
        await firestore.collection('users').doc(firstUid).set({
          'role': 'worker',
          'verificationStatus': 'approved',
          'profileComplete': true,
        }, SetOptions(merge: true));
        await firestore.collection('providers').doc(firstUid).set({
          'vehiclePlate': 'BA 1 PA 1234',
          'selfieUrl': 'https://example.com/selfie.jpg',
        });

        // 2) Settings > Delete Account — exactly the three deletes added to
        //    settings_page.dart's _confirmDeleteAccount().
        await firestore.collection('users').doc(firstUid).delete();
        await firestore.collection('providers').doc(firstUid).delete();
        await firestore
            .collection('phoneAccounts')
            .doc(phoneKey(c.expectedE164))
            .delete();

        // 3) Re-register with the exact same number — a brand new session/
        //    uid (exactly what happens on a real device: Anonymous sign-in
        //    always mints a fresh uid).
        final secondAuth = MockFirebaseAuth(signedIn: false);
        await devTestSignIn(c.expectedE164,
            auth: secondAuth, firestore: firestore);
        final secondUid = secondAuth.currentUser!.uid;
        expect(secondUid, isNot(equals(firstUid)));

        // No resurrected provider profile — the whole point of the fix.
        final newProviderDoc =
            await firestore.collection('providers').doc(secondUid).get();
        expect(newProviderDoc.exists, isFalse);

        // The user doc exists only with what devTestSignIn itself writes
        // (testPhone) — no role/verificationStatus carried over.
        final newUserDoc =
            await firestore.collection('users').doc(secondUid).get();
        expect(newUserDoc.data()!.containsKey('role'), isFalse);
        expect(
            newUserDoc.data()!.containsKey('verificationStatus'), isFalse);

        // The index now correctly points at the new uid.
        final idx = await firestore
            .collection('phoneAccounts')
            .doc(phoneKey(c.expectedE164))
            .get();
        expect(idx.data()!['uid'], secondUid);
      });
    }
  });
}

class _PhoneCase {
  final String label;
  final String countryIso;
  final String typedWithCountryCode;
  final String typedNationalOnly;
  final String expectedE164;
  const _PhoneCase({
    required this.label,
    required this.countryIso,
    required this.typedWithCountryCode,
    required this.typedNationalOnly,
    required this.expectedE164,
  });
}
