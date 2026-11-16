// screens/route_map_view.dart
// काम स्वीकार भएपछि दुवैतिर (worker र employer) प्रयोग हुने साझा route-map
// widget — real सडक मार्ग (Google Directions API, असफल भए OSRM/सीधा-रेखा
// fallback — दुवै `nearby_common.dart` को साझा `fetchRoadRoute()` बाट),
// दुरी/समय जहिल्यै नक्सामाथि नै (कुनै tap नचाहिने) देखिने pill, र "Open in
// Google Maps" बटन। JobRouteScreen (worker) र RequestTrackingScreen
// (employer) दुवैले यही एउटै class प्रयोग गर्छन् — छुट्टाछुट्टै नक्सा
// बनाइएको छैन; तल्लो status/action card भने हरेकको आफ्नै भूमिका अनुसार
// फरक भएकोले caller ले `bottomCard` मार्फत आफैं थप्छ।
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'nearby_common.dart'
    show
        bearingBetween,
        destinationFlagPin,
        haversineKm,
        kCloudMapId,
        labeledFlagPin,
        shortestAngleDelta,
        travelModeMarker,
        travelModeMarkerRotated,
        routePolyline,
        routePolylineCasing,
        walkConnectorPolyline,
        RoadRoute,
        FlagPinGeometry,
        MapPinKind,
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

  /// Ride (Bike/Car) सुरु भइसकेपछि (OTP मिलेर status 'in_progress') मात्र
  /// true — त्यसपछि क्यामेरा pickup↔destination bounds-fit (टाढा भए टाढैको
  /// zoom-out) छोडेर सधैँ ड्राइभरको हालको स्थानमै street/building-level
  /// close-up (zoom १९) मा लक हुन्छ, गाडी बाटोमा सर्दा सर्दै "vividly"
  /// पछ्याउँदै। राइड सुरु नभएसम्म (pickup तिर आउँदै गर्दा) पहिलेकै
  /// bounds-fit व्यवहार यथावत्।
  final bool rideStarted;

  /// Full-Journey Preview — pickup तिर आउँदै गर्दा (अझै `rideStarted` नभएको
  /// बेला) साँचो अन्तिम गन्तव्य (drop-off) पनि देखाउन चाहेमा caller ले यी
  /// दिन्छ — माथिको मुख्य `destination`/`route` (जुन त्यो बेला pickup नै
  /// हो) लाई कहिल्यै नछोइकन, एउटा छुट्टै हल्का/dimmed दोस्रो marker +
  /// polyline मात्र थपिन्छ। राइड सुरु भइसकेपछि यी caller ले नदिए/null
  /// राखे पुग्छ (त्यो बेला मुख्य destination नै drop-off भइसक्छ)।
  final LatLng? secondaryDestination;
  final String secondaryDestinationLabel;
  final RoadRoute? secondaryRoute;

  /// true भए `destination`/`secondaryDestination` मार्कर दुवैमा
  /// `labeledFlagPin()` (झन्डाको ठ्याक्कै माथि सधैँ देखिने लेबल-ब्याज, एउटै
  /// static bitmap भित्रै baked — tap नचाहिने) प्रयोग हुन्छ, सामान्य tap-only
  /// `InfoWindow` को सट्टा। Ride screens (job_route_screen/
  /// request_tracking_screen) ले मात्र यो true दिन्छन् — job-portal screens
  /// अहिलेकै व्यवहारमै (अपरिवर्तित) रहन्छन्।
  final bool showPointLabels;

  /// GPS Velocity Fusion — साँचो GPS chip (Geolocator को `Position.speed`/
  /// `.heading`, Doppler-आधारित, phone कै physical orientation मा भर नपर्ने
  /// — फोन खल्तीमा/हातमा जुनसुकै तरिकाले भए पनि, सवारी साँच्चै कति छिटो/
  /// कुन दिशामा गइरहेको छ भन्ने सही संकेत) बाट आएको हो भने — glide-अवधि
  /// (पहिले travel-mode अनुसारको स्थिर अनुमान मात्र थियो, जस्तै bike=6m/s
  /// सधैं, वास्तविक गति १५ होस् कि ४० km/h) र bearing (पहिले route-tangent
  /// अनुसार मात्र, GPS fix आउनेबित्तिकै होइन) दुवै यिनै साँचो मानबाट अझ
  /// सही/तुरुन्तै हुन्छन्। caller ले confidence (speedAccuracy/headingAccuracy)
  /// पहिल्यै जाँचेर मात्र पठाउनुपर्छ — null/कम-विश्वासिलो भए पुरानै
  /// (travel-mode अनुमान/route-tangent) fallback स्वतः लागू हुन्छ।
  final double? gpsSpeedMps;
  final double? gpsHeadingDeg;

  /// Custom 3D Pickup & Drop Pins — `destination` (primary marker) ले
  /// pickup हो कि drop-off हो भनेर caller ले प्रत्यक्ष तोक्ने (`rideStarted`
  /// बाट अनुमान गर्न मिल्दैन — त्यो त camera-follow mode का लागि मात्र हो,
  /// job_route_screen.dart मा साँचो संकेत `_codeVerified` हो, request_
  /// tracking_screen.dart मा `useDestination` — दुवै `rideStarted`/
  /// `driverArrived` भन्दा फरक milestone)। false (default) = pickup, true
  /// = drop-off। `secondaryDestination` सधैँ अन्तिम गन्तव्य (drop-off) को
  /// preview भएकोले यसमा निर्भर गर्दैन, सधैँ सुनौलो।
  final bool primaryIsDropoff;

  /// Sensor-Fusion Heading Override — दिइएमा (caller, driver-side मात्र,
  /// mounted-phone मान्यता सहित) यो Stream बाट आउने हरेक नयाँ बेअरिङ
  /// (gyroscope-संचालित, निरन्तर/हरेक sensor-sample मा — GPS fix भन्दा
  /// बढी बारम्बार) सिधै marker-rotation मा लागू हुन्छ, `_onMoveTick`-कै
  /// route-tangent/GPS-heading बेअरिङ logic लाई पूर्ण रूपमा बाइपास गरेर।
  /// Position glide भने अझै जस्ताको-त्यस्तै (GPS/simulate-driven) रहन्छ —
  /// यो केवल दिशा/rotation मात्र साँघुर्‍याउँछ। `null` भए (default, सबै
  /// अन्य caller) पुरानै व्यवहार अपरिवर्तित।
  final Stream<double>? headingOverrideStream;

  /// `NativeRouteMapView.vehicleTypeOverride` कै उही अर्थ — Auto-Rickshaw
  /// जस्तो `TravelMode` मा नभएको छुट्टै आइकन चाहिँदा caller ले सिधै asset
  /// path दिन सक्छ (`null` भए सधैंझैं `travelMode` बाटै)।
  final String? vehicleIconOverride;

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
    this.rideStarted = false,
    this.primaryIsDropoff = false,
    this.secondaryDestination,
    this.secondaryDestinationLabel = '',
    this.secondaryRoute,
    this.showPointLabels = false,
    this.gpsSpeedMps,
    this.gpsHeadingDeg,
    this.headingOverrideStream,
    this.vehicleIconOverride,
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

// `ChangeNotifier.notifyListeners()` आफैं `@protected` हो — बाहिरबाट सिधै
// बोलाउन मिल्दैन। `tick()` ले यहीभित्रैबाट मात्र खोल्छ।
class _TickNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// 1D Kalman Filter — route-दूरी (km, state `s`) र गति (km/s, state `v`) मात्र
/// filter गर्ने scalar/2-state फिल्टर। `_projectDistanceAlongRouteWindowed`
/// ले road-snapping मार्फत पहिल्यै 2D GPS jitter लाई 1D (route-सुरुदेखिको
/// दूरी) मा खुम्च्याइसकेको हुन्छ — यो filter त्यो बाँकी 1D noise लाई
/// predict (गति-आधारित अनुमान) + update (नयाँ measurement सँग मिसाउने)
/// दुई चरणमा थप सुमसुम्याउँछ। Output सधैं route.points माथि नै प्रयोग
/// हुने भएकोले (कहिल्यै कच्चा lat/lng होइन) फिल्टर गरिएको मानले पनि
/// मार्करलाई कहिल्यै सडकबाहिर लैजान सक्दैन — केवल दूरी (र त्यसैबाट
/// निस्किने गति/glide) मात्र सुमसुम्याउँछ।
class _DistanceKalman1D {
  double _s = 0;
  double _v = 0;
  // Covariance [[pss, psv],[psv, pvv]] — symmetric भएकोले 3 मान पर्याप्त।
  double _pss = 1, _psv = 0, _pvv = 1;
  bool _initialized = false;

  // Process noise — "white-noise acceleration" मोडेल (standard CV-Kalman
  // process-noise form): sigma_a (km/s², गाडीको अनुमानित गति-परिवर्तन दर)
  // बाट नै dt-अनुसार Q = sigma_a² * [[dt⁴/4, dt³/2], [dt³/2, dt²]] निस्कन्छ
  // (तलको `filter()` मा)। sigma_a = ~3 m/s² (bike/car को सामान्य गति-
  // उतार-चढावको माथिल्लो सीमा जति)।
  static const double _sigmaAccelKmPerS2 = 0.003;
  // Measurement noise — projected-दूरी measurement मा कति विश्वास गर्ने
  // (~8m std-dev जति GPS/road-snap noise अनुमान गरेर)। यो [_sigmaAccelKmPerS2]
  // सापेक्ष सानो राखिएकोले मात्र filter ले साँच्चै jitter सुमसुम्याउँछ —
  // नत्र (पहिले यहाँ सबै covariance term मा एउटै `qAccel*dt²` जोडिएको
  // बग थियो) Kalman gain ~1 नजिक पुगेर measurement लाई लगभग जस्ताको-त्यस्तै
  // पास गर्थ्यो, कुनै वास्तविक smoothing नदिई।
  static const double _rMeasurement = 0.00006;

  void reset(double s) {
    _s = s;
    _v = 0;
    _pss = 1;
    _psv = 0;
    _pvv = 1;
    _initialized = true;
  }

  /// [measurement] (route-projected दूरी, km) लाई [dtSeconds] (अघिल्लो
  /// filter() कलदेखिको वास्तविक समय-अन्तर) प्रयोग गरेर predict+update
  /// गर्छ, filtered दूरी (km) फर्काउँछ। पहिलोपटक (अझै initialize नभएको)
  /// सिधै measurement लाई नै state मानेर सुरु गर्छ — कुनै "शून्यबाट उफ्रने"
  /// transient छैन।
  double filter(double measurement, double dtSeconds) {
    if (!_initialized) {
      reset(measurement);
      return measurement;
    }
    final dt = dtSeconds.clamp(0.05, 3.0);
    // Predict — standard CV (constant-velocity) Kalman propagation:
    // P_pred = F·P·Fᵀ + Q, जहाँ F = [[1,dt],[0,1]] र Q (white-noise-
    // acceleration discretization) = sigma_a² * [[dt⁴/4, dt³/2],[dt³/2, dt²]]।
    final sPred = _s + _v * dt;
    final vPred = _v;
    const accelVar = _sigmaAccelKmPerS2 * _sigmaAccelKmPerS2;
    final qSS = accelVar * dt * dt * dt * dt / 4;
    final qSV = accelVar * dt * dt * dt / 2;
    final qVV = accelVar * dt * dt;
    final pssPred = _pss + 2 * _psv * dt + _pvv * dt * dt + qSS;
    final psvPred = _psv + _pvv * dt + qSV;
    final pvvPred = _pvv + qVV;

    // Update (measurement = दूरी मात्र, H = [1, 0])
    final y = measurement - sPred;
    final sInnovation = pssPred + _rMeasurement;
    final kS = pssPred / sInnovation;
    final kV = psvPred / sInnovation;

    _s = sPred + kS * y;
    _v = vPred + kV * y;
    _pss = (1 - kS) * pssPred;
    _psv = (1 - kS) * psvPred;
    _pvv = pvvPred - kV * psvPred;

    return _s;
  }
}

