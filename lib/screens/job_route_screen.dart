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
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/success_feedback.dart';
import 'chat_screen.dart';
import 'job_actions.dart' show otherPartyUid, startInAppCall;
import 'nearby_common.dart'
    show haversineKm, fetchRoadRoute, RoadRoute, TravelMode, TravelModeChips;
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
  bool _locationDeniedForever = false;
  // getCurrentLocation() ले दिएको ठ्याक्कै कारण — banner मा generic
  // "location needed" भन्दा स्पष्ट सन्देश देखाउन (fix #4: retry + real reason)।
  String _locationStatus = 'pending';

  RoadRoute? _route;
  bool _loading = true;

  // Multi-modal यातायात — worker ले छान्छ, Firestore मा लेखिन्छ ताकि
  // employer (RequestTrackingScreen) ले पनि उही मोड/route देखोस्।
  TravelMode _mode = TravelMode.driving;
  bool _modeLoadedFromDoc = false;

  // Ride-Start OTP (Bike/Car मात्र) — passenger लाई देखिने ४-अंकको कोड,
  // acceptRideOffer() मा नै generate भइसकेको। यहाँ एकपटक मात्र पढिन्छ
  // (कहिल्यै बदलिँदैन), त्यसैले छुट्टै StreamBuilder नचाहिने — `_loadInitialMode()`
  // कै उही एक-पटके doc-fetch मा साथसाथै।
  bool get _isRide => widget.service == 'Bike' || widget.service == 'Car';
  String? _rideStartCode;
  final _codeController = TextEditingController();
  bool _verifyingCode = false;
  bool _codeVerified = false;
  String? _codeError;

  Future<void> _loadInitialMode() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get();
      final saved = snap.data()?['travelMode'] as String?;
      if (saved != null && mounted) {
        setState(() => _mode = TravelMode.fromValue(saved));
      }
      if (_isRide) {
        final code = (snap.data()?['rideStartCode'] ?? '').toString();
        if (code.isNotEmpty && mounted) {
          setState(() => _rideStartCode = code);
        }
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

  // कामदार ग्राहकको ठ्याक्कै pin बाट यति भित्र (~30m, वास्तविक consumer GPS
  // ले भरपर्दो रूपमा दिन सक्ने सटीकता) नआएसम्म "On Arrival" बटन disable नै
  // रहन्छ — टाढाबाटै/proximity मात्रैले काम आफैं सुरु नहोस् भन्ने आवश्यकता
  // (यहाँ केवल बटन unlock हुन्छ, कुनै status auto-लेखिँदैन)।
  static const double _arrivalThresholdKm = 0.03;
  bool _withinArrivalRadius = false;
  // worker ले "On Arrival" बटन साँच्चै थिचेपछि मात्र true — proximity
  // आफैंले होइन। यही deliberate tap ले arrival समय लेख्ने, दुवैतिर
  // सम्पर्क (Call/Video/Message) देखाउने, employer लाई notification पठाउने,
  // र काम status एकैचोटि 'in_progress' मा सार्ने — छुट्टै "Start Work" चरण
  // अब चाहिँदैन।
  bool _arrivalConfirmed = false;
  bool _confirmingArrival = false;

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
    _boot();
    _statusSub = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(widget.requestId)
        .snapshots()
        .listen(_onRequestSnapshot);
  }

  void _onRequestSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted || _adminCancelHandled) return;
    final status = (snap.data()?['status'] ?? '').toString();
    if (status == 'cancelled_by_admin') {
      _adminCancelHandled = true;
      _statusSub?.cancel();
      _handleCancelledByAdmin();
    }
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
      iconBg: const LinearGradient(
          colors: [AppColors.danger, AppColors.kmRose]),
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
    if (visibleRouteScreenRequestId == widget.requestId) {
      visibleRouteScreenRequestId = null;
    }
    _statusSub?.cancel();
    _posSub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  /// आफ्नो लाइभ GPS पछ्याउने + ग्राहकको स्क्रिनका लागि Firestore मा लेख्ने।
  void _startLiveTracking() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen((p) async {
      if (!mounted) return;
      final me = LatLng(p.latitude, p.longitude);
      setState(() => _me = me);

      // ग्राहकलाई लाइभ track गर्न — तर हरेक GPS tick मा होइन, कम्तिमा ५s
      // पर्खेर मात्र (25m distanceFilter सँगै) — Firestore write/employer
      // तर्फको snapshot-driven rebuild बारम्बार नहोस् भनेर (performance)।
      final now = DateTime.now();
      final dueWrite = _lastWorkerPosWrite == null ||
          now.difference(_lastWorkerPosWrite!) > const Duration(seconds: 5);
      if (dueWrite) {
        _lastWorkerPosWrite = now;
        try {
          await FirebaseFirestore.instance
              .collection('serviceRequests')
              .doc(widget.requestId)
              .update({
            'workerLat': p.latitude,
            'workerLng': p.longitude,
            'workerLocationUpdatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      // गन्तव्य-नजिक (geofence) भित्र छ/छैन मात्र ट्र्याक — यसले आफैं कुनै
      // status/arrival नलेख्ने, केवल "On Arrival" बटन unlock/lock गर्ने।
      // साँचो arrival भने worker आफैंले बटन थिचेपछि मात्र (हेर्नुहोस्
      // `_confirmArrival`) — proximity मात्रैले काम आफैं सुरु नहोस् भन्ने
      // आवश्यकता।
      final km = haversineKm(
          me.latitude, me.longitude, _employer.latitude, _employer.longitude);
      final within = km <= _arrivalThresholdKm;
      if (within != _withinArrivalRadius) {
        setState(() => _withinArrivalRadius = within);
      }

      // सडक-मार्ग बारम्बार नहित्याउन कम्तिमा १५s पर्खने।
      final dueRoute = _lastRouteFetch == null ||
          now.difference(_lastRouteFetch!) > const Duration(seconds: 15);
      if (dueRoute) {
        _lastRouteFetch = now;
        await _loadRoute();
      }
    }, onError: (_) {});
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
    if (!_withinArrivalRadius || _confirmingArrival || _arrivalConfirmed) {
      return;
    }
    setState(() => _confirmingArrival = true);
    playSuccessFeedback();
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({
        'arrivedAt': FieldValue.serverTimestamp(),
        if (!_isRide) 'status': 'in_progress',
        if (!_isRide) 'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    unawaited(_notifyEmployerArrived());
    if (!mounted) return;
    setState(() {
      _arrivalConfirmed = true;
      _confirmingArrival = false;
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
    // सुरक्षित server-side जाँच — client ले cache गरेको `_rideStartCode`
    // भन्दा ताजा doc बाटै दोहोर्‍याएर पढ्ने (कतै त्यसबीचमा नबदलिएको सुनिश्चित)।
    String? actual = _rideStartCode;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get();
      actual = (snap.data()?['rideStartCode'] ?? actual ?? '').toString();
    } catch (_) {}
    if (!mounted) return;
    if (actual == null || entered != actual) {
      setState(() {
        _verifyingCode = false;
        _codeError = S.rideCodeMismatch;
      });
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
      });
      playSuccessFeedback();
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // "यो काम स्वीकार गर्नुहोस्" पछि नक्सा स्वतः खुल्दा native Google Map
      // view attach हुन लाग्ने एक क्षणको खाली ठाउँमा dark theme को
      // झन्डै-कालो default को सट्टा यही हल्का, नक्साकै रङ — flash हुँदैन।
      backgroundColor: AppColors.mapPlaceholderBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(S.jobRouteTitle,
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
          RouteMapView(
            origin: _me,
            originLabel: S.yourLocationWord,
            destination: _target,
            destinationLabel: (_isRide && _codeVerified)
                ? S.destinationLabel
                : (widget.employerName.trim().isEmpty
                    ? S.customerWord
                    : widget.employerName),
            destinationAddress:
                (_isRide && _codeVerified) ? widget.destinationAddress : widget.address,
            route: _route,
            routeLoading: _loading,
            travelMode: _mode,
            navigateTarget: _target,
            locationPermanentlyDenied: _locationDeniedForever,
            originMissingMessage: _locationErrorMessage,
            onRetryOrigin: _locationDeniedForever || _me != null
                ? null
                : _fetchAndApplyLocation,
            mapPadding: const EdgeInsets.only(bottom: 190, top: 64),
          ),

          // ── ride-sharing style summary card ──
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
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
                                  ? '${S.serviceName(widget.service)}  ·  ${S.jobSiteWord}'
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
                  if (_arrivalConfirmed && (!_isRide || _codeVerified)) ...[
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
                          child: TextField(
                            controller: _codeController,
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
                              hintStyle:
                                  const TextStyle(color: AppColors.kmMuted, fontSize: 13),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        KmCtaButton(
                          label: S.startRideCta,
                          icon: Icons.lock_open_rounded,
                          loading: _verifyingCode,
                          onPressed: _verifyRideCode,
                        ),
                      ],
                    ),
                    if (_codeError != null) ...[
                      const SizedBox(height: 6),
                      Text(_codeError!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 11.5)),
                    ],
                  ] else ...[
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
                      child: KmCtaButton(
                        label: _withinArrivalRadius
                            ? S.onArrivalButton
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _callEmployer,
                          icon: const Icon(Icons.call_rounded, size: 18),
                          label: Text(S.callWord),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.kmText,
                            side: BorderSide(color: AppColors.kmGlassBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => startInAppCall(
                            context,
                            requestId: widget.requestId,
                            otherName: widget.employerName,
                            video: true,
                          ),
                          icon: const Icon(Icons.videocam_rounded, size: 18),
                          label: Text(S.videoCall),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.kmText,
                            side: BorderSide(color: AppColors.kmGlassBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: KmCtaButton(
                          icon: Icons.chat_bubble_rounded,
                          label: S.messageWord,
                          expand: true,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                requestId: widget.requestId,
                                workerName: widget.employerName,
                                initialStatus:
                                    (_arrivalConfirmed && (!_isRide || _codeVerified))
                                        ? 'in_progress'
                                        : 'accepted',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}
