// config/app_config.dart
// App owner ले बदल्न सक्ने setting हरू (Firestore `config` collection मा)।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

/// ── टेस्टिङ चरण auth toggle ──────────────────────────────────────────────
/// Google Sign-In फेरि सक्रिय गरिएको छ — physical device मा live SHA-1 +
/// signInWithCredential root-cause debug गरेर पुष्टि भइसक्यो (काम गर्छ,
/// नेटवर्क slow भएमा केही सेकेन्ड लाग्न सक्छ, त्यसैले button मा अब busy/
/// spinner राखिएको छ ताकि user "केही भएन" भनेर बीचमै app बाट बाहिरिएर
/// प्रक्रिया नरोकियोस्)। साथै Email/Password login असफल हुँदा देखिने hint
/// (`login_no_match_hint`) ले नै "Google बाट जारी राख्नुहोस्" भन्छ — त्यो
/// बटन लुकाइराखे hint अर्थहीन हुन्थ्यो। `false` पार्दा बटन फेरि लुक्छ।
const bool kEnableGoogleSignIn = true;

/// "Continue with phone number" बटन UI मा सधैँ देखिन्छ (भविष्यको प्रयोगको
/// लागि) — यसलाई लुकाउने toggle होइन। यसको सट्टा तलको `kUseRealPhoneSms`
/// ले नियन्त्रण गर्छ: बटन थिचेर नम्बर हालेपछि साँचो Firebase Phone Auth
/// (SMS + reCAPTCHA) प्रयोग गर्ने कि, अन्तर्निहित नि:शुल्क test-mode
/// (जुनसुकै नम्बर + code 123456, हेर्नुहोस् dev_login.dart::kTestCode)
/// प्रयोग गर्ने।
const bool kEnablePhoneAuth = true;

/// Web मा साँचो Firebase Phone Auth (`signInWithPhoneNumber`) ले invisible
/// reCAPTCHA चालु गर्छ — त्यो domain properly configure नभएसम्म वा
/// popup-blocked भए UI अड्किने/"break वा loop" हुने मुख्य कारण यही थियो।
/// अहिलेको टेस्टिङ चरणमा `false` राखेर phone flow सिधै अन्तर्निहित
/// test-mode (dev_login.dart, कुनै SMS/reCAPTCHA चाहिँदैन) मा जान्छ — बटन
/// र OTP screen दुवै उस्तै काम गर्छन्, केवल वास्तविक SMS भन्दा free
/// bypass प्रयोग हुन्छ। प्रोडक्सनमा साँचो SMS चाहिएपछि यसलाई मात्र `true`
/// पार्नुहोस् (Firebase Console मा Phone sign-in enable + SHA-1/domain
/// setup पूरा भएपछि) — बाँकी कोड उस्तै रहन्छ।
///
/// ── SECURITY: release-build safety net ──────────────────────────────
/// यो `false` ले test-mode OTP (जुनसुकै नम्बर + सार्वजनिक रूपमा देखिने
/// code 123456, dev_login.dart::kTestCode) सक्रिय गर्छ — फोन नम्बर मात्र
/// थाहा भए (real SMS नै नचाहिने) अर्को कसैको पहिल्यैको खाता कब्जा गर्न
/// दिन्छ (dev_login.dart ले उही नम्बरको पुरानो profile/provider doc
/// auto-migrate/claim गर्छ)। यो manually production-release अघि `true`
/// पार्नुपर्ने थियो, तर बिर्सिहाले (वा debug APK नै साँचो प्रयोगकर्तालाई
/// बाँडिहाले) यो खतरनाक hole चुपचाप live रहन्थ्यो। अब `kReleaseMode` मा
/// जहिले पनि जबरजस्ती `true` — release build मा तलको `false` जे भए पनि
/// साँचो SMS नै अनिवार्य हुन्छ, debug/profile build (development/testing)
/// मा मात्र सस्तो test-code bypass चल्छ।
const bool _kUseRealPhoneSmsDebugToggle = false;
bool get kUseRealPhoneSms => kReleaseMode || _kUseRealPhoneSmsDebugToggle;

