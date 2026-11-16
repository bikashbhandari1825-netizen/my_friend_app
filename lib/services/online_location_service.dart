// services/online_location_service.dart
//
// "Online" भएका (स्वीकृत) कामदार/driver को असली, लाइभ स्थान `registeredWorkers`
// (र `users`) मा लगातार अपडेट गर्ने — Home नक्सामा driver को आइकन उसको
// साँचो GPS स्थानमा चलोस् भनेर।
//
// पहिले यी फिल्ड (`lat/lng/locationUpdatedAt`) केवल Online toggle थिच्दा वा
// dashboard खोल्दा एकपटक मात्र लेखिन्थे, त्यसैले driver सडकमा चल्दा पनि Home
// नक्सामा आइकन पुरानै ठाउँमा अडिएर बस्थ्यो। (सक्रिय ride भित्रको लाइभ स्थान
// `serviceRequests.workerLat/Lng` मा अलग लेखिन्छ — यो त्यसको सट्टा होइन।)
//
// नियम:
//   • केवल role == worker, verification == approved, र isOnline != false;
//   • २५ मिटर चलेपछि मात्र नयाँ GPS, र लेखाइ कम्तिमा १५ सेकेन्डको अन्तरमा
//     (Firestore खर्च/ब्याट्री सीमित);
//   • Android मा सूचना-सहितको foreground service — एप minimize भए पनि चल्न;
//   • स्थान अनुमति नभए केही गर्दैन (यहाँ अनुमति माग्दैन); Web मा चल्दैन।
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class OnlineLocationService {
  OnlineLocationService._();

  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  static StreamSubscription<Position>? _posSub;
  static bool _starting = false;
  static String? _uid;
  static List<DocumentReference<Map<String, dynamic>>>? _rwRefs;
  static DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  // एक्लो developer का लागि: `--dart-define=SIM_GPS=1` (debug/profile मात्र) —
  // असली GPS को सट्टा driver ले ~४०० मिटरको वर्गाकार बाटो आफैं हिँडेको नक्कल
  // गर्छ (कोठामै बसेर Home नक्सामा आइकन सरेको हेर्न)। release मा कहिल्यै चल्दैन।
  // नोट: `bool.fromEnvironment` ले केवल "true" मान्छ, "1" होइन — त्यसैले
  // String मा जाँचिन्छ (`SIM_GPS=1` वा `SIM_GPS=true` दुवै चल्छ)।
  static const bool _simEnabled = String.fromEnvironment('SIM_GPS') == '1' ||
      String.fromEnvironment('SIM_GPS') == 'true';
  static bool get _sim => _simEnabled && !kReleaseMode;
  static Timer? _simTimer;
  static int _simTick = 0;
  static double _simLat = 27.7172; // काठमाडौँ (असली स्थान भेटिएन भने)
  static double _simLng = 85.3240;

  static Duration get _minWriteGap =>
      _sim ? const Duration(seconds: 3) : const Duration(seconds: 15);

  static void start() {
    if (kIsWeb) return;
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
  }

  static void stop() {
    _authSub?.cancel();
    _authSub = null;
    _userSub?.cancel();
    _userSub = null;
    _stopLocation();
    _uid = null;
    _rwRefs = null;
  }

  static void _onAuth(User? user) {
    _stopLocation();
    _userSub?.cancel();
    _userSub = null;
    _rwRefs = null;
    _uid = user?.uid;
    if (user == null) return;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(_onUser, onError: (_) {});
  }

  static void _onUser(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? const <String, dynamic>{};
    final isWorker = d['role'] == 'worker';
    final approved = (d['verificationStatus'] ??
                d['workerVerificationStatus'] ??
                '')
            .toString() ==
        'approved';
    final online = d['isOnline'] != false;
    if (kDebugMode) {
      debugPrint('ONLINE_LOC user: worker=$isWorker approved=$approved '
          'online=$online');
    }
    if (isWorker && approved && online) {
      _startLocation();
    } else {
      _stopLocation();
    }
  }

  static Future<void> _startLocation() async {
    if (_posSub != null || _starting || _simTimer != null) return;
    _starting = true;
    try {
      if (_sim) {
        await _startSimulation();
        return;
      }
      final perm = await Geolocator.checkPermission();
      if (kDebugMode) debugPrint('ONLINE_LOC permission=$perm');
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return; // अनुमति यहाँ माग्दैनौँ।
      }
      final LocationSettings settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 25,
              foregroundNotificationConfig: ForegroundNotificationConfig(
                notificationTitle: S.locationTrackingNotifTitle,
                notificationText: S.locationTrackingNotifBody,
                notificationChannelName: 'सहयात्री Location',
                notificationIcon: const AndroidResource(
                    name: 'ic_launcher', defType: 'mipmap'),
                color: AppColors.igViolet,
                setOngoing: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high, distanceFilter: 25);
      _posSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(_onPosition, onError: (e) {
        if (kDebugMode) debugPrint('ONLINE_LOC stream error: $e');
      });
      if (kDebugMode) debugPrint('ONLINE_LOC stream started');
    } catch (e) {
      // अनुमति/service असफल भए चुपचाप — Online toggle को एक-पटके स्थान अझै छ।
      if (kDebugMode) debugPrint('ONLINE_LOC start failed: $e');
    } finally {
      _starting = false;
    }
  }

  static void _stopLocation() {
    _posSub?.cancel();
    _posSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    _starting = false;
  }

  /// नक्कली हिँडाइ — हरेक ३ सेकेन्डमा ~३० मिटर (≈१० मी/से), १३ चरण सीधा
  /// हिँडेर ९०° मोड्ने (वर्गाकार बाटो)।
  static Future<void> _startSimulation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _simLat = last.latitude;
        _simLng = last.longitude;
      }
    } catch (_) {}
    _simTick = 0;
    if (kDebugMode) {
      debugPrint('ONLINE_LOC SIMULATION started at $_simLat,$_simLng');
    }
    _simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      const stepM = 30.0;
      final leg = (_simTick ~/ 13) % 4; // 0: पूर्व, 1: उत्तर, 2: पश्चिम, 3: दक्षिण
      const dLat = stepM / 111000.0;
      final dLng = stepM / (111000.0 * math.cos(_simLat * math.pi / 180));
      switch (leg) {
        case 0:
          _simLng += dLng;
        case 1:
          _simLat += dLat;
        case 2:
          _simLng -= dLng;
        default:
          _simLat -= dLat;
      }
      _simTick++;
      _writeLocation(_simLat, _simLng, 5);
    });
  }

  static Future<void> _onPosition(Position p) =>
      _writeLocation(p.latitude, p.longitude, p.accuracy);

  static Future<void> _writeLocation(
      double lat, double lng, double accuracy) async {
    final uid = _uid;
    if (uid == null) return;
    final now = DateTime.now();
    if (now.difference(_lastWrite) < _minWriteGap) return;
    _lastWrite = now;
    final loc = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    };
    final db = FirebaseFirestore.instance;
    try {
      await db.collection('users').doc(uid).set(loc, SetOptions(merge: true));
      var refs = _rwRefs;
      if (refs == null) {
        final snap = await db
            .collection('registeredWorkers')
            .where('uid', isEqualTo: uid)
            .get();
        refs = snap.docs.map((d) => d.reference).toList();
        _rwRefs = refs;
      }
      for (final r in refs) {
        await r.set(loc, SetOptions(merge: true));
      }
      if (kDebugMode) {
        debugPrint('ONLINE_LOC wrote lat=$lat lng=$lng '
            'acc=${accuracy.toStringAsFixed(0)}m${_sim ? ' (SIM)' : ''} '
            'registeredWorkersDocs=${refs.length}');
      }
    } catch (_) {
      // बेस्ट-इफर्ट — अर्को GPS बिन्दुमा फेरि प्रयास हुन्छ।
      _rwRefs = null;
    }
  }
}
