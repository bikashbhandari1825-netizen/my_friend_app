// screens/route_map_view.dart
// काम स्वीकार भएपछि दुवैतिर (worker र employer) प्रयोग हुने साझा route-map
// widget — real सडक मार्ग (Google Directions API, असफल भए OSRM/सीधा-रेखा
// fallback — दुवै `nearby_common.dart` को साझा `fetchRoadRoute()` बाट),
// दुरी/समय जहिल्यै नक्सामाथि नै (कुनै tap नचाहिने) देखिने pill, र "Open in
// Google Maps" बटन। JobRouteScreen (worker) र RequestTrackingScreen
// (employer) दुवैले यही एउटै class प्रयोग गर्छन् — छुट्टाछुट्टै नक्सा
// बनाइएको छैन; तल्लो status/action card भने हरेकको आफ्नै भूमिका अनुसार
// फरक भएकोले caller ले `bottomCard` मार्फत आफैं थप्छ।
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import 'nearby_common.dart'
    show
        bearingBetween,
        destinationFlagPin,
        haversineKm,
        kCleanMapStyle,
        navigationArrowMarker,
        routePolyline,
        RoadRoute,
        FlagPinGeometry,
        PulseRings;

class RouteMapView extends StatefulWidget {
  /// चलिरहेको पक्ष (worker वा employer) को हालको स्थान — थाहा नभए null
  /// (अनुमति नदिँदा/GPS नआउँदा)।
  final LatLng? origin;
  final String originLabel;

  /// स्थिर काम-स्थल — दुवैतिर सधैँ एउटै coordinate।
  final LatLng destination;
  final String destinationLabel;
  final String destinationAddress;

  /// caller ले आफ्नै तरिकाले (throttled/live-tracking) निकालेको हालको route।
  final RoadRoute? route;
  final bool routeLoading;

  /// "Open in Google Maps" ले कहाँ लैजाने — null भए बटन नै लुक्छ।
  final LatLng? navigateTarget;

  /// GPS अनुमति सधैँका लागि अस्वीकृत भए — settings मा लैजाने बटन देखाउन।
  final bool locationPermanentlyDenied;

  /// `origin == null` हुँदा देखिने सन्देश — नदिए default "turn on location"।
  /// employer को screen ले यहाँ "Waiting for worker location" जस्तो फरक
  /// सन्देश दिन्छ, किनकि त्यहाँ आफ्नै GPS होइन, worker को लाइभ स्थान नआएको हो।
  final String? originMissingMessage;

  /// दिइएमा, `originMissingMessage`/default सन्देशको छेउमा "Retry" बटन देखाउने
  /// (worker को आफ्नै GPS fetch असफल भएको केसमा प्रयोग गर्न)।
  final VoidCallback? onRetryOrigin;

  final EdgeInsets mapPadding;