class _RouteMapViewState extends State<RouteMapView>
    with TickerProviderStateMixin {
  // Worker Close-Follow Camera — पहिले zoom-१९/centered/bearing-follow
  // क्यामेरा (तल `_fitBounds`/`_onMoveTick`) केवल `rideStarted` (राइड सुरु
  // भइसकेपछि) मात्र सक्रिय हुन्थ्यो — सामान्य (non-ride) काम-पोर्टलको worker
  // स्क्रिनमा त यो कहिल्यै सक्रिय नै हुँदैनथ्यो, जहाँ सधैँ टाढाको bounds-fit
  // मात्र देखिन्थ्यो। `widget.navigateTarget` worker कै आफ्नै JobRouteScreen
  // बाहेक अरू कसैले (employer को RequestTrackingScreen ले) कहिल्यै दिँदैन
  // (हेर्नुहोस् माथिको class-doc) — त्यसैले यही भरपर्दो "worker आफ्नै
  // navigation view हो" संकेत, छुट्टै नयाँ parameter नथपी। worker कै सिंगो
  // active-tracking अवधि (pickup तिर आउँदै गर्दा समेत, राइड मात्र होइन)
  // भरि नै close-up/centered camera, employer को map (bounds-fit) भने
  // जस्ताको-त्यस्तै अपरिवर्तित।
  bool get _closeFollowCamera => widget.rideStarted || widget.navigateTarget != null;

  /// Follow मा (native) बाइक नक्साको marker होइन, स्क्रिनको ठ्याक्कै बीचमा
  /// राखिएको Flutter आइकन हो — क्यामेरा नै बाइकमा लक भएकोले दृश्यमा उस्तै
  /// देखिन्छ, तर प्रति-frame marker/polyline platform-channel update हुँदैन।
  ///
  /// Uber-शैली: प्रयोगकर्ताले नक्सा छुँदा/तान्दा follow रोकिन्छ — गाडी स्क्रिनमा
  /// गाडिएको फोटो होइन, नक्साकै साँचो स्थान (असली Marker) मा बस्छ र बाटोमै सर्छ।
  /// औँला उठाएको केही सेकेन्डपछि (वा "recenter" थिचेपछि) फेरि follow।
  bool get _centerOverlay => !kIsWeb && _closeFollowCamera && !_followPaused;

  bool _followPaused = false;
  Timer? _resumeFollowTimer;

  void _pauseFollow() {
    if (kIsWeb || !_closeFollowCamera) return;
    _resumeFollowTimer?.cancel();
    if (!_followPaused && mounted) setState(() => _followPaused = true);
  }

  void _scheduleResumeFollow() {
    if (!_followPaused) return;
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 6), _resumeFollow);
  }

  void _resumeFollow() {
    _resumeFollowTimer?.cancel();
    if (!_followPaused || !mounted) return;
    setState(() => _followPaused = false);
    final at = _displayedOrigin ?? widget.origin;
    if (at != null) _followCameraTo(at);
  }

  String get _vehicleAsset =>
      widget.vehicleIconOverride ??
      switch (widget.travelMode) {
        TravelMode.driving => 'assets/images/car_top.png',
        TravelMode.bicycling => 'assets/images/bike_top.png',
        TravelMode.walking => 'assets/images/walking_top.png',
      };

  GoogleMapController? _map;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  BitmapDescriptor? _flagIcon;
  BitmapDescriptor? _originIcon;
  // Flutter Web Marker-Rotation Workaround — हेर्नुहोस् `nearby_common.dart`
  // को `travelModeMarkerRotated()` doc-comment। Web मा `Marker.rotation`
  // लागू नहुने भएकोले यहाँ आफैं पहिल्यै-घुमाइएको bitmap राख्छौं।
  BitmapDescriptor? _webRotatedIcon;
  double? _webRotatedIconBucket;
  // Web Rotation Out-Of-Order Fix — हरेक नयाँ bucket-request लाई यो counter
  // ले क्रम-संख्या दिन्छ। `travelModeMarkerRotated()` (canvas rasterize +
  // PNG encode, async) ले फर्काउने Future हरू सधैँ सुरु भएकै क्रममा नै
  // नफर्कने (मोडिँदै गर्दा धेरै bucket छोटो-छोटो अन्तरालमा एकपछि अर्को
  // माग्दा, कुनै एउटा अघिल्लोभन्दा ढिलो आइपुग्न सक्छ) — अघिल्लो (पुरानो)
  // bucket को नतिजा नयाँ (पछिल्लो) भन्दा पछि आइपुगेर `_webRotatedIcon`
  // लाई फेरि पुरानो/गलत दिशामा फर्काइदिने बग थियो, ठ्याक्कै मोडिँदाको
  // क्षणमा आइकन अचानक "अडकिएको/तेर्सो" देखिने गुनासोको साँचो जड (native
  // मा यो समस्या नै हुँदैन, त्यहाँ GPU-side `rotation:_bearing` सिधै,
  // कुनै async bitmap-fetch बिना)। अब हरेक request आफ्नै सिरियल नम्बर
  // बोकेर आउँछ — फर्किँदा त्यही अझै सबैभन्दा पछिल्लो हो भने मात्र लागू
  // हुन्छ, पुरानो/stale नतिजा सिधै बेवास्ता हुन्छ।
  int _webRotatedRequestSeq = 0;
  Offset? _pulseAt;

  // "Pickup Point"/"Drop Point" जस्ता सधैँ-देखिने लेबल-ब्याज बोकेको मार्कर
  // (`showPointLabels` बेला मात्र, `labeledFlagPin()` बाट) — label text
  // बदलिएबित्तिकै (pickup↔drop फेज फेरिँदा) नयाँ bitmap पुनः-लोड हुन्छ।
  BitmapDescriptor? _primaryLabeledIcon;
  Offset? _primaryLabeledAnchor;
  String? _primaryLabeledFor;
  BitmapDescriptor? _secondaryLabeledIcon;
  Offset? _secondaryLabeledAnchor;
  String? _secondaryLabeledFor;

  // Uber-शैलीको "बगेको लाइट" — रुटको पोलिलाइनमाथि सानो उज्यालो खण्ड
  // (comet-tail) निरन्तर अगाडि सर्दै loop हुने। हरेक frame मा setState
  // (polylines Set rebuild) महँगो हुने भएकोले ~18fps मा throttle गरिएको —
  // आँखाले सहज नै देख्छ, तर माथिको marker-glide कै जस्तो per-frame
  // platform-channel/rebuild jank निम्त्याउँदैन।
  late final AnimationController _lightCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  double _lightProgress = 0;
  DateTime _lastLightTick = DateTime.fromMillisecondsSinceEpoch(0);

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
  //
  // Bearing Jerk Fix — माथिको दाबी (हरेक tick मा `_bearing` पनि अपडेट
  // हुन्छ) पहिले वास्तवमा साँचो थिएन: `_onMoveTick()` ले `_displayedOrigin`
  // मात्र लर्प गर्थ्यो, `_bearing` भने `_maybeUpdateBearing()` ले सिधै
  // (कुनै animation बिना) नयाँ GPS बिन्दु आउनेबित्तिकै एकैचोटि सेट गर्थ्यो।
  // नतिजा: स्थान (position) त सहज गरी सर्थ्यो, तर गाडी/बाइकको दिशा
  // (rotation) भने प्रत्येक नयाँ GPS fix मा *तुरुन्तै उफ्रन्थ्यो* — ठ्याक्कै
  // गाडी मोडिँदा आइकन "झट्का" खाएको देखिने गुनासो। अब `_bearing` पनि
  // position जस्तै गरी उही `_moveCtrl` बाटै (उही 900ms मा, उही frame मा)
  // एनिमेट हुन्छ — `_bearingAnimFrom`/`_bearingAnimTo` ले कुन बिन्दुबाट कुन
  // बिन्दुसम्म, `_shortestAngleDelta` ले 0°/360° wrap (जस्तै 350°→10°) मा
  // सधैँ छोटो बाटो (फक्त २०°, ३४०° घुमेर गएको जस्तो नदेखियोस्) रोज्छ।
  double _bearing = 0;
  double? _bearingAnimFrom;
  double? _bearingAnimTo;
  LatLng? _bearingFrom;
  LatLng? _displayedOrigin;
  // Narrow-Rebuild Notifier — `_onMoveTick`/`_onLightTick` पहिले यहीं
  // `setState()` बोलाउँथे, जसले `_RouteMapViewState.build()` सिंगै
  // (GoogleMap + summary pill + pulse overlay, सबै) दोहोर्‍याउँथ्यो — तर ती
  // दुई ticker ले साँच्चै छुने भनेको `GoogleMap` कै markers/polylines Set
  // मात्र हो (pill/pulse आफैं त्यही फ्रेममा कहिल्यै बदलिंदैनन्)। अब
  // `_liveTick` (साधारण `ChangeNotifier`) ले मात्र notify गर्छ, र तल
  // `build()` मा केवल `GoogleMap` लाई मात्र बेर्ने `AnimatedBuilder` ले
  // सुन्छ — बाँकी Stack (pill/pulse/ColoredBox) हरेक tick मा फेरि
  // rebuild/diff हुनुपर्दैन। Throttle (तलको `_kMoveTickThrottleMs`/
  // `_kLightTickThrottleMs`) जस्ताको-त्यस्तै अपरिवर्तित रहन्छ — यो केवल
  // "कति बेला" होइन, "के rebuild हुन्छ" मात्र साँघुर्‍याउँछ।
  final _TickNotifier _liveTick = _TickNotifier();
  late final AnimationController _moveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )
    ..addListener(_onMoveTick)
    ..addStatusListener(_onMoveStatus);
  // GPS-Latency Coast — glide सकिएपछि अर्को साँचो अपडेट नआउँदासम्म आइकन
  // ठ्याक्कै त्यहीं पूर्ण स्थिर बसिरहन्थ्यो — Firestore/GPS tick एक-आधा
  // सेकेन्ड ढिलो आए पनि त्यति बेला "रोकिएको" देखिने गुनासो। अब glide साँच्चै
  // सकिएपछि (अर्को वास्तविक अपडेट आइनसकेसम्म मात्र, एकपटक मात्र — तल
  // `_onMoveStatus` हेर्नुहोस्) उही अन्तिम गति/दिशामा अझै छोटो टाढा route
  // मै अगाडि बढ्छ, नत्र ठ्याक्कै उस्तै पूर्ण अड्किने। वास्तविक नयाँ बिन्दु
  // आइहाले (`_startGlideTo`) यो तुरुन्तै रद्द/overwrite हुन्छ — त्यसैले
  // आइकन कहिल्यै साँचो स्थानभन्दा धेरै टाढा गइँदैन। (Buttery-Smooth पास:
  // coast विन्डो ४००ms बाट ५५०ms मा बढाइयो — driver-तर्फको Firestore
  // write throttle ~1s सँग अझ राम्ररी मिलोस्/खाली-ठाउँ छोटो होस् भनेर,
  // अझै bounded/single-shot भएकोले रोकिएको गाडी टाढा "घस्रने" जोखिम
  // उस्तै सानै रहन्छ।)
  double _lastSpeedKmPerSec = 0;
  bool _coasting = false;

  void _onMoveStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!widget.rideStarted || _coasting) return;
    final pts = widget.route?.points;
    final fd = _animToRouteDist;
    if (pts == null ||
        pts.length < 2 ||
        fd == null ||
        _lastSpeedKmPerSec <= 0 ||
        !identical(widget.route, _animRouteRef)) {
      return;
    }
    const coastMs = 550;
    final newDist = fd + _lastSpeedKmPerSec * (coastMs / 1000);
    final newTarget = _pointAtRouteDistance(pts, newDist);
    if (newTarget == null) return;
    _coasting = true;
    _animFrom = _displayedOrigin ?? newTarget;
    _animFromRouteDist = fd;
    _animTo = newTarget;
    _animToRouteDist = newDist;
    _moveCtrl
      ..stop()
      ..duration = const Duration(milliseconds: coastMs)
      ..reset()
      ..forward();
  }
  // Stop-and-Go Glide Fix — पहिले यो glide सधैँ स्थिर 900ms मै सकिन्थ्यो,
  // जबकि साँचो GPS/Firestore अपडेट प्रायः अनियमित अन्तरालमा आउँथ्यो —
  // नतिजा: बाइक छोटो समय सर्ने, बाँकी बेला ठ्याक्कै अडिने, अनि नयाँ बिन्दु
  // आउनासाथ फेरि सर्ने — "अडकि-अडकि चलेको" देखिने बग (rider आफ्नै स्क्रिन
  // र passenger दुवैतिर, उही glide code भएकोले)। अब glide को अवधि दूरी र
  // यात्रा-मोड अनुसारको believable गतिबाट गणना हुन्छ (तल [_startGlideTo]
  // हेर्नुहोस्) — data जति बेला/जति टाढा-टाढा आए पनि, देखिने चाल सधैँ
  // स्वाभाविक गतिमा लगातार जारी रहन्छ, कहिल्यै लामो समय अडिंदैन।
  LatLng? _animFrom;
  LatLng? _animTo;
  // Road Snapping — `_animFrom`/`_animTo` लाई सीधा रेखा (chord) मा लर्प
  // गर्नुको सट्टा, दुवैलाई route.points माथि प्रोजेक्ट गरेर (नजिकको
  // segment, perpendicular projection) route-सुरुदेखिको cumulative दूरी
  // (km) मा बदलेर राखिने — अनि हरेक tick मा त्यही दूरी मात्र लर्प गरेर
  // फेरि route.points माथि नै फर्काइन्छ (`_pointAtRouteDistance`)। यसले
  // गर्दा मोडिएको/बाङ्गो बाटोमा पनि आइकन कहिल्यै "सर्टकट"बाट नगई ठ्याक्कै
  // निलो polyline मै टाँसिएर सर्छ।
  double? _animFromRouteDist;
  double? _animToRouteDist;
  RoadRoute? _animRouteRef;

  // Windowed Map-Matching + 1D Kalman — `_startGlideTo` भित्र मात्र प्रयोग
  // हुने, अघिल्लोपटक टाँसिएको route.points index वरिपरि मात्र खोज्ने
  // (टाढाको parallel सडक/flyover मा गलत snap हुनबाट बचाउन) + त्यसपछिको
  // projected-दूरीलाई Kalman filter (माथिको `_DistanceKalman1D`) बाट
  // सुमसुम्याउने। दुवै route बदलिंदा (`_animRouteRef` फेरिंदा) स्वतः
  // reset हुन्छन् — पुरानो route कै state नयाँमा नबाझियोस्।
  int? _lastMatchedSegmentIndex;
  final _DistanceKalman1D _distanceKalman = _DistanceKalman1D();
  DateTime? _lastKalmanAt;
  List<double>? _snapCumCache;
  List<LatLng>? _snapCumCachePoints;

  // Static Polyline Cache — माथिको दाबी (setState यो widget भित्रै सीमित,
  // route पुनः-तान्दैन) वास्तवमा पूरा थिएन: casing/route/walk-connector
  // polyline हरू (routePolylineCasing/routePolyline/walkConnectorPolyline,
  // route.points माथि geometry काम गर्ने — महँगो) `build()` भित्रै सिधै
  // बन्थे, र `_onMoveTick`/`_onLightTick` दुवैले `build()` लाई हरेक
  // animation frame मा (120Hz डिभाइसमा सेकेन्डको १२० पटकसम्म) दोहोर्‍याउँथे
  // — यसैले प्रत्येक tick मा यी स्थिर polyline पनि बेकार्दै पुनः-गणना
  // हुन्थे (लाइभ ट्र्याकिङ स्क्रिनमा lag/jank गुनासोको सम्भावित ठूलो कारण)।
  // अब यी route/origin/destination साँच्चै बदलिएको बेला मात्र पुनः-गणना
  // हुन्छन्, हरेक frame मा होइन — केवल comet-light को चल्दो खण्ड
  // (_lightWindowPoints, सस्तो) मात्र हरेक tick ताजा बन्छ।
  RoadRoute? _staticPolylinesRoute;
  LatLng? _staticPolylinesOrigin;
  LatLng? _staticPolylinesDestination;
  List<Polyline> _staticPolylines = const [];

  // Secondary-Route Cache — पहिले यो (pickup→drop-off preview) polyline
  // "route geometry function होइन, सीधै points हो, त्यसैले cheap" भनेर
  // माथिकै caching बाट बाहिर राखिएको थियो — तर त्यो गलत अनुमान रहेछ:
  // नयाँ `Polyline` object हरेक tick (AnimatedBuilder, ~40fps) मा बन्दा
  // त्यही एउटै tick मा पठाइने सिंगो `Set<Polyline>` नै (माथिको cached
  // `_staticPolylinesFor`/`_lightPolylinesFor` लगायत) फरक object-identity
  // भएर platform-channel मार्फत native तिर फेरि-फेरि पुरै marshal हुन्थ्यो
  // — ठ्याक्कै यही secondary route pre-pickup phase मात्र (OTP अघि)
  // सक्रिय हुने भएकोले, "pickup भन्दा अघिको चरणमा मात्र camera-tracking
  // कमजोर, OTP पछि राम्रो" भन्ने phase-specific गुनासोको साँचो सम्भाव्य
  // जड। अब उही route object नबदलिएसम्म (`identical` जाँच) उही cached
  // list नै फर्काउँछ — माथिकै अन्य सबै polyline कै उस्तै pattern।
  RoadRoute? _secondaryPolylineRoute;
  List<Polyline> _secondaryPolyline = const [];

  List<Polyline> _secondaryPolylineFor(RoadRoute? secondaryRoute) {
    if (secondaryRoute == null || secondaryRoute.points.length < 2) {
      _secondaryPolylineRoute = null;
      _secondaryPolyline = const [];
      return _secondaryPolyline;
    }
    if (identical(secondaryRoute, _secondaryPolylineRoute)) {
      return _secondaryPolyline;
    }
    _secondaryPolylineRoute = secondaryRoute;
    _secondaryPolyline = [
      Polyline(
        polylineId: const PolylineId('secondary_route'),
        points: secondaryRoute.points,
        color: AppColors.kmMuted.withValues(alpha: 0.65),
        width: 4,
        patterns: [PatternItem.dash(14), PatternItem.gap(10)],
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1,
      ),
    ];
    return _secondaryPolyline;
  }

  List<Polyline> _staticPolylinesFor(
      RoadRoute? route, LatLng? origin, LatLng destination) {
    if (route == null || route.points.length < 2) return const [];
    if (identical(route, _staticPolylinesRoute) &&
        origin == _staticPolylinesOrigin &&
        destination == _staticPolylinesDestination) {
      return _staticPolylines;
    }
    final built = <Polyline?>[
      routePolylineCasing('route', route),
      routePolyline('route', route),
      // Stray Black Line Fix — पहिले यहाँ `origin` (चलिरहेको बाइक/गाडीको
      // लाइभ GPS स्थान) तर्फ पनि `walk_origin` connector थियो। origin
      // स्थिर बिन्दु होइन — हरेक नयाँ GPS fix मा अलिकति चलिरहन्छ (OSRM
      // route-snap भन्दा प्रायः >20m टाढा, raw GPS/road-snap noise कारण),
      // जबकि marker आइकन चाहिं सहज गरी glide हुन्छ (`_displayedOrigin`)।
      // नतिजा: यो dotted रेखा हरेक raw GPS fix मा आफ्नै ठाउँमा उफ्रिरहने,
      // सहज गरी सर्दै गरेको आइकनसँग कहिल्यै नमिल्ने — ठ्याक्कै "आइकनमा
      // टाँसिएको/पछ्याउँदै गरेको अनावश्यक कालो रेखा" देखिने गुनासोको साँचो
      // जड। Connector आफैं `destination` (स्थिर पिन, जहाँ routing साँच्चै
      // ठ्याक्कै ढोकासम्म नपुग्ने) जस्ता साँच्चै स्थिर बिन्दुका लागि मात्र
      // अर्थपूर्ण हो — त्यो अझै राखिएको छ।
      walkConnectorPolyline(
        id: 'walk_destination',
        routeEnd: route.points.last,
        markerPos: destination,
      ),
    ].whereType<Polyline>().toList();
    _staticPolylinesRoute = route;
    _staticPolylinesOrigin = origin;
    _staticPolylinesDestination = destination;
    _staticPolylines = built;
    return built;
  }

  // GPS jitter (उभिइरहँदा पनि १-३मी यताउता हुने) ले bearing लाई हरेक
  // पटक अनियमित दिशामा घुमाइरहनबाट जोगाउन — यो भन्दा कम चलेको बेला
  // अघिल्लै दिशा नै कायम राख्ने।
  static const double _minMoveForBearingKm = 0.004; // ~4m

  @override
  void initState() {
    super.initState();
    _lightCtrl.addListener(_onLightTick);
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
    if (widget.showPointLabels) {
      _loadPrimaryLabeledIcon(widget.destinationLabel);
      if (widget.secondaryDestination != null) {
        _loadSecondaryLabeledIcon(widget.secondaryDestinationLabel);
      }
    }
    _subscribeHeadingOverride(widget.headingOverrideStream);
  }

  // Sensor-Fusion Heading Override — `headingOverrideStream` doc-comment
  // हेर्नुहोस्। `didUpdateWidget` मा stream identity बदलिएमा मात्र
  // पुनः-subscribe हुन्छ (caller ले `late final` स्थिर field बाट दिए
  // हरेक rebuild मा दोहोरिने छैन)।
  //
  // Live-Fallback Guard — यो stream caller (job_route_screen.dart) ले
  // Ride-जागामा सधैं (Simulate GPS होस् वा साँचो GPS) दिन्छ, तर Simulate
  // GPS ले कहिल्यै साँचो GPS heading/speed दिंदैन — त्यसैले इन्जिनले
  // कहिल्यै `anchorToGps()` नपाई सधैं "null" नै रहन्छ, gyro-tick ले पनि
  // कहिल्यै केही पठाउँदैन (dead_reckoning.dart हेर्नुहोस्)। पहिले यहाँ
  // "stream दिइएको भए सधैं पुरानो route-tangent/GPS-heading प्रणाली पूर्ण
  // बन्द" गरिन्थ्यो — Simulate GPS मा त्यो नयाँ इन्जिन कहिल्यै trigger
  // नभएकोले bearing नै सधैं default (शून्य/उत्तर) मा अडकिने, बाइक बाटोसँग
  // "ठाडो/बेमेल" देखिने गम्भीर regression थियो। अब यो override साँच्चै
  // भर्खरै (३ सेकेन्डभित्रै) कुनै मान पठाएको छ भने मात्र भरपर्दो मानिन्छ —
  // नत्र पुरानो, प्रमाणित प्रणाली स्वतः फर्केर सम्हाल्छ।
  DateTime? _lastHeadingOverrideAt;
  static const Duration _headingOverrideStaleAfter = Duration(seconds: 3);

  bool get _headingOverrideIsLive {
    final at = _lastHeadingOverrideAt;
    return at != null && DateTime.now().difference(at) < _headingOverrideStaleAfter;
  }

  StreamSubscription<double>? _headingOverrideSub;
  Stream<double>? _subscribedHeadingStream;
  // Gyro-Rebuild-Storm Fix — `HeadingFusionEngine` (dead_reckoning.dart) ले
  // हरेक raw gyroscope sample (native Android मा प्रायः 50-100+ Hz) मा नै
  // यो callback चलाउँछ; पहिले यहाँ हरेक सानो-सानो sample मा पनि
  // `_liveTick.tick()` (पूरा GoogleMap marker/polyline Set rebuild,
  // platform-channel round-trip सहित) दोहोरिन्थ्यो — साँचो gyroscope भएको
  // फोनमा निरन्तर दर्जनौं रिबिल्ड/सेकेन्ड, तर desktop Chrome (कुनै
  // gyroscope नभएको, sensors_plus ले कहिल्यै sample नै नदिने) मा यो बाटो
  // कहिल्यै trigger नै नहुने। "browser मा सहज, साँचो फोनमा मात्र stutter"
  // भन्ने गुनासोको साँचो जड यही थियो — marker/route logic दुवैतिर उही
  // कोड हो, फरक यति मात्र हो कि यो bug फोनमा मात्रै (gyroscope भएकोले)
  // साँच्चै चल्छ। अब यहाँ पनि `_onLightTick` कै उस्तै ढाँचा/दर — ~18fps मा
  // throttle (मानव आँखाले अझै सहज नै देख्छ, तर 50-100Hz भन्दा धेरै सस्तो)।
  DateTime _lastHeadingTick = DateTime.fromMillisecondsSinceEpoch(0);

  void _subscribeHeadingOverride(Stream<double>? stream) {
    if (identical(stream, _subscribedHeadingStream)) return;
    _headingOverrideSub?.cancel();
    _subscribedHeadingStream = stream;
    _lastHeadingOverrideAt = null;
    _headingOverrideSub = stream?.listen((deg) {
      if (!mounted) return;
      _lastHeadingOverrideAt = DateTime.now();
      _bearing = deg;
      final now = DateTime.now();
      if (now.difference(_lastHeadingTick).inMilliseconds < 55) return;
      _lastHeadingTick = now;
      _liveTick.tick();
      // गाडी उभिएको/glide नचलेको बेला पनि क्यामेरा gyro bearing सँग घुमोस्।
      final at = _displayedOrigin ?? widget.origin;
      if (_closeFollowCamera && at != null) _followCameraTo(at);
    });
  }

  void _loadOriginIcon(TravelMode mode) {
    travelModeMarker(mode, iconOverride: widget.vehicleIconOverride).then((b) {
      if (mounted) setState(() => _originIcon = b);
    });
    _webRotatedIconBucket = null;
    _maybeRefreshWebRotatedIcon(mode);
    if (kIsWeb) unawaited(_prewarmWebRotatedIcons(mode));
  }

  /// Web Rotation Latency Fix — `_maybeRefreshWebRotatedIcon` हरेक नयाँ
  /// 5°-bucket मा `travelModeMarkerRotated()` (canvas rasterize + PNG
  /// encode + image decode, साँच्चैको async काम, instant होइन) लाई
  /// लाइभ/मोडिँदै गर्दा नै पहिलोपटक बोलाउँथ्यो — turn/roundabout मा
  /// bearing छोटो समयमै धेरै bucket काट्छ, र हरेक एउटाले आफ्नै async
  /// round-trip नसकिउन्जेल पर्खनुपर्ने भएकोले, मार्करको स्थान (हरेक tick
  /// तुरुन्तै/सिंक्रोनस) ले आइकनको देखिने दिशा (ढिलो/लैग्ड) भन्दा सधैँ
  /// अगाडि निस्कन्थ्यो — ठ्याक्कै "ठीक ठाउँमा छ तर गलत दिशा देखाउँदै
  /// चिप्लिएको/crab-walking" देखिने गुनासोको साँचो जड, मोडिँदा झन् नराम्रो
  /// (bucket जति छिटो बदलिन्छ, lag त्यति धेरै)। अब सम्भाव्य सबै ७२
  /// bucket (हरेक 5°) यात्रा-मोड छानिनेबित्तिकै (ride साँच्चै सुरु हुनुअघि
  /// नै, पर्याप्त फुर्सदमा) एकचोटि अगाडि नै रेन्डर/क्यास गरिन्छ — त्यसपछि
  /// वास्तविक मोडिँदै गर्दा `_maybeRefreshWebRotatedIcon` ले जहिल्यै यही
  /// क्यासबाटै तुरुन्तै (कुनै नयाँ async रेन्डर बिना) पाउँछ।
  Future<void> _prewarmWebRotatedIcons(TravelMode mode) async {
    for (var deg = 0; deg < 360; deg += 5) {
      if (!mounted) return;
      await travelModeMarkerRotated(mode, deg.toDouble(),
          iconOverride: widget.vehicleIconOverride);
    }
  }

  /// हेर्नुहोस् `_webRotatedIcon` doc-comment — web-मात्र, 5° bucket मा
  /// throttle गरिएको (नत्र bearing-animation कै हरेक tick मा नयाँ canvas
  /// rasterize हुन्थ्यो)।
  void _maybeRefreshWebRotatedIcon(TravelMode mode) {
    if (!kIsWeb) return;
    // Note: `_onMoveTick`/`_fitBounds` also set the GoogleMap camera's own
    // `bearing` during `rideStarted`. That does NOT visually rotate this
    // map on web — Google's JS API docs: "For raster maps, [heading] only
    // applies to aerial imagery," and this project uses a standard
    // roadmap with no `mapId`/vector rendering configured. So the map
    // itself never rotates here; this baked-bitmap rotation (by `_bearing`
    // directly) remains the only real rotation mechanism on web, in every
    // phase — always use the true `_bearing`, never zero it out.
    final bucket = (((_bearing % 360) + 360) % 360 / 5).round() * 5 % 360;
    if (bucket == _webRotatedIconBucket) return;
    _webRotatedIconBucket = bucket.toDouble();
    final seq = ++_webRotatedRequestSeq;
    travelModeMarkerRotated(mode, _bearing,
            iconOverride: widget.vehicleIconOverride)
        .then((b) {
      if (mounted && seq == _webRotatedRequestSeq) {
        setState(() => _webRotatedIcon = b);
      }
    });
  }

  // Custom 3D Pickup & Drop Pins — `destination` (primary marker) ले
  // `rideStarted` अनुसार दुई फरक भूमिका निभाउँछ: ride सुरु नहुँदासम्म यो
  // pickup बिन्दु हो (निलो पिन), सुरु भएपछि साँचो drop-off (सुनौलो पिन)।
  // `secondaryDestination` भने सधैँ अन्तिम गन्तव्य (drop-off) को dimmed
  // preview मात्र हो (माथि class doc हेर्नुहोस्) — त्यसैले सधैँ सुनौलो।
  void _loadPrimaryLabeledIcon(String label) {
    if (label.isEmpty) return;
    _primaryLabeledFor = label;
    final kind =
        widget.primaryIsDropoff ? MapPinKind.dropoff : MapPinKind.pickup;
    final color =
        widget.primaryIsDropoff ? AppColors.kmOrange : AppColors.kmTealBlue;
    labeledFlagPin(label, color, kind).then((r) {
      if (mounted && _primaryLabeledFor == label) {
        setState(() {
          _primaryLabeledIcon = r.icon;
          _primaryLabeledAnchor = r.anchorFraction;
        });
      }
    });
  }

  void _loadSecondaryLabeledIcon(String label) {
    if (label.isEmpty) return;
    _secondaryLabeledFor = label;
    labeledFlagPin(label, AppColors.kmOrange, MapPinKind.dropoff).then((r) {
      if (mounted && _secondaryLabeledFor == label) {
        setState(() {
          _secondaryLabeledIcon = r.icon;
          _secondaryLabeledAnchor = r.anchorFraction;
        });
      }
    });
  }

  // Frame-Budget Throttle — पहिले यो AnimationController को listener भएकोले
  // डिभाइसको पूरै refresh rate (कतिपय फोनमा 90/120Hz) मा नै चल्थ्यो — हरेक
  // पटक पूरै setState (markers/polylines Set पुनः-निर्माण) + नयाँ थपिएको
  // प्रति-tick `moveCamera` platform call दुवै। कमजोर/मध्यम डिभाइसमा यति
  // उच्च दरमा निरन्तर दिन नसक्दा frame skip भएर बाइक "अडकिंदै-उफ्रिंदै"
  // (catch-up jerk) जस्तो देखिन्थ्यो — ठ्याक्कै comet-light (`_onLightTick`,
  // तलै हेर्नुहोस्) मा पहिल्यै भेटिएकै समस्या, उही समाधान यहाँ पनि: एउटा
  // स्थिर, achievable दर (~45fps — comet-light भन्दा छिटो, किनकि यहाँ
  // मुख्य गाडी-marker कै स्थान हो) मा क्याप गर्दा हरेक tick सधैँ फत्ते
  // हुन्छ, कुनै पनि छुटेर ढिलो हुँदैन।
  DateTime _lastMoveTick = DateTime.fromMillisecondsSinceEpoch(0);

  // Web Camera-Jitter/Crab-Walk Fix — स्रोत कोडमै पुष्टि भयो
  // (`third_party/google_maps_flutter_web/lib/src/google_maps_flutter_web.dart`
  // हेर्नुहोस्): web मा `animateCamera()` ले सिधै `moveCamera()` लाई नै
  // forward गर्छ — दुवै उस्तै हुन्, अनि दुवै अन्ततः Google Maps JS को
  // `panTo()` मा पुग्छन्, जुन आफैं सधैँ छोटो built-in एनिमेसन हो (native
  // कै `moveCamera` जस्तो कहिल्यै तुरुन्तै/instant होइन)। तल्लो
  // "Continuous Camera Follow" ले हरेक tick (~22-40ms मा) `moveCamera`
  // बोलाउँदा, web मा त्यो हरेक पटक अघिल्लो अझै नसकिएको `panTo` एनिमेसनलाई
  // बीचैमा रोकेर फेरि नयाँ सानो एनिमेसन सुरु गराउँछ — लगातार अवरोधित/फेरि-
  // सुरु भइरहने क्यामेरा-गति, जुन (मार्कर आफैं ठीकसँग लर्प भइरहे पनि)
  // बाटोको सापेक्षमा बाइक "छेउतिर चिप्लिएको/crab-walking" र tile-redraw
  // "झिलिमिली" दुवै देखिने गुनासोको साँचो जड हो — झन् मोडिँदा नराम्रो
  // (दिशा छिटो-छिटो बदलिने)। native मा यो समस्याै छैन (त्यहाँको
  // `moveCamera` साँच्चै instant/GPU-side हो, कहिल्यै interrupt हुने
  // एनिमेसन नै हुँदैन)। अब web मा मात्र यो follow-call लाई `panTo` आफैं
  // पूरा हुनलाई पर्याप्त (४००ms) ढिलो दरमा मात्र बोलाउने — मार्करको
  // आफ्नै position/rotation lerp (माथिको `_kMoveTickThrottleMs`) भने
  // जस्ताको-त्यस्तै छिटो/सहज नै रहन्छ, यो केवल क्यामेरा-follow call लाई
  // मात्र छुट्टै ढिलो गर्छ।
  DateTime _lastWebCameraFollow = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _kWebCameraFollowThrottleMs = 400;

  // Native Camera-Follow Throttle — माथिको दाबी ("native मा moveCamera
  // साँच्चै सस्तो/तुरुन्तै हो") लाइभ फोन-टेस्टमा (RMX2151, साँचो राइड,
  // turning point हरूमा) गलत सावित भयो: zoom १९ (building-level close-up)
  // मा हरेक move-tick (~22ms, ~45/सेकेन्ड) मा `moveCamera` बोलाउँदा Android
  // GoogleMap SDK ले प्रत्येक पटक नयाँ tile/camera-matrix पुनः-गणना/render
  // गर्नुपर्ने हुँदो रहेछ — `Davey!`/`Skipped N frames` (कहिलेकाहीं
  // 100-300+ frame, सेकेन्डौं) लगातार, ride भरि नरोकिने गरी, ठ्याक्कै
  // यही phase (`rideStarted`) मा मात्र देखिएको प्रमाणित भयो। Marker आफ्नै
  // position/bearing lerp (`_kMoveTickThrottleMs`) चाहिं उस्तै छिटो/सहज
  // नै राखेर, केवल native क्यामेरा-follow call लाई मात्र web कै जस्तै
  // छुट्टै (अझ छिटो दरमा, native रेन्डर गति web भन्दा राम्रो भएकोले)
  // throttle गरिएको — बाइक/दिशा अझै हरेक frame सहज गरी सर्छ, क्यामेरा
  // मात्र एकैचोटि धेरैपटक नघुम्ने।
  // Re-Confirmed By Fresh Live Measurement (third time) — marker-tick कै
  // दरमा (`_kMoveTickThrottleMs`, २५ms) क्यामेरा पनि चलाउने प्रयास गर्दा
  // `adb logcat` मा प्रत्यक्ष नापिएको: "Skipped 112-131 frames!" + "Davey!
  // duration=~2000ms" हरेक ~2 सेकेन्डमा, लगातार, पूरै simulation भरि। यो
  // पुरानो (comment-मात्रको) दाबी होइन — यही session मा फेरि ताजै नापिएको
  // हो, त्यसैले फेरि १५०ms मा फर्काइयो। यो स्थिरांक नबदल्नुहोस् — फेरि
  // बदल्नुअघि नयाँ measurement नै चाहिन्छ, पुरानो/यो comment भरोसा नगरी।

  // Web Stutter Fix — native मा हरेक tick सस्तो (GPU-side platform call
  // मात्र), तर Flutter Web (`google_maps_flutter_web`) मा हरेक tick
  // `setState` ले पूरै markers/polylines Set पुनः-निर्माण गर्छ अनि त्यो
  // JS interop/DOM तिर मार्शल हुन्छ — यो native भन्दा धेरै महँगो हुँदा
  // ~45fps मा नै web मा भने उल्टो jank/stutter (catch-up skip) देखिन्थ्यो।
  // Web मा कम (~25fps, अझै आँखाले सहज देखिने) दरमा क्याप गर्दा उही
  // interpolation (position+bearing lerp, तल) जस्ताको-त्यस्तै — फरक
  // फ्रेम-दर मात्र, movement कहिल्यै "बिग्रिएको"/टुटेको देखिँदैन।
  //
  // Native 60fps Bump — Reverted — यो 22ms बाट 16ms (60fps) मा बढाइएको
  // थियो, तर वास्तविक डिभाइसमा (RMX2151) प्रत्यक्ष जाँचमा नै उल्टो बढी
  // jank/freeze देखियो — अर्थात् यही डिभाइसले हरेक 16ms मा setState+
  // marker-rebuild+platform-channel लाई पच्न सक्दो रहेनछ, ठ्याक्कै
  // माथिकै "Web Stutter Fix" मा web-को लागि वर्णन गरिएकै catch-up-skip
  // समस्या यता native मै पनि।
  //
  // Native 22ms Also Insufficient — Measured Live — त्यो बेला comet-light
  // caching/camera-follow throttle थपिसकेपछि पनि gंभीर jank देखिएर 33ms
  // (~30fps) मा झारिएको थियो।
  //
  // Re-Test At 25ms (~40fps) — Controlled — त्यसयता धेरै थप per-tick
  // cost घटाइसकियो (comet-light polyline cache, native camera animateCamera
  // + अझ बढी throttle, runaway simulate-loop बग fix, tick-drift fix) —
  // त्यसैले अब बेसलाइन लोड नै पहिले भन्दा स्पष्ट कम छ। 30fps मा पनि
  // "हरेक tick एउटा छोटो step" भिजिबल हुन सक्ने (यो नै tick-based glide
  // को अन्तर्निहित प्रकृति हो, कुनै बग होइन) भन्ने गुनासोपछि — सीधै फेरि
  // 45fps/60fps मा नफर्केर (पहिल्यै दुईपटक नापिएर बिग्रिएको प्रमाणित),
  // बीचको सानो/नियन्त्रित वृद्धि (25ms) मात्र — live Davey/frame-skip
  // monitor सँगै तुरुन्तै जाँच्न, फेरि नबिग्रियोस्।
  //
  // Native Full-Frame-Rate — 25ms throttle ले 60Hz मा (16.7ms frame) हरेक
  // दोस्रो frame मात्र पास गर्थ्यो (~30fps)। 12ms ले 60Hz मा हरेक frame
  // (र 120Hz मा हरेक दोस्रो = 60fps) पास गर्छ। मुख्य खर्च (Transform.scale
  // 1.5x + rotate ले 2.25x pixel render गर्ने) अब हटिसकेको छ।
  static const int _kMoveTickThrottleMs = kIsWeb ? 40 : 12;

  void _onMoveTick() {
    final from = _animFrom;
    final to = _animTo;
    if (from == null || to == null || !mounted) return;
    final now = DateTime.now();
    final isFinalFrame = _moveCtrl.status != AnimationStatus.forward;
    if (!isFinalFrame &&
        now.difference(_lastMoveTick).inMilliseconds < _kMoveTickThrottleMs) {
      return; // फ्रेम-दर क्याप — अन्तिम frame (एनिमेसन सकिएको) भने कहिल्यै नछुट्ने।
    }
    _lastMoveTick = now;
    final t = _moveCtrl.value;
    final bFrom = _bearingAnimFrom;
    final bTo = _bearingAnimTo;
    // Road Snapping — `_animFromRouteDist`/`_animToRouteDist` (यो glide
    // सुरु हुँदा `_startGlideTo` मै पहिल्यै प्रोजेक्ट/क्यास भइसकेको) उपलब्ध
    // र अझै उही route object (`_animRouteRef`) कै हो भने — सीधा chord
    // लर्प होइन, route.points माथिकै दूरी-आधारित लर्प (सधैँ निलो
    // polyline मै टाँसिएको)। Route बीचमै बदलिए (live refresh) वा route
    // नै नभए (fallback सीधा-रेखा) — पुरानै chord-lerp मा नै फर्कने।
    final fd = _animFromRouteDist;
    final td = _animToRouteDist;
    final pts = widget.route?.points;
    final useRoute = fd != null &&
        td != null &&
        pts != null &&
        pts.length >= 2 &&
        identical(widget.route, _animRouteRef);
    LatLng displayed;
    double? routeBearing;
    if (useRoute) {
      final curDist = fd + (td - fd) * t;
      displayed = _pointAtRouteDistance(pts, curDist) ?? _lerpLatLng(from, to, t);
      // Curve-Tangent Bearing Fix — पहिले यहाँ (position जस्तै route कै
      // curve अनुसार होइन) bearing लाई सीधै सुरु/अन्त्यको bearing बीच
      // लर्प (`bFrom + (bTo-bFrom)*t`) गरिन्थ्यो। सीधा बाटोमा यो अदृश्य
      // हुन्थ्यो, तर मोडिएको ठाउँमा (glide को बीचमै नै बाटो मोडियो भने)
      // स्थिति त ठ्याक्कै curve मै (`_pointAtRouteDistance`) सही हुन्थ्यो,
      // तर फर्किने दिशा (facing) भने ती दुई टाढा-टाढा bearing बीचको
      // सीधा औसतमा मात्र — त्यो exact बिन्दुको साँचो road-tangent सँग
      // नमिल्दा बाइक "सडकमा छ तर छेउतिर फर्किएको/crooked" देखिने बग थियो।
      // ग्राहकतर्फ (कम बारम्बार अपडेट हुने, हेर्नुहोस् job_route_screen.dart
      // को Passenger-Side Stutter Fix) यो झन् देखिने हुन्थ्यो — update
      // कम बारम्बार हुँदा हरेक glide ले बाटोको लामो खण्ड (मोड पर्ने
      // सम्भावना बढी) ओगट्थ्यो। अब bearing पनि position जस्तै हरेक tick मा
      // curDist कै ठ्याक्कै local tangent बाट पुनः-गणना हुन्छ — glide
      // जतिसुकै लामो/छोटो भए पनि सधैँ साँचो road-direction।
      // Jitter-Threshold Guard — `bFrom`/`bTo` null हुनु (माथि
      // `_maybeUpdateBearing`, ~4m भन्दा कम चलेको) को अर्थ हो यो पटक
      // bearing साँच्चै अपडेट हुनु हुँदैन (GPS noise, अघिल्लै दिशा कायम)।
      // पहिले यहाँ यो guard बिर्सिएर route उपलब्ध भएमा जहिल्यै routeBearing
      // लागू हुन्थ्यो — सानो/jitter movement मा पनि बाइक तुरुन्तै नजिकैको
      // (कहिलेकाहीँ noisy/उल्टो) tangent तिर फर्कने बग हुन्थ्यो।
      // GPS Velocity Fusion — `_maybeUpdateBearing` कै उस्तै प्राथमिकता
      // (साँचो GPS course-over-ground, विश्वासिलो+सवारी साँच्चै चलिरहेको
      // बेला) — नत्र यहाँको route-tangent ले त्यो fusion लाई हरेक tick
      // ओभरराइट गरिदिन्थ्यो (route उपलब्ध भएको सामान्य अवस्थामा)। corner-
      // ease smoothing (तल) भने दुवै हालतमा उस्तै लागू हुन्छ — केवल लक्ष्य
      // कोण मात्र बदलिन्छ, smoothing mechanism होइन।
      final gpsHeading = widget.gpsHeadingDeg;
      final gpsSpeedOk = (widget.gpsSpeedMps ?? 0) > 0.8;
      routeBearing = (bFrom == null || bTo == null)
          ? null
          : (gpsHeading != null && gpsSpeedOk)
              ? gpsHeading
              : _bearingAtRouteDistance(pts, curDist);
    } else {
      displayed = _lerpLatLng(from, to, t);
    }
    // Narrow-Rebuild — पहिले यहाँ `setState()` थियो (हेर्नुहोस् `_liveTick`
    // doc-comment) — अब field सिधै अपडेट गरेर `_liveTick.notifyListeners()`
    // मात्र, ताकि केवल तल्लो `AnimatedBuilder`-बेरिएको GoogleMap मात्र
    // फेरि बन्छ, बाँकी widget tree (pill/pulse) होइन।
    _displayedOrigin = displayed;
    // bearing पनि (सेट भएको भए मात्र — जित्टर-थ्रेसहोल्ड भन्दा कम चलेको
    // बेला यी null नै रहन्छन्, अघिल्लै दिशा कायमै रहन्छ) position कै
    // उही t मा सँगसँगै — दुवै सधैँ एउटै frame मा, एउटै गतिमा सरून्।
    if (routeBearing != null) {
      // Corner-Snap Fix — पहिले यहाँ `_bearing = _bearing +
      // shortestAngleDelta(_bearing, routeBearing)` — जुन साँच्चै
      // `_bearing = routeBearing` कै बराबर थियो, अर्थात् हरेक tick मा
      // सिधै नयाँ tangent मा *तुरुन्तै* उफ्रिने। सीधा बाटोमा tangent
      // tick-देखि-tick लगभग उस्तै भएकोले यो अदृश्य थियो, तर बाटो मोडिएको
      // ठ्याक्कै बिन्दु (vertex) curDist ले काटेको क्षण tangent आफैं
      // एकैचोटि धेरै डिग्री फड्किन्थ्यो — एउटै frame मा बाइक अचानक
      // फर्किएको ("stutter"/"snap" at corners) गुनासोको साँचो जड। अब
      // Buttery-Smooth Corner Re-Ease — "Instant Corner Snap" (१.०, माथिको
      // इतिहास हेर्नुहोस्) ले sharp मोडमा आइकन एकै frame मा "pop" हुने
      // देखाउँथ्यो — ठ्याक्कै "jerky/stutter" भन्ने नयाँ स्पष्ट गुनासोसँग
      // मिल्दो। पहिले नै प्रमाणित (production मा चलिसकेको) ०.५ मानमा
      // फर्कियो — ०.२५ (पहिलो प्रयास) जति ढिलो/"लागि परेको" होइन, तर १.०
      // जत्तिकै तीखो snap पनि होइन — प्रत्येक tick मा बाँकी कोणको आधा
      // मात्र घुम्ने भएकोले केही tick भित्रै (throttle अनुसार २५-४०ms-को
      // केही गुणा, व्यवहारमा आँखाले नदेखिने छोटो समय) नै लक्ष्य tangent
      // भेट्छ — तर एकैचोटि उफ्रने भन्दा धेरै सहज/तरल देखिन्छ।
      // Camera-Rotation Smoothing — क्यामेरा नै अब bearing सँगै घुम्ने
      // भएकोले ०.५ (एक-दुई frame मा snap) ले पूरै नक्सा मोडमा झट्का दिन्थ्यो;
      // ०.२ ले ~१५ frame (~२५०ms) मा सहज घुमाउँछ।
      const cornerEase = 0.2;
      _bearing += shortestAngleDelta(_bearing, routeBearing) * cornerEase;
    } else if (bFrom != null && bTo != null) {
      _bearing = bFrom + (bTo - bFrom) * t;
    }
    // Overlay मोडमा बाइक Flutter widget हो (स्क्रिनको बीचमा स्थिर) — marker
    // बदलिँदैन, त्यसैले हरेक frame पूरै GoogleMap rebuild नगरी क्यामेरा
    // मात्र सारिन्छ (तल `_followCameraTo`)।
    if (!_centerOverlay) _liveTick.tick();
    _maybeRefreshWebRotatedIcon(widget.travelMode);
    // Continuous Camera Follow — zoom १९ को tight close-up phase मा
    // (`rideStarted`) क्यामेरा पहिले ~50m चलेपछि मात्र (माथि `_fitBounds`/
    // `didUpdateWidget`) पुनः-fit हुन्थ्यो — तर त्यो थ्रेसहोल्ड यति साँघुरो
    // zoom (स्क्रिनमै ~50-100m मात्र देखिने) मा धेरै ठूलो हुँदो रहेछ:
    // बाइक अर्को re-fit नआउँदासम्म स्क्रिनको किनारैतिर पुगिसक्थ्यो, वा
    // मोडिएको बाटोमा क्यामेराको स्थिर केन्द्रभन्दा टाढा देखिन्थ्यो —
    // "बाइक रोडबाट बाहिर गए जस्तो/हराए जस्तो" गुनासोको साँचो जड। अब यही
    // marker-glide कै उही tick मा क्यामेरा पनि सँगसँगै सर्छ — बाइक सधैँ
    // स्क्रिनको बीचमै, Uber नेभिगेसन मोड जस्तै। native मा `moveCamera`
    // साँच्चै सस्तो/तुरुन्तै (GPU-side) हो — तर web मा होइन (माथि
    // `_lastWebCameraFollow` doc-comment हेर्नुहोस् — त्यहाँ throttle
    // नै गर्नुपर्ने साँचो कारण), त्यसैले web मा छुट्टै ढिलो दरमा।
    if (_closeFollowCamera) {
      // Heading-Up Camera (Explicit Product Override) — पहिले यहाँ bearing
      // सधैं ०/उत्तर-माथि नै रहन्थ्यो, किनभने यही रोटेसनले नापिएको गम्भीर
      // jank (300+ frame skip) देखाएको थियो दुईपटक। Product-level निर्णय
      // (जोखिम थाहा पाएरै, explicitly स्वीकार गरेर) अनुसार अब फेरि
      // heading-up सक्रिय — क्यामेरा सधैं `_bearing` तिर नै घुम्छ, बाइकको
      // अगाडिको बाटो सधैं स्क्रिनको माथितिर देखियोस् भनेर। कमजोर डिभाइसमा
      // यसले उही पुरानो frame-skip फेरि देखाउन सक्छ — त्यो बेला फेरि
      // उत्तर-माथि (bearing: 0) मा फर्कनु नै प्रमाणित/सुरक्षित बाटो हो।
      //
      // Bearing-Relative Look-Ahead — पहिले उत्तर-माथि मात्र भएकोले
      // "अगाडि" सधैं ठ्याक्कै भौगोलिक उत्तर हुन्थ्यो (सीधा latitude-shift
      // पुग्थ्यो)। अब क्यामेरा नै घुम्ने भएकोले "अगाडि" भनेको जे दिशामा
      // बाइक फर्किरहेको छ (`_bearing`) त्यही हो — look-ahead offset पनि
      // सोही दिशामा घुमाउनुपर्छ, नत्र बाइक मोडिँदा look-ahead बिन्दु
      // स्क्रिनको गलत छेउमा (कहिलेकाहीं पछाडि समेत) देखिन्थ्यो।
      // Dead-Center Lock — look-ahead offset हटाइयो: क्यामेरा target ठ्याक्कै
      // बाइकको हालको (animated) स्थान हो, त्यसैले बाइक सधैं स्क्रिनको
      // बीचमा। क्यामेरा र marker एउटै tick (एउटै `displayed`/`_bearing`)
      // बाट सँगै सर्छन् — पहिले क्यामेरा छुट्टै 150ms-throttled
      // `animateCamera` मा थियो, marker भने हरेक tick मा, त्यसैले marker
      // बीच-बीचमा केन्द्रबाट खिसकेको देखिन्थ्यो।
      if (kIsWeb) {
        final nowCam = DateTime.now();
        if (nowCam.difference(_lastWebCameraFollow).inMilliseconds >=
            _kWebCameraFollowThrottleMs) {
          _lastWebCameraFollow = nowCam;
          _followCameraTo(displayed);
        }
      } else {
        _followCameraTo(displayed);
      }
    }
  }

  /// Heading-up follow: native camera बाइकमाथि zoom 19 मा लक, bearing =
  /// बाइकको दिशा (route अगाडि स्क्रिनको माथितिर)। `moveCamera` (instant) —
  /// `animateCamera` ले हरेक frame नयाँ animation सुरु गरेर आफैंसँग लड्थ्यो।
  /// Web मा नक्सा north-up नै (marker को bitmap नै घुमाइएको हुन्छ)।
  // Camera update rate cap (Hz) — 0 = camera never moves (परीक्षणको लागि)।
  static const int _kCamHz = int.fromEnvironment('CAM_HZ', defaultValue: 60);
  DateTime _lastCamMove = DateTime.fromMillisecondsSinceEpoch(0);

  void _followCameraTo(LatLng target) {
    final c = _map;
    if (c == null || _kCamHz <= 0 || _followPaused) return;
    if (_kCamHz < 60) {
      final now = DateTime.now();
      if (now.difference(_lastCamMove).inMilliseconds < 1000 ~/ _kCamHz - 2) {
        return;
      }
      _lastCamMove = now;
    }
    final bearing = kIsWeb ? 0.0 : ((_bearing % 360) + 360) % 360;
    c.moveCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 19, bearing: bearing)));
  }

  static LatLng _lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  /// route.points माथि, route सुरुदेखि [distKm] जति टाढाको ठ्याक्कै बिन्दु
  /// (cumulative haversine-दूरी walk) — point density जतिसुकै असमान भए
  /// पनि दूरी-आधारित भएकोले सही।
  static LatLng? _pointAtRouteDistance(List<LatLng> pts, double distKm) {
    if (pts.isEmpty) return null;
    if (pts.length < 2) return pts.first;
    final remaining = distKm < 0 ? 0.0 : distKm;
    double cum = 0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final segLen = haversineKm(
          a.latitude, a.longitude, b.latitude, b.longitude);
      if (cum + segLen >= remaining) {
        final t = segLen <= 0 ? 0.0 : (remaining - cum) / segLen;
        return _lerpLatLng(a, b, t);
      }
      cum += segLen;
    }
    return pts.last;
  }

  /// [query] बिन्दु route.points माथि कहाँ "snap" हुन्छ भन्ने — हरेक
  /// segment (points[i-1]→points[i]) लाई सीधा रेखा मानेर [query] लाई
  /// त्यसमाथि लम्ब (perpendicular) प्रोजेक्ट गरी, सबैभन्दा नजिकको segment
  /// छान्छ (equirectangular local-flat approximation — सहर-स्तरको छोटो
  /// दूरीमा पर्याप्त सटीक), अनि त्यो प्रोजेक्सनको route-सुरुदेखिको
  /// cumulative दूरी (km) फर्काउँछ।
  static double _projectDistanceAlongRoute(List<LatLng> pts, LatLng query) {
    if (pts.length < 2) return 0;
    const latKmPerDeg = 111.32;
    double bestDistSq = double.infinity;
    double bestCum = 0;
    double cum = 0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final segLen =
          haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
      final lngKmPerDeg = latKmPerDeg * cos(a.latitude * pi / 180);
      final bx = (b.longitude - a.longitude) * lngKmPerDeg;
      final by = (b.latitude - a.latitude) * latKmPerDeg;
      final qx = (query.longitude - a.longitude) * lngKmPerDeg;
      final qy = (query.latitude - a.latitude) * latKmPerDeg;
      final segLenSq = bx * bx + by * by;
      var t = segLenSq <= 0 ? 0.0 : (qx * bx + qy * by) / segLenSq;
      t = t.clamp(0.0, 1.0);
      final dx = qx - bx * t;
      final dy = qy - by * t;
      final distSq = dx * dx + dy * dy;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestCum = cum + segLen * t;
      }
      cum += segLen;
    }
    return bestCum;
  }

  /// `_startGlideTo` कै hot-path मात्रको लागि — route कै सुरुदेखि हरेक
  /// बिन्दुसम्मको cumulative दूरी (km), एकपटक मात्र बन्ने/cache हुने
  /// (route.points reference नबदलिएसम्म)। `_projectDistanceAlongRoute`
  /// (माथि, पूरै route प्रति-कल scan गर्ने, अझै ETA pill/bearing जस्ता
  /// कम-फ्रिक्वेन्सी ठाउँमा प्रयोग भइरहेको, अपरिवर्तित) भन्दा फरक — यो
  /// cache ले नै तलको windowed search लाई साँच्चै O(window) बनाउँछ,
  /// O(route-length) होइन।
  List<double> _snapCumKmFor(List<LatLng> pts) {
    if (identical(_snapCumCachePoints, pts) && _snapCumCache != null) {
      return _snapCumCache!;
    }
    final cum = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length; i++) {
      cum[i] = cum[i - 1] +
          haversineKm(pts[i - 1].latitude, pts[i - 1].longitude,
              pts[i].latitude, pts[i].longitude);
    }
    _snapCumCache = cum;
    _snapCumCachePoints = pts;
    return cum;
  }

  /// [loIndex]..[hiIndex] (route.points index, दुवैतिर inclusive) भित्रका
  /// segment मात्र जाँचेर [query] सबैभन्दा नजिक कुन segment मा "snap" हुन्छ
  /// भन्ने पत्ता लगाउँछ — [cum] (पहिल्यै तयार cumulative-दूरी array) प्रयोग
  /// गरेर प्रत्येक match को route-सुरुदेखिको absolute दूरी O(1) मा निकाल्छ।
  /// `distFromRouteKm` ले त्यो best-match बिन्दु [query] बाट वास्तवमै कति
  /// टाढा छ भन्ने पनि फर्काउँछ — caller (तल) ले यो धेरै ठूलो भए (window
  /// भित्र साँच्चो सडकै नभेटिएको, होला route बाहिर गइसकेको/नयाँ route)
  /// पूरै-route fallback गर्न प्रयोग गर्छ।
  ({double distKm, int segmentIndex, double distFromRouteKm})
      _projectDistanceAlongRouteIndexed(
    List<LatLng> pts,
    List<double> cum,
    LatLng query,
    int loIndex,
    int hiIndex,
  ) {
    const latKmPerDeg = 111.32;
    double bestDistSq = double.infinity;
    double bestCum = 0;
    int bestIndex = loIndex;
    for (var i = loIndex; i <= hiIndex; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final lngKmPerDeg = latKmPerDeg * cos(a.latitude * pi / 180);
      final bx = (b.longitude - a.longitude) * lngKmPerDeg;
      final by = (b.latitude - a.latitude) * latKmPerDeg;
      final qx = (query.longitude - a.longitude) * lngKmPerDeg;
      final qy = (query.latitude - a.latitude) * latKmPerDeg;
      final segLenSq = bx * bx + by * by;
      var t = segLenSq <= 0 ? 0.0 : (qx * bx + qy * by) / segLenSq;
      t = t.clamp(0.0, 1.0);
      final dx = qx - bx * t;
      final dy = qy - by * t;
      final distSq = dx * dx + dy * dy;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestCum = cum[i - 1] + sqrt(segLenSq) * t;
        bestIndex = i;
      }
    }
    return (
      distKm: bestCum,
      segmentIndex: bestIndex,
      distFromRouteKm: sqrt(bestDistSq),
    );
  }

  // Windowed Map-Matching — अघिल्लोपटक टाँसिएको segment (`_lastMatchedSegmentIndex`)
  // वरिपरि ±[_snapWindowRadius] segment मात्र खोज्छ — टाढाको parallel सडक/
  // flyover मा गलत snap हुनबाट बचाउन (र पूरै-route scan भन्दा छिटो)। केन्द्र
  // अझै थाहा नभए (पहिलोपटक) वा window भित्रको best-match अझै धेरै टाढा
  // (धेरैजसो route साँच्चै बदलिएको/ठूलो reroute भएको बेला मात्र) भेटिए —
  // सुरक्षित fallback: पूरै route मा फर्केर खोज्छ, कहिल्यै गलत/टाढा
  // बिन्दुमै अड्किंदैन।
  static const int _snapWindowRadius = 15;
  static const double _snapWindowMaxMissKm = 0.25;

  ({double distKm, int segmentIndex}) _projectDistanceAlongRouteWindowed(
      List<LatLng> pts, LatLng query) {
    final cum = _snapCumKmFor(pts);
    final center = _lastMatchedSegmentIndex;
    if (center != null) {
      final lo = (center - _snapWindowRadius).clamp(1, pts.length - 1);
      final hi = (center + _snapWindowRadius).clamp(1, pts.length - 1);
      final windowed =
          _projectDistanceAlongRouteIndexed(pts, cum, query, lo, hi);
      if (windowed.distFromRouteKm <= _snapWindowMaxMissKm) {
        return (distKm: windowed.distKm, segmentIndex: windowed.segmentIndex);
      }
    }
    final full =
        _projectDistanceAlongRouteIndexed(pts, cum, query, 1, pts.length - 1);
    return (distKm: full.distKm, segmentIndex: full.segmentIndex);
  }

  /// [distKm] मा route.points को local tangent दिशा (segment bearing) —
  /// मोडिएको ठाउँमा पनि साँचो road-direction, टाढाको दुई बिन्दुबीचको
  /// सीधा chord bearing होइन।
  static double? _bearingAtRouteDistance(List<LatLng> pts, double distKm) {
    if (pts.length < 2) return null;
    double cum = 0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final segLen =
          haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
      if (cum + segLen >= distKm || i == pts.length - 1) {
        return bearingBetween(a, b);
      }
      cum += segLen;
    }
    return bearingBetween(pts[pts.length - 2], pts.last);
  }

  // Web Stutter Fix — यो ticker सधैँभरि (गाडी नचलिरहँदा पनि, comet-glow कै
  // लागि मात्र) चलिरहन्छ — हरेक tick ले पनि पूरै widget rebuild गराउने
  // भएकोले, `_onMoveTick` कै उस्तै कारणले web मा यो पनि कम दरमा राम्रो।
  static const int _kLightTickThrottleMs = kIsWeb ? 100 : 55;

  void _onLightTick() {
    // Follow मा comet-light polyline बन्द — हरेक 55ms मा polyline Set बदल्दा
    // native map फेरि render हुन्थ्यो (smoothness सँग लडाइँ)।
    if (_centerOverlay) return;
    final now = DateTime.now();
    if (now.difference(_lastLightTick).inMilliseconds < _kLightTickThrottleMs) {
      return; // ~18fps (native) / ~10fps (web) cap
    }
    _lastLightTick = now;
    // Narrow-Rebuild — `_liveTick` doc-comment हेर्नुहोस् — पहिले यहाँ
    // `setState` थियो।
    if (!mounted) return;
    _lightProgress = _lightCtrl.value;
    _liveTick.tick();
  }

  /// route.points माथि, कुल दूरीको [windowFraction] जति लामो एउटा चम्किलो
  /// "comet" खण्ड — [progress] (0→1, लुप हुने) ले route कै सुरुदेखि अन्त्यसम्म
  /// स्थिरगतिमा (point density जतिसुकै असमान भए पनि, दूरी-आधारित interpolation
  /// भएकोले) सारिन्छ। route.points सानो भए (<2) खाली सूची फर्काउँछ।
  // Light-Cumulative Cache — माथि `_staticPolylinesFor` कै उस्तै सिद्धान्त:
  // `cum` (route कै सुरुदेखि हरेक बिन्दुसम्मको cumulative दूरी, haversine/
  // trig-heavy) `route.points` मात्रमा भर पर्छ, `progress` मा होइन — तर
  // पहिले यो हरेक `_lightWindowPoints()` call (प्रत्येक light-tick, ~१८fps
  // native मा पनि) मा शून्यबाटै पुनः-गणना हुन्थ्यो। लामो (सय-सय बिन्दुको)
  // साँचो सडक-route मा यो निरन्तर दोहोरिने trig काम नै main-thread jank/GC
  // दबाबको एउटा साँचो (नापिएको) कारण थियो — route साँच्चै नबदलिएसम्म अब
  // एकपटक मात्र बन्छ।
  List<double>? _lightCumCache;
  RoadRoute? _lightCumCacheRoute;

  List<LatLng> _lightWindowPoints(RoadRoute route, double progress,
      {double windowFraction = 0.09}) {
    final points = route.points;
    if (points.length < 2) return const [];
    List<double> cum;
    if (identical(route, _lightCumCacheRoute) && _lightCumCache != null) {
      cum = _lightCumCache!;
    } else {
      cum = List<double>.filled(points.length, 0);
      for (var i = 1; i < points.length; i++) {
        cum[i] = cum[i - 1] +
            haversineKm(points[i - 1].latitude, points[i - 1].longitude,
                points[i].latitude, points[i].longitude);
      }
      _lightCumCache = cum;
      _lightCumCacheRoute = route;
    }
    final total = cum.last;
    if (total <= 0) return const [];

    LatLng interpAt(double dist) {
      dist = dist.clamp(0.0, total);
      for (var i = 1; i < cum.length; i++) {
        if (cum[i] >= dist) {
          final segLen = cum[i] - cum[i - 1];
          final t = segLen <= 0 ? 0.0 : (dist - cum[i - 1]) / segLen;
          return _lerpLatLng(points[i - 1], points[i], t);
        }
      }
      return points.last;
    }

    final headDist = progress * total;
    final tailDist = (headDist - total * windowFraction).clamp(0.0, total);
    final result = <LatLng>[interpAt(tailDist)];
    for (var i = 0; i < points.length; i++) {
      if (cum[i] > tailDist && cum[i] < headDist) result.add(points[i]);
    }
    result.add(interpAt(headDist));
    return result;
  }

  // Light-Polyline Cache — यो comet-glow (२ वटा `Polyline`) को सामग्री
  // `_lightProgress` मा मात्र भर पर्छ (~१८fps मा बदलिने), तर `build()`
  // भित्रैको यो closure पहिले हरेक `_liveTick` notify (marker-glide कै
  // ~45fps समेत, किनकि दुवै ticker अब उही `_liveTick` साझा गर्छन्) मा
  // दोहोरिन्थ्यो — प्रत्येक पटक नयाँ `Polyline` + बिन्दु-सूची allocate
  // हुने, अनि `GoogleMap` ले ती (भिन्न object भए पनि) native तिर पठाउन
  // पर्ने। `_lightProgress` नबदलिएसम्म ठ्याक्कै उही (identical) cached
  // list नै फर्काउँदा — `Polyline` value-equal भएकोले GoogleMap plugin
  // आफैंले "केही बदलिएन" भनेर ती move-only tick हरूमा native platform-
  // channel call नै नगर्ने हुन्छ, allocation/GC दबाब दुवै घट्छ।
  List<Polyline>? _lightPolylinesCache;
  RoadRoute? _lightPolylinesCacheRoute;
  double? _lightPolylinesCacheProgress;

  List<Polyline> _lightPolylinesFor(RoadRoute route, double progress) {
    if (identical(route, _lightPolylinesCacheRoute) &&
        _lightPolylinesCacheProgress == progress &&
        _lightPolylinesCache != null) {
      return _lightPolylinesCache!;
    }
    final win = _lightWindowPoints(route, progress);
    final built = win.length < 2
        ? const <Polyline>[]
        : [
            // बाहिरी नरम glow — फराकिलो, कम-alpha।
            Polyline(
              polylineId: const PolylineId('route_light_glow'),
              points: win,
              color: Colors.white.withValues(alpha: 0.35),
              width: 14,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              zIndex: 2,
            ),
            // भित्री चम्किलो core — पातलो, लगभग-सेतो।
            Polyline(
              polylineId: const PolylineId('route_light_core'),
              points: win,
              color: Colors.white.withValues(alpha: 0.95),
              width: 5,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              zIndex: 3,
            ),
          ];
    _lightPolylinesCache = built;
    _lightPolylinesCacheRoute = route;
    _lightPolylinesCacheProgress = progress;
    return built;
  }

  /// नयाँ GPS बिन्दु आउनेबित्तिकै — हालको (देखिइरहेको, नयाँ आउनुअघिकै)
  /// स्थानबाट यो नयाँ स्थानसम्म सहज गरी सार्ने (glide), सिधै "jump" होइन।
  void _startGlideTo(LatLng newOrigin) {
    // वास्तविक नयाँ अपडेट आइपुग्यो — अघिल्लो coast (भए) अब stale, रद्द।
    _coasting = false;
    final from = _displayedOrigin ?? newOrigin;
    _animFrom = from;
    _animTo = newOrigin;
    final pts = widget.route?.points;
    if (pts != null && pts.length >= 2) {
      final fromDist = _projectDistanceAlongRoute(pts, from);
      // Windowed Map-Matching + 1D Kalman — raw projected दूरी सिधै
      // प्रयोग नगरी, अघिल्लो matched-segment वरिपरि मात्र खोजेर (माथिको
      // `_projectDistanceAlongRouteWindowed`) अनि Kalman filter बाट
      // सुमसुम्याएर मात्र। Route बदलिंदा (`_animRouteRef` फेरिंदा) वा
      // पहिलोपटक नै — filter लाई raw measurement मै सिधै reset गर्ने,
      // पुरानो route/estimate नयाँमा नबाझियोस्।
      final routeChanged = !identical(widget.route, _animRouteRef);
      if (routeChanged) _lastMatchedSegmentIndex = null;
      final windowedTo = _projectDistanceAlongRouteWindowed(pts, newOrigin);
      final now = DateTime.now();
      final double toDist;
      if (routeChanged || _lastKalmanAt == null) {
        _distanceKalman.reset(windowedTo.distKm);
        toDist = windowedTo.distKm;
      } else {
        final dt = now.difference(_lastKalmanAt!).inMilliseconds / 1000.0;
        toDist = _distanceKalman.filter(windowedTo.distKm, dt);
      }
      _lastKalmanAt = now;
      _lastMatchedSegmentIndex = windowedTo.segmentIndex;
      // Backward-Projection Guard — GPS जित्टर/टाढा-टाढा अपडेट (passenger-
      // तर्फ विशेष गरी) ले कहिलेकाहीँ नयाँ बिन्दु पुरानोभन्दा *पछाडि*
      // (route-दूरी कम) प्रोजेक्ट हुन सक्छ, साँचो गाडी कहिल्यै पछाडि
      // नगए पनि। त्यो बेला route-snapping प्रयोग गरे `curDist` नै glide
      // भर पछाडि सर्थ्यो (स्थिति पछाडि, तर bearing अझै अगाडिको tangent) —
      // "बाइक उल्टो/पछाडि गइरहेको" देखिने बग। त्यस्तो केस (toDist < fromDist)
      // मा route-snapping नै नगरी सीधा chord लर्पमा फर्कने — सुरक्षित।
      if (toDist >= fromDist) {
        _animRouteRef = widget.route;
        _animFromRouteDist = fromDist;
        _animToRouteDist = toDist;
      } else {
        _animRouteRef = null;
        _animFromRouteDist = null;
        _animToRouteDist = null;
      }
    } else {
      _animRouteRef = null;
      _animFromRouteDist = null;
      _animToRouteDist = null;
      _lastMatchedSegmentIndex = null;
    }
    // Speed-Based Glide Duration — पहिले यो पछिल्लो दुई अपडेट-बीचको साँचो
    // wall-clock समयमा आधारित थियो (elapsed-time), तर "Simulate GPS" जस्ता
    // टाढा-टाढा/अनियमित-अन्तरालका थोप्लाहरूमा त्यो गलत आधार रहेछ — लामो
    // pause पछि आएको सानो चाल पनि लामै समय घस्रिने ("लाग भएको/dragging"
    // देखिने गुनासो), छोटो pause पछिको ठूलो जम्प पनि अनाकर्षक छोटो समयमै
    // सकिने। अब दूरी÷यात्रा-मोड अनुसारको believable गति (bike ~6 मी/से,
    // car ~11 मी/से, हिँड्ने ~1.4 मी/से) बाट अवधि गणना हुन्छ — glide
    // हमेशा साँचो गतिजस्तै "स्वाभाविक" लाग्छ, data कति बारम्बार/छरिएर आयो
    // भन्दा स्वतन्त्र। सानो भन्दा सानो चाल पनि कम्तिमा ४००ms (देखिने
    // movement हुने) देखि बढीमा २s (धेरै टाढाको जम्प पनि "घस्रिने" नलागोस्)
    // बीच clamp।
    const minGlide = Duration(milliseconds: 400);
    const maxGlide = Duration(milliseconds: 2000);
    // Curve-Distance Duration Fix — यो अवधि पहिले सधैँ `from`→`newOrigin`
    // कै सीधा chord दूरी (haversine) बाट मात्र गणना हुन्थ्यो — तर glide
    // आफैं (route-snapping हुँदा) chord होइन, बाटोकै बाँगो/arc दूरी
    // (`_animToRouteDist - _animFromRouteDist`, माथि नै गणना भइसकेको)
    // हिंड्छ। सीधा बाटोमा यी दुई झन्डै उस्तै भएकोले अदृश्य थियो, तर
    // roundabout/तीखो मोडमा arc दूरी chord भन्दा धेरै लामो हुन सक्छ —
    // अवधि (छोटो chord-आधारित) ले चाहिं कम समय मात्र दिन्थ्यो, जबकि
    // marker ले (लामो arc) त्यति नै छोटो समयभित्र पार गर्नुपर्ने हुँदा
    // स्थिति र bearing-easing दुवै त्यो मोडमा मात्र हतार-हतार/"हिच्किएको"
    // देखिने गुनासोको साँचो जड — ठ्याक्कै सीधा सडकमा नभई मोड/roundabout
    // मै मात्र देखिनुको कारण पनि यही हो। अब route-snapping हुँदा arc
    // दूरी नै प्रयोग हुन्छ (chord होइन); route नभए/backward-projection
    // भएमा मात्र पुरानै chord fallback।
    final distKm = (_animFromRouteDist != null && _animToRouteDist != null)
        ? _animToRouteDist! - _animFromRouteDist!
        : haversineKm(
            from.latitude, from.longitude, newOrigin.latitude, newOrigin.longitude);
    // GPS Velocity Fusion — साँचो GPS-मापित गति उपलब्ध र विश्वासिलो (caller
    // ले पहिल्यै speedAccuracy जाँचेर मात्र पठाउने) भए त्यही — travel-mode
    // अनुसारको स्थिर अनुमान (सधैं bike=6m/s जस्तो) भन्दा वास्तविक पेस सँगै
    // मिल्दो। धेरै सानो/शून्यनजिकको मान (GPS jitter, उभिंदा पनि आउन सक्ने)
    // बाट बचाउन न्यूनतम 0.5 m/s floor।
    final gpsSpeed = widget.gpsSpeedMps;
    final speedMps = (gpsSpeed != null && gpsSpeed > 0.5)
        ? gpsSpeed
        : switch (widget.travelMode) {
            TravelMode.bicycling => 6.0,
            TravelMode.driving => 11.0,
            TravelMode.walking => 1.4,
          };
    _lastSpeedKmPerSec = speedMps / 1000;
    final seconds = (distKm * 1000) / speedMps;
    // Never-Stop Glide — अवधि ठ्याक्कै दूरी÷गति हुँदा glide अर्को GPS बिन्दु
    // आउनुअघि नै सकिएर बाइक क्षणभर रोकिन्थ्यो (हरेक बिन्दुमा "अड्किने")।
    // १.३x लामो बनाउँदा अर्को बिन्दु आउँदा अझै सरिरहेकै हुन्छ, र नयाँ glide
    // हालको displayed स्थानबाटै सुरु हुने भएकोले कहिल्यै रोकिँदैन/उफ्रिँदैन।
    var glideDuration = Duration(milliseconds: (seconds * 1300).round());
    if (glideDuration < minGlide) glideDuration = minGlide;
    if (glideDuration > maxGlide) glideDuration = maxGlide;
    // Continuous Playhead — follow मोडमा (route-snapped) हरेक GPS बिन्दुमा
    // glide फेरि सुरु गर्दा गति बदलिने/क्षणभर रोकिने (micro-stutter) हुन्थ्यो।
    // अब GPS बिन्दुले केवल "लक्ष्य दूरी + गति" अपडेट गर्छ; बाइक/क्यामेरा
    // एउटै निरन्तर ticker बाट हरेक frame मा route माथि बग्छ।
    final snappedRoute = widget.route;
    final snappedTo = _animToRouteDist;
    if (_centerOverlay && snappedRoute != null && snappedTo != null &&
        identical(snappedRoute, _animRouteRef)) {
      _moveCtrl.stop();
      _feedPlayhead(snappedRoute, _animFromRouteDist ?? snappedTo, snappedTo);
      return;
    }
    _playTicker?.stop();
    _playDist = null;
    _moveCtrl
      ..stop()
      ..duration = glideDuration
      ..reset()
      ..forward();
  }

  // ── Continuous Playhead (route-distance, per-frame) ──
  Ticker? _playTicker;
  RoadRoute? _playRoute;
  double? _playDist; // km, route सुरुदेखि — हाल देखिने स्थान
  double _playTarget = 0; // km, पछिल्लो GPS (Kalman-सहित) दूरी
  double _playSpeedKmS = 0; // km/s, लक्ष्यको चालबाट EMA
  DateTime _playTargetAt = DateTime.now();
  Duration _playLastElapsed = Duration.zero;

  void _feedPlayhead(RoadRoute route, double fromDist, double toDist) {
    final now = DateTime.now();
    if (_playDist == null || !identical(route, _playRoute)) {
      _playRoute = route;
      _playDist = fromDist;
      _playTarget = toDist;
      _playSpeedKmS = _lastSpeedKmPerSec;
    } else {
      final dt = now.difference(_playTargetAt).inMilliseconds / 1000.0;
      if (dt > 0.05) {
        final inst = ((toDist - _playTarget) / dt).clamp(0.0, 0.05).toDouble();
        _playSpeedKmS = _playSpeedKmS == 0
            ? inst
            : _playSpeedKmS * 0.6 + inst * 0.4;
      }
      _playTarget = toDist;
    }
    _playTargetAt = now;
    final t = _playTicker ??= createTicker(_onPlayTick);
    if (!t.isActive) {
      _playLastElapsed = Duration.zero;
      t.start();
    }
  }

  /// Route Swap Rebase — passenger तर्फ `_liveRoute` हरेक ३-१५s मा नयाँ object
  /// बन्छ। पहिले `_onPlayTick` ले `identical(route, widget.route)` असफल हुनासाथ
  /// ticker रोक्थ्यो, अनि अर्को GPS बिन्दु (≥१s) नआउँदासम्म marker जम्थ्यो —
  /// यही "बेला-बेलामा अड्किने" को जड। अब playhead लाई नयाँ route माथि
  /// हालको देखिने स्थानबाटै पुनः-आधारित गरिन्छ, ticker कहिल्यै रोकिँदैन।
  bool _rebasePlayhead(RoadRoute route) {
    final pts = route.points;
    final shown = _displayedOrigin;
    final target = widget.origin;
    if (pts.length < 2 || shown == null || target == null) return false;
    final shownDist = _projectDistanceAlongRoute(pts, shown);
    final targetDist = _projectDistanceAlongRoute(pts, target);
    _playRoute = route;
    _playDist = shownDist;
    _playTarget = targetDist < shownDist ? shownDist : targetDist;
    _lastMatchedSegmentIndex = null;
    _distanceKalman.reset(_playTarget);
    _lastKalmanAt = DateTime.now();
    _animRouteRef = route;
    _animToRouteDist = _playTarget;
    return true;
  }

  void _onPlayTick(Duration elapsed) {
    var route = _playRoute;
    final liveRoute = widget.route;
    if (mounted &&
        route != null &&
        liveRoute != null &&
        !identical(route, liveRoute) &&
        _rebasePlayhead(liveRoute)) {
      route = liveRoute;
    }
    final cur = _playDist;
    final pts = route?.points;
    if (!mounted || route == null || cur == null || pts == null ||
        pts.length < 2 ||
        !identical(route, widget.route)) {
      _playTicker?.stop();
      return;
    }
    final dt = ((elapsed - _playLastElapsed).inMicroseconds / 1e6)
        .clamp(0.0, 0.05);
    _playLastElapsed = elapsed;
    if (dt <= 0) return;
    final sinceTarget = DateTime.now()
            .difference(_playTargetAt)
            .inMilliseconds /
        1000.0;
    // लक्ष्यलाई उही गतिमा अगाडि extrapolate (≤1.2s) — नयाँ GPS नआउँदा पनि
    // नरोकिने, तर धेरै टाढा पनि नजाने।
    final extrapolated =
        _playTarget + _playSpeedKmS * sinceTarget.clamp(0.0, 1.2);
    // First-order follow (τ=0.3s): स्थिर गतिमा स्थिर lag, कुनै झट्का छैन।
    final k = 1 - exp(-dt / 0.3);
    var next = cur + (extrapolated - cur) * k;
    if (next < cur) next = cur; // कहिल्यै पछाडि नजाने।
    _playDist = next;

    final displayed = _pointAtRouteDistance(pts, next);
    if (displayed == null) return;
    _displayedOrigin = displayed;
    if (!_headingOverrideIsLive) {
      final gpsHeading = widget.gpsHeadingDeg;
      final gpsOk = gpsHeading != null && (widget.gpsSpeedMps ?? 0) > 0.8;
      // ~6m अगाडिको tangent — मोड अगाडिबाटै सहज घुम्न थाल्छ।
      final target = gpsOk
          ? gpsHeading
          : _bearingAtRouteDistance(pts, next + 0.006);
      if (target != null) {
        _bearing += shortestAngleDelta(_bearing, target) *
            (1 - exp(-dt / 0.15));
      }
    }
    if (!_centerOverlay) _liveTick.tick(); // follow रोकिएको बेला Marker सार्ने
    _followCameraTo(displayed);
    if ((extrapolated - next).abs() < 1e-7 && _playSpeedKmS <= 1e-7) {
      _playTicker?.stop();
    }
  }

  void _maybeUpdateBearing(LatLng newOrigin) {
    final from = _bearingFrom;
    if (from == null) {
      _bearingFrom = newOrigin;
      return;
    }
    final movedKm = haversineKm(
        from.latitude, from.longitude, newOrigin.latitude, newOrigin.longitude);
    if (movedKm < _minMoveForBearingKm) {
      // दिशा यो पटक अपडेट भएन (जित्टर-थ्रेसहोल्ड भन्दा सानो चाल) — तर
      // position चाहिं अझै ग्लाइड हुन्छ (`_startGlideTo` यो function बाहिर,
      // सधैँ unconditional)। अघिल्लो चक्रका `_bearingAnimFrom/To` नसफा
      // गरे, `_moveCtrl` यो नयाँ (बेकार्दै सानो) ग्लाइडका लागि फेरि t=0
      // बाट चल्दा `_onMoveTick` ले त्यही पुरानो interpolation दोहोर्‍याउँथ्यो
      // — नतिजा: बेअर्ड पहिले नै पुगिसकेको (`bTo`) बाट क्षणभर `bFrom` मा
      // फर्केर फेरि `bTo` तिर गएको देखिने ("wobble") — ठ्याक्कै उस्तै
      // jerk, फरक कारणबाट। अब null राखेर यो cycle मा बेअरिङ नै नछोइने।
      _bearingAnimFrom = null;
      _bearingAnimTo = null;
      return;
    }
    // Correct Bearing on Curves — route उपलब्ध भए सीधा chord (from→newOrigin,
    // टाढाका दुई GPS/simulated बिन्दुबीच सीधै) होइन, route.points कै local
    // tangent (मोडिएको ठाउँमा पनि साँचो road-direction) — नत्र बाटो मोडिँदा
    // आइकनको मुख (अगाडि/पछाडिको बत्ती) बाटो भन्दा फरक दिशामा देखिन्थ्यो।
    //
    // GPS Velocity Fusion — साँचो GPS chip को course-over-ground (`Position.
    // heading`, caller ले पहिल्यै confidence जाँचेर मात्र पठाउने) उपलब्ध र
    // सवारी साँच्चै चलिरहेको (gpsSpeedMps केही हुनुपर्छ, उभिंदा GPS heading
    // आफैं अर्थहीन/noisy हुन्छ) भए — त्यही सिधै प्रयोग, route-tangent गणना
    // नपर्खी। बाँकी अवस्थामा (route नभए, वा GPS heading अनुपलब्ध/अविश्वासिलो)
    // पुरानै route-tangent/chord fallback।
    final gpsHeading = widget.gpsHeadingDeg;
    final gpsSpeedOk = (widget.gpsSpeedMps ?? 0) > 0.8;
    final pts = widget.route?.points;
    final target = (gpsHeading != null && gpsSpeedOk)
        ? gpsHeading
        : (pts != null && pts.length >= 2)
            ? (_bearingAtRouteDistance(pts, _projectDistanceAlongRoute(pts, newOrigin)) ??
                bearingBetween(from, newOrigin))
            : bearingBetween(from, newOrigin);
    _bearingFrom = newOrigin;
    // सिधै `_bearing = target` (पहिले जस्तै) होइन — `_onMoveTick()` ले
    // `_moveCtrl` कै उही 900ms मा `_bearingAnimFrom`→`_bearingAnimTo`
    // एनिमेट गरोस् भनेर। `_bearing` आफैं अघिल्लो एनिमेसनले जता पुर्‍याएको
    // थियो त्यहीँबाट (shortest-path मार्फत) सुरु हुन्छ, कहिल्यै उफ्रिँदैन।
    _bearingAnimFrom = _bearing;
    _bearingAnimTo = _bearing + shortestAngleDelta(_bearing, target);
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
    _subscribeHeadingOverride(widget.headingOverrideStream);
    if (widget.showPointLabels &&
        (widget.destinationLabel != _primaryLabeledFor ||
            old.primaryIsDropoff != widget.primaryIsDropoff)) {
      _loadPrimaryLabeledIcon(widget.destinationLabel);
    }
    if (widget.showPointLabels && widget.secondaryDestination != null &&
        widget.secondaryDestinationLabel != _secondaryLabeledFor) {
      _loadSecondaryLabeledIcon(widget.secondaryDestinationLabel);
    }
    final newOrigin = widget.origin;
    if (newOrigin != null && newOrigin != old.origin) {
      // Sensor-Fusion Heading Override — यो साँच्चै live/भर्खरै डेटा
      // दिइरहेको बेला मात्र `bFrom`/`bTo` (route-tangent/GPS-heading
      // बेअरिङको लक्ष्य) नसेट्ने — नत्र `_onMoveTick()` को पछिल्लो fallback
      // branch (`_bearing = bFrom + (bTo-bFrom)*t`) ले gyro-driven
      // `_bearing` लाई प्रत्येक glide-tick मा ओभरराइट गर्थ्यो, दुई system
      // आपसमा लड्दै। `_headingOverrideIsLive` doc-comment हेर्नुहोस् —
      // Simulate GPS (जसले इन्जिनलाई कहिल्यै anchor गर्दैन) मा यो स्वतः
      // false रहन्छ, पुरानो प्रमाणित प्रणाली नै सम्हाल्छ। Position glide
      // (`_startGlideTo`, तल) भने दुवै हालतमा जस्ताको-त्यस्तै।
      if (!_headingOverrideIsLive) {
        _maybeUpdateBearing(newOrigin);
      }
      if (old.origin == null) {
        // पहिलोपटक (null बाट) — सिधै देखिने, कुनै टाढाबाट glide होइन।
        _displayedOrigin = newOrigin;
      } else {
        _startGlideTo(newOrigin);
      }
    }
    final destChanged = old.destination != widget.destination;
    final originAppeared = old.origin == null && widget.origin != null;
    // राइड ठ्याक्कै अहिले नै सुरु भएको क्षण (OTP मिलेको) — destination
    // नबदलिए/origin पहिल्यैदेखि भए पनि, close-up zoom मा तुरुन्तै (अर्को
    // 50m सर्नुअघि नै) सर्नुपर्छ, नत्र केही सेकेन्ड पुरानै टाढाको दृश्यमा
    // अड्किएको देखिन्थ्यो।
    final rideJustStarted = !old.rideStarted && widget.rideStarted;
    if (destChanged || originAppeared || rideJustStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      _lastFitOrigin = newOrigin;
    } else if (!_closeFollowCamera &&
        newOrigin != null &&
        newOrigin != old.origin) {
      // Competing-Camera Stutter Fix — `rideStarted` भइसकेपछि माथिकै
      // `_onMoveTick()` ले नै हरेक glide-tick मा `moveCamera` (continuous
      // follow, हेर्नुहोस् "Continuous Camera Follow" doc-comment) पहिल्यै
      // गरिसक्छ। यो तल्लो 50m-threshold `_fitBounds()` (पुरानो, continuous
      // follow थपिनुअघिको मेकानिजम — त्यो बेला हटाउन बिर्सिएको) ले
      // छुट्टै `animateCamera` पनि सँगसँगै तान्दा दुई क्यामेरा-एनिमेसन
      // एकअर्कासँग लडेर बाइक आइकन (वास्तवमा स्थिर गरी लर्प भइरहेको भए पनि)
      // स्क्रिनमा "अडकि-अडकि/झट्का" देखिने गुनासोको साँचो जड थियो। अब
      // rideStarted मा यो पुरानो re-fit path नै नचलाउने — continuous
      // per-tick follow एक्लैले पुग्छ।
      final lastFit = _lastFitOrigin;
      final movedKm = lastFit == null
          ? double.infinity
          : haversineKm(lastFit.latitude, lastFit.longitude, newOrigin.latitude,
              newOrigin.longitude);
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
    _resumeFollowTimer?.cancel();
    _pulse.dispose();
    _playTicker?.dispose();
    _moveCtrl.dispose();
    _lightCtrl.dispose();
    _liveTick.dispose();
    _headingOverrideSub?.cancel();
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
    // Immersive Close-Up Zoom on Ride Start — राइड सुरु भइसकेपछि (OTP मिलेर
    // 'in_progress') destination जतिसुकै टाढा भए पनि pickup↔destination
    // दुवै देखिने गरी जबरजस्ती zoom-out (`newLatLngBounds`) कहिल्यै नगर्ने
    // — बरु ड्राइभरकै हालको स्थानमा सधैँ street/building-level close-up
    // (zoom १९) मा लक गरेर, माथिकै `didUpdateWidget` को ~50m-movement
    // re-fit थ्रेसहोल्डले नै निरन्तर "follow" गराउँछ (गाडी बाटोमा सर्दै
    // जाँदा क्यामेरा पनि सँगसँगै सर्छ, वास्तविक vehicle-movement देखियोस्)।
    if (_closeFollowCamera && origin != null) {
      // North-Up Camera — Re-Confirmed By Live Measurement (third time) —
      // heading-up rotation was explicitly re-enabled per product request
      // and live phone test immediately reproduced the same severe,
      // worsening jank as the prior two attempts (Davey durations climbing
      // past 6000ms within under a minute, same device). Reverted back to
      // north-up; `_bearing` still drives the marker's own cheap sprite
      // rotation, only the camera/map itself stays fixed. Do not re-enable
      // without new measurement showing this device can sustain it.
      // Heading-up: per-tick `_followCameraTo` सँग उही target/bearing/zoom,
      // र सधैं instant — `animateCamera` ले चलिरहेको follow सँग लड्थ्यो।
      _didInitialFit = true;
      _followCameraTo(_displayedOrigin ?? origin);
      return;
    }
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
        // Full-Journey Preview — secondaryDestination (pickup/drop-off
        // मध्ये अर्को, maathi widget doc-comment हेर्नुहोस्) भए यो
        // bounds-fit मा पनि समेट्ने — नत्र caller ले पठाएको secondary
        // marker पर्दाबाहिरै पर्थ्यो (रेन्डर त हुन्थ्यो, तर कहिल्यै
        // नदेखिने)। साँच्चैको ride मा pickup/drop प्रायः एउटै शहरभित्रै
        // (नजिकै) हुने भएकोले यसले सामान्यतया ठीकै zoom दिन्छ — धेरै
        // टाढा-टाढाको test data मा मात्र व्यापक zoom-out देखिनु स्वाभाविक
        // हो (दुवै बिन्दु साँच्चै त्यति टाढा भएकै हो)।
        final secondary = widget.secondaryDestination;
        final swLat = secondary == null
            ? min(origin.latitude, widget.destination.latitude)
            : min(min(origin.latitude, widget.destination.latitude),
                secondary.latitude);
        final swLng = secondary == null
            ? min(origin.longitude, widget.destination.longitude)
            : min(min(origin.longitude, widget.destination.longitude),
                secondary.longitude);
        final neLat = secondary == null
            ? max(origin.latitude, widget.destination.latitude)
            : max(max(origin.latitude, widget.destination.latitude),
                secondary.latitude);
        final neLng = secondary == null
            ? max(origin.longitude, widget.destination.longitude)
            : max(max(origin.longitude, widget.destination.longitude),
                secondary.longitude);
        update = CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(swLat, swLng),
            northeast: LatLng(neLat, neLng),
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

  DateTime _lastPulseRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _refreshPulse() async {
    final c = _map;
    if (c == null || !mounted) return;
    // Follow मा हरेक moveCamera पछि `onCameraIdle` आउँछ — प्रति-frame
    // `getScreenCoordinate` platform round-trip + setState नगर्न throttle।
    if (_closeFollowCamera) {
      final now = DateTime.now();
      if (now.difference(_lastPulseRefresh).inMilliseconds < 500) return;
      _lastPulseRefresh = now;
    }
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

  // ── बैजनी route-रेखा गाडीसँगै "खाइँदै" जाने (consumed trail) ──
  // `widget.route` को सुरु बिन्दु = route पछिल्लोपटक fetch हुँदा गाडी भएको
  // ठाउँ (३–१५s को अन्तरमा बदलिन्छ), जबकि आइकन (`_displayedOrigin`) हरेक
  // frame glide हुन्छ — त्यसैले आइकन अगाडि बढिसक्दा पनि पछाडिको रेखा
  // अर्को route आउँदासम्म (सेकेन्डौँ) बाँकी रहन्थ्यो। अब रेखा गाडीको हालको
  // (देखिने) स्थानबाट मात्र सुरु हुन्छ; पछाडिको भाग ≤१२०ms मै मेटिन्छ।
  // (केवल यात्रीको नक्सा — worker को follow-camera मोडमा होइन।)
  RoadRoute? _trimSrc;
  int _trimIdx = 0;
  RoadRoute? _trimCached;
  DateTime _trimAt = DateTime.fromMillisecondsSinceEpoch(0);

  RoadRoute? _routeFromVehicle(RoadRoute? route) {
    if (route == null || route.points.length < 2) return route;
    final shown = _displayedOrigin;
    if (_centerOverlay || shown == null) return route;
    if (!identical(route, _trimSrc)) {
      _trimSrc = route;
      _trimIdx = 0;
      _trimCached = null;
    }
    final now = DateTime.now();
    final cached = _trimCached;
    if (cached != null && now.difference(_trimAt).inMilliseconds < 120) {
      return cached;
    }
    final pts = route.points;
    final cosLat = cos(shown.latitude * pi / 180);
    final px = shown.longitude * cosLat;
    final py = shown.latitude;
    var best = double.infinity;
    var bi = _trimIdx;
    var bp = pts[bi];
    final end = min(_trimIdx + 60, pts.length - 2);
    for (var i = _trimIdx; i <= end; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final ax = a.longitude * cosLat;
      final ay = a.latitude;
      final dx = b.longitude * cosLat - ax;
      final dy = b.latitude - ay;
      final l2 = dx * dx + dy * dy;
      final t =
          l2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
      final qx = ax + dx * t;
      final qy = ay + dy * t;
      final d = (px - qx) * (px - qx) + (py - qy) * (py - qy);
      if (d < best) {
        best = d;
        bi = i;
        bp = LatLng(a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t);
      }
    }
    // गाडी route बाट धेरै (>८०m) टाढा भए (route-बाहिर/पुरानो route) — नकाटी
    // पूरै रेखा देखाउने; गलत ठाउँमा काट्नु भन्दा सुरक्षित।
    if (sqrt(best) * 111000 > 80) return route;
    _trimIdx = bi;
    final r = (
      points: <LatLng>[bp, ...pts.sublist(bi + 1)],
      km: route.km,
      minutes: route.minutes,
      real: route.real,
      mode: route.mode,
    );
    _trimCached = r;
    _trimAt = now;
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = _routeFromVehicle(widget.route);
    return ColoredBox(
      // native platform view attach हुनुअघिको क्षणभर यही देखियोस् भनेर —
      // caller (JobRouteScreen/RequestTrackingScreen) को Scaffold background
      // पनि यही राखिएको छ, तर यहाँ widget-level मै राख्दा यो कतै अरू ठाउँमा
      // (फरक/dark background भएको) प्रयोग भए पनि कहिल्यै कालो flash हुँदैन।
      color: AppColors.mapPlaceholderBg,
      child: Stack(
        children: [
          // Narrow-Rebuild — `_liveTick` doc-comment हेर्नुहोस्: यो
          // `AnimatedBuilder` ले मात्र `_onMoveTick`/`_onLightTick` का
          // frequent notify सुन्छ, बाहिरको Stack/pill/pulse होइन।
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _pauseFollow(),
            onPointerUp: (_) => _scheduleResumeFollow(),
            onPointerCancel: (_) => _scheduleResumeFollow(),
            child: AnimatedBuilder(
            animation: _liveTick,
            // Compositor-Level Heading-Up (Explicit Product Override, v2) —
            // native camera bearing रोटेसन (पहिले प्रयास गरिएको, मापिएको
            // गम्भीर jank पछि फिर्ता गरिएको) यहाँ कहिल्यै प्रयोग हुँदैन —
            // `GoogleMap` आफैं सधैं bearing: 0 मै रहन्छ, त्यसैले native
            // side ले महँगो per-frame tile re-render कहिल्यै गर्दैन। बरु
            // पहिल्यै-रेन्डर भइसकेको सिंगो native surface लाई Flutter कै
            // आफ्नै compositor-level `Transform.rotate` ले (सस्तो, image-
            // rotate जत्तिकै) घुमाइन्छ — marker आफ्नै `rotation: _bearing`
            // (अपरिवर्तित) सँग मिलेर बाइक सधैं माथितिरै फर्किएको देखिन्छ,
            // बाँकी संसार (बाटो/लेबल) यसको वरिपरि घुम्छ, ठ्याक्कै heading-
            // up nav जस्तै। ज्ञात सीमा: Google का आफ्नै native label/logo
            // (native surface भित्रैको भएकोले छुट्टै छेक्न नमिल्ने) पनि
            // यही रोटेसनसँगै घुम्छन् — PlatformView bounds भन्दा बाहिर
            // केही कुनामा पृष्ठभूमि देखिने (live-test ले पुष्टि गर्‍यो)
            // समस्या — rotated rectangle ले आफ्नै unrotated bounding-box
            // का कुनाहरू कहिल्यै ढाक्दैन भन्ने गणितीय निश्चितता — अब
            // `Transform.scale` (1.5x, सबैभन्दा सामान्य angle हरूमा
            // पर्याप्त, अति-ठाडो phone aspect ratio मा चरम ९०°-नजिकको
            // angle मा सानो gap अझै सम्भव) + `ClipRect` (स्क्रिनभन्दा
            // बाहिरको भाग लुकाउन) ले ढाक्छ। याद गर्नुहोस्: यसले रेन्डर
            // हुने pixel क्षेत्र (र त्यही अनुपातमा लागत) पनि बढाउँछ —
            // यो प्रविधिको "सस्तो" भन्ने दाबीविरुद्ध नै एउटा साँचो tradeoff,
            // live-test ले नै हेर्नुपर्ने।
            builder: (context, _) => GoogleMap(
            initialCameraPosition: CameraPosition(
                target: widget.destination, zoom: 18, bearing: 0),
            // Vector Tiles — Google Cloud Console मा बनाइएको Map ID
            // (GPU-accelerated vector rendering, raster tile भन्दा सस्तो
            // pan/zoom)। महत्त्वपूर्ण: Cloud-based Map ID प्रयोग गर्दा, Google
            // ले style लाई server-side (Cloud Console कै Map Style editor)
            // बाट मात्र लिन्छ — local JSON `style:` (kCleanMapStyle, अझै
            // nearby_common.dart मा reference को लागि राखिएको) लाई बेवास्ता
            // गर्छ, त्यसैले यहाँ नराखिएको।
            mapId: kCloudMapId,
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
            // 3D Buildings/Indoor Off — both default to true on this
            // Cloud (vector) Map ID and neither has ever been touched in
            // this file's extensive camera-jank tuning history. At zoom 19
            // with continuous per-tick camera moves, re-lighting/re-
            // extruding 3D building geometry on every pan is a well-known
            // heavy cost on Android vector maps — pure overhead for a
            // ride-tracking map that never needs building extrusions or
            // indoor floor plans.
            buildingsEnabled: false,
            indoorViewEnabled: false,
            padding: widget.mapPadding,
            markers: {
              // झन्डाको bitmap load नभएसम्म marker नै नदेखाउने — कुनै
              // default/fallback pin कहिल्यै यसको सट्टा नदेखियोस्। Ride
              // screens (`showPointLabels: true`) मा सामान्य `_flagIcon`
              // होइन, `labeledFlagPin()` बाट बनेको — झन्डाको ठ्याक्कै माथि
              // "Pickup Point"/"Drop Point" सधैँ देखिने (tap नचाहिने) —
              // bitmap प्रयोग हुन्छ।
              if (widget.showPointLabels
                  ? _primaryLabeledIcon != null
                  : _flagIcon != null)
                Marker(
                  markerId: const MarkerId('destination'),
                  position: widget.destination,
                  anchor: widget.showPointLabels
                      ? _primaryLabeledAnchor!
                      : FlagPinGeometry.markerAnchorFraction,
                  icon: widget.showPointLabels
                      ? _primaryLabeledIcon!
                      : _flagIcon!,
                  infoWindow: InfoWindow(
                    title: widget.destinationLabel,
                    snippet: widget.destinationAddress.isEmpty
                        ? S.jobSiteWord
                        : widget.destinationAddress,
                  ),
                ),
              // Full-Journey Preview — पहिले pickup तिर आउँदै गर्दा अन्तिम
              // गन्तव्य नै कहीं देखिँदैनथ्यो, driver/passenger दुवैले
              // बाटोको आधा भाग मात्र थाहा पाउँथे। अब (caller ले दिएमा मात्र)
              // त्यही एउटै `_flagIcon` bitmap, हल्का/dimmed (`alpha`) —
              // "यो नै अन्तिम गन्तव्य हो, अहिले होइन पछि" भन्ने स्पष्ट होस्।
              // (`showPointLabels` मा dim गर्ने आफ्नै labeled bitmap छ,
              // `alpha` त्यहाँ पनि उस्तै लागू हुन्छ।)
              if (widget.secondaryDestination != null &&
                  (widget.showPointLabels
                      ? _secondaryLabeledIcon != null
                      : _flagIcon != null))
                Marker(
                  markerId: const MarkerId('secondary_destination'),
                  position: widget.secondaryDestination!,
                  anchor: widget.showPointLabels
                      ? _secondaryLabeledAnchor!
                      : FlagPinGeometry.markerAnchorFraction,
                  icon: widget.showPointLabels
                      ? _secondaryLabeledIcon!
                      : _flagIcon!,
                  alpha: 0.55,
                  infoWindow: InfoWindow(
                    title: widget.secondaryDestinationLabel.isEmpty
                        ? S.destinationLabel
                        : widget.secondaryDestinationLabel,
                  ),
                ),
              if (!_centerOverlay && widget.origin != null && _originIcon != null)
                Marker(
                  markerId: const MarkerId('origin'),
                  // `_displayedOrigin` (animated glide-in-progress position)
                  // — साँचो `widget.origin` (नयाँ GPS fix) होइन, जबसम्म
                  // glide पूरा नभएको। यसैले marker सिधै "jump" नगरी सहज
                  // गरी सर्छ।
                  position: _displayedOrigin ?? widget.origin!,
                  anchor: const Offset(0.5, 0.5),
                  // Flutter Web Marker-Rotation Workaround — माथि
                  // `_webRotatedIcon` doc-comment हेर्नुहोस्: web मा
                  // pre-rotated bitmap (rotation:0), native मा साधारण
                  // unrotated icon + native `rotation:_bearing` (सस्तो,
                  // GPU-side)।
                  icon: kIsWeb ? (_webRotatedIcon ?? _originIcon!) : _originIcon!,
                  // `flat: true` नभई rotation ले 3D tilt/perspective दिन्छ
                  // (उत्तर-माथि 2D नक्सामा अनावश्यक) — यसले सीधै नक्साकै
                  // सतहमा (native, GPU-side) घुमाउँछ, कुनै Flutter rebuild
                  // नचाहिने।
                  flat: true,
                  rotation: kIsWeb ? 0 : _bearing,
                  infoWindow: InfoWindow(title: widget.originLabel),
                ),
            },
            polylines: {
              // सेतो casing सधैँ मुख्य रेखामुनि (मानक Google Maps navigation
              // जस्तै) + "last-mile" डट्टेड connector — route साँच्चै
              // बदलिएको बेला मात्र पुनः-गणना (माथि `_staticPolylinesFor`
              // doc-comment हेर्नुहोस्), हरेक animation tick मा होइन।
              ..._staticPolylinesFor(route, widget.origin, widget.destination),
              // Full-Journey Preview — दोस्रो (pickup→drop-off) खण्ड, हल्का/
              // ग्रे/dashed रेखा — मुख्य (अहिले चलिरहेको) बैजनी रेखासँग
              // कहिल्यै नझुक्किने गरी छुट्टै स्पष्ट शैली। अब cached (माथि
              // `_secondaryPolylineFor` हेर्नुहोस्) — route object नबदलिएसम्म
              // हरेक tick मा नयाँ object होइन।
              ..._secondaryPolylineFor(widget.secondaryRoute),
              // ── Uber-शैलीको बगेको लाइट — मुख्य purple रेखामाथि नै ──
              // `_lightPolylinesFor` doc-comment हेर्नुहोस् — `_lightProgress`
              // नबदलिएसम्म cached (move-only tick मा native call नै छोड्छ)।
              if (!_centerOverlay && route != null && route.points.length >= 2)
                ..._lightPolylinesFor(route, _lightProgress),
            },
            ),
          ),
          ),

          // ── बाइक — स्क्रिनको ठ्याक्कै बीचमा (क्यामेरा यसैमा लक) ──
          if (_centerOverlay && widget.origin != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Image.asset(_vehicleAsset,
                      width: 96, height: 96, filterQuality: FilterQuality.medium),
                ),
              ),
            ),

          // ── Recenter — नक्सा हातले सारेपछि (follow रोकिएको) फेरि गाडीमा फर्कने ──
          if (_followPaused && _closeFollowCamera)
            Positioned(
              right: 12,
              top: 64,
              child: Material(
                color: AppColors.kmPurple,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _resumeFollow,
                  child: const Padding(
                    padding: EdgeInsets.all(11),
                    child: Icon(Icons.my_location_rounded,
                        size: 22, color: Colors.white),
                  ),
                ),
              ),
            ),

          // ── इनड्राइभ-शैलीको धड्किने halo, स्थिर काम-स्थलको पिनमाथि ──
          // दुवै overlay आफ्नै RepaintBoundary — "बगेको लाइट" एनिमेसनले
          // (माथिको GoogleMap कै polylines Set) हरेक tick मा यो पूरै
          // build() दोहोर्‍याउँछ, तर यी दुई (स्थिर summary pill, आफ्नै
          // बेग्लै `_pulse` controller ले चलेको halo) कुनै हालतमा त्यही
          // कारणले repaint हुनु पर्दैन।
          if (_pulseAt != null)
            Positioned(
              left: _pulseAt!.dx - 70,
              top: _pulseAt!.dy - 70,
              child: RepaintBoundary(
                child: PulseRings(t: _pulse, color: AppColors.kmPurple),
              ),
            ),

          // ── दूरी/समय — नक्सामाथि सधैँ देखिने pill, कुनै tap नचाहिने ──
          Positioned(
            top: 14,
            left: 12,
            right: 12,
            child: RepaintBoundary(
              child: Center(child: _summaryPill(theme)),
            ),
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
              size: 15, color: AppColors.kmAmber),
          const SizedBox(width: 8),
          Flexible(
            child: Text(S.locationNeededForRoute,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: openLocationAppSettings,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.kmOrange,
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
                    size: 15, color: AppColors.kmAmber),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                      widget.originMissingMessage ?? S.locationNeededForRoute,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (widget.onRetryOrigin != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onRetryOrigin,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.kmOrange,
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
              size: 15, color: AppColors.kmAmber),
          const SizedBox(width: 8),
          Flexible(
            child: Text(S.routeUnavailable,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      );
    } else {
      // Live Remaining Distance/ETA — पहिले यहाँ सधैँ `route.km`/
      // `route.minutes` (जुन route पहिलोपटक/पछिल्लोपटक fetch भएको
      // बेलाको सिंगो-यात्राको कुल आँकडा हो) सिधै देखाइन्थ्यो — गाडी
      // बाटोमा जतिसुकै अगाडि बढे पनि यो संख्या कहिल्यै घट्दैनथ्यो, किनकि
      // route बारम्बार पुनः-fetch हुँदैन (विशेष गरी "Simulate GPS" चलिरहेको
      // बेला, जहाँ route एकपटक मात्र तानिन्छ)। अब हालको स्थान route.points
      // माथि नै प्रोजेक्ट गरेर (ठ्याक्कै marker-position कै उही
      // `_projectDistanceAlongRoute` प्रयोग गरेर) "अझै कति बाँकी" गणना
      // गरिन्छ — route पुनः-fetch नभईकनै, हरेक tick मा सहज रूपमा घट्दै जाने।
      final currentPos = _displayedOrigin ?? widget.origin;
      final remainingKm = (currentPos != null && route.points.length >= 2)
          ? (route.km - _projectDistanceAlongRoute(route.points, currentPos))
              .clamp(0.0, route.km)
          : route.km;
      final remainingMinutes = route.km > 0
          ? (route.minutes * (remainingKm / route.km)).round()
          : route.minutes;
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // यातायात मोड (driving/walking/bike) कै आइकन — generic route/
          // timeline icon भन्दा प्रस्ट, ride-hailing app जस्तै तुरुन्तै
          // चिनिने। `!route.real` (fallback source) भए मात्र त्यो जनाउने
          // छुट्टै icon तल थपिन्छ।
          Icon(route.mode.icon, size: 16, color: AppColors.kmText),
          const SizedBox(width: 8),
          Text(
            '${remainingKm.toStringAsFixed(remainingKm < 10 ? 1 : 0)} km  ·  ${S.minutesShort(remainingMinutes)}',
            style: const TextStyle(
                color: AppColors.kmText,
                fontWeight: FontWeight.w800,
                fontSize: 13.5),
          ),
          if (!route.real) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: S.routeFallbackWarning,
              child: const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.kmAmber),
            ),
          ],
          if (widget.navigateTarget != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _openInGoogleMaps,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  gradient: AppColors.kmCtaGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded,
                    size: 14, color: AppColors.kmInk),
              ),
            ),
          ],
        ],
      );
    }

    return GlassPanel2(
      radius: AppRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: content,
    );
  }

  Widget _loadingRow(String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.kmOrange)),
          const SizedBox(width: 9),
          Text(label,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      );
}
