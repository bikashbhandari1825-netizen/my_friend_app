// screens/job_route_screen.dart
// काम स्वीकार गरेपछि तुरुन्तै देखिने नक्सा — कामदारको हालको स्थान ↔ ग्राहकको
// स्थान बीचको सडक मार्ग, ठ्याक्कै दूरी र अनुमानित यात्रा समय। वास्तविक
// नक्सा-रेन्डरिङ (markers/polyline/pulse halo/"Open in Google Maps") साझा
// `route_map_view.dart` को `RouteMapView` बाट — RequestTrackingScreen
// (ग्राहकतर्फ) ले पनि उही widget प्रयोग गर्छ, छुट्टै नक्सा बनाइएको छैन।
//
// सडक मार्ग `nearby_common.dart` कै साझा `fetchRoadRoute()` बाट — पहिले
// Google Directions API (साँचो road route), असफल भए OSRM, त्यो पनि असफल भए
// सीधा रेखा + haversine।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/live_gps_metrics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart';
import '../dead_reckoning.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/success_feedback.dart';
import 'chat_screen.dart';
import 'job_feed_screen.dart' show JobFeedScreen;
import 'job_actions.dart'
    show
        deleteCancelledBooking,
        offerErrorSnackBar,
        otherPartyUid,
        pickCancellationReason,
        startInAppCall,
        takeCancelNoticeReason,
        webSafeTimeout;
import 'nearby_common.dart'
    show
        haversineKm,
        fetchRoadRoute,
        RoadRoute,
        TravelMode,
        TravelModeChips,
        travelModeForVehicle,
        fallbackLat,
        fallbackLng;
import 'route_map_view.dart';

class JobRouteScreen extends StatefulWidget {
  final String requestId;
  final double employerLat;
  final double employerLng;
  final String employerName;
  final String service;
  final String address;
  final String employerPhone;
  // Ride (Bike/Car) मात्र — राइड सुरु (OTP मिलेपछि) भएपछि नक्साको गन्तव्य
  // pickup (माथिको employerLat/Lng) बाट यता (साँचो drop-off) मा सर्छ।
  final double? destinationLat;
  final double? destinationLng;
  final String destinationAddress;

  const JobRouteScreen({
    super.key,
    required this.requestId,
    required this.employerLat,
    required this.employerLng,
    required this.employerName,
    required this.service,
    required this.address,
    this.employerPhone = '',
    this.destinationLat,
    this.destinationLng,
    this.destinationAddress = '',
  });

  @override
  State<JobRouteScreen> createState() => _JobRouteScreenState();
}

class _JobRouteScreenState extends State<JobRouteScreen> {
  late final LatLng _employer = LatLng(widget.employerLat, widget.employerLng);
  // नक्साको हालको गन्तव्य — pickup पुगेर OTP मिलाई राइड सुरु नभएसम्म सधैँ
  // pickup (`_employer`); सुरु भइसकेपछि (ride मात्र) साँचो drop-off तिर सर्छ।
  LatLng get _target {
    if (_isRide &&
        _codeVerified &&
        widget.destinationLat != null &&
        widget.destinationLng != null) {
      return LatLng(widget.destinationLat!, widget.destinationLng!);
    }
    return _employer;
  }

  LatLng? _me;
  // GPS Velocity Fusion — साँचो GPS chip बाट आएको गति/दिशा (Doppler-आधारित,
  // phone physical orientation मा भर नपर्ने — RouteMapView को doc-comment
  // हेर्नुहोस्) — route_map_view.dart ले यिनै प्रयोग गरेर glide-अवधि/bearing
  // अझ सही/तुरुन्तै बनाउँछ। confidence (accuracy) राम्रो नभए null नै
  // रहन्छ — route_map_view.dart ले आफैं पुरानै (travel-mode अनुमान/route-
  // tangent) fallback लागू गर्छ, caller ले केही थप गर्नुपर्दैन। Simulate
  // GPS ले यी कहिल्यै सेट गर्दैन (साँचो GPS होइन) — त्यसैले simulate बेला
  // स्वतः पुरानै व्यवहार (stale/null भए पनि) कायम रहन्छ।
  double? _gpsSpeedMps;
  double? _gpsHeadingDeg;

  // Sensor-Fusion Heading Engine — Ride (Bike/Car) मा मात्र (dead_reckoning.dart
  // को "Mounted-Phone Assumption" doc-comment हेर्नुहोस् — काम-पोर्टल/
  // पैदल काममा यो कहिल्यै सुरु हुँदैन, किनभने त्यहाँ phone साँचो सवारीमा
  // टाँसिएको मान्न मिल्दैन)। `_headingStreamController` ले RouteMapView
  // लाई broadcast stream दिन्छ (`headingOverrideStream`), `_headingEngine`
  // ले gyroscope बाट निरन्तर अपडेट गरेर त्यसैमा पठाउँछ, GPS fix आउँदा
  // `anchorToGps()` ले drift सच्याउँछ।
  HeadingFusionEngine? _headingEngine;
  StreamController<double>? _headingStreamController;
  bool _locationDeniedForever = false;
  // getCurrentLocation() ले दिएको ठ्याक्कै कारण — banner मा generic
  // "location needed" भन्दा स्पष्ट सन्देश देखाउन (fix #4: retry + real reason)।
  String _locationStatus = 'pending';

  RoadRoute? _route;
  bool _loading = true;

  // Full-Journey Preview — pickup तिर आउँदै गर्दा (अझै राइड सुरु नभएको
  // बेला) अन्तिम drop-off सम्मको खण्ड पनि (हल्का/dimmed) देखाउन — यो
  // live-tracking `_route` (माथि, हरेक १५s refresh हुने) जस्तो हैन,
  // pickup/destination दुवै स्थिर coordinate भएकोले एकपटक मात्र चाहिन्छ।
  RoadRoute? _secondLegRoute;
  bool _secondLegFetched = false;

  Future<void> _loadSecondLegIfNeeded() async {
    if (_secondLegFetched ||
        !_isRide ||
        widget.destinationLat == null ||
        widget.destinationLng == null) {
      return;
    }
    _secondLegFetched = true;
    final result = await fetchRoadRoute(
      _employer,
      LatLng(widget.destinationLat!, widget.destinationLng!),
      mode: _mode,
    );
    if (mounted) setState(() => _secondLegRoute = result);
  }

  // Multi-modal यातायात — सामान्य काम (mechanic/plumber) मा worker ले
  // छान्छ, Firestore मा लेखिन्छ ताकि employer (RequestTrackingScreen) ले
  // पनि उही मोड/route देखोस्। Ride (Bike/Car) मा भने picker नै लुकाइएको
  // छ (Strict Vehicle Type Isolation) — त्यसैले सुरुदेखि नै साँचो सवारी-
  // प्रकार अनुसार auto-derive (तल `_isRide` जाँच्नुहोस्), कहिल्यै Firestore
  // को `travelMode` field (जुन राइडमा अब कहिल्यै लेखिँदैन) बाट होइन। यही
  // नहुँदा Bike राइडमा पनि default (`driving`) कै कारण गलत कार-आइकन
  // देखिने बग हुन्थ्यो।
  late TravelMode _mode =
      _isRide ? travelModeForVehicle(widget.service) : TravelMode.driving;
  bool _modeLoadedFromDoc = false;

  // Ride-Start OTP (Bike/Car/Auto) — passenger लाई देखिने ४-अंकको कोड,
  // acceptRideOffer() मा नै generate भइसकेको। यहाँ एकपटक मात्र पढिन्छ
  // (कहिल्यै बदलिँदैन), त्यसैले छुट्टै StreamBuilder नचाहिने — `_loadInitialMode()`
  // कै उही एक-पटके doc-fetch मा साथसाथै।
  bool get _isRide =>
      widget.service == 'Bike' ||
      widget.service == 'Car' ||
      widget.service == 'Auto';
  // Auto-Collapse Summary Card — Uber-style: बाटोमा हिँड्दै गर्दा (pickup
  // तिर) तल्लो card (employer info + Call/Video/Message) ले नक्सा धेरै
  // ढाक्थ्यो। 3.5s निष्क्रियतापछि आफैं स्क्रिनको फेदमुनि सर्छ (मात्र slide,
  // पूरै हटाइँदैन — भित्री सामग्री/OTP controller/focus जस्ताको-त्यस्तै
  // अपरिवर्तित रहन्छ)। नक्सा वा card सँग कुनै पनि अन्तर्क्रिया (tap/drag/
  // OTP typing) ले ३.५s फेरि सुरु गराउँछ — `_registerCardInteraction()`।
  // Ride सुरु भइसकेपछि (OTP/On-Arrival चरण) पनि उस्तै auto-collapse हुन्छ
  // — खाली manual expand (tap/swipe-up) ले फेरि timer सुरु गराउँछ।
  bool _cardCollapsed = false;
  Timer? _autoCollapseTimer;

  // Manual-Hold — driver ले आफैं (tap/swipe-up) card खोलेपछि, पहिले पनि
  // उही पुरानो ३.५s निष्क्रियता-timer फेरि सुरु हुन्थ्यो — अर्थात् driver
  // ले आफैं हेर्न खोलेको केही सेकेन्डमै फेरि आफैं लुक्थ्यो, जुन deliberate
  // "म अहिले हेर्दैछु" कार्यसँग मेल खाँदैनथ्यो। अब manual expand ले कुनै
  // auto-collapse timer नै नसुरु गरी card लाई driver आफैंले तल नताने
  // (swipe-down/`_collapseCard()`) सम्म खुल्लै राख्छ — automatic triggers
  // (geofence auto-expand, verify-linger) भने जस्ताको-त्यस्तै आफ्नै floor/
  // timer सहित चल्छन्, यो flag ले तिनलाई छेक्दैन (ती आफैं फेरि सेट गर्छन्)।
  bool _manualHold = false;

  // Protected-Minimum Collapse Deadline — pickup-arrival auto-expand
  // (तल geofence-entry block हेर्नुहोस्) ले card लाई जबरजस्ती 4s का लागि
  // खुल्ला राख्नुपर्छ। तर यो 4s बीचमै अरू कुनै ठाउँबाट (जस्तै नक्सा/card
  // माथि कुनै छोटो touch, वा फेरि geofence flap हुँदा) `_restartAutoCollapseTimer()`
  // आफ्नै default (3.5s) सहित फेरि बोलाइयो भने, त्यसले यो 4s floor लाई
  // बेवास्ता गरेर छोटो समयमै collapse गराइदिन्थ्यो — ठ्याक्कै "4s भनेको
  // तर लगभग तुरुन्तै collapse भयो" गुनासोको सम्भाव्य जड। अब कुनै पनि
  // restart-call ले यो floor भन्दा चाँडो कहिल्यै collapse नगराओस् भनेर,
  // हरेक पटक "यो call ले माग्ने duration" र "floor सम्मको बाँकी समय" मा
  // जुन बढी हो त्यही प्रयोग हुन्छ।
  DateTime? _minCollapseAt;

  void _restartAutoCollapseTimer(
      {Duration duration = const Duration(milliseconds: 3500)}) {
    _autoCollapseTimer?.cancel();
    if (_manualHold) return;
    var effective = duration;
    final minAt = _minCollapseAt;
    if (minAt != null) {
      final remaining = minAt.difference(DateTime.now());
      if (remaining > effective) effective = remaining;
    }
    _autoCollapseTimer = Timer(effective, () {
      if (mounted && !_manualHold) setState(() => _cardCollapsed = true);
    });
  }

  /// नक्सा वा card सँग interaction भएको संकेत — card हाल देखिँदै छ भने
  /// मात्र timer रिसेट गर्ने (पहिल्यै collapsed भइसकेको बेला कुनै पेन्डिङ
  /// timer नै हुँदैन, रिसेट गर्नुपर्दैन)।
  void _registerCardInteraction() {
    if (_cardCollapsed) return;
    _restartAutoCollapseTimer();
  }

  /// Tap वा swipe-up — collapsed pill बाट फेरि पूरा card देखाउने। अब कुनै
  /// auto-collapse timer नै सुरु नहुने (माथिकै `_manualHold` doc-comment
  /// हेर्नुहोस्) — driver आफैं swipe-down/`_collapseCard()` नगरेसम्म card
  /// खुल्लै बस्छ।
  void _expandCard() {
    if (!_cardCollapsed) return;
    _autoCollapseTimer?.cancel();
    _minCollapseAt = null;
    setState(() {
      _cardCollapsed = false;
      _manualHold = true;
    });
  }

  /// Swipe-down (वा कुनै "collapse" affordance) — driver आफैं card तल
  /// ताने जहिले पनि, जुनसुकै automatic floor/timer भए पनि तुरुन्तै सम्मान
  /// गर्ने (deliberate user action ले सधैं auto-logic लाई override गर्छ)।
  /// collapsed पछि पनि pill बाट फेरि जहिले पनि माथि तान्न/थिच्न मिल्छ।
  void _collapseCard() {
    if (_cardCollapsed) return;
    _autoCollapseTimer?.cancel();
    _minCollapseAt = null;
    setState(() {
      _cardCollapsed = true;
      _manualHold = false;
    });
  }
  final _codeController = TextEditingController();
  // Keyboard/Focus Hardening — स्थिर, आफ्नै `FocusNode` (पहिले कुनै
  // explicit `focusNode` नै थिएन, TextField आफैंले एउटा default/implicit
  // बनाउँथ्यो) — live GPS tick ले यो OTP row भएको parent फेरि-फेरि
  // rebuild गर्दा पनि यही एउटै, स्थिर node कायम रहोस् भनेर, keyboard/focus
  // नहराओस्।
  final _codeFocusNode = FocusNode();
  bool _verifyingCode = false;
  bool _codeVerified = false;
  String? _codeError;

  // Live OTP Match — टाइप गर्दै गर्दा नै (button नथिची) सही/बेठीक जाँच्ने,
  // field रातो/हरियो देखाउन र "Start Ride" बटन सही कोड नभएसम्म disabled
  // राख्न प्रयोग हुन्छ।
  bool get _codeComplete => _codeController.text.trim().length == 4;
  // कोड अब सर्भरमा मात्र जाँचिन्छ (`verifyRideStartCode`) — क्लाइन्टले कोड
  // कहिल्यै पाउँदैन, त्यसैले यहाँ केवल ४ अंक भरिएको मात्र हेर्ने।
  bool get _codeMatches => _codeComplete;