  const RouteMapView({
    super.key,
    required this.origin,
    required this.originLabel,
    required this.destination,
    required this.destinationLabel,
    this.destinationAddress = '',
    required this.route,
    this.routeLoading = false,
    this.navigateTarget,
    this.locationPermanentlyDenied = false,
    this.originMissingMessage,
    this.onRetryOrigin,
    this.mapPadding = const EdgeInsets.only(top: 64, bottom: 16),
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView>
    with TickerProviderStateMixin {
  GoogleMapController? _map;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  // ── worker/vehicle marker: नयाँ GPS बिन्दु आउनेबित्तिकै तुरुन्तै नउफ्रिने
  // (teleport), बरु navigation app जस्तै ~900ms मा सहज गरी सर्ने + दिशा
  // (bearing) अनुसार घुम्ने। स्थान/दिशा दुवै `build()` भित्रैको
  // `AnimatedBuilder` ले (यहाँ `setState` कहीं छैन — पहिले `onCameraMove`
  // मा जस्तै हरेक frame मा पूरै widget rebuild हुने गल्ती यहाँ दोहोर्‍याइएको
  // छैन) `_move.value` बाट live computed हुन्छन्; GoogleMap कै Camera-fit
  // भने सधैँ साँचो (interpolate नभएको) `widget.origin` प्रयोग गर्छ।
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  LatLng? _lastKnownOrigin; // पछिल्लो साँचो (राw) GPS बिन्दु — bearing निकाल्न
  LatLng? _posStart;
  LatLng? _posTarget;
  double _headingStart = 0;
  double _headingTarget = 0;

  /// `_move` को अहिलेको मानमा आधारित, अहिले नक्सामा देखिनुपर्ने (interpolated)
  /// स्थान। `_posStart`/`_posTarget` नभेटिए (अझै कुनै GPS नआएको) null।
  LatLng? get _currentRenderedOrigin {
    final start = _posStart;
    final target = _posTarget;
    if (start == null || target == null) return _lastKnownOrigin;
    final t = Curves.easeInOut.transform(_move.value);
    return LatLng(
      start.latitude + (target.latitude - start.latitude) * t,
      start.longitude + (target.longitude - start.longitude) * t,
    );
  }

  double get _currentHeading {
    final t = Curves.easeInOut.transform(_move.value);
    return _lerpAngle(_headingStart, _headingTarget, t);
  }

  /// कोण दुई मानको छोटो बाटो हुँदै interpolate — नत्र ३५०°→१०° जस्तो
  /// घुमाइ गलत दिशाबाट (लामो बाटो, -३४०°) हुन्थ्यो।
  static double _lerpAngle(double a, double b, double t) {
    var diff = (b - a) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (a + diff * t) % 360;
  }

  BitmapDescriptor? _flagIcon;
  BitmapDescriptor? _navIcon;
  Offset? _pulseAt;

  @override
  void initState() {
    super.initState();
    destinationFlagPin().then((b) {
      if (mounted) setState(() => _flagIcon = b);
    });
    navigationArrowMarker(AppColors.igViolet).then((b) {
      if (mounted) setState(() => _navIcon = b);
    });
    final origin = widget.origin;
    if (origin != null) {
      _lastKnownOrigin = origin;
      _posStart = origin;
      _posTarget = origin;
      // गाडी चल्न सुरु नगरेसम्म — गन्तव्यतिरै फर्किएको मान्ने (सामान्य
      // navigation app को default व्यवहार)।
      _headingStart = bearingBetween(origin, widget.destination);
      _headingTarget = _headingStart;
    }
  }

  @override
  void didUpdateWidget(covariant RouteMapView old) {
    super.didUpdateWidget(old);
    final destChanged = old.destination != widget.destination;
    final originAppeared = old.origin == null && widget.origin != null;
    if (destChanged || originAppeared) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    } else if (old.origin != widget.origin) {
      // हरेक GPS movement मा पूरै camera फेरि fit नगरी — halo मात्र refresh
      // (नत्र worker आफैं चल्दा नक्सा बारम्बार जर्क हुन्छ)।
      _refreshPulse();
    }

    final newOrigin = widget.origin;
    if (newOrigin == null) return;
    final last = _lastKnownOrigin;
    if (last == null) {
      // पहिलोपटक GPS आयो — सीधै देखाउने, कतैबाट "उड्ने" एनिमेसन चाहिँदैन।
      _lastKnownOrigin = newOrigin;
      _posStart = newOrigin;
      _posTarget = newOrigin;
      _headingStart = bearingBetween(newOrigin, widget.destination);
      _headingTarget = _headingStart;
      return;
    }
    // GPS jitter (केही मिटर भित्रको शोर) ले बारम्बार दिशा नबदलियोस् भनेर
    // कम्तिमा ~3m चलेको भए मात्र नयाँ bearing/एनिमेसन।
    final movedKm = haversineKm(
        last.latitude, last.longitude, newOrigin.latitude, newOrigin.longitude);
    if (movedKm < 0.003) return;

    // अघिल्लो एनिमेसन अझै चलिरहेको भए, त्यसको अहिलेकै (बीचैमा भएको) देखिने
    // स्थान/दिशाबाटै नयाँ यात्रा सुरु हुने — नत्र बीचमै अर्को अपडेट आउँदा
    // marker पुरानो लक्ष्यमा फर्केर उफ्रिन्थ्यो।
    _headingStart = _currentHeading;
    _headingTarget = bearingBetween(last, newOrigin);
    _posStart = _currentRenderedOrigin ?? last;
    _posTarget = newOrigin;
    _lastKnownOrigin = newOrigin;
    _move
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _move.dispose();
    _map?.dispose();
    super.dispose();
  }

  // पहिलोपटकको fit मात्र `moveCamera` (तुरुन्तै, कुनै pan-animation नगरी) —
  // `animateCamera` ले टाढाको सुरुवात बिन्दुदेखि गन्तव्यसम्म नक्सालाई
  // दृश्यात्मक रूपमा उड्दै/जुम गर्दै लैजान्छ, र त्यो बीचको हरेक zoom/pan
  // फ्रेमका tile अझै cache नभएकोले सेतो/खाली देखिन्छ (ठ्याक्कै "गन्तव्य र
  // प्रयोगकर्ताको बीचमा खाली नक्सा" भन्ने गुनासो)। सीधै उफ्रिँदा (moveCamera)
  // ती बीचका फ्रेम कहिल्यै render नै हुँदैनन् — अन्तिम स्थिर दृश्यको tile
  // मात्र लोड हुन्छ। पछिका fit (destination/route परिवर्तन भएमा) भने सहज
  // देखियोस् भनेर अझै animate नै गर्छ।
  bool _didInitialFit = false;

  void _fitBounds() {
    final c = _map;
    if (c == null) return;
    final origin = widget.origin;
    final update = origin == null
        ? CameraUpdate.newLatLngZoom(widget.destination, 15)
        : CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(min(origin.latitude, widget.destination.latitude),
                  min(origin.longitude, widget.destination.longitude)),
              northeast: LatLng(max(origin.latitude, widget.destination.latitude),
                  max(origin.longitude, widget.destination.longitude)),
            ),
            90,
          );
    if (_didInitialFit) {
      c.animateCamera(update);
    } else {
      _didInitialFit = true;
      c.moveCamera(update);
    }
    Future.delayed(const Duration(milliseconds: 350), _refreshPulse);
  }