/// ── Hidden Admin Gateway ─────────────────────────────────────────────────
/// एउटै ठाउँमा (single source of truth) — `app.dart` (कसलाई Owner Dashboard
/// देखाउने) र `auth/admin_gate_page.dart` (Google sign-in पछि यही इमेल
/// नमिले तुरुन्तै sign-out) दुवैले यहीँबाट पढ्छन्, कतै हार्डकोड दोहोरिँदैन।
const String kAdminEmail = 'bikashbhandari1825@gmail.com';

/// सामान्य "Continue with phone" फिल्डमै यो ठ्याक्कै नम्बर (कुनै पनि देश
/// कोडसँग, राष्ट्रिय अंक मात्र तुलना गरिन्छ) हाले मात्र गुप्त Admin Gate
/// खुल्छ — UI मा कतै यसको संकेत/लिङ्क/बटन देखिँदैन। हेर्नुहोस्
/// `auth/phone_input_page.dart::_continue()`।
const String kAdminSecretPhoneDigits = '9848391825';

// Web OAuth client ID — यो lib/firebase_options.dart कै project
// (504837034251 / kaammitra-87e38) को हुनुपर्छ। मोबाइलमा मात्र
// google_sign_in लाई चाहिन्छ। auth_page.dart र auth/admin_gate_page.dart
// दुवैले यहीँबाट प्रयोग गर्छन् — दोहोरिँदैन।
const String kGoogleWebClientId =
    '504837034251-h3ol9ehaksf1biicqgig2o5hn6fv14u2.apps.googleusercontent.com';

/// KaamMitra ले हरेक पूरा भएको कामबाट लिने कमिसन (०.१० = १०%)।
/// एउटै ठाउँमा — earnings/wallet हिसाब यहीँबाट आउँछ।
const double kCommissionRate = 0.10;

/// "Top Worker" badge पाउन चाहिने न्यूनतम — औसत रेटिङ र समीक्षा संख्या।
const double kTopWorkerMinRating = 4.5;
const int kTopWorkerMinReviews = 5;

/// Contact Support नम्बर — Firestore: config/support { phone: "..." }
class SupportConfig {
  SupportConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('support');

  /// Live support नम्बर (सेट नभए null/खाली)।
  static Stream<String> phoneStream() => _doc.snapshots().map((s) {
        final data = s.data();
        return (data?['phone'] ?? '').toString().trim();
      });

  static Future<String> phoneOnce() async {
    final s = await _doc.get();
    return (s.data()?['phone'] ?? '').toString().trim();
  }

