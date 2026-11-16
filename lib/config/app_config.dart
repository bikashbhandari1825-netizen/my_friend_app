// config/app_config.dart
// App owner ले बदल्न सक्ने setting हरू (Firestore `config` collection मा)।
import 'dart:async';
import 'dart:convert' show utf8;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' show sha256;

/// ── टेस्टिङ चरण auth toggle ──────────────────────────────────────────────
/// Google Sign-In फेरि सक्रिय गरिएको छ — physical device मा live SHA-1 +
/// signInWithCredential root-cause debug गरेर पुष्टि भइसक्यो (काम गर्छ,
/// नेटवर्क slow भएमा केही सेकेन्ड लाग्न सक्छ, त्यसैले button मा अब busy/
/// spinner राखिएको छ ताकि user "केही भएन" भनेर बीचमै app बाट बाहिरिएर
/// प्रक्रिया नरोकियोस्)। साथै Email/Password login असफल हुँदा देखिने hint
/// (`login_no_match_hint`) ले नै "Google बाट जारी राख्नुहोस्" भन्छ — त्यो
/// बटन लुकाइराखे hint अर्थहीन हुन्थ्यो। `false` पार्दा बटन फेरि लुक्छ।
const bool kEnableGoogleSignIn = true;

/// "Continue with phone number" बटन थिचेर नम्बर हालेपछि साँचो Firebase
/// Phone Auth (SMS + reCAPTCHA, हेर्नुहोस् तलको `kUseRealPhoneSms`) चल्छ।
const bool kEnablePhoneAuth = true;

/// साँचो Firebase Phone Auth (SMS + reCAPTCHA) सधैँ प्रयोग हुन्छ — debug
/// build समेत। test-mode bypass (dev_login.dart::kTestCode) हटाइएको छ,
/// केवल फोन नम्बर थाहा पाएर अर्को कसैको खाता कब्जा गर्न सकिने सुरक्षा-प्वाल
/// अब कुनै build मा सम्भव छैन।
const bool kUseRealPhoneSms = true;

/// ── Hidden Admin Gateway ─────────────────────────────────────────────────
/// एउटै ठाउँमा (single source of truth) — `app.dart` (कसलाई Owner Dashboard
/// देखाउने) र `auth/admin_gate_page.dart` (Google sign-in पछि यही इमेल
/// नमिले तुरुन्तै sign-out) दुवैले यहीँबाट पढ्छन्, कतै हार्डकोड दोहोरिँदैन।
const String kAdminEmail = 'bikashbhandari1825@gmail.com';

/// सामान्य "Continue with phone" फिल्डमै यो ठ्याक्कै नम्बर (कुनै पनि देश
/// कोडसँग, राष्ट्रिय अंक मात्र तुलना गरिन्छ) हाले मात्र गुप्त Admin Gate
/// खुल्छ — UI मा कतै यसको संकेत/लिङ्क/बटन देखिँदैन। हेर्नुहोस्
/// `auth/phone_input_page.dart::_continue()`।
///
/// सुरक्षा — नम्बर आफैं (plain text) अब एपमा राखिएको छैन, केवल यसको SHA-256
/// hash; APK निकालेर नम्बर सीधै पढ्न नमिल्ने। (१० अङ्कको नम्बर hash भए पनि
/// brute-force हुन सक्छ — त्यसैले यो गोप्यता मात्र हो, साँचो सुरक्षा admin को
/// Google खाता + verified email + Firestore rules हुन्; यही नम्बर अब
/// अपरिवर्तनीय रूपमा "खुला" मान्नुहोस् र आवश्यक भए बदल्नुहोस्।)
const String kAdminSecretPhoneSha256 =
    'c3076ea526bb9d74bfa44244f3b145e7de81c0cc4091125ea34413168107fa22';

/// [digits] (राष्ट्रिय अङ्क मात्र) गुप्त Admin Gate को नम्बर हो कि।
bool isAdminGatePhone(String digits) =>
    sha256.convert(utf8.encode('sahyatri-admin-gate:$digits')).toString() ==
    kAdminSecretPhoneSha256;

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