  Future<void> _refreshPulse() async {
    final c = _map;
    if (c == null || !mounted) return;
    try {
      final sc = await c.getScreenCoordinate(widget.destination);
      if (!mounted) return;
      final mq = MediaQuery.of(context);
      final raw = Offset(sc.x.toDouble(), sc.y.toDouble());
      final off = kIsWeb ? raw : raw / mq.devicePixelRatio;
      final size = mq.size;
      final onScreen = off.dx > -120 &&
          off.dy > -120 &&
          off.dx < size.width + 120 &&
          off.dy < size.height + 120;
      if (mounted) setState(() => _pulseAt = onScreen ? off : null);
    } catch (_) {}
  }

  /// gesture (pan/pinch) सुरु हुनेबित्तिकै — halo लाई लगत्तै लुकाउने (एकपटक
  /// मात्रको सस्तो setState, per-frame होइन)। पहिले यहाँ `onCameraMove` ले
  /// प्रत्येक frame मा (गेस्चर छँदासम्म सेकेन्डको दर्जनौँ पटक)
  /// `getScreenCoordinate` (native platform-channel round-trip) कल गरेर
  /// अनि `setState` (पूरै widget rebuild, GoogleMap कै markers/polylines
  /// Set सहित) गथ्र्यो — यही नै नक्सा touch गर्दा/तान्दा फोन ढिलो/jerky
  /// भएको साँचो कारण थियो। अब गेस्चर चलिरहेको बेला कुनै पनि platform call
  /// वा rebuild हुँदैन; `onCameraIdle` ले गेस्चर टुंगिएपछि एकपटक मात्र सही
  /// स्थानमा halo फर्काउँछ।
  void _onCameraMoveStarted() {
    if (_pulseAt != null) setState(() => _pulseAt = null);
  }

