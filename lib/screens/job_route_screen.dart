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
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/success_feedback.dart';
import 'chat_screen.dart';
import 'job_actions.dart' show otherPartyUid, startInAppCall;
import 'nearby_common.dart' show haversineKm, fetchRoadRoute, RoadRoute;
import 'route_map_view.dart';

class JobRouteScreen extends StatefulWidget {
  final String requestId;
  final double employerLat;
  final double employerLng;
  final String employerName;
  final String service;
  final String address;
  final String employerPhone;

  const JobRouteScreen({
    super.key,
    required this.requestId,
    required this.employerLat,
    required this.employerLng,
    required this.employerName,
    required this.service,
    required this.address,
    this.employerPhone = '',
  });

  @override
  State<JobRouteScreen> createState() => _JobRouteScreenState();
}

class _JobRouteScreenState extends State<JobRouteScreen> {
  late final LatLng _employer = LatLng(widget.employerLat, widget.employerLng);
  LatLng? _me;
  bool _locationDeniedForever = false;
  // getCurrentLocation() ले दिएको ठ्याक्कै कारण — banner मा generic
  // "location needed" भन्दा स्पष्ट सन्देश देखाउन (fix #4: retry + real reason)।
  String _locationStatus = 'pending';

  RoadRoute? _route;
  bool _loading = true;

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

  @override
  void initState() {
    super.initState();
    visibleRouteScreenRequestId = widget.requestId;
    _boot();
  }

  @override
  void dispose() {
    if (visibleRouteScreenRequestId == widget.requestId) {
      visibleRouteScreenRequestId = null;
    }
    _posSub?.cancel();
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
    final result = await fetchRoadRoute(me, _employer);
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
  /// चाहिन्छ) — chime, arrival समय + status एकैचोटि 'in_progress' मा,
  /// employer लाई "Worker has arrived" notification, र दुवैतिर Call/Video
  /// Call/Message UI तुरुन्तै प्रस्ट देखिने।
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
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    unawaited(_notifyEmployerArrived());
    if (!mounted) return;
    setState(() {
      _arrivalConfirmed = true;
      _confirmingArrival = false;
    });
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
    final theme = Theme.of(context);
    return Scaffold(
      // "यो काम स्वीकार गर्नुहोस्" पछि नक्सा स्वतः खुल्दा native Google Map
      // view attach हुन लाग्ने एक क्षणको खाली ठाउँमा dark theme को
      // झन्डै-कालो default को सट्टा यही हल्का, नक्साकै रङ — flash हुँदैन।
      backgroundColor: AppColors.mapPlaceholderBg,
      appBar: AppBar(
        title: Text(S.jobRouteTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: Stack(
        children: [
          // ── साझा route-map widget — worker/employer दुवैतिर उही class ──
          RouteMapView(
            origin: _me,
            originLabel: S.yourLocationWord,
            destination: _employer,
            destinationLabel: widget.employerName.trim().isEmpty
                ? S.customerWord
                : widget.employerName,
            destinationAddress: widget.address,
            route: _route,
            routeLoading: _loading,
            navigateTarget: _employer,
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
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 6)),
                ],
              ),
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
                          gradient: AppColors.buttonGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: Colors.white, size: 22),
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
                                  fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            Text(
                              widget.address.trim().isEmpty
                                  ? '${S.serviceName(widget.service)}  ·  ${S.jobSiteWord}'
                                  : widget.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_arrivalConfirmed) ...[
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: AppColors.igViolet),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(S.arrivedJobInProgress,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.igViolet)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // "On Arrival" — गन्तव्यको ठ्याक्कै geofence भित्र नआएसम्म
                  // disabled नै रहन्छ; प्रयोगकर्ताले साँच्चै थिच्नुपर्छ,
                  // दूरी मात्रैले काम आफैं सुरु हुँदैन।
                  if (!_arrivalConfirmed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PrimaryButton(
                        label: _withinArrivalRadius
                            ? S.onArrivalButton
                            : S.getCloserToArrive,
                        icon: Icons.pin_drop_rounded,
                        loading: _confirmingArrival,
                        onPressed:
                            _withinArrivalRadius ? _confirmArrival : null,
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _callEmployer,
                          icon: const Icon(Icons.call_rounded, size: 18),
                          label: Text(S.callWord),
                          style: OutlinedButton.styleFrom(
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GradientActionButton(
                          icon: Icons.chat_bubble_rounded,
                          label: S.messageWord,
                          expand: true,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                requestId: widget.requestId,
                                workerName: widget.employerName,
                                // यो screen सधैँ accept भइसकेको काम (worker
                                // route मा) कै लागि मात्र खुल्छ।
                                initialStatus: 'accepted',
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
