// config/app_config.dart
// App owner ले बदल्न सक्ने setting हरू (Firestore `config` collection मा)।
import 'package:cloud_firestore/cloud_firestore.dart';

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
const bool kUseRealPhoneSms = false;

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
