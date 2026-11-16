// integration_test/live_phone_auth_test.dart
//
// REAL on-device execution — not a headless/fake-Firestore test. This runs
// the actual app (via `app.main()`, the same entrypoint `main.dart` uses)
// inside Flutter's own test binding, driving real widgets through real
// gesture/text-entry APIs. It bypasses the Realme/ColorOS block on `adb
// shell input tap/swipe` entirely because it never goes through the OS
// input-injection path at all — `tester.tap()`/`tester.enterText()` call
// directly into the Flutter engine's gesture/text-input binding from
// in-process, the same mechanism Flutter's own widget tests use, just
// running on the physical device's real engine instead of a host-side
// test harness. It talks to the real Firebase project (kaammitra-87e38)
// through the live, already-deployed `kUseRealPhoneSms = false` test-mode
// bypass — no real SMS/reCAPTCHA involved, same as a human tester would
// hit.
//
// Run: flutter test integration_test/live_phone_auth_test.dart -d <deviceId>
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_friend_app/l10n/strings.dart';
import 'package:my_friend_app/main.dart' as app;

class _PhoneCase {
  final String label;
  final String typed; // फिल्डमै टाइप हुने — country code सहित (+..)
  const _PhoneCase(this.label, this.typed);
}

const _cases = [
  _PhoneCase('Poland #1', '+48 574 726 831'),
  _PhoneCase('Nepal #1', '+977 9849458279'),
  _PhoneCase('Poland #2', '+48 506 994 366'),
  _PhoneCase('Nepal #2', '+977 9848391825'),
  _PhoneCase('Malta', '+356 7775 6050'),
];

Future<void> _settle(WidgetTester tester, [int seconds = 15]) =>
    tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, Duration(seconds: seconds));

/// Landing page बाट phone number टाइप गरेर OTP screen सम्म (live widgets,
/// live taps/enterText) लैजाने — दुवै live-dashboard test र auth-sweep
/// test ले साझा गर्ने।
Future<void> _goFromLandingToOtp(WidgetTester tester, String typedPhone) async {
  // PhoneLandingPage — "Continue with phone number".
  expect(find.text(S.continueWithPhone), findsOneWidget,
      reason: 'expected to be on the landing page');
  await tester.tap(find.text(S.continueWithPhone));
  await _settle(tester);

  // PhoneInputPage — एउटै TextField (फोन नम्बर)।
  expect(find.byType(TextField), findsOneWidget,
      reason: 'expected the single phone-number field');
  await tester.enterText(find.byType(TextField), typedPhone);
  await _settle(tester);

  await tester.tap(find.text(S.continueWord));
  await _settle(tester);
}

/// OTP screen (६ वटा छुट्टाछुट्टै digit box) मा '1'..'6' टाइप गरेर
/// auto-verify सम्म पर्खने।
Future<void> _enterOtpAndWait(WidgetTester tester) async {
  final boxes = find.byType(TextField);
  expect(boxes, findsNWidgets(6), reason: 'expected 6 OTP digit boxes');
  for (var i = 0; i < 6; i++) {
    await tester.enterText(boxes.at(i), '${i + 1}');
    await tester.pump(const Duration(milliseconds: 150));
  }
  // अन्तिम अंक पछि auto-verify + 650ms success-animation + pop — generous
  // real-network बजेट दिने।
  await _settle(tester, 20);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'LIVE on-device sweep — all 5 pre-registered test numbers reach a '
      'signed-in state via the real app, real widgets, real taps',
      (tester) async {
    app.main();
    await _settle(tester, 20);

    // कुनै अघिल्लो session बाट signed-in अवस्था बाँकी भए — सफा सुरुवात।
    await FirebaseAuth.instance.signOut();
    await _settle(tester);

    for (final c in _cases) {
      debugPrint('>>> LIVE_SWEEP_START: ${c.label} (${c.typed})');
      await _goFromLandingToOtp(tester, c.typed);
      await _enterOtpAndWait(tester);

      // sign-in सफल भयो भन्ने प्रमाण — Firebase Auth मा currentUser अब छ,
      // अनि landing page (phone field) फेरि देखिएन (RoleSelectionPage वा
      // अर्को post-auth screen मा पुग्यो)।
      expect(FirebaseAuth.instance.currentUser, isNotNull,
          reason: '${c.label}: expected a signed-in user after OTP 123456');
      expect(find.text(S.continueWithPhone), findsNothing,
          reason: '${c.label}: should have left the landing page');
      debugPrint('>>> LIVE_SWEEP_OK: ${c.label} uid='
          '${FirebaseAuth.instance.currentUser!.uid}');

      // अर्को नम्बरको लागि landing page मा सफा फर्कने।
      await FirebaseAuth.instance.signOut();
      await _settle(tester);
    }

    debugPrint('>>> LIVE_SWEEP_ALL_DONE');
  });

  testWidgets(
      'LIVE on-device — full registration through to the real Passenger & '
      'Employer dashboard (MainContainer), live widgets only',
      (tester) async {
    app.main();
    await _settle(tester, 20);
    await FirebaseAuth.instance.signOut();
    await _settle(tester);

    await _goFromLandingToOtp(tester, _cases.first.typed); // Poland #1
    await _enterOtpAndWait(tester);

    // RoleSelectionPage — "Passenger & Employer" कार्ड।
    expect(find.text(S.roleSelectPassengerEmployerTitle), findsOneWidget,
        reason: 'expected RoleSelectionPage for a fresh account');
    await tester.tap(find.text(S.roleSelectPassengerEmployerTitle));
    await _settle(tester);

    // EmployerRegistrationPage — firstName/lastName/phone, Next.
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Live');
    await tester.enterText(fields.at(1), 'Test');
    await tester.enterText(fields.at(2), '9800000111');
    await _settle(tester);
    await tester.tap(find.text(S.next));
    await _settle(tester, 20);

    // MainContainer — पुष्टि: role-selection/registration form कुनै पनि
    // अब देखिँदैन (वास्तविक dashboard मा पुगियो)।
    expect(find.text(S.roleSelectPassengerEmployerTitle), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    debugPrint('>>> LIVE_DASHBOARD_REACHED: Passenger & Employer '
        '(MainContainer) uid=${FirebaseAuth.instance.currentUser!.uid}');

    // स्क्रिनशट/live-viewing को लागि केही सेकेन्ड स्थिर राख्ने।
    await tester.pump(const Duration(seconds: 6));
  });
}
