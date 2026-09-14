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

  // कामदार ग्राहकको ठ्याक्कै coordinate नजिक (~50m भित्र) पुगेपछि एकपटक मात्र
  // arrival chime + sheet देखाउने — GPS jitter ले पटक-पटक नबजोस्।
  static const double _arrivalThresholdKm = 0.05;
  bool _arrived = false;

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

      // ग्राहकलाई लाइभ track गर्न — हरेक movement मा।
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

      // arrival-detection मात्र (सीधा-रेखा दूरी) — यसले कहिल्यै देखिने
      // polyline/`_route` लाई छुँदैन। `_route` अब EXCLUSIVELY `_loadRoute()`
      // (getRoute Cloud Function, साँचो सडक मार्ग) बाट मात्र सेट हुन्छ —
      // पहिले यहाँ हरेक GPS tick मा सीधा रेखा (points: [me, _employer]) ले
      // `_route` लाई तुरुन्तै ओभरराइट गर्थ्यो (त्यो पनि `real` flag साथैं
      // साटेर!), जसले साँचो मार्ग आइसकेपछि पनि अर्को tick मा फेरि सीधा
      // रेखामा फर्किने/झलक्क देखिने बग दिन्थ्यो। अब कहिल्यै सीधा रेखा
      // बन्दैन — Cloud Function ले `real: true` सहित नदिँदासम्म polyline
      // नै देखिँदैन (RouteMapView मा "route unavailable"/loading हुन्छ)।
      final km = haversineKm(
          me.latitude, me.longitude, _employer.latitude, _employer.longitude);
      if (!_arrived && km <= _arrivalThresholdKm) {
        _onArrived();
      }

      // सडक-मार्ग बारम्बार नहित्याउन कम्तिमा १५s पर्खने।
      final now = DateTime.now();
      final due = _lastRouteFetch == null ||
          now.difference(_lastRouteFetch!) > const Duration(seconds: 15);
      if (due) {
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
        _ => null, // 'denied'/'pending' — default S.locationNeededForRoute नै ठीक
      };

  /// कामदार ग्राहकको ठाउँमा पुगेपछि (Step 2: Arrival Notification) — chime +
  /// SnackBar, र काम स्थलमा पुगेको समय Firestore मा रेकर्ड।
  Future<void> _onArrived() async {
    _arrived = true;
    if (mounted) setState(() {});
    playSuccessFeedback();
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({'arrivedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.arrivedAtLocation),
        action: SnackBarAction(
          label: S.startWorkNow,
          onPressed: _startWorkFromHere,
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// यहीँबाट सिधै "काम सुरु" (in_progress) मा लैजाने — requests tab मा फर्किन
  /// नपरोस्।
  Future<void> _startWorkFromHere() async {
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .update({
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.workStarted)));
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
                  if (_arrived) ...[
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: AppColors.igViolet),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(S.arrivedAtLocation,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.igViolet)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_arrived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PrimaryButton(
                        label: S.startWorkNow,
                        icon: Icons.play_arrow_rounded,
                        onPressed: _startWorkFromHere,
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
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
