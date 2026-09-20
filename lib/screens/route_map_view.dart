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
        travelModeMarker,
        routePolyline,
        routePolylineCasing,
        walkConnectorPolyline,
        RoadRoute,
        FlagPinGeometry,
        PulseRings,
        TravelMode;

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

  /// हालको छानिएको यात्रा-मोड — live-location marker आइकन (कार/बाइक/पैदल-
  /// यात्री, माथिबाट-हेर्दाको आकृति) यसैअनुसार तुरुन्तै बदलिन्छ।
  final TravelMode travelMode;

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
    this.travelMode = TravelMode.driving,
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

  BitmapDescriptor? _flagIcon;
  BitmapDescriptor? _originIcon;
  Offset? _pulseAt;

  // Direction-facing live marker — पहिले यहाँ हरेक GPS बिन्दुबीच सहज
  // गरी सर्ने/घुम्ने animated navigation-arrow थियो, जुन प्रत्येक movement
  // मा ~900ms सम्म frame-by-frame GoogleMap rebuild गराउँथ्यो — तर त्यो
  // ढिलाइको साँचो कारण animation आफैं होइन, हरेक frame मा marker आइकन
  // (bitmap) नै पुनः-निर्माण हुनु र/वा route/camera जस्ता महँगो काम पनि
  // सँगसँगै दोहोरिनु थियो। अब त्यही गल्ती नदोहोर्‍याई — bitmap एकपटक मात्र
  // बन्छ, हरेक tick मा त्यही `AnimationController` ले केवल [_displayedOrigin]
  // (position) र [_bearing] (rotation, GPU-side/native — Flutter बाट कुनै
  // पुनः-रेन्डर नचाहिने) मात्र अपडेट गर्छ — `setState` यही सानो widget
  // (route_map_view.dart) भित्रै सीमित, न route पुनः-तान्ने न camera
  // पुनः-fit गर्ने। यसैले Uber/Pathao जस्तै सहज ग्लाइड दिन्छ, तर हल्का।
  double _bearing = 0;
  LatLng? _bearingFrom;
  LatLng? _displayedOrigin;
  late final AnimationController _moveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(_onMoveTick);
  LatLng? _animFrom;
  LatLng? _animTo;

  // GPS jitter (उभिइरहँदा पनि १-३मी यताउता हुने) ले bearing लाई हरेक
  // पटक अनियमित दिशामा घुमाइरहनबाट जोगाउन — यो भन्दा कम चलेको बेला
  // अघिल्लै दिशा नै कायम राख्ने।
  static const double _minMoveForBearingKm = 0.004; // ~4m

  @override
  void initState() {
    super.initState();
    destinationFlagPin().then((b) {
      if (mounted) setState(() => _flagIcon = b);
    });
    // छानिएको यात्रा-मोड अनुसारको top-down कार/बाइक/पैदल-यात्री आकृति —
    // यसैको `rotation` field (माथिको `_bearing`) ले हिँडिरहेको दिशा देखाउँछ।
    _loadOriginIcon(widget.travelMode);
    _bearingFrom = widget.origin;
    // पहिलोपटक सिधै (कुनै glide बिना) देखिने — animation त बरु दोस्रो
    // बिन्दुदेखि मात्र (साँच्चै "अघिल्लो ठाउँबाट सरेको" देखियोस्)।
    _displayedOrigin = widget.origin;
  }

  void _loadOriginIcon(TravelMode mode) {
    travelModeMarker(mode).then((b) {
      if (mounted) setState(() => _originIcon = b);
    });
  }

  void _onMoveTick() {
    final from = _animFrom;
    final to = _animTo;
    if (from == null || to == null || !mounted) return;
    setState(() {
      _displayedOrigin = _lerpLatLng(from, to, _moveCtrl.value);
    });
  }

  static LatLng _lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  /// नयाँ GPS बिन्दु आउनेबित्तिकै — हालको (देखिइरहेको, नयाँ आउनुअघिकै)
  /// स्थानबाट यो नयाँ स्थानसम्म सहज गरी सार्ने (glide), सिधै "jump" होइन।
  void _startGlideTo(LatLng newOrigin) {
    _animFrom = _displayedOrigin ?? newOrigin;
    _animTo = newOrigin;
    _moveCtrl
      ..stop()
      ..reset()
      ..forward();
  }

  void _maybeUpdateBearing(LatLng newOrigin) {
    final from = _bearingFrom;
    if (from == null) {
      _bearingFrom = newOrigin;
      return;
    }
    final movedKm = haversineKm(
        from.latitude, from.longitude, newOrigin.latitude, newOrigin.longitude);
    if (movedKm < _minMoveForBearingKm) return;
    _bearing = bearingBetween(from, newOrigin);
    _bearingFrom = newOrigin;
  }

  // Camera-follow — यो भन्दा टाढा सरेपछि मात्र फेरि दुवै पिन (origin +
  // destination) देखिने गरी camera पुनः-fit गर्ने। पहिले यहाँ कहिल्यै
  // दोस्रोपटक fit हुँदैनथ्यो (सुरुमै एकपटक मात्र) — worker टाढा हिँड्दै
  // जाँदा marker स्क्रिनबाटै बाहिर गएर हराउँथ्यो, "ट्र्याकिङ अड्किएको/
  // halted" जस्तो देखिने। धेरै सानो movement मा भने re-fit नगरी (त्यो
  // भने साँच्चै jerk दिन्थ्यो) — `animateCamera` (smooth pan/zoom, कुनै
  // अचानक jump होइन) ले नै "follow" अनुभव दिन्छ।
  static const double _minMoveForRefitKm = 0.05; // ~50m
  LatLng? _lastFitOrigin;

  @override
  void didUpdateWidget(covariant RouteMapView old) {
    super.didUpdateWidget(old);
    if (widget.travelMode != old.travelMode) {
      _loadOriginIcon(widget.travelMode);
    }
    final newOrigin = widget.origin;
    if (newOrigin != null && newOrigin != old.origin) {
      _maybeUpdateBearing(newOrigin);
      if (old.origin == null) {
        // पहिलोपटक (null बाट) — सिधै देखिने, कुनै टाढाबाट glide होइन।
        _displayedOrigin = newOrigin;
      } else {
        _startGlideTo(newOrigin);
      }
    }
    final destChanged = old.destination != widget.destination;
    final originAppeared = old.origin == null && widget.origin != null;
    if (destChanged || originAppeared) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      _lastFitOrigin = newOrigin;
    } else if (newOrigin != null && newOrigin != old.origin) {
      final lastFit = _lastFitOrigin;
      final movedKm = lastFit == null
          ? double.infinity
          : haversineKm(lastFit.latitude, lastFit.longitude,
              newOrigin.latitude, newOrigin.longitude);
      if (movedKm >= _minMoveForRefitKm) {
        _lastFitOrigin = newOrigin;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      } else {
        // सानो movement — पूरै camera फेरि fit नगरी, halo मात्र refresh।
        _refreshPulse();
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _moveCtrl.dispose();
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
    CameraUpdate update;
    if (origin == null) {
      // कुनै एउटा मात्र बिन्दु थाहा छ — सिधै street/house-level close-up
      // (पहिले 15, धेरै टाढाको शहर-स्तर view थियो)।
      update = CameraUpdate.newLatLngZoom(widget.destination, 18.5);
    } else {
      final distKm = haversineKm(origin.latitude, origin.longitude,
          widget.destination.latitude, widget.destination.longitude);
      if (distKm < 0.5) {
        // दुवै बिन्दु नजिकै (सामान्यतया worker job-site नजिक पुगिसकेको) —
        // `newLatLngBounds` को fixed padding (तल हेर्नुहोस्) ले यस्तो
        // अवस्थामा पनि अनावश्यक रूपमा टाढाको zoom दिन्थ्यो; बीचको बिन्दुमा
        // सिधै close-up zoom गरेर दुवै पिन अझै टाढा नदेखियोस्।
        final mid = LatLng(
          (origin.latitude + widget.destination.latitude) / 2,
          (origin.longitude + widget.destination.longitude) / 2,
        );
        update = CameraUpdate.newLatLngZoom(mid, 18);
      } else {
        // दुवै बिन्दु टाढा-टाढा — दुवै पिन देखिनैपर्ने भएकोले जबरजस्ती
        // close-up गर्न मिल्दैन, तर padding घटाएर (90→60) सकेसम्म तानिएको।
        update = CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(min(origin.latitude, widget.destination.latitude),
                min(origin.longitude, widget.destination.longitude)),
            northeast: LatLng(max(origin.latitude, widget.destination.latitude),
                max(origin.longitude, widget.destination.longitude)),
          ),
          60,
        );
      }
    }
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
          GoogleMap(
            initialCameraPosition: CameraPosition(
                target: widget.destination, zoom: 18, bearing: 0),
            style: kCleanMapStyle,
            onMapCreated: (c) {
              _map = c;
              _fitBounds();
            },
            onCameraMoveStarted: _onCameraMoveStarted,
            onCameraIdle: _refreshPulse,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // Google को native "blue dot" + accuracy circle कहिल्यै नदेखियोस्
            // भनेर सधैँ false — माथि `_originIcon` (pulseDotMarker,
            // igViolet) ले नै "तपाईं यहाँ हुनुहुन्छ" देखाइसकेको छ; दुवै
            // एकैचोटि देखिँदा (native + custom dot) एउटै स्थानमा दुई
            // फरक-फरक थोप्ला देखिने बग हुन्थ्यो।
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            // नक्सा सधैँ उत्तर-माथि (upright) रहोस् — compass/gyroscope वा
            // दुई-औँला gesture ले घुमाएर "उल्टो/घुमेको" देखिने बग नआओस्।
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
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
              if (widget.origin != null && _originIcon != null)
                Marker(
                  markerId: const MarkerId('origin'),
                  // `_displayedOrigin` (animated glide-in-progress position)
                  // — साँचो `widget.origin` (नयाँ GPS fix) होइन, जबसम्म
                  // glide पूरा नभएको। यसैले marker सिधै "jump" नगरी सहज
                  // गरी सर्छ।
                  position: _displayedOrigin ?? widget.origin!,
                  anchor: const Offset(0.5, 0.5),
                  icon: _originIcon!,
                  // `flat: true` नभई rotation ले 3D tilt/perspective दिन्छ
                  // (उत्तर-माथि 2D नक्सामा अनावश्यक) — यसले सीधै नक्साकै
                  // सतहमा (native, GPU-side) घुमाउँछ, कुनै Flutter rebuild
                  // नचाहिने।
                  flat: true,
                  rotation: _bearing,
                  infoWindow: InfoWindow(title: widget.originLabel),
                ),
            },
            polylines: {
              if (route != null && route.points.length >= 2)
                ...[
                  // सेतो casing सधैँ मुख्य रेखामुनि — मानक Google Maps
                  // navigation जस्तै बाक्लो/छुट्टै देखियोस् भनेर।
                  routePolylineCasing('route', route),
                  routePolyline('route', route),
                  // Google Maps-शैली "last-mile" डट्टेड connector — solid
                  // road route ठ्याक्कै marker सम्मै नपुगेको खाली ठाउँमा
                  // (गन्तव्य/लाइभ स्थान दुवैतिर हुन सक्छ)।
                  if (widget.origin != null)
                    walkConnectorPolyline(
                      id: 'walk_origin',
                      routeEnd: route.points.first,
                      markerPos: widget.origin!,
                    ),
                  walkConnectorPolyline(
                    id: 'walk_destination',
                    routeEnd: route.points.last,
                    markerPos: widget.destination,
                  ),
                ].whereType<Polyline>(),
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
          // यातायात मोड (driving/walking/bike) कै आइकन — generic route/
          // timeline icon भन्दा प्रस्ट, ride-hailing app जस्तै तुरुन्तै
          // चिनिने। `!route.real` (fallback source) भए मात्र त्यो जनाउने
          // छुट्टै icon तल थपिन्छ।
          Icon(route.mode.icon, size: 16, color: const Color(0xFF111111)),
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