  /// Admin ले नम्बर सेट/अपडेट गर्ने।
  static Future<void> setPhone(String phone) => _doc.set(
        {'phone': phone.trim(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
}

/// Help & Support screen का लामो text (Service Standard, Privacy Policy,
/// Data Security, FAQ) — Firestore: config/helpContent। पहिले यी सबै
/// `content/legal_text.dart` मा hardcoded थिए (बदल्न नयाँ app release
/// चाहिने) — अब SupportConfig कै उस्तै ढाँचामा admin ले Owner Dashboard
/// बाटै, कुनै नयाँ release बिनै, तुरुन्तै सम्पादन गर्न सक्छ। कुनै field
/// खाली/नसेट भए (पहिलोपटक कहिल्यै सम्पादन नगरे पनि) `LegalText` कै मूल
/// (default) copy नै देखिन्छ — help_support_screen.dart मा हेर्नुहोस्।
class HelpContentConfig {
  HelpContentConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('helpContent');

  static Stream<Map<String, dynamic>> stream() =>
      _doc.snapshots().map((s) => s.data() ?? const {});

  static Future<Map<String, dynamic>> once() async {
    final s = await _doc.get();
    return s.data() ?? const {};
  }

  /// एउटा text field (जस्तै 'serviceStandardEn') सेट/अपडेट गर्ने।
  static Future<void> setField(String key, String value) => _doc.set(
        {key: value, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  /// FAQ सूची पूरै (add/edit/delete सबै) एकैचोटि replace गर्ने — प्रत्येक
  /// entry: {qEn, qNe, aEn, aNe}।
  static Future<void> setFaq(List<Map<String, String>> faq) => _doc.set(
        {'faq': faq, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  /// Editor screen कै "Save All" — सबै text field + FAQ एकैचोटि एउटै
  /// write मा।
  static Future<void> saveAll(Map<String, dynamic> fields) => _doc.set(
        {...fields, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
}

/// WebRTC कल (audio/video) का STUN/TURN server — Firestore:
/// config/webrtc { iceServers: [ { urls, username?, credential? }, ... ] }
///
/// किन Firestore मा (हार्डकोड होइन): TURN relay प्रोडक्सन-स्तरको (जस्तै
/// Twilio/Cloudflare Calls, महिनैपिच्छे GB-अनुसार शुल्क लाग्ने) मा
/// अपग्रेड गर्दा owner ले नयाँ app release/build बिनै, यहीँ Firestore
/// doc अपडेट गरेर तुरुन्तै लागू गर्न सकून् भनेर। doc नभए वा खाली भए
/// [defaultIceServers] (हाल free/public relay) प्रयोग हुन्छ — पहिलोपटक
/// कहिल्यै नसेट गरे पनि कल चल्न रोकिँदैन।
class WebRtcConfig {
  WebRtcConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('webrtc');

  static const Map<String, dynamic> defaultIceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  /// [CallSession.start()] ले हरेक कल सुरु हुँदा एकपटक पढ्छ।
  static Future<Map<String, dynamic>> iceServersOnce() async {
    try {
      final s = await _doc.get();
      final list = s.data()?['iceServers'];
      if (list is List && list.isNotEmpty) {
        return {'iceServers': list};
      }
    } catch (_) {
      // पढ्न नसके पनि कल अड्किनु हुँदैन — default मै अगाडि बढ्ने।
    }
    return defaultIceServers;
  }

  /// Admin ले नयाँ TURN provider (जस्तै Twilio/Cloudflare Calls) मा
  /// अपग्रेड गर्दा — प्रत्येक [entries] item मा `urls` (required) र
  /// ऐच्छिक `username`/`credential`।
  static Future<void> setIceServers(
          List<Map<String, dynamic>> entries) =>
      _doc.set({
        'iceServers': entries,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

/// In-app auto-update checker (Android APK) — Firestore: config/appUpdate
/// { latestVersionCode: int, versionName: string, apkUrl: string,
///   releaseNotes: string, forceUpdate: bool }
/// `services/app_update_service.dart` ले app startup मा यही doc पढेर हालको
/// installed versionCode सँग तुलना गर्छ — Admin Dashboard बाट owner ले नयाँ
/// APK release गर्दा यहीं update गर्नुपर्छ (Firebase Console बाट पनि मिल्छ)।
class AppUpdateConfig {
  AppUpdateConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('appUpdate');

  static Future<Map<String, dynamic>?> readOnce() async {
    final s = await _doc.get();
    return s.data();
  }

  static Stream<Map<String, dynamic>?> stream() =>
      _doc.snapshots().map((s) => s.data());

  /// Admin ले नयाँ release publish गर्दा — [apkUrl] Firebase Storage वा
  /// अरू जुनसुकै सिधा-download URL हुन सक्छ।
  static Future<void> publish({
    required int latestVersionCode,
    required String versionName,
    required String apkUrl,
    String releaseNotes = '',
    bool forceUpdate = false,
  }) =>
      _doc.set({
        'latestVersionCode': latestVersionCode,
        'versionName': versionName.trim(),
        'apkUrl': apkUrl.trim(),
        'releaseNotes': releaseNotes.trim(),
        'forceUpdate': forceUpdate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