  // `AppColors.success` (0xFFE1306C) साँच्चै हरियो होइन — pink/magenta
  // brand रङ हो, जुन `AppColors.danger` (0xFFFF5A5F, रातो) सँग दृष्टिगत
  // रूपमा लगभग उस्तै देखिन्छ। OTP verified संकेत स्पष्ट रूपमा हरियो नै
  // देखियोस् भनेर यहाँ छुट्टै साँचो हरियो।
  static const _otpVerifiedGreen = Color(0xFF00E676);

  Future<void> _loadInitialMode() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get();
      // राइडमा माथिकै auto-derived (vehicle-प्रकार अनुसार) मोड नै अन्तिम
      // सत्य हो — Firestore को `travelMode` field ले कहिल्यै ओभरराइट
      // नगरोस् (त्यो field राइडमा अब कहिल्यै लेखिँदैन, तर पुरानो/stale
      // मान बचेको भए पनि होस्)।
      // Driving-Only — अब सामान्य (non-ride) काममा पनि Driving नै स्थायी/
      // एकमात्र mode हो (TravelModeChips बाट Walking/Bike चयन गर्ने विकल्प
      // नै हटाइसकियो)। यो fix भन्दा अघि (जब picker थियो) कसैले साँच्चै
      // Walking/Bike छानेर Firestore मा साँचिएको पुरानो/stale मान अझै भेटिए
      // पनि अब फर्काइँदैन — नत्र त्यही पुरानो मान फेरि लोड हुँदा "permanent
      // Driving-only" भन्ने आवश्यकता नै तोडिन्थ्यो।
      if (_isRide) {
        // स्क्रिन फेरि खोलेको बेला (app restart, वा notification बाट फेरि
        // यहीं आइपुगेको) राइड पहिल्यै 'in_progress' भइसकेको भए — arrival/OTP
        // दुवै state फेरि पहिल्यैको स्थितिमा फर्काउने, नत्र नक्साले फेरि
        // गलत pickup-तर्फ हेर्थ्यो।
        final status = (snap.data()?['status'] ?? '').toString();
        if (status == 'in_progress' && mounted) {
          setState(() {
            _arrivalConfirmed = true;
            _codeVerified = true;
          });
        }
      }
    } catch (_) {
    } finally {
      _modeLoadedFromDoc = true;
    }
  }

  Future<void> _setMode(TravelMode m) async {
    if (m == _mode) return;
    setState(() => _mode = m);
    unawaited(FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(widget.requestId)
        .set({'travelMode': m.value}, SetOptions(merge: true)));
    if (_me != null) await _loadRoute();
  }

  // आफ्नो लाइभ स्थान — ग्राहकको स्क्रिनमा लाइभ track होस् भनेर Firestore मा
  // लगातार पठाउने। हरेक अपडेटमा OSRM नहित्याउन time-throttle गरिएको।
  StreamSubscription<Position>? _posSub;
  DateTime? _lastRouteFetch;
  DateTime? _lastWorkerPosWrite;

  // ── Mock Location / GPS Simulator (debug/profile-मात्र, `!kReleaseMode`) ──
  // वास्तविक बाटोमा हिँडेर/गाडी चढेर टेस्ट गर्न नसकिने बेला, नक्सा-जुम,
  // vehicle-animation, र OTP/payment-lock फ्लो ल्यापटप/फोनबाटै बसेर जाँच्न —
  // हालको `_route.points` (साँचो सडक मार्ग) कै दुरी-आधारित इन्टरपोलेसनमा
  // (haversine) एउटा सिंथेटिक LatLng तेस्रो-तेस्रो सेकेन्डमा अगाडि बढाएर
  // साँचो GPS (`_handleNewPosition`) कै उही बाटो (Firestore write, arrival-
  // geofence, OTP, zoom, animation) मार्फत पठाउने — production/release
  // build मा यो पूरै कहिल्यै compile नै हुँदैन (`!kReleaseMode` बेरिएको —
  // profile mode मा पनि उपलब्ध, ताकि release-नजिकको performance मा नै
  // स्मूथनेस जाँच्न सकियोस्)।
  // पहिले Timer.periodic + अलग-अलग "pending"/"target-ref" flag हरूबाट
  // चल्थ्यो — त्यसमा धेरैपटक race condition भेटियो (नयाँ route ल्याउँदाको
  // network-पर्खाइ बीचमा timer ले फेरि tick गरेर पुरानो route/प्रगति
  // मिसिने, बाइक "बीचमै गायब भएर सिधै drop point मा" देखिने गुनासोको जड)।
  // अब एउटै सिंगो async लुप — `await` ले नै route-fetch सकिएसम्म अर्को
  // कुनै step अगाडि नबढोस् भनेर स्वतः ग्यारेन्टी गर्छ, छुट्टै flag/race
  // चाहिँदैन।
  bool _simulating = false;
  double _simProgressKm = 0;
  // Overlapping-Loop Race Fix — पहिले यहाँ कुनै per-run पहिचान थिएन, केवल
  // साझा `_simulating` बुलियन। छिटो-छिटो Start→Stop→Start थिच्दा (पहिलो
  // `fetchRoadRoute` network-पर्खाइ अझै नसकिंदै) दुईवटा `_runSimulationLoop`
  // instance एकैसाथ चलिरहन्थे, दुवैले एउटै साझा `_simProgressKm`/`_route`
  // field लाई स्वतन्त्र रूपमै बदल्दा बाइक एकैचोटि दुई फरक गतिमा/बाटोमा
  // हिँडेको वा अचानक "अडिएको" (freeze) देखिने गुनासोको साँचो जड। अब हरेक
  // Start ले आफ्नै अनौठो `_simRunId` लिन्छ — पुरानो (superseded) loop ले
  // आफ्नो run id अब हालको होइन भनेर थाहा पाउनेबित्तिकै आफैं चुपचाप रोकिन्छ,
  // साझा state कहिल्यै नछोइकन।
  int _simRunId = 0;
  // Test-Mode Pause/Speed — Start/Stop मात्रभन्दा थप नियन्त्रण (बाटोको
  // बीचमा रोकेर स्क्रिन/state जाँच्न, वा छिटो/बिस्तारै हिँडेको अनुभव टेस्ट
  // गर्न)। Pause ले loop चलिरहेकै (tick timing/route अपरिवर्तित) राख्छ,
  // केवल progress अगाडि नबढाउने — Resume गर्दा ठ्याक्कै उही बिन्दुबाट।
  bool _simPaused = false;
  static const _simSpeedOptions = [0.5, 1.0, 2.0, 4.0];
  int _simSpeedIndex = 1; // 1.0x डिफल्ट
  double get _simSpeed => _simSpeedOptions[_simSpeedIndex];

  void _toggleSimulate() {
    if (_simulating) {
      _stopSimulate();
    } else {
      _startSimulate();
    }
  }

  void _startSimulate() {
    // Simulate-GPS-Button-Unresponsive Fix — पहिले यहाँ `_me == null` भए
    // (साँचो GPS fix नपाएको — ठ्याक्कै जुन बेला यो simulator सबैभन्दा
    // बढी चाहिन्छ: permission denied, GPS off, वा indoor टेस्टिङ) बटन
    // नै चुपचाप केही नगरी रोकिन्थ्यो — माथिको `onTap: _me == null ? null
    // : _toggleSimulate` ले InkWell लाई नै disable गरिदिने भएकोले ट्याप
    // गर्दा कुनै प्रतिक्रिया (ripple समेत) नदेखिने, "बटन काम नगरेको"
    // जस्तो देखिने गुनासोको साँचो जड यही थियो। अब साँचो GPS नभेटिए
    // (मात्र) एपभरि पहिल्यैदेखि प्रयोग हुने उही शहर-केन्द्र fallback
    // (`fallbackLat`/`fallbackLng`, job_feed_screen.dart/home_screen.dart
    // कै उस्तै) बाट सिमुलेसन सुरु गरिदिने — बटन सधैं तुरुन्तै प्रतिक्रिया
    // दिन्छ।
    _me ??= const LatLng(fallbackLat, fallbackLng);
    _posSub?.cancel(); // साँचो GPS ले simulated स्थानसँग नलडोस्।
    // Stale-Real-GPS-Velocity Stutter Fix — Simulate सुरु हुनुअघि साँचो GPS
    // ले हिँड्दै/गुडिंदै गर्दाको वास्तविक गति/दिशा (`_gpsSpeedMps`/
    // `_gpsHeadingDeg`) पहिल्यै सेट गरेको भए, यी field हरू `_posSub.cancel()`
    // ले मात्र छोइँदैनथ्यो — उस्तै पुरानै (stale, अब कुनै सेन्सरसँग सम्बन्ध
    // नभएको) मान सिमुलेसनभरि नै route_map_view.dart लाई पुगिरहन्थ्यो। त्यो
    // widget ले glide-अवधि नै यही गतिबाट गणना गर्ने भएकोले (हेर्नुहोस्
    // RouteMapView._startGlideTo) — साँचो गति सिमुलेटरको प्रति-tick दूरी/२s
    // भन्दा फरक भएमा ग्लाइड कहिल्यै ठ्याक्कै tick-अन्तराल (2000ms) नपुग्ने,
    // बीचमा केही समय आइकन अडिएर फेरि उफ्रने (stutter) देखिन्थ्यो — साथै
    // बेअरिङ पनि route-दिशा नभई त्यही पुरानो GPS heading तिर तानिने। अब
    // Simulate सुरु हुनेबित्तिकै यी null मा फर्काइन्छ — route_map_view.dart
    // ले आफैं travel-mode-आधारित अनुमान (जो ठ्याक्कै tick-timing सँग मिल्ने
    // गरी tune गरिएको) र route-tangent बेअरिङमा फर्कन्छ।
    _gpsSpeedMps = null;
    _gpsHeadingDeg = null;
    _simulating = true;
    _simPaused = false;
    final myRunId = ++_simRunId;
    setState(() {});
    unawaited(_runSimulationLoop(myRunId));
  }

  void _stopSimulate() {
    _simulating = false;
    _simPaused = false;
    // अहिले उड्डिरहेको (अझै `fetchRoadRoute` पर्खिरहेको वा tick-बीचमा भएको)
    // loop भए पनि, यसले आफ्नो run id अब stale भएको तुरुन्तै थाहा पाओस्।
    _simRunId++;
    // Glide-Speed Mismatch Fix (माथि `_runSimulationLoop` हेर्नुहोस्) ले
    // सिमुलेसनभर `_gpsSpeedMps` सेट गर्छ — बीचैमै Stop थिचेर साँचो GPS फेरि
    // सुरु गर्दा (तल) त्यो पुरानो (अब कुनै सेन्सरसँग सम्बन्ध नभएको) मान
    // साँचो GPS ले आफ्नै पहिलो confident speed reading नपाउन्जेल glide-
    // duration मा bleed नहोस् भनेर यहीं null मा फर्काइन्छ।
    _gpsSpeedMps = null;
    if (mounted) setState(() {});
    _startLiveTracking(); // साँचो GPS फेरि सुरु।
  }

  void _togglePauseSimulate() {
    if (!_simulating) return;
    setState(() => _simPaused = !_simPaused);
  }

  void _cycleSimSpeed() {
    setState(() =>
        _simSpeedIndex = (_simSpeedIndex + 1) % _simSpeedOptions.length);
  }

  /// Test Mode panel कै साझा pill — Start/Stop/Pause/Resume/Speed चारैले
  /// उस्तै shape/style प्रयोग गर्छन्, यहीं एकै ठाउँमा।
  Widget _simControlChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
          decoration: BoxDecoration(
            color:
                (active ? AppColors.kmOrange : AppColors.kmSurface)
                    .withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: compact ? 14 : 16,
                  color: active ? Colors.white : AppColors.kmText),
              SizedBox(width: compact ? 4 : 6),
              Text(label,
                  style: TextStyle(
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : AppColors.kmText)),
            ],
          ),
        ),
      ),
    );
  }

  static double _routeTotalKm(List<LatLng> pts) {
    double total = 0;
    for (var i = 1; i < pts.length; i++) {
      total += haversineKm(pts[i - 1].latitude, pts[i - 1].longitude,
          pts[i].latitude, pts[i].longitude);
    }
    return total;
  }

  static LatLng? _pointAtDistanceKm(List<LatLng> pts, double distKm) {
    if (pts.isEmpty) return null;
    if (pts.length < 2) return pts.first;
    double acc = 0;
    for (var i = 1; i < pts.length; i++) {
      final segLen = haversineKm(pts[i - 1].latitude, pts[i - 1].longitude,
          pts[i].latitude, pts[i].longitude);
      if (acc + segLen >= distKm) {
        final t = segLen <= 0 ? 0.0 : (distKm - acc) / segLen;
        return LatLng(
          pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * t,
          pts[i - 1].longitude +
              (pts[i].longitude - pts[i - 1].longitude) * t,
        );
      }
      acc += segLen;
    }
    return pts.last;
  }

  /// यो एउटा खण्ड (पिकअपसम्म, वा OTP पछि ड्रपसम्म) को सिंगो सिमुलेसन —
  /// ~25m प्रति ~2000ms step (route_map_view.dart कै glide-duration clamp
  /// सँगै ठ्याक्कै सिंक, हेर्नुहोस् "Glide-Sync Fix" तल — नत्र हरेक glide
  /// बीचैमा काटिन्थ्यो), route-fetch सकिएसम्म (await)
  /// अर्को कुनै step सुरु नहुने (race-मुक्त)। खण्ड सकिएपछि (पिकअप/ड्रप
  /// पुगेपछि) आफैं रोकिन्छ — अर्को खण्ड (OTP पछि ड्रपसम्म) को लागि
  /// प्रयोगकर्ताले फेरि "Simulate GPS" थिच्नुपर्छ, ताकि arrival-confirm/OTP
  /// (जुन प्रयोगकर्ताले आफैं गर्ने हो) बीचमा नपर्खी कुनै auto-continue
  /// लुपले जान नपाओस्।
  Future<void> _runSimulationLoop(int myRunId) async {
    final me = _me;
    if (me == null || !mounted) {
      if (mounted && myRunId == _simRunId) setState(() => _simulating = false);
      return;
    }
    // Instant-Start Fix — पहिले यहाँ सधैं `fetchRoadRoute` (Cloud Function
    // round-trip, 15s सम्मको timeout) लाई unconditionally `await` गरिन्थ्यो
    // — स्क्रिनमा पहिल्यै सहि (`_target` तर्फकै) route देखिइरहेको भए पनि।
    // "Simulate GPS" थिचेको क्षणदेखि बाइक नचल्दासम्मको 15-20s को देखिने
    // ढिलाइको साँचो जड यही नेटवर्क-round-trip थियो, कुनै रेन्डरिङ/tick
    // समस्या होइन। `_route` भने ठ्याक्कै pickup↔drop-off संक्रमण (OTP
    // मिलेपछि `_codeVerified=true` सेट हुने ठ्याक्कै उही setState मा, तल
    // `_verifyRideCode()` हेर्नुहोस्) मै null मा फर्काइन्छ — त्यसैले यहाँ
    // non-null भेटिनु नै त्यो यही `_target` का लागि ताजा हो भन्ने ग्यारेन्टी
    // हो (पुरानो pickup-तर्फको route drop-off मा कहिल्यै bleed हुँदैन,
    // null-reset ले नै छुट्याइदिन्छ)। भेटिएमा सिधै त्यही प्रयोग गरेर बाइक
    // तुरुन्तै चलाउने, अनि ताजा route पृष्ठभूमिमै (नचल्दै) ल्याउने — भेटिएन
    // भने (स्क्रिन भर्खरै खुलेको, वा संक्रमणको साँघुरो झ्यालमै थिचेको) मात्र
    // पहिलेकै जस्तै await गर्ने।
    final cachedRoute = _route;
    RoadRoute route;
    if (cachedRoute != null && cachedRoute.points.length >= 2) {
      route = cachedRoute;
      unawaited(_loadRoute());
    } else {
      // Silent-Freeze Fix — यो cold-start await (माथिकै "Instant-Start Fix"
      // भन्दा बाहिरको, कहिल्यै कुनै route अझै cache नभएको केस — स्क्रिन
      // भर्खरै खोलेर, वास्तविक GPS/route अझै लोड नहुँदै "Simulate GPS"
      // थिचेको बेला) पहिले पूर्ण रूपमा चुपचाप थियो — route_map_view.dart
      // कै आफ्नै प्रमाणित "Finding route…" पंक्ति (`routeLoading`, बुट-टाइम
      // मै पहिल्यैदेखि प्रयोग हुने, हेर्नुहोस् S.findingRoute) यहाँ कहिल्यै
      // सक्रिय हुँदैनथ्यो। Cloud Function round-trip आफैं (१५s सम्मको
      // timeout) ले कहिलेकाहीं धेरै सेकेन्ड लिन सक्ने भएकोले, यो मौनताले
      // नै बाइक "अडकिएको/freeze भएको" जस्तो (वास्तवमा मात्र route लोड
      // हुँदै) देखाउँथ्यो। अब उही पुरानो/प्रमाणित मेकानिजम यहीं पनि।
      if (mounted) setState(() => _loading = true);
      final freshRoute = await fetchRoadRoute(me, _target, mode: _mode);
      // Overlapping-Loop Race Fix — यो `await` भरिमा नै कोही अर्को (पुरानो
      // Stop वा नयाँ Start) ले `_simRunId` बढाइसकेको भए, यो loop अब stale
      // — साझा `_route`/`_simProgressKm` कहिल्यै नछोइकन चुपचाप फर्कने।
      if (myRunId != _simRunId || !mounted) return;
      setState(() => _loading = false);
      if (freshRoute == null || freshRoute.points.length < 2) {
        setState(() => _simulating = false);
        return;
      }
      route = freshRoute;
      setState(() => _route = route);
    }
    _simProgressKm = 0;
    final pts = route.points;
    while (myRunId == _simRunId && mounted) {
      // Pause — loop आफैं चलिरहन्छ (route/tick-timing केही नबिग्रिकन), तर
      // प्रयोगकर्ताले Resume नथिचेसम्म progress अगाडि नबढ्ने — बीचैमा
      // स्क्रिन/map state जाँच्न रोकिन मिल्ने।
      if (_simPaused) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final totalKm = _routeTotalKm(pts);
      // High-Frequency Sampling Pass — पहिले यहाँ 2000ms प्रति-tick मा 25m
      // (= 12.5 मी/से @1x) थियो — route_map_view.dart को glide-duration
      // (distance÷believable-speed, 400-2000ms clamp) ठ्याक्कै त्यो 2000ms
      // सँग मिल्नु *आवश्यक* थियो, नत्र glide चाँडै सकिएर अर्को बिन्दु
      // नआउन्जेल बाइक छोटो समय ठ्याक्कै अडिने (stutter)। अब उही समग्र गति
      // (12.5 मी/से @1x) कायम राखेरै, 4 गुणा बढी बारम्बार (500ms प्रति-tick,
      // 6.25m) साना-साना थोप्ला पठाइन्छ — यसरी हरेक मोड (bike/car/walking)
      // को अनुमानित गतिमा glide-अवधि सधैँ tick-अन्तराल (500ms) भन्दा लामो
      // नै पर्छ (कहिल्यै छोटो होइन), अर्थात् अर्को बिन्दु आउँदा अघिल्लो
      // glide अझै चलिरहेकै हुन्छ (`_startGlideTo` ले हालको एनिमेटेड
      // स्थानबाटै निरन्तर फेरि-लक्ष्य गर्छ) — कुनै पनि हालतमा idle-pause
      // (stutter को साँचो जड) हुनै नसक्ने, speed-table मा भविष्यमा जे बदले
      // पनि।
      const simTickDistanceKm = 0.00625;
      // Glide-Speed Mismatch Fix — यो loop को डिजाइन-अनुमान (माथिको
      // comment) 12.5 मी/से (@1x) मा glide-अवधि tick-अन्तराल (500ms) भन्दा
      // सधैं लामो रहोस् भन्ने हो — तर `route_map_view.dart` को glide-duration
      // ले (`gpsSpeedMps` null हुँदा, अहिलेसम्म simulation मा सधैं null नै
      // रहन्थ्यो, माथि `_startSimulate` हेर्नुहोस्) बाइक-मोडको फरक नै
      // "believable" फलब्याक गति (6.0 मी/से) प्रयोग गर्थ्यो — यी दुई फरक
      // फाइलका दुई फरक संख्या कहिल्यै cross-check नभएको। 1x मा यो margin
      // साँघुरिन्थ्यो, 2x/4x मा glide-duration बारम्बार tick-अन्तराल भन्दा
      // धेरै गुणा लामो हुन्थ्यो — प्रत्येक tick ले अघिल्लो glide (अझै धेरै
      // टाढा) लाई बीचैमा काटेर फेरि-लक्ष्य गर्दा देखिने स्थिति वास्तविक
      // प्रगतिभन्दा लगातार झन्-झन् पछाडि पर्दै जान्थ्यो, अनि route सकिएर
      // अन्तिम बिन्दुमा (`pts.last`) एकैचोटि त्यो सारा जम्मा भएको बाँकी
      // दूरी एकै glide मा — नै "ठप्प भएर अचानक pickup मा उफ्रेको" देखिने
      // गुनासोको साँचो जड। अब simulator आफैंले ठ्याक्कै जानेको (र Test-Mode
      // speed-cycle ले जुनसुकै बेला बदलिए पनि सही) प्रति-सेकेन्ड गति सिधै
      // `_gpsSpeedMps` मार्फत (realGPS कै उही बाटो) पठाइन्छ — glide-duration
      // अब सधैं simulator कै साँचो गतिसँगै ठ्याक्कै मिल्छ, chronic lag/
      // अन्तिम ठूलो-हप कहिल्यै हुँदैन।
      // 500 = tickInterval.inMilliseconds (declared below, after this tick's
      // point is computed) — kept in sync manually since Dart can't forward-
      // reference a later local const from here.
      // Short-Route Instant-Finish Fix — यदि सुरु र pickup बिन्दु साँच्चै
      // नजिकै छन् (dev-टेस्ट प्रायः आफ्नै हालको ठाउँबाटै गरिने भएकोले
      // सामान्य) — माथिको स्थिर प्रति-tick चाल (`simTickDistanceKm *
      // _simSpeed`, 1x मा ~6.25m, स्पीड बढाउँदा झन् बढी) नै पूरै route
      // भन्दा लामो/उस्तै हुन सक्छ। त्यो बेला यहाँको पहिलो/एकमात्र tick मै
      // `_simProgressKm >= totalKm` तुरुन्तै साँचो हुँदा, बाइक कुनै पनि
      // बीचको बिन्दु कहिल्यै नदेखाई सिधै अन्तिम बिन्दु (`pts.last`,
      // व्यवहारमा destination) मा एकैचोटि "उफ्रिने" देखिन्थ्यो — माथिको
      // 15-20s cold-start पर्खाइपछि नै ठ्याक्कै यही हुँदा "freeze अनि
      // अचानक destination मा jerk" देखिने गुनासोको साँचो जड (live-test
      // बाट पुष्टि भयो: सुरु र pickup बिन्दु साँच्चै नजिकै थिए)। अब
      // totalKm आफैं सामान्य tick-चाल भन्दा सानो भए, route जतिसुकै छोटो
      // भए पनि कम्तिमा [minStepsForShortRoute] वटा समान-साइजका tick मा
      // बाँडिन्छ — `_gpsSpeedMps` पनि ठ्याक्कै त्यही साना-step अनुसार
      // (होइन पुरानै स्थिर अनुमान) पठाइने भएकोले, route_map_view.dart को
      // glide-duration अझै सधैं real step-distance सँगै मिल्छ (माथिकै
      // "Glide-Speed Mismatch Fix" कै उही ग्यारेन्टी कायमै रहन्छ, छोटो-
      // route केसमा पनि)। पूर्ण रूपमा शून्य-दूरी route (सुरु=अन्त्य,
      // व्यवहारमा कहिल्यै नहुने) मात्र सिधै पूरा हुन्छ — division-by-zero
      // बाट बचाउन।
      if (totalKm <= 0) {
        await _handleNewPosition(pts.last);
        break;
      }
      const minStepsForShortRoute = 4;
      final baseStepKm = simTickDistanceKm * _simSpeed;
      final isShortRoute = totalKm < baseStepKm * minStepsForShortRoute;
      final stepKm = isShortRoute ? totalKm / minStepsForShortRoute : baseStepKm;
      _gpsSpeedMps = (stepKm * 1000) / (500 / 1000);
      _simProgressKm += stepKm;
      if (_simProgressKm >= totalKm) {
        await _handleNewPosition(pts.last);
        break;
      }
      // Tick-Drift Fix — `_handleNewPosition` आफैं (Firestore write, अनि
      // कहिलेकाहीं `_loadRoute` network-await) ले अनिश्चित समय (केही
      // सय ms देखि बढी सम्म पनि) लिन सक्छ — पहिले त्यो समय गणना नगरी
      // त्यसपछि फेरि पूरै tick-अन्तराल थप्दा, वास्तविक अन्तराल त्यो भन्दा
      // लामो हुन्थ्यो। अब tick सुरु हुनेबित्तिकैको समय नाप्छ, अनि बाँकी
      // (tickInterval − `_handleNewPosition` ले ओगटेको समय) मात्र पर्खन्छ —
      // ताकि हरेक tick साँच्चै ठ्याक्कै तोकिएको अन्तरालमै आओस्।
      final tickStart = DateTime.now();
      final p = _pointAtDistanceKm(pts, _simProgressKm);
      if (p != null) await _handleNewPosition(p);
      const tickInterval = Duration(milliseconds: 500);
      final elapsed = DateTime.now().difference(tickStart);
      final remaining = tickInterval - elapsed;
      // Runaway-Loop Guard — `_handleNewPosition` आफैं कहिलेकाहीं (Firestore
      // write/route-fetch सुस्त भएमा) 2000ms भन्दा बढी लिन सक्छ — त्यो
      // बेला `remaining` ऋणात्मक हुन्थ्यो, र माथिको `if` ले कुनै delay
      // नै नदिई तुरुन्तै अर्को iteration सुरु गराउँथ्यो — कुनै breathing
      // room बिनाको tight loop, जसले अर्को `_handleNewPosition` लाई झन्
      // सुस्त बनाउने र जान्दा-नजान्दै झन्-झन् जम्मा हुँदै जाने (runaway)
      // दुष्चक्र सिर्जना गथ्र्यो — ठ्याक्कै सत्र लामो हुँदै जाँदा jank
      // निरन्तर बिग्रिंदै गएको (कहिल्यै नसुध्रिने) गुनासोको साँचो जड। अब
      // कम्तिमा ५०ms त सधैं पर्खन्छ — event loop/UI thread लाई सधैं
      // केही फुर्सद दिन्छ, loop कहिल्यै zero-delay मा नचल्ने ग्यारेन्टी।
      final waitTime =
          remaining > Duration.zero ? remaining : const Duration(milliseconds: 50);
      await Future.delayed(waitTime);
      if (myRunId != _simRunId || !mounted) break;
    }
    if (mounted && myRunId == _simRunId) setState(() => _simulating = false);
  }

  // कामदार ग्राहकको ठ्याक्कै pin बाट यति भित्र नआएसम्म "On Arrival"/OTP बटन
  // disable नै रहन्छ — टाढाबाटै/proximity मात्रैले काम आफैं सुरु नहोस् भन्ने
  // आवश्यकता (यहाँ केवल बटन unlock हुन्छ, कुनै status auto-लेखिँदैन)। पहिले
  // 0.03 (30m) थियो — तर साँचो phone GPS प्रायः ठ्याक्कै pin भन्दा ३०-४०m
  // तानिन्छ (भवन/सहर-घनत्व अनुसार), नतिजा: driver visually pin मै उभिए
  // पनि "Get closer to the pin" कहिल्यै नहट्ने, OTP box/Start Ride सधैं
  // locked रहने गुनासोको जड। 0.04 (40m) ले त्यो ठीक गर्‍यो।
  //
  // Tightened To 13m (Explicit Product Requirement) — Uber/InDrive-grade
  // strictness माग अनुसार फेरि साँघुरो (10-15m दायरा) पारिएको — तर माथिकै
  // ३०m-को गुनासो (साँचो GPS drift ३०-४०m सम्म हुन सक्छ) अझै उस्तै जोखिम हो।
  // Real device मा घना-सहर/भवन-नजिकको GPS ले यो threshold भित्र कहिल्यै
  // नआई "Get closer to the pin" फेरि कहिल्यै नहट्ने देखिन सक्छ — त्यो भेटिए
  // 0.04 (40m) मा फर्काउने विचार गर्नुहोस्, घटाउने होइन।
  static const double _arrivalThresholdKm = 0.013;
  bool _withinArrivalRadius = false;
  // Visual-Arrival Sync Fix — तल `_handleNewPosition` मा हेर्नुहोस् —
  // `_withinArrivalRadius` साँच्चै true हुनुअघि route_map_view.dart कै
  // marker-glide लाई टुंगिन दिने जगेडा (worst-case 2000ms) समय।
  // `_lastWithinArrivalRaw` ले ढिलो timer फायर हुँदा अझै साँच्चै radius
  // भित्रै छ कि (बीचमै फेरि बाहिर गइसकेको त होइन) जाँच्न प्रयोग हुन्छ।
  Timer? _arrivalUnlockDelayTimer;
  bool _lastWithinArrivalRaw = false;
  // worker ले "On Arrival" बटन साँच्चै थिचेपछि मात्र true — proximity
  // आफैंले होइन। यही deliberate tap ले arrival समय लेख्ने, दुवैतिर
  // सम्पर्क (Call/Video/Message) देखाउने, employer लाई notification पठाउने,
  // र काम status एकैचोटि 'in_progress' मा सार्ने — छुट्टै "Start Work" चरण
  // अब चाहिँदैन।
  bool _arrivalConfirmed = false;
  bool _confirmingArrival = false;

  // Explicit "Start Work" Step (Worker/Employer job-portal मात्र, Ride
  // होइन) — arrival (`arrivedAt`) र काम साँच्चै सुरु (`status: in_progress`)
  // अब छुट्टै दुई क्षण। worker पुगेपछि पनि यो आफैं थिचेसम्म काम "सुरु"
  // मानिँदैन, र completion/payment चरण (auto-open payment sheet) यही
  // नभएसम्म कहिल्यै ट्रिगर हुँदैन (हेर्नुहोस् request_tracking_screen.dart
  // auto-open block)।
  bool _workStarted = false;
  bool _startingWork = false;

  // Dual-Confirmation Completion (Worker/Employer job-portal मात्र, Ride
  // होइन — हेर्नुहोस् `_markWorkerJobComplete()`) — worker आफैंले "Job
  // Completed" थिचेको हो कि भन्ने, `serviceRequests.workerConfirmedComplete`
  // सँग live sync (तल `_onRequestSnapshot`)। Employer-side (request_tracking_
  // screen.dart/bookings_screen.dart) को "Complete Job" (भुक्तानी+rating)
  // बटन यही true नभएसम्म disabled रहन्छ।
  bool _workerConfirmedComplete = false;
  bool _confirmingWorkerComplete = false;

  // Admin Cancellation — यो पेज खुलेकै बेला owner dashboard बाट काम
  // "Cancel Task" भइहाले (status: 'cancelled_by_admin') worker लाई तुरुन्तै
  // थाहा हुनुपर्छ, नत्र यहीं अड्किरहन्थ्यो (काम बीचमै कतै गएको जस्तो,
  // ग्राहकसँग सम्पर्क गर्दा पनि जवाफ नआउने)। यो पेज नखुली बसेको बेला (job
  // feed/bookings मा) चाहिँ स्वतः पहिल्यै फिल्टर हुन्छ ( `kActiveJobStatuses`
  // ले `cancelled_by_admin` लाई active मान्दैन) — त्यसैले छुट्टै global
  // listener चाहिँदैन, यही एउटा पेज-स्तरको subscription पुग्छ।
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  bool _adminCancelHandled = false;

  @override
  void initState() {
    super.initState();
    visibleRouteScreenRequestId = widget.requestId;
    // चलिरहेको नक्सामाथि blur हरेक frame दोहोरिन्छ — यो स्क्रिनमा बन्द।
    glassBlurDisabled = true;
    _boot();
    unawaited(_loadSecondLegIfNeeded());
    _restartAutoCollapseTimer();
    // OTP कोड टाइप गर्दा (keyboard बाट, pointer event बिना) पनि card
    // सक्रिय मानिने — नत्र बिस्तारै कोड हाल्दा बीचमै card लुक्न सक्थ्यो।
    _codeFocusNode.addListener(() {
      if (_codeFocusNode.hasFocus) _registerCardInteraction();
    });
    _codeController.addListener(_registerCardInteraction);
    // Live OTP Color Feedback — हरेक keystroke मा field रातो/हरियो
    // तुरुन्तै अपडेट होस् भनेर (माथिको `_registerCardInteraction` ले
    // केवल auto-collapse timer रिसेट गर्छ, rebuild गर्दैन)।
    _codeController.addListener(() {
      if (mounted) setState(() {});
    });
    _statusSub = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(widget.requestId)
        .snapshots(includeMetadataChanges: true)
        .listen(_onRequestSnapshot, onError: (_) => _verifyBookingGone());
    // Safety Net — passenger ले cancel गर्दा doc मेटिन्छ, तर listener मेटिएको
    // event नपाउन सक्छ (rules ले मेटिएपछि `resource` null हुँदा listener
    // चुपचाप टुट्न सक्छ)। त्यसैले हरेक ८s सर्भरबाटै जाँच्ने।
    _goneCheckTimer = Timer.periodic(
        const Duration(seconds: 8), (_) => _verifyBookingGone());
    if (_isRide) {
      final controller = StreamController<double>.broadcast();
      _headingStreamController = controller;
      _headingEngine =
          HeadingFusionEngine(onHeadingUpdate: controller.add)..start();
    }
  }

  void _onRequestSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted || _adminCancelHandled) return;
    // Passenger-Side Cancel Not Reflected On Driver's Screen — यहाँ पहिले
    // केवल `status == 'cancelled_by_admin'` मात्र जाँचिन्थ्यो। तर passenger
    // ले cancel गर्दा (`deleteCancelledBooking`) status कहीं बदलिंदैन —
    // पूरै doc नै मेटिन्छ (status मात्र कहीं "cancelled" राख्दैन)। त्यसैले
    // driver यही route screen मा अड्किरहन्थ्यो — doc मेटिए पनि यो listener
    // ले कहिल्यै थाहा नपाउने (live test मा नै समातिएको: Chrome बाट cancel
    // भइसके पनि driver को फोनमा route/Call/Video call बटनसहितको पुरानै
    // screen उस्तैको-उस्तै देखिरह्यो)। ride completion ले status मात्र
    // 'completed' मा बदल्छ, doc कहिल्यै मेट्दैन (complete_job_sheet.dart
    // हेर्नुहोस्) — त्यसैले `!snap.exists` सधैं साँच्चैको cancel मात्र हो।
    if (!snap.exists) {
      // Cache बाट आएको "छैन" (सर्भरको जवाफ अझै नआएको) लाई cancel नमान्ने —
      // सर्भरबाट पुष्टि हुँदा मात्र।
      if (snap.metadata.isFromCache) {
        unawaited(_verifyBookingGone());
        return;
      }
      _triggerBookingGone();
      return;
    }
    final workerDone = snap.data()?['workerConfirmedComplete'] == true;
    if (workerDone != _workerConfirmedComplete) {
      setState(() => _workerConfirmedComplete = workerDone);
    }
    final status = (snap.data()?['status'] ?? '').toString();
    // Arrival/Start-Work Restore On Reopen — स्क्रिन फेरि खोलेको बेला
    // (app restart, notification बाट फेरि यहीं आइपुगेको) सामान्य काम
    // (Ride होइन) पहिल्यै arrive/start भइसकेको भए दुवै state यहीँबाट
    // फर्काउने — नत्र arrivedAt/status पहिल्यै लेखिएको भए पनि UI ले फेरि
    // "On Arrival"/"Start Work" बटन देखाउँथ्यो।
    if (!_isRide) {
      final arrived = snap.data()?['arrivedAt'] != null;
      if (arrived != _arrivalConfirmed) {
        setState(() => _arrivalConfirmed = arrived);
      }
      final started = status == 'in_progress' || status == 'completed';
      if (started != _workStarted) {
        setState(() => _workStarted = started);
      }
    }
    if (status == 'cancelled_by_admin') {
      _adminCancelHandled = true;
      _statusSub?.cancel();
      _handleCancelledByAdmin();
    } else if (status == 'cancelled') {
      // Defensive — हालसम्म कुनै लेखाइ-मार्गले यो exact value कहिल्यै
      // लेख्दैन (cancel सधैँ doc नै मेटेर हुन्छ, माथिको `!snap.exists`
      // हेर्नुहोस्), तर कुनै भविष्यको/बाह्य लेखाइले यो status सेट गरिहाले
      // पनि worker यहीँ अड्किइरहन नपरोस् भनेर — उही instant/non-blocking
      // redirect (`_handleBookingCancelledByPassenger`)।
      _adminCancelHandled = true;
      _statusSub?.cancel();
      _handleBookingCancelledByPassenger();
    } else if (status == 'completed' && !_completionHandled) {
      // Rider-Side Completion Feedback — पहिले employer ले payment+rating
      // सबमिट गरेर status 'completed' भएपछि worker कै यो route screen
      // मा कुनै संकेत नै थिएन — worker यहीँ अनिश्चित रूपमा अडिरहन्थ्यो,
      // भुक्तानी भइसकेको पत्तो नपाई। अब उही साझा success कार्ड (passenger
      // ले पनि देख्ने) देखाएर, त्यसपछि आफैं home (पहिलो route) सम्म फर्कन्छ।
      _completionHandled = true;
      _statusSub?.cancel();
      _handleRideCompleted();
    }
  }

  bool _completionHandled = false;
  Timer? _goneCheckTimer;

  void _triggerBookingGone() {
    if (!mounted || _adminCancelHandled) return;
    _adminCancelHandled = true;
    _statusSub?.cancel();
    _goneCheckTimer?.cancel();
    _handleBookingCancelledByPassenger();
  }

  /// सर्भरबाटै जाँच्छ: doc मेटिएको वा पढ्ने अनुमति नै गएको (rules मा
  /// `resource` null भएपछि permission-denied आउँछ) भए — cancel भएको मान्छ।
  Future<void> _verifyBookingGone() async {
    if (!mounted || _adminCancelHandled || _completionHandled) return;
    try {
      final s = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get(const GetOptions(source: Source.server));
      if (!s.exists) _triggerBookingGone();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') {
        _triggerBookingGone();
      }
    } catch (_) {}
  }

  Future<void> _handleRideCompleted() async {
    if (!mounted) return;
    await showPaymentSuccessCard(context, isRide: _isRide);
    if (!mounted) return;
    // Land On Home (Main Map Dashboard), Not Whatever Tab Was Last Active —
    // पहिले केवल popUntil(isFirst) मात्र गर्थ्यो, जसले MainContainer सम्मै
    // त फर्काउँथ्यो तर त्यसको `_currentIndex` जे तोकिएको थियो (प्रायः
    // Profile/Driver Hub, driver त्यहींबाट काम स्वीकार गरेको भएकाले) त्यही
    // नै देखाउँथ्यो — driver नयाँ राइड लिन तयार हुने Home dashboard मा
    // कहिल्यै ल्याउँदैनथ्यो। अब `requestedMainTabIndex` (app_globals.dart)
    // लाई स्पष्ट Home (0) मा सेट गरेर मात्र फर्कने।
    requestedMainTabIndex.value = 0;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    // Ride सकिएपछि राइडर सिधै Home मा होइन, "Find nearby jobs" नक्सामा
    // (नयाँ राइड खोज्न तयार) — Home मा जान चाहेमा आफैं तलको Home बटन थिच्छ
    // (DashboardExitBar)। Handyman काम भने पहिलेकै Home मा।
    if (_isRide) {
      navigator.push(MaterialPageRoute(builder: (_) => const JobFeedScreen()));
    }
  }

  /// True Auto-Cancellation — पहिले यहाँ एउटा `barrierDismissible: false`
  /// modal dialog (OK बटन कुर्दै) देखाएपछि मात्र pop हुन्थ्यो — employer/
  /// passenger ले cancel गरेको क्षणमा worker आफैं केही नतिचेसम्म यो
  /// screen मै (अब बेकार भइसकेको route/Call/Video बटनसहित) अडिरहन्थ्यो।
  /// अब doc-delete थाहा हुनेबित्तिकै कुनै button-tap नपर्खी तुरुन्तै Home
  /// dashboard मा फर्किन्छ (`_handleRideCompleted` कै उस्तै "Land On Home"
  /// ढाँचा) — किन फर्कियो भन्ने संकेत भने पूर्ण रूपमा नहराओस् भनेर एउटा
  /// गैर-blocking SnackBar (auto-dismiss, कुनै tap नचाहिने) मात्र।
  Future<void> _handleBookingCancelledByPassenger() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // cancel गर्नेले छानेको कारण (भए) — पहिले पढ्ने, ताकि सन्देशमा देखियोस्।
    final reason = await takeCancelNoticeReason(widget.requestId);
    if (!mounted) return;
    // Role-Correct Cancellation Copy — Plumber/Electrician/Carpenter/
    // Painter/Cleaner/Mechanic जस्ता handyman काम (ride होइन, अर्को पक्ष
    // "employer") मा ride-सान्दर्भिक शब्द ("passenger") नदेखियोस् भनेर
    // `_isRide` अनुसार सही सन्देश छानिन्छ।
    final base =
        _isRide ? S.taskCancelledByPassengerBody : S.taskCancelledByEmployerBody;
    final message =
        reason == null ? base : '$base\n${S.cancelReasonLabel}: $reason';
    requestedMainTabIndex.value = 0;
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6), content: Text(message)));
  }

  /// Admin ले cancel गरेको प्रस्ट देखाएर worker लाई यही पेजबाट बाहिर —
  /// सिधा active map/waiting स्क्रिन (यो पेज जहाँबाट पुशियो, त्यहीं) मा
  /// फर्काउने।
  Future<void> _handleCancelledByAdmin() async {
    await showKmDialog<void>(
      context: context,
      title: S.taskCancelledByAdminTitle,
      message: S.taskCancelledByAdminBody,
      icon: Icons.cancel_rounded,
      iconBg:
          const LinearGradient(colors: [AppColors.danger, AppColors.kmRose]),
      barrierDismissible: false,
      actions: [
        KmDialogAction(
          label: S.ok,
          filled: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    glassBlurDisabled = glassBlurDefaultDisabled;
    if (visibleRouteScreenRequestId == widget.requestId) {
      visibleRouteScreenRequestId = null;
    }
    _statusSub?.cancel();
    _goneCheckTimer?.cancel();
    _posSub?.cancel();
    _autoCollapseTimer?.cancel();
    _arrivalUnlockDelayTimer?.cancel();
    _simulating = false; // `_runSimulationLoop` ले `mounted` जाँचेर आफैं रोकिन्छ।
    _codeController.dispose();
    _codeFocusNode.dispose();
    _headingEngine?.dispose();
    _headingStreamController?.close();
    super.dispose();
  }

  /// आफ्नो लाइभ GPS पछ्याउने + ग्राहकको स्क्रिनका लागि Firestore मा लेख्ने।
  ///
  /// Passenger-Side Stutter Fix — पहिले यहाँ `distanceFilter: 25` (मात्र
  /// २५मी चलेपछि नयाँ GPS reading) + तल्लो `_handleNewPosition` को ५-सेकेन्ड
  /// write-throttle गरेर, साधारण बाइक गतिमा (~५ मी/से) ग्राहकले ५-१०+
  /// सेकेन्डमा मात्र एउटा नयाँ `workerLat/Lng` पाउँथ्यो — अनि RouteMapView
  /// को glide animation (~900ms) त्यो छोटो समयमै सकिएर बाँकी ४-९ सेकेन्ड
  /// बाइक-आइकन पूर्ण रूपमा अडिएर बस्थ्यो, अनि नयाँ बिन्दु आउनेबित्तिकै फेरि
  /// छोटो glide — यही नै ग्राहकतर्फ "lag/stutter" देखिनुको साँचो जड थियो
  /// (driver आफ्नै स्क्रिनमा भने लाइभ GPS नै सिधै देखाउने भएकोले सहज देखिन्थ्यो,
  /// render गर्ने widget उही कोड भए पनि)। render प्रविधि (Dart/native जे
  /// भए पनि) ले यो ठीक गर्दैन — डेटा नै त्यति बेलासम्म आउँदैनथ्यो। अब
  /// distanceFilter घटाएर (8मी) + throttle घटाएर (३स) ग्राहकतर्फ धेरै
  /// बारम्बार ताजा बिन्दु पुग्छ (Firestore write/battery अलि बढ्छ, तर
  /// अझै unbounded/per-tick होइन — उस्तै सुरक्षा कायमै)।
  void _startLiveTracking() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        // Navigation-grade fused fix, फिक्स 1s अन्तरालमा — चालक गतिमा
        // glide (route_map_view.dart) लाई नियमित बिन्दु पुग्छ।
        accuracy: LocationAccuracy.bestForNavigation,
        intervalDuration: const Duration(seconds: 1),
        // Typing-Breaks-On-Live-Screen Revert — 5m मा झारिएको थियो
        // (Tighter Passenger Sync), तर यसले `_handleNewPosition` भित्रको
        // `setState(() => _me = me)` (तलै हेर्नुहोस्, यो हरेक GPS reading मा
        // unconditional चल्छ — write-throttle ले त Firestore लेखाइलाई मात्र
        // ढिला गर्छ, यो local rebuild लाई होइन) लाई लगभग हरेक सेकेन्ड चलायो।
        // Ride-Start OTP keyboard खुलेको बेला यति बारम्बार पूरै-स्क्रिन
        // rebuild ले keyboard/focus flicker गरायो — driver ले ४-अंक code
        // नै टाइप गर्न नसक्ने गुनासोको साँचो जड। फेरि 8m मा फर्काइयो।
        distanceFilter: 8,
      ),
    ).listen((p) {
      _updateGpsVelocity(p);
      _handleNewPosition(LatLng(p.latitude, p.longitude));
    }, onError: (_) {});
  }

  /// GPS Velocity Fusion — `Position.speed`/`.heading` (GPS chip कै Doppler-
  /// आधारित मान, phone orientation मा भर नपर्ने) — caller (यहाँ) ले पहिल्यै
  /// confidence जाँचेर मात्र `_gpsSpeedMps`/`_gpsHeadingDeg` सेट गर्छ, नत्र
  /// null नै राख्छ (route_map_view.dart को fallback स्वतः लागू हुन्छ)।
  /// कम-confidence/अनुपलब्ध मान (NaN, वा ठूलो accuracy-त्रुटि) लाई कहिल्यै
  /// विश्वास नगर्ने — galat GPS jitter लाई साँचो मानेर bearing/गति बिगार्न
  /// नदिन।
  void _updateGpsVelocity(Position p) {
    final speed = p.speed;
    final speedOk = !speed.isNaN && speed >= 0 && p.speedAccuracy < 3.0;
    _gpsSpeedMps = speedOk ? speed : null;
    final heading = p.heading;
    final headingOk =
        !heading.isNaN && heading >= 0 && p.headingAccuracy < 40.0;
    _gpsHeadingDeg = headingOk ? heading : null;
    // Gyro-Drift Correction — gyro-fused heading लाई यही विश्वासिलो GPS
    // बिन्दुमा बेला-बेला "तान्ने" (dead_reckoning.dart को complementary-
    // filter gain हेर्नुहोस्) — नत्र gyro-मात्रको integration लामो समयमा
    // संचित त्रुटि (drift) ले बिग्रिंदै जान्छ। उभिंदा/सानो गति (GPS heading
    // आफैं noisy हुने) मा कहिल्यै correct नगर्ने।
    if (headingOk && speedOk && speed > 0.8) {
      _headingEngine?.anchorToGps(heading);
    }
  }

  /// वास्तविक GPS (`_startLiveTracking`) र Mock GPS Simulator (माथि
  /// `_runSimulationLoop`) दुवैले उही बाटो प्रयोग गर्छन् — यसले नै `_me`, Firestore
  /// `workerLat/Lng`, arrival-geofence, र route-refresh सबै अपडेट गर्छ,
  /// ताकि simulator ले साँचो GPS भन्दा फरक/अलग व्यवहार नदेखाओस्।
  Future<void> _handleNewPosition(LatLng me) async {
    if (!mounted) return;
    setState(() => _me = me);

    // ग्राहकलाई लाइभ track गर्न — तर हरेक GPS tick मा होइन, कम्तिमा 1s
    // पर्खेर मात्र (5m distanceFilter सँगै, माथि `_startLiveTracking` को
    // Passenger-Side Stutter Fix doc-comment हेर्नुहोस्) — Firestore write/
    // employer तर्फको snapshot-driven rebuild बेलगाम नहोस् भनेर (performance),
    // तर ग्राहकको RouteMapView glide लाई पुग्ने जति ताजा। Tighter Passenger
    // Sync — पहिले 3s थियो (ride/employer दुवैको live-position "lag" गुनासो
    // पछि 1s मा झारिएको) — याद राख्नुहोस्: यसले Firestore write/listener
    // ट्राफिक लगभग ३ गुणा बढाउँछ (ब्याट्री/cost tradeoff), तर अझै
    // unbounded/per-GPS-tick होइन।
    final now = DateTime.now();
    final dueWrite = _lastWorkerPosWrite == null ||
        now.difference(_lastWorkerPosWrite!) > const Duration(seconds: 1);
    if (dueWrite) {
      _lastWorkerPosWrite = now;
      LiveGpsMetrics.driverWrite();
      // Non-Blocking Write (Runaway-Loop Guard, completed) — पहिले यो
      // `await` गरिन्थ्यो (१०s सम्मको timeout), सिधै `_runSimulationLoop`
      // कै tick भित्रैबाट (माथिको "Tick-Drift Fix"/"Runaway-Loop Guard"
      // doc-comment हेर्नुहोस्) — नेटवर्क ढिलो हुँदा यही await ले हरेक
      // simulate-tick लाई केही सेकेन्डसम्म रोक्थ्यो, `adb logcat` मा
      // प्रत्यक्ष नापिएको बहुसेकेन्ड "Davey!"/frame-skip को साँचो जड यही
      // थियो (route_map_view.dart कै क्यामेरा/marker code होइन)। साँचो
      // GPS stream (`_startLiveTracking`) ले यो function लाई पहिल्यैदेखि
      // कहिल्यै await नगरी बोलाउँछ — अब यहाँ पनि उही ढाँचा: लेखाइ
      // पृष्ठभूमिमै जान्छ, `_me`/UI glide कहिल्यै यसको पर्खाइमा अड्किंदैन।
      unawaited(
        webSafeTimeout(
          FirebaseFirestore.instance
              .collection('serviceRequests')
              .doc(widget.requestId)
              .update({
            'workerLat': me.latitude,
            'workerLng': me.longitude,
            'workerLocationUpdatedAt': FieldValue.serverTimestamp(),
          }),
          const Duration(seconds: 10),
        ).catchError((e) {
          debugPrint('[LiveLocation] worker position write failed: $e');
          LiveGpsMetrics.driverWriteFailed();
        }),
      );
    }

    // गन्तव्य-नजिक (geofence) भित्र छ/छैन मात्र ट्र्याक — यसले आफैं कुनै
    // status/arrival नलेख्ने, केवल "On Arrival" बटन unlock/lock गर्ने।
    // साँचो arrival भने worker आफैंले बटन थिचेपछि मात्र (हेर्नुहोस्
    // `_confirmArrival`) — proximity मात्रैले काम आफैं सुरु नहोस् भन्ने
    // आवश्यकता।
    final km = haversineKm(
        me.latitude, me.longitude, _employer.latitude, _employer.longitude);
    final within = km <= _arrivalThresholdKm;
    if (!kReleaseMode && within != _withinArrivalRadius) {
      // Geofence-Flip Trace — "arrival भयो भने पनि बाइक टाढै थियो" भन्ने
      // गुनासो आउँदा अब अनुमान होइन, यही लाइनले ठ्याक्कै त्यो क्षणको
      // साँचो दूरी (मिटरमा) देखाउँछ — पिकअप coordinate आफैं गलत/टेस्ट-
      // डेटा नजिकै भएको हो कि geofence-logic नै हो भन्ने छुट्याउन।
      debugPrint(
          '[ArrivalGeofence] within=$within distanceM=${(km * 1000).toStringAsFixed(1)} thresholdM=${(_arrivalThresholdKm * 1000).toStringAsFixed(0)}');
    }
    _lastWithinArrivalRaw = within;
    if (!within) {
      // टाढा गए भने तुरुन्तै lock — ढिलाइ (तल) केवल unlock हुने दिशामा
      // मात्र लागू हुन्छ, lock गर्न कहिल्यै पर्खनु पर्दैन।
      _arrivalUnlockDelayTimer?.cancel();
      _arrivalUnlockDelayTimer = null;
      if (_withinArrivalRadius) {
        setState(() => _withinArrivalRadius = false);
      }
    } else if (!_withinArrivalRadius && _arrivalUnlockDelayTimer == null) {
      // Visual-Arrival Sync Fix — पहिले यहाँ data (raw GPS/simulated `_me`)
      // ले radius भित्र छिरेकै क्षण तुरुन्तै "On Arrival"/Start Ride बटन
      // unlock हुन्थ्यो — तर स्क्रिनमा देखिने marker (route_map_view.dart
      // कै `_displayedOrigin`) त्यहाँसम्म पुग्न अझै आफ्नै छुट्टै glide
      // (400-2000ms, `_startGlideTo` को maxGlide) बाँकी हुन सक्थ्यो, अर्थात्
      // "बाइक अझै बाटोमै देखिँदै छ तर बटन पहिल्यै देखिइसक्यो" भन्ने mismatch
      // — ठ्याक्कै "साँच्चै पुगेपछि मात्र" भन्ने Uber-grade आवश्यकता तोडेको।
      // दुवै फाइल बीच अहिलेसम्म glide-completion जनाउने कुनै च्यानल
      // नभएकोले, यहाँ route_map_view.dart कै glide को सबैभन्दा लामो
      // सम्भावित अवधि (maxGlide=2000ms) जति नै पर्खेर मात्र unlock — यो
      // worst-case सुरक्षित सीमा हो (glide कहिल्यै यो भन्दा बढी समय
      // लिँदैन), त्यसैले बटन देखिंदासम्म marker साँच्चै (वा लगभग) त्यहीं
      // पुगिसकेको ग्यारेन्टी हुन्छ। Edge-triggered — यो branch radius
      // भित्र *छिरेकै* पहिलो tick मा मात्र चल्छ (`_arrivalUnlockDelayTimer
      // == null` जाँचले दोहोरिन/फेरि-फेरि reset हुनबाट जोगाउँछ), नत्र हरेक
      // tick मा नयाँ 2000ms फेरि सुरु भइरहने भई कहिल्यै फायर नहुने थियो।
      const visualCatchUpDelay = Duration(milliseconds: 2000);
      _arrivalUnlockDelayTimer = Timer(visualCatchUpDelay, () {
        _arrivalUnlockDelayTimer = null;
        if (!mounted || !_lastWithinArrivalRaw) return;
        // Pickup-Arrival Auto-Expand — geofence भित्र छिरेको (अब marker
        // पनि पुगिसकेको) संकेत मिलेपछि (collapsed भए पनि, अझै arrival
        // confirm नभएसम्म मात्र) — "On Arrival"/Start Ride बटन अब सक्रिय
        // भएको rider ले तुरुन्तै देख्न पाओस्, स्वाइप थिच्न नपरोस्।
        // 15-Second Mandatory Floor — OTP-Entry Minimum-Visible Floor
        // (`_confirmArrival()` हेर्नुहोस्) कै उस्तै 15s।
        final justEntered = !_arrivalConfirmed;
        setState(() {
          _withinArrivalRadius = true;
          if (justEntered) _cardCollapsed = false;
        });
        if (justEntered) {
          const arrivalExpand = Duration(seconds: 15);
          _minCollapseAt = DateTime.now().add(arrivalExpand);
          // Automatic trigger — कुनै अघिल्लो manual hold (हेर्नुहोस्
          // `_manualHold` doc-comment) भए पनि यहाँबाट आफ्नै floor/timer
          // फेरि लिन सकोस्।
          _manualHold = false;
          _restartAutoCollapseTimer(duration: arrivalExpand);
        }
      });
    }

    // सडक-मार्ग बारम्बार नहित्याउन कम्तिमा १५s पर्खने। Simulator चलिरहेको
    // बेला यो live-refresh पूर्ण रूपमा स्किप — simulator आफ्नै fixed खण्ड
    // (`_runSimulationLoop`, एकपटक मात्र route ल्याएर) मा मात्र हिँड्छ,
    // बीचमा यहाँबाट अर्को route फेरि-fetch भइदिंदा बाइक पछाडि/गलत ठाउँमा
    // उफ्रेको देखिन्थ्यो।
    final dueRoute = !_simulating &&
        (_lastRouteFetch == null ||
            now.difference(_lastRouteFetch!) > const Duration(seconds: 15));
    if (dueRoute) {
      _lastRouteFetch = now;
      await _loadRoute();
    }
  }

  Future<void> _boot() => _fetchAndApplyLocation();

  /// पहिलो कोसिस र "Retry" बटन दुवैले यही एउटै बाटो प्रयोग गर्छन् — सफल भए
  /// route/live-tracking सुरु, असफल भए ठ्याक्कै कारण (`_locationStatus`)
  /// सुरक्षित गरेर banner मा देखाउने।
  Future<void> _fetchAndApplyLocation() async {
    if (mounted) setState(() => _loading = true);
    if (!_modeLoadedFromDoc) await _loadInitialMode();
    final r = await getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _locationStatus = r.status;
      _locationDeniedForever = r.permanentlyDenied;
      if (r.ok) _me = LatLng(r.lat!, r.lng!);
    });
    if (_me == null) {
      setState(() => _loading = false);
      return;
    }
    await _loadRoute();
    _lastRouteFetch = DateTime.now();
    _startLiveTracking();
  }

  Future<void> _loadRoute() async {
    final me = _me!;
    final result = await fetchRoadRoute(me, _target, mode: _mode);
    if (!mounted) return;
    setState(() {
      _route = result;
      _loading = false;
    });
  }

  /// `_locationStatus` अनुसार ठ्याक्कै किन location भेटिएन भन्ने सन्देश —
  /// सधैँ उस्तै generic "turn on location" भन्दा स्पष्ट (fix #4)।
  String? get _locationErrorMessage => switch (_locationStatus) {
        'service_disabled' => S.locationServiceOff,
        'error' => S.locationFetchFailed,
        _ =>
          null, // 'denied'/'pending' — default S.locationNeededForRoute नै ठीक
      };

  /// worker ले "On Arrival" बटन थिचेपछि (geofence भित्र भएमा मात्र सक्रिय
  /// हुने बटन — proximity मात्रैले आफैं यो चल्दैन, deliberate tap नै
  /// चाहिन्छ) — chime, arrival समय लेख्ने, employer लाई "Worker has arrived"
  /// notification, र दुवैतिर Call/Video/Message UI तुरुन्तै प्रस्ट देखिने।
  /// Ride (Bike/Car) मा भने status यहीं 'in_progress' मा नसारी, passenger ले
  /// भनेको OTP driver ले मिलाएपछि मात्र (`_verifyRideCode`) — गलत यात्री/
  /// गलत pickup बाट जोगाउन। अरू सामान्य सेवा (plumber, ...) मा पहिलेकै जस्तै
  /// यहीं एकैचोटि 'in_progress'।
  Future<void> _confirmArrival() async {
    // Proximity Gate Restored — यो internal guard पहिले `!_isRide &&` ले
    // Ride जागाका लागि `_withinArrivalRadius` लाई बाइपास गर्थ्यो (बटनकै
    // `onPressed` तहमा पहिल्यै फिक्स भइसकेको उस्तै बाइपास — हेर्नुहोस्
    // Proximity Gate Restored comment, बटन-निर्माण भाग)। बटनले अब कहिल्यै
    // टाढाबाट call नै गर्दैन, तर यो function आफैं पनि (कुनै अर्को बाटोबाट
    // call भए पनि) सुरक्षित रहोस् भनेर यहाँ पनि उस्तै — Ride/सामान्य job
    // दुवैमा `_withinArrivalRadius` अनिवार्य।
    if (!_withinArrivalRadius || _confirmingArrival || _arrivalConfirmed) {
      return;
    }
    setState(() => _confirmingArrival = true);
    playSuccessFeedback();
    try {
      // Start Work अब छुट्टै स्पष्ट चरण (`_startWork()` हेर्नुहोस्) — यहाँ
      // पुगेको मात्र लेख्ने, status कहिल्यै यहीँबाट 'in_progress' नहोस्।
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({
        'arrivedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // पहिले यहाँ चुपचाप (`catch (_) {}`) — लेखाइ नै असफल भए पनि तल
      // unconditionally `_arrivalConfirmed = true` हुन्थ्यो, अर्थात् UI ले
      // "पुगियो" देखाउँथ्यो तर Firestore मा status कहिल्यै 'in_progress'
      // नभएको (सामान्य सेवाका लागि) हुन सक्थ्यो — ठ्याक्कै Cancel/counter-
      // offer मा भेटिएकै "UI ले सफल भनेको तर backend नबदलिएको" वर्गको बग।
      // अब असफल भए स्पष्ट त्रुटि देखाएर फेरि थिच्न दिने, UI चुपचाप सफल
      // नदेखाउने।
      if (!mounted) return;
      setState(() => _confirmingArrival = false);
      ScaffoldMessenger.of(context).showSnackBar(offerErrorSnackBar(context, e));
      return;
    }
    unawaited(_notifyEmployerArrived());
    if (!mounted) return;
    // OTP/On-Arrival control अब देखिनैपर्ने भएकोले — collapsed भइसकेको
    // भए पनि तुरुन्तै फर्काउने, अनि फेरि 3.5s निष्क्रियता-timer सुरु
    // (उस्तै auto-collapse व्यवहार यहाँबाट पनि लागू हुन्छ)।
    //
    // OTP-Entry Minimum-Visible Floor — यहीँनेर OTP input box पहिलोपटक
    // देखिन्छ (worker ले "On Arrival" थिचेपछि)। पहिले यहाँ कुनै floor नै
    // सेट हुँदैनथ्यो — केवल माथिकै सामान्य 3.5s निष्क्रियता-timer (टाइप
    // गर्दा प्रत्येक keystroke ले रिसेट हुन्छ, तर code सम्झन/passenger लाई
    // फेरि सोध्न केही सेकेन्ड रोकिंदा त्यही छोटो pause मै card लुक्न
    // सक्थ्यो, OTP box नै हराउने)। अब "Protected-Minimum Collapse
    // Deadline" (`_minCollapseAt`, माथि doc-comment हेर्नुहोस्) यहीँबाट
    // पनि — कम्तिमा 15s OTP box पूर्ण रूपमा देखिइरहोस् भन्ने ग्यारेन्टी।
    setState(() {
      _arrivalConfirmed = true;
      _confirmingArrival = false;
      _cardCollapsed = false;
    });
    const otpMinVisible = Duration(seconds: 15);
    _minCollapseAt = DateTime.now().add(otpMinVisible);
    _manualHold = false; // माथिकै "Automatic trigger" कमेन्ट हेर्नुहोस्।
    _restartAutoCollapseTimer(duration: otpMinVisible);
  }

  /// "Start Work" — worker/employer job-portal मात्र (Ride होइन, त्यो
  /// `_verifyRideCode` मार्फत OTP मिलेपछि नै in_progress हुन्छ)। Arrival
  /// confirm भइसकेपछि मात्र सक्रिय — status यहीँ मात्र 'in_progress' हुन्छ,
  /// completion/payment auto-open (request_tracking_screen.dart) यही
  /// नभएसम्म कहिल्यै ट्रिगर हुँदैन।
  Future<void> _startWork() async {
    if (_isRide || !_arrivalConfirmed || _workStarted || _startingWork) {
      return;
    }
    setState(() => _startingWork = true);
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingWork = false);
      ScaffoldMessenger.of(context).showSnackBar(offerErrorSnackBar(context, e));
      return;
    }
    if (!mounted) return;
    setState(() {
      _workStarted = true;
      _startingWork = false;
    });
  }

  /// Dual-Confirmation Job Completion — worker आफैं "Job Completed" थिचेको
  /// (Worker/Employer job-portal मात्र, Ride होइन — Ride मा passenger नै
  /// गन्तव्यमा पुगेपछि एकतर्फी रूपमा complete गर्छ, त्यो उही पुरानो flow
  /// यथावत्)। यो केवल एउटा संकेत हो — भुक्तानी/rating अझै पनि employer
  /// आफैंले (`complete_job_sheet.dart`) मात्र गर्छ, तर अब त्यो बटन worker
  /// ले यो नथिचेसम्म disabled रहन्छ (request_tracking_screen.dart/
  /// bookings_screen.dart हेर्नुहोस्) — "दुवैले confirm गरेपछि मात्र
  /// भुक्तानी चरण" भन्ने नियम लागू गर्न।
  Future<void> _markWorkerJobComplete() async {
    if (_isRide || _workerConfirmedComplete || _confirmingWorkerComplete) {
      return;
    }
    setState(() => _confirmingWorkerComplete = true);
    playSuccessFeedback();
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({
        'workerConfirmedComplete': true,
        'workerConfirmedCompleteAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirmingWorkerComplete = false);
      ScaffoldMessenger.of(context).showSnackBar(offerErrorSnackBar(context, e));
      return;
    }
    if (!mounted) return;
    setState(() {
      _workerConfirmedComplete = true;
      _confirmingWorkerComplete = false;
    });
  }

  /// राइड सुरु गर्ने OTP जाँच्ने — driver ले passenger लाई सोधेर टाइप गरेको
  /// ४-अंक `_rideStartCode` सँग मिल्यो भने मात्र status 'in_progress' मा।
  Future<void> _verifyRideCode() async {
    final entered = _codeController.text.trim();
    if (entered.length < 4) {
      setState(() => _codeError = S.rideCodeTooShort);
      return;
    }
    setState(() {
      _verifyingCode = true;
      _codeError = null;
    });
    // सर्भर-साइड जाँच (Cloud Function) — सही कोड मिले मात्र सर्भरले status
    // 'in_progress' + startedAt लेख्छ; क्लाइन्टले कोड देख्दै/लेख्दै नपाउने।
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('verifyRideStartCode')
          .call({'requestId': widget.requestId, 'code': entered}).timeout(
              const Duration(seconds: 20));
      final ok = (res.data is Map) && res.data['ok'] == true;
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _verifyingCode = false;
          _codeError = S.rideCodeMismatch;
        });
        return;
      }
      playSuccessFeedback();
    } catch (e) {
      // असफलता (नेटवर्क / धेरै गलत प्रयास लक आदि) — स्पष्ट देखाएर फेरि थिच्न दिने।
      if (!mounted) return;
      setState(() => _verifyingCode = false);
      ScaffoldMessenger.of(context).showSnackBar(offerErrorSnackBar(context, e));
      return;
    }
    if (!mounted) return;
    setState(() {
      _verifyingCode = false;
      _codeVerified = true;
      // गन्तव्य pickup बाट drop-off मा ठ्याक्कै अहिल्यै सरेको भएकाले पुरानो
      // (pickup-तर्फको) route तुरुन्तै हटाउने — नत्र अर्को थ्रोटल्ड
      // `_loadRoute()` नआएसम्म (~१५s) गलत/पुरानो polyline देखिन्थ्यो।
      _route = null;
    });
    if (_me != null) unawaited(_loadRoute());
    // Post-Verify Linger — Sequential, "floor नसकिई कुनै hide-countdown
    // सुरु नहोस्" — पहिले यहाँ सिधै 4s दिन्थ्यो (माथिकै `_minCollapseAt`
    // 15s floor अझै बाँकी भए `_restartAutoCollapseTimer` आफैंले max लिने
    // भएकोले सुरक्षित थियो नै, तर floor भित्रै verify भइहाले card floor
    // सकिनेबित्तिकै (floor-boundary मै) हराउँथ्यो, verify पछिको छुट्टै
    // 4s "transition" कहिल्यै देखिँदैनथ्यो)। अब दुई अवस्था छुट्याइन्छ:
    // floor अझै बाँकी भए — पहिले त्यो बाँकी समय पूरै पर्खने, अनि मात्र
    // त्यसपछि थप 4s linger थप्ने (floor + linger, क्रमिक); floor पहिल्यै
    // सकिसकेको भए (सामान्यतया साँचो प्रयोगमा यही हुन्छ — OTP साट्न/टाइप
    // गर्न आफैं १५s भन्दा बढी लाग्छ) त्यही सामान्य 4s linger।
    final floorRemaining = _minCollapseAt?.difference(DateTime.now());
    const verifyLinger = Duration(seconds: 4);
    final hideDelay = (floorRemaining != null && floorRemaining > Duration.zero)
        ? floorRemaining + verifyLinger
        : verifyLinger;
    // Stale-Floor Race Fix — `_minCollapseAt` अझै पुरानै (arrival-तर्फकै
    // 15s) deadline मै रहन्थ्यो। यसपछि driver ले नक्सामाथि जुनसुकै सामान्य
    // tap/pan गरे (`_registerCardInteraction` → `_restartAutoCollapseTimer`
    // default 3.5s सहित) त्यो पुरानै (छोटो) floor विरुद्ध नै max() गणना
    // गर्थ्यो — floor पहिल्यै लगभग सकिसकेको भए card माथि गणना गरिएको सही
    // "floor + 4s linger" भन्दा धेरै चाँडै (floor-boundary मै) हराउँथ्यो,
    // verify पछिको linger हराएर। अब यहीं `_minCollapseAt` लाई पनि नयाँ
    // साँचो deadline (`hideDelay` पछिको क्षण) मा अद्यावधिक — पछिको जुनसुकै
    // interaction-reset ले पनि यही सही deadline नै सम्मान गरोस्।
    _minCollapseAt = DateTime.now().add(hideDelay);
    _manualHold = false; // माथिकै "Automatic trigger" कमेन्ट हेर्नुहोस्।
    _restartAutoCollapseTimer(duration: hideDelay);
  }

  Future<void> _notifyEmployerArrived() async {
    final employerUid = await otherPartyUid(widget.requestId);
    if (employerUid == null || employerUid.isEmpty) return;
    try {
      await createNotificationForUser(
        employerUid,
        S.workerArrivedNotifTitle,
        S.workerArrivedNotifBody,
        data: {'requestId': widget.requestId, 'type': 'worker_arrived'},
      );
    } catch (_) {}
  }

  Future<void> _callEmployer() async {
    final phone = widget.employerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.noPhoneOnFile)));
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  /// Matched/active job cancel गर्ने — पहिले यहाँ (worker कै live-tracking
  /// route screen) कुनै cancel बटन नै थिएन, केवल main shell कै pinned
  /// `ActiveJobBar` (यो full-screen route पुश भएपछि ढाकिने, अदृश्य) बाट
  /// मात्र सम्भव थियो — worker यो screen मा हुँदा cancel गर्न बाहिरिएर
  /// main shell फर्कनुपर्ने। `active_job_bar.dart::_confirmCancel` कै उस्तै
  /// pattern, `cancelledByWorker: true` (penalty strike लाग्छ, employer ले
  /// cancel गर्दा भने कहिल्यै लाग्दैन)। `deleteCancelledBooking` ले doc
  /// पूरै मेटाउने भएकोले employer को RequestTrackingScreen मा (live
  /// listener, `data == null` जाँच) यही क्षण तुरुन्तै देखिन्छ — छुट्टै
  /// sync code चाहिँदैन।
  Future<void> _cancelActiveJob() async {
    final ok = await showKmDialog<bool>(
      context: context,
      title: S.activeJobBarCancelTitleFor(_isRide),
      message: S.activeJobBarCancelBodyFor(_isRide),
      icon: Icons.close_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.keepJobFor(_isRide),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        KmDialogAction(
          label: S.cancelRequest,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    final reason = await pickCancellationReason(context);
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Self-Cancel Listener Race Fix — `deleteCancelledBooking` मेटाउने यही
    // doc हो जो `_statusSub` (माथि `_onRequestSnapshot`) ले पनि हेरिरहेको
    // छ। Local optimistic delete event प्रायः यो `await` भन्दा पहिले नै
    // फायर हुन्छ, र `_onRequestSnapshot` ले `!snap.exists` लाई सधैं "अर्कोले
    // cancel गरेको" (passenger/employer) मानेर `_handleBookingCancelledByPassenger()`
    // देखाउँथ्यो — worker आफैंले आफ्नै काम cancel गर्दा पनि आफैंलाई "Request
    // was cancelled by the employer" भन्ने गलत dialog देखिने र तल्लो
    // `popUntil` सँग दौड (race) हुने गुनासोको जड। अब admin/passenger-cancel
    // बाटै प्रयोग हुने उस्तै गार्ड (`_adminCancelHandled` + `_statusSub.cancel()`)
    // यहाँ पनि delete अघि नै लगाइन्छ, ताकि listener ले यो self-triggered
    // delete लाई कहिल्यै नछोओस्।
    _adminCancelHandled = true;
    _statusSub?.cancel();
    try {
      await deleteCancelledBooking(
        widget.requestId,
        workerUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        cancelledByWorker: true,
        reason: reason,
      );
      if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      // Delete असफल भए listener फेरि चाहिने (अझै doc बाँचेकै छ) — नत्र
      // पछि साँच्चै passenger/admin ले cancel गरे पनि यो screen अनजानमै
      // अडिरहन्थ्यो।
      _adminCancelHandled = false;
      _statusSub = FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .snapshots()
          .listen(_onRequestSnapshot);
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // "यो काम स्वीकार गर्नुहोस्" पछि नक्सा स्वतः खुल्दा native Google Map
      // view attach हुन लाग्ने एक क्षणको खाली ठाउँमा dark theme को
      // झन्डै-कालो default को सट्टा यही हल्का, नक्साकै रङ — flash हुँदैन।
      backgroundColor: AppColors.mapPlaceholderBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(S.jobRouteTitleFor(_isRide),
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
        // Glassmorphism Home Pill — पहिले Flutter को default plain सेतो
        // back-arrow (कुनै `leading` नदिंदा auto-generate हुने) थियो। अब
        // यही `leading` slot मा (कुनै नयाँ Stack-layer/overlap-जोखिम बिना
        // — AppBar आफैं पहिल्यै `extendBodyBehindAppBar` + पारदर्शी/blurred
        // भएकोले यो पनि "नक्सामाथि तैरिरहेको" जस्तै देखिन्छ) साझा glass
        // भाषा (`AppColors.kmGlass2Fill/Border`, GlassIconButton कै उस्तै
        // RepaintBoundary+blur ढाँचा) प्रयोग गरी एउटा सानो icon+"Home" pill।
        // Strict-Dashboard Home Button Fix — पहिले यहाँ `Navigator.maybePop()`
        // (एक-तहको bare pop) थियो — ठीकै हुन्थ्यो जब JobRouteScreen सिधै
        // MainContainer माथि नै push भएको हुन्थ्यो, तर worker_requests_page.dart
        // (सिधा offer) वा notification_screen.dart बाट (push notification
        // tap) खोलिएको बेला त्यो बीचको पेजमै फर्कन्थ्यो — "Home" भनेर लेबल
        // गरिएको बटनले साँच्चै Home dashboard नदिने, बीचैको पेजमा अड्किने
        // bug। अब `_handleRideCompleted`/`_handleBookingCancelledByPassenger`
        // (यही फाइल) कै उस्तै प्रमाणित ढाँचा — Home tab (index 0) स्पष्ट
        // सेट गरेर, navigator stack कै जरासम्मै (`popUntil(isFirst)`) फर्कने
        // — जुनसुकै बाटोबाट यो screen खोलिए पनि सधैं साँचो Home dashboard मै।
        leadingWidth: 112,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: _HomeGlassPill(onTap: () {
            requestedMainTabIndex.value = 0;
            Navigator.of(context).popUntil((route) => route.isFirst);
          }),
        ),
        flexibleSpace: ClipRect(
          child: glassBackdrop(
        sigma: 18,
        child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.kmVoid.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // ── साझा route-map widget — worker/employer दुवैतिर उही class ──
          // Listener ले राख्दा नक्सा आफ्नै pan/zoom gesture (arena) मा कुनै
          // असर पार्दैन — यसले केवल raw pointer-down हेरेर card-collapse
          // timer रिसेट गर्छ।
          //
          // Mapbox Removal — पहिले यहाँ Ride (bike/car) मा मात्र native
          // Kotlin/Mapbox (`NativeVehicleMapView.kt`) मार्फत चल्थ्यो; off-
          // road drift/choppy रेन्डरिङ गुनासो पछि पूरै हटाइयो। अब सबै
          // job-type (Ride लगायत) ले उही Dart-based `RouteMapView`
          // (google_maps_flutter, आफ्नै road-snapping/Kalman-जस्तै
          // cumulative-distance projection सहित) प्रयोग गर्छन् — छुट्टै
          // native code-path अब छैन।
          Listener(
            onPointerDown: (_) => _registerCardInteraction(),
            child: RouteMapView(
            origin: _me,
            originLabel: S.yourLocationWord,
            destination: _target,
            destinationLabel: !_isRide
                ? (widget.employerName.trim().isEmpty
                    ? S.customerWord
                    : widget.employerName)
                : (_codeVerified ? S.dropPointLabel : S.pickupPointLabel),
            destinationAddress: (_isRide && _codeVerified)
                ? widget.destinationAddress
                : widget.address,
            route: _route,
            routeLoading: _loading,
            travelMode: _mode,
            vehicleIconOverride:
                widget.service == 'Auto' ? 'assets/images/auto_top.png' : null,
            // Uber-Style Nav From Acceptance — पहिले यो `_arrivalConfirmed`
            // (OTP/arrival भइसकेपछि मात्र) सम्म पर्खन्थ्यो — pickup तिर
            // हिँड्दै गर्दा (ride accept भएकै क्षणदेखि) साधारण bounds-fit
            // (दुवै पिन एकैचोटि देखिने, टाढाको) view मात्र हुन्थ्यो, close-up
            // heading-up continuous camera-follow/auto-rotation कहिल्यै
            // सक्रिय हुँदैनथ्यो। अब Ride (Bike/Car) मा सुरुदेखि नै (`_isRide`
            // मात्र, arrival-गेट होइन) — pickup र drop-off दुवैतर्फ उस्तै
            // Uber/Google-Maps-nav-style tight follow।
            rideStarted: _isRide,
            primaryIsDropoff: _codeVerified,
            showPointLabels: _isRide,
            navigateTarget: _target,
            // Full-Journey Preview — "अर्को" बिन्दु सधैं (दुवै phase मा)
            // देखिने: pickup तिर आउँदै गर्दा त्यो अर्को बिन्दु drop-off हो,
            // राइड सुरु भइसकेपछि (in_progress) चाहिँ pickup आफैं (अब
            // "पछाडि छुटेको" सन्दर्भ-बिन्दु) बन्छ। secondary ROUTE भने
            // केवल pickup-तिरको चरणमा मात्र (in_progress मा मुख्य route
            // आफैं लगभग यही बाटो देखाइसक्छ — दोहोरिएर overlap हुने थिएन)।
            secondaryDestination: !_isRide
                ? null
                : (_codeVerified
                    ? _employer
                    : (widget.destinationLat != null &&
                            widget.destinationLng != null
                        ? LatLng(widget.destinationLat!, widget.destinationLng!)
                        : null)),
            secondaryDestinationLabel:
                _codeVerified ? S.pickupPointLabel : S.dropPointLabel,
            secondaryRoute:
                (_isRide && !_codeVerified) ? _secondLegRoute : null,
            locationPermanentlyDenied: _locationDeniedForever,
            originMissingMessage: _locationErrorMessage,
            onRetryOrigin: _locationDeniedForever || _me != null
                ? null
                : _fetchAndApplyLocation,
            gpsSpeedMps: _gpsSpeedMps,
            gpsHeadingDeg: _gpsHeadingDeg,
            headingOverrideStream: _headingStreamController?.stream,
            // Map-Centering Fix — पहिले यो bottom:190 सधैं स्थिर (card
            // पूरै खुल्ला हुँदाको उचाइ अनुसार) रहन्थ्यो — तर card auto-
            // collapse भएपछि (माथि `_cardCollapsed` doc-comment हेर्नुहोस्)
            // स्क्रिनको तल्लो भाग फेरि खाली हुन्छ, जबकि नक्साले अझै त्यही
            // ठूलो 190px लाई "ढाकिएको/बाइक नदेखियोस्" मानेर बाइक/route
            // लाई माथितिरै केन्द्रित राख्थ्यो — स्क्रिनको साँचो बीचमा
            // नभई माथि चिप्लिएको/off-center देखिने गुनासोको साँचो जड।
            // Exact-Symmetry Fix — पहिले collapsed बेला bottom:70 थियो
            // (top:64 भन्दा 6px बढी) — सानो भए पनि नापिने असमानता, बाइक
            // ठ्याक्कै बीचमा नभई अलिकति माथि देखिने। Collapsed pill को
            // साँचो फुटप्रिन्ट (~58px: bottom:14 gap + ~44px pill उचाइ)
            // 64px भन्दा कममात्र भएकोले, अब bottom पनि ठ्याक्कै top कै
            // उस्तै 64 — pill लाई अझै पूरै छोप्छ, तर गणितीय रूपमा ठ्याक्कै
            // सन्तुलित (exact symmetric) padding दिन्छ, बाइक ठ्याक्कै
            // स्क्रिनको बीचमा।
            // Dead-Center Fix — नक्सा पूरै स्क्रिन (AppBar पछाडिसम्म) ढाक्छ र
            // padding शून्य: native camera को केन्द्र = स्क्रिनको साँचो केन्द्र।
            // पहिले top:64/bottom:190 (card खुल्दा/बन्द हुँदा बदलिने) ले
            // बाइकलाई माथि सारेको थियो र card हेर्दा हरेकपटक क्यामेरा खिस्कन्थ्यो।
            mapPadding: EdgeInsets.zero,
            ),
          ),

          // ── Mock Location / GPS Simulator टगल — debug/profile build मात्र ──
          // वास्तविक बाटोमा हिँडेर टेस्ट गर्न नसकिने बेला, नक्सा-जुम/
          // vehicle-animation/OTP/payment फ्लो ल्यापटप/फोनबाटै बसेर
          // जाँच्नका लागि — साथै profile mode मा (debug भन्दा साँचो/
          // release-नजिकको performance मा) यिनै tools प्रयोग गरेर
          // स्मूथनेस जाँच्न। `kDebugMode` मात्रले profile mode लाई
          // भित्र्याउँदैनथ्यो (profile आफैं debug होइन) — release build
          // मा भने `!kReleaseMode` पनि false नै फोल्ड हुन्छ, त्यसैले यो
          // widget अझै त्यहाँ कहिल्यै compile हुँदैन (tree-shaken)।
          //
          // पहिले यहाँ `&& _isRide` पनि थियो — `_runSimulationLoop()` आफैं
          // (माथि हेर्नुहोस्) ride-विशेष कुनै logic प्रयोग गर्दैन (`_target`/
          // `_route`/`_mode` दुवै प्रकारमा पहिल्यै सामान्य रूपमा काम गर्छन्),
          // त्यसैले सामान्य job-portal (plumber/electrician...) काममा पनि
          // बटन देखिनुपर्छ — नत्र worker dashboard मा बाटोमा हिँडेर/गाडी
          // चढेर मात्र GPS/route-update टेस्ट गर्न सकिन्थ्यो।
          // Test Mode Panel — Start/Stop (माथिकै pill) + सक्रिय हुँदा
          // Pause/Resume र Speed (0.5x/1x/2x/4x) थप नियन्त्रण। यी दुवै
          // `_simulating` हुँदा मात्र देखिन्छन् — Start नगरीकनै पहिल्यैदेखि
          // देखिने भए अर्थहीन (केही control गर्ने चिज नै हुँदैन)।
          if (!kReleaseMode)
            Positioned(
              top: 70,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _simControlChip(
                    icon: _simulating
                        ? Icons.stop_circle_rounded
                        : Icons.science_rounded,
                    label: _simulating ? 'Stop Sim' : 'Simulate GPS',
                    active: _simulating,
                    // अब `_me == null` भए पनि बटन सधैं tappable — माथि
                    // `_startSimulate()` भित्रै fallback seed गरिन्छ।
                    onTap: _toggleSimulate,
                  ),
                  if (_simulating) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _simControlChip(
                          icon: _simPaused
                              ? Icons.play_circle_rounded
                              : Icons.pause_circle_rounded,
                          label: _simPaused ? 'Resume' : 'Pause',
                          active: _simPaused,
                          onTap: _togglePauseSimulate,
                          compact: true,
                        ),
                        const SizedBox(width: 6),
                        _simControlChip(
                          icon: Icons.speed_rounded,
                          label: '${_simSpeed}x',
                          active: _simSpeedIndex != 1,
                          onTap: _cycleSimSpeed,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // ── ride-sharing style summary card ──
          // Auto-Collapse — माथि `_cardCollapsed` doc-comment हेर्नुहोस्।
          // केवल स्थिति (bottom offset) मात्र बदलिन्छ, geofence/OTP भित्री
          // सामग्री जस्ताको-त्यस्तै अपरिवर्तित — स्क्रिनको फेदमुनि चिप्लेर
          // लुक्छ मात्र, destroy/rebuild हुँदैन (controller/focus सुरक्षित)।
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            left: 12,
            right: 12,
            bottom: _cardCollapsed ? -520 : 14,
            child: Listener(
              onPointerDown: (_) => _registerCardInteraction(),
              // Swipe-Down-To-Collapse — पहिले card लाई हातले तल तान्ने
              // कुनै बाटो नै थिएन (pill मा स्वाइप-अप/tap ले माथि तान्ने
              // मात्र थियो) — यता अहिले थपिएको, pill कै उस्तै velocity-
              // threshold ढाँचामा, तर उल्टो दिशामा। OTP TextField/बटनको
              // साधारण tap सँग नठोक्किने (vertical-drag recognizer ती
              // widget ले दाबी नगर्ने भएकोले)।
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  final vy = details.primaryVelocity ?? 0;
                  if (vy > 150) _collapseCard();
                },
                child: GlassPanel2(
              radius: AppRadius.lg,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: AppColors.kmCtaGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: AppColors.kmInk, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.employerName.trim().isEmpty
                                  ? S.customerWord
                                  : widget.employerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15),
                            ),
                            Text(
                              widget.address.trim().isEmpty
                                  ? '${S.serviceName(widget.service)}  ·  ${S.jobSiteWordFor(_isRide)}'
                                  : widget.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.kmMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Pickup/Drop कार्डभित्रै (बाहिर/लुकाएर होइन) — सधैँ दुवै
                  // नाम स्पष्ट टेक्स्टमा, राइड सुरु/अघि/पछि जुनसुकै चरणमा।
                  if (_isRide) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.radio_button_checked_rounded,
                            size: 14, color: AppColors.kmTeal),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: '${S.pickupPointLabel}: ',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.kmMuted)),
                              TextSpan(
                                  text: widget.address.trim().isEmpty
                                      ? S.pickupPointLabel
                                      : widget.address,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.kmText)),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.flag_rounded,
                            size: 14, color: AppColors.kmOrange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: '${S.dropPointLabel}: ',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.kmMuted)),
                              TextSpan(
                                  text: widget.destinationAddress
                                          .trim()
                                          .isEmpty
                                      ? S.destinationLabel
                                      : widget.destinationAddress,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.kmText)),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_arrivalConfirmed &&
                      (_isRide ? _codeVerified : _workStarted)) ...[
                    Divider(height: 20, color: AppColors.kmGlassBorder),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: AppColors.kmTeal),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              _isRide
                                  ? S.rideStartedInProgress
                                  : S.arrivedJobInProgress,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.kmTeal)),
                        ),
                      ],
                    ),
                    // Dual-Confirmation Completion — Worker/Employer
                    // job-portal मात्र (Ride होइन, त्यो पुरानै flow)। Worker
                    // ले आफ्नो काम सकिएपछि यहीं "Job Completed" थिचेर आफ्नो
                    // confirmation दिन्छ — employer-side को भुक्तानी बटन
                    // यो नथिचेसम्म disabled रहन्छ (request_tracking_screen.dart/
                    // bookings_screen.dart हेर्नुहोस्)।
                    if (!_isRide) ...[
                      const SizedBox(height: 10),
                      if (_workerConfirmedComplete)
                        Row(
                          children: [
                            const Icon(Icons.hourglass_top_rounded,
                                size: 16, color: AppColors.kmOrange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(S.workerConfirmedWaitingPayment,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.kmOrange)),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: KmCtaButton(
                            label: S.markJobCompletedCta,
                            icon: Icons.task_alt_rounded,
                            loading: _confirmingWorkerComplete,
                            onPressed: _markWorkerJobComplete,
                          ),
                        ),
                    ],
                  ] else if (_arrivalConfirmed && _isRide) ...[
                    // ── Ride-Start OTP — arrival भइसक्यो, passenger ले
                    // भनेको ४-अंकको कोड driver ले यहीँ हाल्नुपर्छ ──
                    Divider(height: 20, color: AppColors.kmGlassBorder),
                    Text(S.enterRideCodeTitle,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.kmText)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Builder(builder: (context) {
                            // Live Red/Green OTP Feedback — ठ्याक्कै सही
                            // ४-अंक नभएसम्म रातो, मिलेपछि तुरुन्तै हरियो।
                            // नोट: `AppColors.success` (0xFFE1306C) साँच्चै
                            // हरियो होइन — pink/magenta brand रङ हो (अरू
                            // धेरै ठाउँमा "success" अर्थमा नै प्रयोग भए
                            // पनि) — border रातोसँग (`AppColors.danger`,
                            // 0xFFFF5A5F) लगभग उस्तै देखिन्थ्यो, जसले
                            // "हरियो हुँदै भएन" भन्ने गुनासो ल्यायो। यहाँ
                            // त्यसैले साँचो हरियो (`_otpVerifiedGreen`) छुट्टै
                            // प्रयोग।
                            final codeColor = _codeMatches
                                ? _otpVerifiedGreen
                                : AppColors.danger;
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                boxShadow: _codeMatches
                                    ? [
                                        BoxShadow(
                                          color: _otpVerifiedGreen
                                              .withValues(alpha: 0.45),
                                          blurRadius: 12,
                                          spreadRadius: 0.5,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: TextField(
                                controller: _codeController,
                                focusNode: _codeFocusNode,
                                keyboardType: TextInputType.number,
                                maxLength: 4,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    letterSpacing: 6),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: S.enterRideCodeHint,
                                  hintStyle: const TextStyle(
                                      color: AppColors.kmMuted, fontSize: 13),
                                  filled: true,
                                  fillColor: codeColor.withValues(alpha: 0.12),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    borderSide: BorderSide(
                                        color: codeColor, width: 1.4),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    borderSide: BorderSide(
                                        color: codeColor, width: 1.4),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    borderSide:
                                        BorderSide(color: codeColor, width: 2),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(width: 10),
                        // `KmCtaButton` डिफल्टमा `expand: true` (आफैं
                        // `SizedBox(width: double.infinity)` मा बेरिन्छ) —
                        // यो bare Row भित्र (कुनै Expanded/Flexible बिना)
                        // राख्दा "BoxConstraints forces an infinite width"
                        // crash हुन्थ्यो (पहिले यो OTP स्क्रिन शायदै
                        // live पुगिन्थ्यो, arrival-distance gate हटेपछि
                        // अब सजिलै पुगिने भएर पहिलोपटक देखिएको पुरानै बग)।
                        KmCtaButton(
                          label: S.startRideCta,
                          icon: Icons.lock_open_rounded,
                          loading: _verifyingCode,
                          expand: false,
                          onPressed: _codeMatches ? _verifyRideCode : null,
                        ),
                      ],
                    ),
                    if (_codeMatches) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 14, color: _otpVerifiedGreen),
                          const SizedBox(width: 4),
                          Text(S.rideCodeVerifiedGoodToGo,
                              style: const TextStyle(
                                  color: _otpVerifiedGreen,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5)),
                        ],
                      ),
                    ] else if (_codeError != null) ...[
                      const SizedBox(height: 6),
                      Text(_codeError!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 11.5)),
                    ],
                  ] else if (_arrivalConfirmed && !_isRide) ...[
                    // "Start Work" On Arrival — काम-स्थलमा पुगिसकेपछि पनि,
                    // worker आफैंले यो स्पष्ट बटन नथिचेसम्म status कहिल्यै
                    // 'in_progress' हुँदैन — completion/payment चरण यही
                    // नभएसम्म सुरुई हुँदैन (request_tracking_screen.dart::
                    // auto-open payment sheet को `workerStarted` जाँच
                    // हेर्नुहोस्)।
                    Divider(height: 20, color: AppColors.kmGlassBorder),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: AppColors.kmTeal),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(S.arrivedAtLocation,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.kmTeal)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: KmCtaButton(
                        label: S.startWorkNow,
                        icon: Icons.play_arrow_rounded,
                        loading: _startingWork,
                        onPressed: _startWork,
                      ),
                    ),
                  ] else if (!_isRide) ...[
                    // Strict Vehicle Type Isolation — Bike/Car राइडमा भने यो
                    // साधारण Driving/Walking/Bike chip picker कहिल्यै
                    // नदेखियोस्: सवारी-प्रकार राइड-मिलानकै बेला पहिल्यै
                    // तय भइसकेको हो (worker आफैंले Bike/Car दर्ता गरेको),
                    // बीचमा "Walking" मा switch गर्न मिल्नु भ्रामक हुन्थ्यो।
                    // सामान्य काम (mechanic/plumber जागा-स्थल जाने) मा
                    // भने यो अझै उपयोगी (कुनै पनि यातायातले जान सक्ने)।
                    const SizedBox(height: 10),
                    TravelModeChips(selected: _mode, onChanged: _setMode),
                  ],
                  const SizedBox(height: 12),
                  // "On Arrival" — गन्तव्यको ठ्याक्कै geofence भित्र नआएसम्म
                  // disabled नै रहन्छ; प्रयोगकर्ताले साँच्चै थिच्नुपर्छ,
                  // दूरी मात्रैले काम आफैं सुरु हुँदैन। यसले arrivedAt +
                  // status 'in_progress' मा सार्छ, तर Call/Video/Message
                  // यसमा अब निर्भर छैनन् (तल हेर्नुहोस्)।
                  if (!_arrivalConfirmed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      // Proximity Gate Restored — यो बटनले Ride जागामा
                      // पहिले `_isRide ||` ले GPS दूरी-सर्त (30m,
                      // `_withinArrivalRadius`) बाइपास गर्थ्यो — जुनसुकै
                      // टाढाबाट पनि थिच्न मिल्ने, तुरुन्तै `_arrivalConfirmed`
                      // true हुने (अनि OTP field देखिने)। अब Ride/सामान्य
                      // job दुवैमा उस्तै — पिकअप pin बाट ३०m भित्र नआएसम्म
                      // बटन disabled नै रहन्छ, OTP कहिल्यै टाढाबाटै देखिँदैन।
                      child: KmCtaButton(
                        label: _withinArrivalRadius
                            ? (_isRide
                                ? S.startRideConfirmArrival
                                : S.onArrivalButton)
                            : S.getCloserToArrive,
                        icon: Icons.pin_drop_rounded,
                        loading: _confirmingArrival,
                        onPressed:
                            _withinArrivalRadius ? _confirmArrival : null,
                      ),
                    ),
                  // Acceptance-Gated Communication — काम स्वीकृत भएकै क्षणदेखि
                  // (यो स्क्रिन नै accepted भएपछि मात्र खुल्ने भएकोले) Call/
                  // Video/Message स्थायी रूपमा खुल्ला रहन्छन् — worker
                  // साँच्चै आइपुगे/नआइपुगे भन्ने कुराले फरक पार्दैन।
                  NeonCommBar(
                    callLabel: S.callWord,
                    videoLabel: S.videoCall,
                    messageLabel: S.messageWord,
                    onCall: _callEmployer,
                    onVideo: () => startInAppCall(
                      context,
                      requestId: widget.requestId,
                      otherName: widget.employerName,
                      video: true,
                    ),
                    onMessage: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          requestId: widget.requestId,
                          workerName: widget.employerName,
                          initialStatus: (_arrivalConfirmed &&
                                  (_isRide ? _codeVerified : _workStarted))
                              ? 'in_progress'
                              : 'accepted',
                        ),
                      ),
                    ),
                  ),
                  // Cancel (Active Job) — माथिकै `_cancelActiveJob`
                  // doc-comment हेर्नुहोस्।
                  const SizedBox(height: 10),
                  NeonCancelPill(
                      label: S.cancelRequest, onTap: _cancelActiveJob),
                ],
              ),
              ),
              ),
            ),
          ),
          // Tap-To-Expand Pill — card collapsed हुँदा मात्र देखिने, थिचेर
          // फेरि पूरा card फर्काउने सजिलो/प्रस्ट बाटो।
          if (_cardCollapsed)
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: GestureDetector(
                // Swipe-up — pill मा माथितिर चिप्लाएर पनि card फर्काउन
                // मिल्ने (tap को साथसाथै, tap कहिल्यै नतोडिने गरी)।
                onVerticalDragEnd: (details) {
                  final vy = details.primaryVelocity ?? 0;
                  if (vy < -150) _expandCard();
                },
                child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _expandCard,
                  child: GlassPanel2(
                    radius: 999,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.keyboard_arrow_up_rounded,
                            color: AppColors.kmText, size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              widget.employerName.trim().isEmpty
                                  ? S.customerWord
                                  : widget.employerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Glassmorphism Home Pill — नक्सामाथि "तैरिरहेको" देखिने सानो frosted-glass
/// back/home बटन, `GlassIconButton` (`widgets/glass_ui.dart`) कै उस्तै
/// visual भाषा (blur, fill/border रङ, RepaintBoundary) मात्र यहाँ icon+
/// text दुवै समेट्ने pill आकारमा। हल्का "press" micro-interaction (scale)
/// सहित।
class _HomeGlassPill extends StatefulWidget {
  final VoidCallback onTap;
  const _HomeGlassPill({required this.onTap});

  @override
  State<_HomeGlassPill> createState() => _HomeGlassPillState();
}

class _HomeGlassPillState extends State<_HomeGlassPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // `BackdropFilter` (blur) महँगो — `GlassIconButton` कै उस्तै कारणले
    // (यो पनि नक्सामाथि नै तैरिरहने) `RepaintBoundary` ले छेउछाउका अरू
    // animation (marker glide, card slide) कै कारण यो हरेक frame फेरि
    // re-paint हुनबाट जोगाउँछ।
    return RepaintBoundary(
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: glassBackdrop(
        sigma: 16,
        child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onTap,
                onTapDown: (_) => setState(() => _pressed = true),
                onTapCancel: () => setState(() => _pressed = false),
                onTapUp: (_) => setState(() => _pressed = false),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.kmGlass2Fill,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.kmGlass2Border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_left_rounded,
                          color: AppColors.kmText, size: 22),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          S.navHome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