  Future<void> _openInGoogleMaps() async {
    final target = widget.navigateTarget;
    if (target == null) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination='
        '${target.latitude},${target.longitude}&travelmode=driving');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = widget.route;
    return ColoredBox(
      // native platform view attach हुनुअघिको क्षणभर यही देखियोस् भनेर —
      // caller (JobRouteScreen/RequestTrackingScreen) को Scaffold background
      // पनि यही राखिएको छ, तर यहाँ widget-level मै राख्दा यो कतै अरू ठाउँमा
      // (फरक/dark background भएको) प्रयोग भए पनि कहिल्यै कालो flash हुँदैन।
      color: AppColors.mapPlaceholderBg,
      child: Stack(
        children: [
          // `_move` को हरेक tick मा यहाँभित्रको GoogleMap मात्र फेरि
          // बन्छ (setState होइन, AnimatedBuilder) — नक्साबाहिरका अरू
          // widget (pill, halo स्थिति हिसाब आदि) हरेक frame मा रिबिल्ड
          // हुँदैनन्, जुन पहिले onCameraMove/radar-wave मा भेटिएको
          // jank-कारक ढाँचा हो।
          AnimatedBuilder(
            animation: _move,
            builder: (context, _) {
              final renderedOrigin = _currentRenderedOrigin;
              final heading = _currentHeading;
              return GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: widget.destination, zoom: 13),
                style: kCleanMapStyle,
                onMapCreated: (c) {
                  _map = c;
                  _fitBounds();
                },
                onCameraMoveStarted: _onCameraMoveStarted,
                onCameraIdle: _refreshPulse,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                padding: widget.mapPadding,
                markers: {
                  // झन्डाको bitmap load नभएसम्म marker नै नदेखाउने — कुनै
                  // default/fallback pin कहिल्यै यसको सट्टा नदेखियोस्।
                  if (_flagIcon != null)
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: widget.destination,
                      anchor: FlagPinGeometry.markerAnchorFraction,
                      icon: _flagIcon!,
                      infoWindow: InfoWindow(
                        title: widget.destinationLabel,
                        snippet: widget.destinationAddress.isEmpty
                            ? S.jobSiteWord
                            : widget.destinationAddress,
                      ),
                    ),
                  if (renderedOrigin != null)
                    Marker(
                      markerId: const MarkerId('origin'),
                      position: renderedOrigin,
                      rotation: heading,
                      flat: true,
                      anchor: const Offset(0.5, 0.5),
                      icon: _navIcon ??
                          BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueAzure),
                      infoWindow: InfoWindow(title: widget.originLabel),
                    ),
                },
                polylines: {
                  if (route != null && route.points.length >= 2)
                    routePolyline('route', route),
                },
              );
            },
          ),

          // ── इनड्राइभ-शैलीको धड्किने halo, स्थिर काम-स्थलको पिनमाथि ──
          if (_pulseAt != null)
            Positioned(
              left: _pulseAt!.dx - 70,
              top: _pulseAt!.dy - 70,
              child: PulseRings(t: _pulse, color: AppColors.igViolet),
            ),

          // ── दूरी/समय — नक्सामाथि सधैँ देखिने pill, कुनै tap नचाहिने ──
          Positioned(
            top: 14,
            left: 12,
            right: 12,
            child: Center(child: _summaryPill(theme)),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(ThemeData theme) {
    final route = widget.route;
    Widget content;
    if (widget.locationPermanentlyDenied) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_rounded,
              size: 15, color: AppColors.warning),
          const SizedBox(width: 8),
          Flexible(
            child: Text(S.locationNeededForRoute,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: openLocationAppSettings,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(S.openSettings,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      );
    } else if (widget.origin == null) {
      content = widget.routeLoading
          ? _loadingRow(S.findingRoute)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off_rounded,
                    size: 15, color: AppColors.warning),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                      widget.originMissingMessage ?? S.locationNeededForRoute,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (widget.onRetryOrigin != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onRetryOrigin,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(S.retryWord,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            );
    } else if (widget.routeLoading) {
      content = _loadingRow(S.findingRoute);
    } else if (route == null) {
      // Cloud Function (Directions + OSRM दुवै) असफल भयो — कहिल्यै सीधा
      // रेखालाई "route" भनेर नदेखाउने; प्रस्ट रूपमा unavailable भन्ने।
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 15, color: AppColors.warning),
          const SizedBox(width: 8),
          Flexible(
            child: Text(S.routeUnavailable,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            route.real ? Icons.route_rounded : Icons.timeline_rounded,
            size: 16,
            color: const Color(0xFF111111),
          ),
          const SizedBox(width: 8),
          Text(
            '${route.km.toStringAsFixed(route.km < 10 ? 1 : 0)} km  ·  ${S.minutesShort(route.minutes)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          if (!route.real) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: S.routeFallbackWarning,
              child: const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.warning),
            ),
          ],
          if (widget.navigateTarget != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _openInGoogleMaps,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: content,
    );
  }

  Widget _loadingRow(String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 9),
          Text(label,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      );
}