/// अनुमानित भाडा (`estimateFare`, screens/nearby_common.dart) को दर — Firestore:
/// config/fareMatrix { baseByService: {mechanic: 400, ...}, perKm: 35,
/// perMinute: 3, minimumFare: 100, roundTo: 50 }। पहिले यी सबै दर सिधै
/// `estimateFare()` भित्रै hardcoded थिए — owner ले भाडा बदल्न चाहँदा नयाँ
/// app release नै चाहिन्थ्यो। अब owner dashboard बाटै (कुनै release बिनै)
/// बदल्न सकिने।
///
/// `estimateFare()` भने अझै पूर्ण रूपमा synchronous नै रहन्छ (UI build/
/// gesture भित्रैबाट सिधै कल हुने भएकोले) — यहाँ Firestore बाट पढेको मान
/// app startup मै एकपटक (`preload()`, main.dart) background मा
/// cache हुन्छ; त्यो नआएसम्म/असफल भए वा doc नै नभए तलकै [defaultBaseByService]
/// (उही पुरानो दर) प्रयोग हुन्छ — भाडा गणना कहिल्यै कुनै network/await
/// पर्खिँदैन।
class FareMatrixConfig {
  FareMatrixConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('fareMatrix');

  static const Map<String, int> defaultBaseByService = {
    'mechanic': 400,
    'plumber': 500,
    'electrician': 500,
    'carpenter': 600,
    'painter': 800,
    'cleaner': 700,
    'driver': 250,
    'bike': 150,
    'car': 350,
    'auto': 250,
    'tutor': 500,
  };
  static const int defaultPerKm = 35;
  // यात्रा-समय (OSRM/Directions बाट, `RoadRoute.minutes`) अनुसार थप शुल्क —
  // ट्राफिकमा अडिएर लामो समय लागे पनि worker/driver लाई उचित मूल्य पाओस्।
  static const int defaultPerMinute = 3;
  // दूरी/समय जतिसुकै छोटो भए पनि यसभन्दा तल भाडा कहिल्यै नझरोस्।
  static const int defaultMinimumFare = 100;
  static const int defaultRoundTo = 50;
  // रातको समय (defaultNightStartHour देखि defaultNightEndHour सम्म, अर्को
  // दिनसम्म फैलिने) मा लाग्ने थप शुल्क — estimateFare() (nearby_common.dart)
  // ले नै लागू गर्छ।
  static const double defaultNightSurchargeMultiplier = 1.25;
  static const int defaultNightStartHour = 21;
  static const int defaultNightEndHour = 6;

  static Map<String, int>? _baseByService;
  static int? _perKm;
  static int? _perMinute;
  static int? _minimumFare;
  static int? _roundTo;
  static double? _nightSurchargeMultiplier;
  static int? _nightStartHour;
  static int? _nightEndHour;

  /// हाल effective दर — Firestore बाट cache भइसकेको भए त्यही, नत्र default।
  static Map<String, int> get baseByService =>
      _baseByService ?? defaultBaseByService;
  static int get perKm => _perKm ?? defaultPerKm;
  static int get perMinute => _perMinute ?? defaultPerMinute;
  static int get minimumFare => _minimumFare ?? defaultMinimumFare;
  static int get roundTo => _roundTo ?? defaultRoundTo;
  static double get nightSurchargeMultiplier =>
      _nightSurchargeMultiplier ?? defaultNightSurchargeMultiplier;
  static int get nightStartHour => _nightStartHour ?? defaultNightStartHour;
  static int get nightEndHour => _nightEndHour ?? defaultNightEndHour;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// App startup मा एकपटक (fire-and-forget, `main.dart` हेर्नुहोस्) — तर
  /// एकपटकको `.get()` होइन, live `.snapshots()` listener: admin ले owner
  /// dashboard बाट (`FareMatrixEditorScreen`) नयाँ दर save गरेपछि, यो
  /// listener चलिरहेको जुनसुकै अर्को (passenger/worker) device को app
  /// (नयाँ install/restart नगरिकनै) केही सेकेन्डभित्रै त्यही नयाँ दर
  /// स्वतः पाउँछ — अर्को कुनै fare गणना (उदाहरण: अर्को worker card
  /// देखाउँदा) मा तुरुन्तै लागू हुन्छ। पढ्न नसके/doc नभए/network नभएमा
  /// चुपचाप default मै रहन्छ, कुनै हालतमा app launch रोकिँदैन। फर्काएको
  /// Future पहिलो snapshot (वा त्रुटि) आएपछि मात्र पूरा हुन्छ — त्यसपछि
  /// पनि subscription जिउँदै रहन्छ (app कै पूरै lifetime भरि)।
  static Future<void> preload() {
    final completer = Completer<void>();
    _sub?.cancel();
    _sub = _doc.snapshots().listen(
      (snap) {
        final data = snap.data();
        if (data != null) {
          final base = data['baseByService'];
          if (base is Map) {
            _baseByService = base.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
          }
          final perKm = data['perKm'];
          if (perKm is num) _perKm = perKm.toInt();
          final perMinute = data['perMinute'];
          if (perMinute is num) _perMinute = perMinute.toInt();
          final minimumFare = data['minimumFare'];
          if (minimumFare is num) _minimumFare = minimumFare.toInt();
          final roundTo = data['roundTo'];
          if (roundTo is num) _roundTo = roundTo.toInt();
          final nightMult = data['nightSurchargeMultiplier'];
          if (nightMult is num) _nightSurchargeMultiplier = nightMult.toDouble();
          final nightStart = data['nightStartHour'];
          if (nightStart is num) _nightStartHour = nightStart.toInt();
          final nightEnd = data['nightEndHour'];
          if (nightEnd is num) _nightEndHour = nightEnd.toInt();
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        // network/permission जे भए पनि — default दर सधैँ काम गर्छ।
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Admin ले owner dashboard बाट नयाँ दर सेट गर्दा।
  static Future<void> setMatrix({
    required Map<String, int> baseByService,
    required int perKm,
    required int perMinute,
    required int minimumFare,
    required int roundTo,
    required double nightSurchargeMultiplier,
    required int nightStartHour,
    required int nightEndHour,
  }) async {
    await _doc.set({
      'baseByService': baseByService,
      'perKm': perKm,
      'perMinute': perMinute,
      'minimumFare': minimumFare,
      'roundTo': roundTo,
      'nightSurchargeMultiplier': nightSurchargeMultiplier,
      'nightStartHour': nightStartHour,
      'nightEndHour': nightEndHour,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _baseByService = baseByService;
    _perKm = perKm;
    _perMinute = perMinute;
    _minimumFare = minimumFare;
    _roundTo = roundTo;
    _nightSurchargeMultiplier = nightSurchargeMultiplier;
    _nightStartHour = nightStartHour;
    _nightEndHour = nightEndHour;
  }

  /// Admin edit-screen ले हाल के दर लागू छ भनेर पढ्न (Firestore बाट सधैँ
  /// ताजा, `preload()` कै cache भरमा होइन)।
  static Future<Map<String, dynamic>> readOnce() async {
    final s = await _doc.get();
    return s.data() ?? const {};
  }
}

/// Centralized Payment/Commission Settings — Firestore: config/payments
/// { commissionRate, esewaEnabled, esewaMerchantId, khaltiEnabled,
///   khaltiMerchantId, bankEnabled, bankName, bankAccountName,
///   bankAccountNumber, connectIpsId }
///
/// पहिले commission rate (`kCommissionRate`) र gateway credential/toggle
/// कतै Firestore मा थिएनन् — सिधै code भित्रै hardcoded थिए, बदल्न नयाँ app
/// release नै चाहिन्थ्यो। `FareMatrixConfig` कै उही ढाँचामा — owner ले
/// Admin Dashboard बाटै (कुनै release बिनै) commission % बदल्न, र
/// eSewa/Khalti/Bank मध्ये कुन देखाउने/लुकाउने (जस्तै merchant अझै तयार
/// नभएको gateway अस्थायी रूपमा निष्क्रिय पार्न) रोज्न सक्छन्। `preload()`
/// नआएसम्म/असफल भए तलकै [defaultCommissionRate] (उही पुरानो १०%) प्रयोग
/// हुन्छ — commission गणना कहिल्यै network/await पर्खिँदैन।
class PaymentConfig {
  PaymentConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('payments');

  static const double defaultCommissionRate = kCommissionRate;
  // Worker को walletBalance (ऋणात्मक = प्रणालीलाई तिर्न बाँकी commission)
  // यो magnitude भन्दा बढी ऋणी भएमा मात्र नयाँ काम लिन रोकिन्छ — payout
  // बाँकी भएको (धनात्मक) worker कहिल्यै रोकिँदैन। `isEligibleForJobs`
  // (users/{uid}) हेर्नुहोस् — widgets/complete_job_sheet.dart र
  // screens/admin_settlement_screen.dart ले नै गणना/लेख्छन्।
  static const double defaultMinimumWalletThreshold = 100.0;

  static double? _commissionRate;
  static double? _minimumWalletThreshold;
  static bool _esewaEnabled = true;
  static bool _khaltiEnabled = true;
  static bool _bankEnabled = true;
  static String _esewaMerchantId = '';
  static String _khaltiMerchantId = '';
  static String _bankName = '';
  static String _bankAccountName = '';
  static String _bankAccountNumber = '';
  static String _connectIpsId = '';

  static double get commissionRate => _commissionRate ?? defaultCommissionRate;
  static double get minimumWalletThreshold =>
      _minimumWalletThreshold ?? defaultMinimumWalletThreshold;
  static bool get esewaEnabled => _esewaEnabled;
  static bool get khaltiEnabled => _khaltiEnabled;
  static bool get bankEnabled => _bankEnabled;
  static String get esewaMerchantId => _esewaMerchantId;
  static String get khaltiMerchantId => _khaltiMerchantId;
  static String get bankName => _bankName;
  static String get bankAccountName => _bankAccountName;
  static String get bankAccountNumber => _bankAccountNumber;
  static String get connectIpsId => _connectIpsId;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// App startup मा एकपटक (fire-and-forget, `main.dart`) — live listener,
  /// `FareMatrixConfig.preload()` कै उस्तै व्यवहार (हेर्नुहोस् त्यहाँको
  /// टिप्पणी)।
  static Future<void> preload() {
    final completer = Completer<void>();
    _sub?.cancel();
    _sub = _doc.snapshots().listen(
      (snap) {
        final data = snap.data();
        if (data != null) {
          final rate = data['commissionRate'];
          if (rate is num) _commissionRate = rate.toDouble();
          final threshold = data['minimumWalletThreshold'];
          if (threshold is num) _minimumWalletThreshold = threshold.toDouble();
          _esewaEnabled = (data['esewaEnabled'] as bool?) ?? true;
          _khaltiEnabled = (data['khaltiEnabled'] as bool?) ?? true;
          _bankEnabled = (data['bankEnabled'] as bool?) ?? true;
          _esewaMerchantId = (data['esewaMerchantId'] ?? '').toString();
          _khaltiMerchantId = (data['khaltiMerchantId'] ?? '').toString();
          _bankName = (data['bankName'] ?? '').toString();
          _bankAccountName = (data['bankAccountName'] ?? '').toString();
          _bankAccountNumber = (data['bankAccountNumber'] ?? '').toString();
          _connectIpsId = (data['connectIpsId'] ?? '').toString();
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Admin editor screen ले हाल के सेटिङ लागू छ भनेर पढ्न (सधैँ ताजा)।
  static Future<Map<String, dynamic>> readOnce() async {
    final s = await _doc.get();
    return s.data() ?? const {};
  }

  /// Admin ले owner dashboard बाट नयाँ commission rate/gateway सेटिङ save
  /// गर्दा — cache तुरुन्तै अपडेट, अरू device ले live listener मार्फत पाउँछन्।
  static Future<void> setPaymentSettings({
    required double commissionRate,
    required double minimumWalletThreshold,
    required bool esewaEnabled,
    required String esewaMerchantId,
    required bool khaltiEnabled,
    required String khaltiMerchantId,
    required bool bankEnabled,
    required String bankName,
    required String bankAccountName,
    required String bankAccountNumber,
    required String connectIpsId,
  }) async {
    await _doc.set({
      'commissionRate': commissionRate,
      'minimumWalletThreshold': minimumWalletThreshold,
      'esewaEnabled': esewaEnabled,
      'esewaMerchantId': esewaMerchantId,
      'khaltiEnabled': khaltiEnabled,
      'khaltiMerchantId': khaltiMerchantId,
      'bankEnabled': bankEnabled,
      'bankName': bankName,
      'bankAccountName': bankAccountName,
      'bankAccountNumber': bankAccountNumber,
      'connectIpsId': connectIpsId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _commissionRate = commissionRate;
    _minimumWalletThreshold = minimumWalletThreshold;
    _esewaEnabled = esewaEnabled;
    _khaltiEnabled = khaltiEnabled;
    _bankEnabled = bankEnabled;
    _esewaMerchantId = esewaMerchantId;
    _khaltiMerchantId = khaltiMerchantId;
    _bankName = bankName;
    _bankAccountName = bankAccountName;
    _bankAccountNumber = bankAccountNumber;
    _connectIpsId = connectIpsId;
  }
}

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

/// सामाजिक सञ्जाल लिंक (Facebook/Instagram/TikTok/X) — Firestore:
/// config/socialLinks { facebook, instagram, tiktok, twitter }। Home
/// screen को promo banner (`_SocialLinksRow`, home_screen.dart) मा देखिने
/// बटनले यहीँबाट पढ्छन् (खाली भएको प्लेटफर्म देखिँदैन); Owner Dashboard
/// बाट admin ले `SupportConfig` कै उस्तै ढाँचामा अपडेट गर्न सक्छ।
class SocialLinksConfig {
  SocialLinksConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('socialLinks');

  static Map<String, String> _fromData(Map<String, dynamic>? data) => {
        'facebook': (data?['facebook'] ?? '').toString().trim(),
        'instagram': (data?['instagram'] ?? '').toString().trim(),
        'tiktok': (data?['tiktok'] ?? '').toString().trim(),
        'twitter': (data?['twitter'] ?? '').toString().trim(),
      };

  static Stream<Map<String, String>> stream() =>
      _doc.snapshots().map((s) => _fromData(s.data()));

  static Future<Map<String, String>> readOnce() async {
    final s = await _doc.get();
    return _fromData(s.data());
  }

  /// Admin ले owner dashboard बाट ४ वटै URL सँगसँगै सेट/अपडेट गर्ने।
  static Future<void> setLinks({
    required String facebook,
    required String instagram,
    required String tiktok,
    required String twitter,
  }) =>
      _doc.set({
        'facebook': facebook.trim(),
        'instagram': instagram.trim(),
        'tiktok': tiktok.trim(),
        'twitter': twitter.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

  // NAT Traversal Resilience — पहिले TURN भनेर एउटै provider को केवल दुई
  // plain (UDP/TCP) entry मात्र थियो। धेरै mobile-carrier NAT/restrictive
  // WiFi (विशेष गरी corporate/hostel networks) ले plain TURN (port 80/443
  // भए पनि UDP/TCP raw traffic) समेत ब्लक गर्छन् — त्यसबेला STUN ले host/
  // srflx candidate त फेला पार्छ (signaling/SDP exchange सामान्य देखिन्छ),
  // तर कुनै candidate pair साँच्चै जोडिन नसक्दा ICE सधैँ "checking" मै
  // अड्किन्छ — ठ्याक्कै "Connecting... देखाइरहने, कालो स्क्रिन, कुनै
  // audio/video नआउने" गुनासोको मुख्य सम्भावित कारण। `turns:` (TURN-over-
  // TLS, port 443) चाहिँ HTTPS जस्तै देखिने भएकोले लगभग कुनै पनि firewall
  // ले ब्लक गर्दैन — त्यही थपिएको। साथै एउटै provider नै down/rate-limited
  // भए पनि (free/public service, guarantee छैन) थप STUN redundancy।
  static const Map<String, dynamic> defaultIceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
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
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turns:openrelay.metered.ca:443?transport=tcp',
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
  static Future<void> setIceServers(List<Map<String, dynamic>> entries) =>
      _doc.set({
        'iceServers': entries,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

/// In-app auto-update checker (Android APK) — Firestore: config/appUpdate
/// { latestVersionCode: int, versionName: string, apkUrl: string,
///   apkSha256: string (64-hex, अनिवार्य — नभए अपडेट देखिँदैन),
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
    required String apkSha256,
    String releaseNotes = '',
    bool forceUpdate = false,
  }) =>
      _doc.set({
        'latestVersionCode': latestVersionCode,
        'versionName': versionName.trim(),
        'apkUrl': apkUrl.trim(),
        'apkSha256': apkSha256.trim().toLowerCase(),
        'releaseNotes': releaseNotes.trim(),
        'forceUpdate': forceUpdate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
