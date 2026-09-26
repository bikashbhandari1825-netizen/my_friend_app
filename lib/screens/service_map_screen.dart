// screens/service_map_screen.dart
// Pathao/InDrive-style: होमपेजको सर्च वा category थिच्दा यो MAP खुल्छ।
// नक्सा जानाजान सफा राखिएको — व्यक्तिगत worker pin देखिँदैनन्, आफ्नो
// (pickup) झन्डा मात्र। तल "Post job" बटनले नजिकका सबै worker लाई
// एकैचोटि अनुरोध पठाउँछ (broadcast), अनि tracking स्क्रिन खुल्छ।
import 'dart:async';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_avatar.dart';
import 'nearby_common.dart';
import 'request_tracking_screen.dart';
import 'worker_profile_screen.dart';

class ServiceMapScreen extends StatefulWidget {
  final String serviceType;
  // अघिल्लो (होम) स्क्रिनले पहिल्यै GPS fetch गरिसकेको भए त्यही स्थान —
  // यसले नयाँ पेज खुल्नेबित्तिकै (कुनै GPS पर्खाइ/spinner बिना) तुरुन्तै
  // सही ठाउँमा नक्सा देखाउन दिन्छ। नदिए (null) fallback केन्द्रबाट सुरु
  // भएर पृष्ठभूमिमा आफ्नै GPS ले चाँडै सच्याउँछ।
  final double? initialLat;
  final double? initialLng;
  const ServiceMapScreen({
    super.key,
    required this.serviceType,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<ServiceMapScreen> createState() => _ServiceMapScreenState();
}

class _ServiceMapScreenState extends State<ServiceMapScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;

  // `initState()` मा तुरुन्तै (होमपेजबाट आएको सिड वा fallback) भरिन्छ —
  // State को field initializer चल्ने बेला `widget` अझै जोडिएको हुँदैन,
  // त्यसैले यहाँ होइन initState() भित्रै सेट गर्नुपर्छ।
  double _originLat = fallbackLat;
  double _originLng = fallbackLng;
  double _lat = fallbackLat;
  double _lng = fallbackLng;
  bool _centeredOnce = false;
  // `onCameraMoveStarted` हाम्रै कोडले चलाएको (`animateCamera`, जस्तै
  // सुरुको auto-centre वा "home" बटन) कारणले पनि फायर हुन्छ, प्रयोगकर्ताले
  // औंलाले pan गरेकै बेला मात्र होइन — त्यसैले haptic feedback प्रयोगकर्ताले
  // साँच्चै आफैं pin/नक्सा चलाउँदा मात्र दिन (auto-centre मा अनावश्यक
  // भाइब्रेट नहोस्), यो flag ले छुट्याउने।
  bool _programmaticCameraMove = false;
  bool _sending = false;
  // "Confirm job details" sheet खुला हुँदा नक्साका gesture निष्क्रिय — नत्र
  // web मा बटनको tap पछाडिको Google Map ले खोस्थ्यो।
  bool _postSheetOpen = false;
  // तल्लो प्यानल अब सधैँ पूरै खुला रहनुको सट्टा, सुरुमा बन्द/peek मात्र —
  // माथि स्वाइप (वा header tap) गरेपछि मात्र पूरा (worker chips, भाडा
  // stepper, Post job बटन) देखिने। बन्द छँदा header row (icon + "N
  // providers nearby") मात्र देखिन्छ।
  //
  // 0 = बन्द/peek, 1 = पूरा खुला — live drag बेला हरेक फ्रेममा औंलासँगै
  // सिधै (कुनै setState/animation-lag बिना) अपडेट हुन्छ, छोड्दा नजिकैको
  // छेउमा (0 वा 1) SpringSimulation ले settle गर्छ। पहिले यो साधारण
  // `bool` थियो र panel को visual आकार `AnimatedSize` ले आफ्नै गतिमा
  // (छुट्टै, प्यानलको साँचो rendered height पछि-मात्र GlobalKey बाट नापेर)
  // बदल्थ्यो — ती दुई (animation कति पुग्यो vs माथिको `_RideSummaryCard`/
  // `_ProviderCard` कहाँ टाँसिने) कहिल्यै एउटै फ्रेममा synchronized थिएनन्,
  // त्यसैले प्यानल तान्दा/खुल्दा-बन्द हुँदा माथिको ठेगाना/सारांश बक्स
  // एक फ्रेम ढिलो गएर छोटो समयको लागि ओभरल्याप/जर्क देखिन्थ्यो — ठ्याक्कै
  // "प्यानल तान्दा माथिको ठेगाना बक्स नमिलेर ओभरल्याप हुने" गुनासोको साँचो
  // जड। अब दुवै (प्यानलको आफ्नै आकार + सारांश बक्सको `bottom:`) यही एउटै
  // `AnimationController` बाट, एउटै build/frame मा गणना हुन्छन् — कहिल्यै
  // एक-अर्कोभन्दा फरक हुनै सक्दैन्।
  late final AnimationController _panelCtrl = AnimationController(
    vsync: this,
    value: 0,
  );

  Future<void> _animatePanelTo(double target, {double velocity = 0}) {
    // iOS/Android bottom-sheet जस्तै — critically-damped स्प्रिङ, बाउन्स
    // नगरी सफा/छिटो settle हुने (`_pinLiftCtrl` कै damping 14 चाहिँ त्यो
    // "nail drop" bounce-effect कै लागि जानाजानी कम राखिएको हो, यहाँ
    // प्यानलको लागि उपयुक्त होइन)।
    return _panelCtrl.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 340, damping: 30),
      _panelCtrl.value,
      target,
      velocity,
    ));
  }

  // InDrive-style: ग्राहकको प्रस्तावित मूल्य (अनुमानित भाडाबाट सुरु)।
  int? _offer;
  static const int _priceStep = 50;
  void _setOffer(int v) =>
      setState(() => _offer = v.clamp(_priceStep, 1000000));

  // दायरा filter (किमी) — यसलाई बदल्ने UI हटाइएको भएकाले अब सधैँ यही
  // default (10km) कायम रहन्छ (worker list यही अनुसार फिल्टर हुन्छ)।
  final int _radiusKm = 10;

  // Ride-Hailing (Bike/Car मात्र) — सामान्य सेवा (plumber/electrician) मा
  // एउटै स्थान (काम हुने ठाउँ) भए पुग्छ, तर सवारी सेवामा pickup पछि गन्तव्य
  // (destination) पनि छान्नुपर्छ। यही पुरानै drag-pin मेकानिजम दुई पासमा
  // प्रयोग हुन्छ — पहिलो पास pickup (आजैकै जस्तै व्यवहार), दोस्रो पास
  // destination; अरू सेवाहरूको व्यवहार यसले कहिल्यै छोड्दैन (`_isRide`
  // सधैँ false रहन्छ तिनका लागि)।
  bool get _isRide =>
      widget.serviceType == 'Bike' || widget.serviceType == 'Car';
  bool _pickingDestination = false;
  double? _pickupLat;
  double? _pickupLng;
  String _pickupAddress = '';
  double? _destLat;
  double? _destLng;
  String _destAddress = '';
  // InDrive-शैली "Enter your route" कार्ड — तल्लो "Confirm pickup · Where
  // to?" बटन नथिचेसम्म लुकेको रहन्छ; थिचेपछि मात्र माथि आउँछ। भित्र एकपल्टमा
  // एउटै फिल्ड मात्र सक्रिय (खुला खोज बक्स) हुन्छ — अर्को सानो/compact
  // पंक्तिमा खुम्चिन्छ (`_activeRouteField`: 'from'/'to'/null=दुवै खुम्चिएको)।
  // "To" छानेपछि सिधै टक्राउँदैन — `_pendingDest*` मा पर्खिरहन्छ, प्रयोगकर्ताले
  // "Confirm"/"Done" नथिचेसम्म।
  bool _routeCardOpen = false;
  String? _activeRouteField;
  double? _pendingDestLat;
  double? _pendingDestLng;
  String _pendingDestAddress = '';
  RoadRoute? _rideRoute;
  bool _rideRouteLoading = false;
  // Confirm भइसकेपछि pickup+destination दुवैका native marker यही एउटै
  // custom झन्डा bitmap प्रयोग गर्छन् (Google को default नीलो/हरियो थोप्लो
  // होइन) — त्यो बेला केन्द्रको ठूलो drag-pin overlay पहिल्यै लुकिसकेको
  // हुन्छ, त्यसैले "दोहोरो ठूलो झन्डा" को पुरानो समस्या फेरि आउँदैन।
  BitmapDescriptor? _flagMarkerIcon;
  // Uber/inDrive-शैली — pickup/destination marker माथि सधैँ टाँसिएको "Pickup"/
  // "Drop-off" लेबल-ब्याज (साँचो GPS-बिन्दु + झन्डा सँगै baked भएको एउटै
  // native Marker bitmap — `labeledFlagPin()` हेर्नुहोस्)। `_flagMarkerIcon`
  // माथि नै fallback कायमै — यी async load नभइन्जेलसम्म मात्र प्रयोग हुन्छ।
  BitmapDescriptor? _pickupLabeledIcon;
  Offset? _pickupLabeledAnchor;
  BitmapDescriptor? _destLabeledIcon;
  Offset? _destLabeledAnchor;
  // Pin Drop — काम/pickup स्थान अब सधैँ GPS मै बाँधिएको छैन। झन्डा
  // (यही bitmap, अब plain Flutter `Image.memory` overlay मार्फत) स्क्रिनकै
  // ठ्याक्कै बीचमा स्थिर बस्छ; प्रयोगकर्ताले नक्सा नै pan गरेर मुनिको
  // कुन बिन्दु त्यो झन्डाको मुनि पर्ने भनेर आफैं छान्छ — त्यही बिन्दु नै
  // (`onCameraMove`/`onCameraIdle` ले `_lat`/`_lng` अपडेट गर्ने) साँचो
  // काम/booking स्थान बन्छ। कहिल्यै लड्खडाउँदैन/भाग-भाग देखिँदैन — पिन
  // आफैं कहिल्यै screen-position बदल्दैन, नक्सा मात्र चल्छ।
  Uint8List? _pickupPinBytes;
  // Pin Touch & Lift — प्रयोगकर्ताले नक्सा pan गर्न थालेकै बित्तिकै पिन
  // हल्का माथि उठ्ने (0 = बिश्राम, 1 = उठेको), पान रोकिएपछि spring physics
  // सहित तल "ठोक्किँदै" फर्कने (Uber/inDrive-style "nail drop" feel) —
  // `_buildPickupPinOverlay()` ले यही value पढेर translate+scale गर्छ।
  late final AnimationController _pinLiftCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  // Camera pan हुँदा-हुँदै (`onCameraMove`) हरेक frame मा setState नगरी
  // यहीं थाती राख्ने, pan रोकिएपछि (`onCameraIdle`) मात्र एकैचोटि
  // `_lat`/`_lng` मा लागू गर्ने — नत्र थुप्रै rebuild ले pan नै jank हुन्थ्यो।
  double? _pendingLat;
  double? _pendingLng;
  // प्रयोगकर्ताको साँचो live GPS — अब सिधै `_lat`/`_lng` (booking स्थान)
  // होइन, केवल "मेरो स्थानमा फर्कनुहोस्" बटनका लागि छुट्टै राखिएको। यसले
  // म्यानुअली छानिएको pin लाई कहिल्यै ओभरराइट गर्दैन।
  double? _myGpsLat;
  double? _myGpsLng;

  // Pin Drop — बीचको झन्डाले ठ्याक्कै छोपेको ठाउँको पढ्न मिल्ने ठेगाना,
  // माथि floating card मा (location_picker_page.dart कै उस्तै debounced
  // reverse-geocode pattern)। pan रोकिएपछि (`onCameraIdle`) मात्र एकपटक
  // — हरेक frame मा होइन, नत्र बेकारमा धेरै network call जान्थ्यो।
  String _pinAddress = '';
  bool _loadingPinAddress = false;
  Timer? _addrDebounce;
  // झन्डा tap गर्दा ठेगाना बक्स लुकाउने/देखाउने — झन्डामाथि tap गर्दा लुक्छ,
  // प्रयोगकर्ताले फेरि पिन तानेर नयाँ ठाउँमा "ड्रप" गर्दा (साँचो Nail Drop
  // settle) फेरि देखिन्छ (`onCameraIdle` हेर्नुहोस्)।
  bool _addrCardHidden = false;
  // "Where & for how much?" बटन थिचेपछि खुल्ने खोजी पट्टी (तल्लो प्यानलको
  // ठ्याक्कै माथि) — छानेपछि फेरि बटन आकारमा फर्किन्छ।
  bool _bottomSearchOpen = false;

  /// झन्डाको भिजुअल टुप्पो (pole/flag को टुप्पो, GPS-anchor थोप्लो होइन)
  /// स्क्रिनको तल्लो किनाराबाट कति माथि पर्छ — [_PinAddressCard] लाई
  /// त्यही बिन्दुको ठ्याक्कै माथि टाँस्न। नक्सा/झन्डा कै उही
  /// `top: 118, bottom: 260` padding प्रयोग गर्छ (माथि `_buildPickupPinOverlay`
  /// हेर्नुहोस्)।
  double _pinTipBottomOffset(BuildContext context) {
    const topPad = 118.0;
    const bottomPad = 260.0;
    const displayHeight = 60.0;
    const scale = displayHeight / FlagPinGeometry.displayH;
    final tipAboveCenter = FlagPinGeometry.anchor.dy * scale;
    final h = MediaQuery.of(context).size.height;
    return (h - topPad + bottomPad) / 2 + tipAboveCenter;
  }

  void _scheduleReverseGeocode() {
    _addrDebounce?.cancel();
    _addrDebounce = Timer(const Duration(milliseconds: 400), _reverseGeocodePin);
  }

  Future<void> _reverseGeocodePin() async {
    final lat = _lat, lng = _lng;
    if (mounted) setState(() => _loadingPinAddress = true);
    final addr = await reverseGeocode(lat, lng);
    // पर्खँदा-पर्खँदै pin अरू सर्‍यो भने यो (अब पुरानो भइसकेको) जवाफ लागू
    // नगर्ने — पछिल्लो `_scheduleReverseGeocode()` कै जवाफले मात्र देखिने।
    if (!mounted || _lat != lat || _lng != lng) return;
    setState(() {
      // खाली जवाफले पहिल्यै देखिरहेको (सायद खोजी-नतिजाबाट आएको ठ्याक्कै)
      // ठेगाना नामेटाउने — Nominatim असफल/rate-limit भए पनि प्रयोगकर्ताले
      // पहिल्यै देखेको ठेगाना अचानक खाली नदेखियोस्।
      if (addr.isNotEmpty) _pinAddress = addr;
      _loadingPinAddress = false;
      // Pin ↔ Input Sync — "Enter your route" कार्ड खुला र "From"/"To"
      // सक्रिय (search-चालित होइन, नक्सा तानेरै) हुँदा पिन ड्रप भयो भने
      // पनि त्यही फिल्डको pending मान (input text + "Confirm route" बटनको
      // enablement दुवैले प्रयोग गर्ने) उत्तिकै ताजा हुनुपर्छ — नत्र search
      // बाहेक drag ले कहिल्यै "Confirm route" सक्रिय गर्दैनथ्यो, र "To"
      // बक्सले तानिएको ठाउँ कहिल्यै नदेखाउँथ्यो।
      if (_isRide && _routeCardOpen) {
        if (_activeRouteField == 'to') {
          _pendingDestLat = lat;
          _pendingDestLng = lng;
          if (addr.isNotEmpty) _pendingDestAddress = addr;
        } else if (_activeRouteField == 'from') {
          _pickupLat = lat;
          _pickupLng = lng;
          if (addr.isNotEmpty) _pickupAddress = addr;
        }
      }
    });
  }

  // ── तल्लो सूचीबाट छानिएको worker (नक्सामा कुनै pin छैन — सूचीको कार्डबाटै
  // छनौट हुन्छ) ──
  String? _selId;
  Map<String, dynamic>? _selData;
  double _selKm = 0;
  RoadRoute? _route;
  bool _routeLoading = false;

  // तल्लो orange panel को "peek+chrome" (handle+header +
  // कहिलेकाहीं vehicle-chip-row/trust-banner, + वरपरको Container
  // padding/SafeArea) भाग को उचाइ स्थिर छैन — worker chip row देखिए/नदेखिए
  // अनुसार बढ्छ/घट्छ। _ProviderCard लाई त्यसमाथि सधैं पूरै देखिने गरी राख्न
  // (अघि hardcoded `bottom: 270` ले chip row देखिँदा panel यो भन्दा अग्लो
  // भएर card को तल्लो भाग ढाकिदिन्थ्यो) यो भाग को साँचो rendered height
  // नाप्ने — GlobalKey बाट। यो `key` सिधै पूरै panel (`ClipRRect`, peek +
  // हाल जति खुलेको छ त्यो animated भाग दुवै सामेल) माथि छ, त्यसैले तलको
  // measurement मा हाल कति खुलेको छ (`_panelExpandedHeight * _panelCtrl.value`)
  // घटाएर मात्र साँचो "बन्द छँदाको" baseline निकालिन्छ — नत्र सोही अंश
  // दोहोरिएर (एकपटक यहाँ raw measurement मार्फत, अर्कोपटक `_RideSummaryCard`
  // को सूत्रमा छुट्टै थपिँदा) प्यानलभन्दा बढी माथि गलत ठाउँमा card पुग्थ्यो।
  // यो भाग `_panelCtrl` ले जति नै बदलिए पनि यो baseline आफैं स्थिर रहन्छ
  // (worker सूची/मोड बदलिँदा मात्र फेरिन्छ) — त्यसैले सामान्य post-frame
  // measurement (एक फ्रेम ढिलो भए पनि हानि छैन, किनभने drag/animation
  // बेला यो बदलिँदै बदलिँदैन) पर्याप्त छ।
  final _panelKey = GlobalKey();
  double _panelHeight = 96;

  // प्यानलको खुल्ने/बन्द हुने (animated) भागको साँचो प्राकृतिक उचाइ — worker
  // chips + भाडा stepper + CTA + आदि। `_panelCtrl` ले जे मान भए पनि (0..1,
  // drag/spring जुनसुकै बेला) यो भाग सधैँ पूरै (natural size मै) layout
  // हुन्छ (`Align(heightFactor:)` ले केवल कति देखिने भन्ने मात्र नियन्त्रण
  // गर्छ, child को आफ्नै layout कहिल्यै साँघुर्‍याउँदैन) — त्यसैले यो उचाइ
  // drag/animation-बेला कहिल्यै बदलिँदैन (worker सूची/मोड बदलिँदा मात्र
  // बदलिन्छ), र `_RideSummaryCard`/`_ProviderCard` को `bottom:` गणना गर्न
  // (`_panelHeight + _panelExpandedHeight * _panelCtrl.value`) कुनै lag
  // बिना प्रयोग गर्न मिल्छ — दुवै एउटै build/frame मै एउटै source बाट आउने
  // भएकोले सधैँ ठ्याक्कै synchronized।
  final _expandedKey = GlobalKey();
  double _panelExpandedHeight = 300;

  void _measurePanel() {
    final expandedBox =
        _expandedKey.currentContext?.findRenderObject() as RenderBox?;
    final eh = expandedBox?.size.height;
    if (eh != null && eh > 0 && (eh - _panelExpandedHeight).abs() > 0.5) {
      setState(() => _panelExpandedHeight = eh);
    }
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    final rawTotal = box?.size.height;
    if (rawTotal != null && rawTotal > 0) {
      final visibleExtra =
          _panelExpandedHeight * _panelCtrl.value.clamp(0.0, 1.0);
      final peekBaseline = rawTotal - visibleExtra;
      if ((peekBaseline - _panelHeight).abs() > 0.5) {
        setState(() => _panelHeight = peekBaseline);
      }
    }
  }

  Future<void> _selectWorker(
      String id, Map<String, dynamic> data, double km, LatLng pos) async {
    setState(() {
      _selId = id;
      _selData = data;
      _selKm = km;
      _route = null;
      _routeLoading = true;
    });
    final route = await fetchRoadRoute(LatLng(_lat, _lng), pos);
    if (!mounted || _selId != id) return; // बीचमा अर्को worker छानिए बेवास्ता
    setState(() {
      _route = route;
      _routeLoading = false;
    });
  }

  void _clearSelection() => setState(() {
        _selId = null;
        _selData = null;
        _route = null;
        _routeLoading = false;
      });

  @override
  void initState() {
    super.initState();
    final seedLat = widget.initialLat;
    final seedLng = widget.initialLng;
    if (seedLat != null && seedLng != null) {
      _originLat = seedLat;
      _originLng = seedLng;
      _lat = seedLat;
      _lng = seedLng;
    }
    _initLocation();
    // सुरुमा जुनसुकै भए पनि (seed/fallback/GPS) — कम्तिमा एकपटक ठेगाना
    // अवश्य देखियोस्, GPS सफल भए पछि मात्र होइन।
    _reverseGeocodePin();
    destinationFlagPinBytes().then((b) {
      if (mounted) setState(() => _pickupPinBytes = b);
    });
    if (_isRide) {
      destinationFlagPin().then((bd) {
        if (mounted) setState(() => _flagMarkerIcon = bd);
      });
      labeledFlagPin(S.pickupLabel, AppColors.kmTeal).then((r) {
        if (mounted) {
          setState(() {
            _pickupLabeledIcon = r.icon;
            _pickupLabeledAnchor = r.anchorFraction;
          });
        }
      });
      labeledFlagPin(S.destinationLabel, AppColors.kmOrange).then((r) {
        if (mounted) {
          setState(() {
            _destLabeledIcon = r.icon;
            _destLabeledAnchor = r.anchorFraction;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _addrDebounce?.cancel();
    _pinLiftCtrl.dispose();
    _panelCtrl.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _useFallback();
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _originLat = p.latitude;
        _originLng = p.longitude;
        _lat = p.latitude;
        _lng = p.longitude;
        _myGpsLat = p.latitude;
        _myGpsLng = p.longitude;
      });
      _recentre();
      _startTracking();
      _reverseGeocodePin();
    } catch (_) {
      _useFallback();
    }
  }

  /// GPS असफल भयो — तर होमपेजबाटै राम्रो सिड स्थान पहिल्यै आइसकेको भए
  /// त्यसैलाई कायम राख्ने (generic Kathmandu fallback ले नबदल्ने); सिड
  /// नै नभएको बेला मात्र fallback केन्द्रमा जाने।
  void _useFallback() {
    if (!mounted || widget.initialLat != null) return;
    setState(() {
      _originLat = fallbackLat;
      _originLng = fallbackLng;
      _lat = fallbackLat;
      _lng = fallbackLng;
    });
    _recentre();
  }

  /// Pin Drop — live GPS अब सिधै booking स्थान (`_lat`/`_lng`) लाई कहिल्यै
  /// ओभरराइट गर्दैन (त्यसो भए प्रयोगकर्ताले म्यानुअली छानेको pin स्थान
  /// हरेक ~25m हिँडाइमा फेरि आफ्नो हालको स्थानमा फर्किन्थ्यो!)। केवल
  /// `_myGpsLat`/`_myGpsLng` ताजा राख्ने — "मेरो स्थानमा फर्कनुहोस्" बटनले
  /// मात्र प्रयोग गर्छ।
  void _startTracking() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 25,
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() {
        _myGpsLat = p.latitude;
        _myGpsLng = p.longitude;
      });
    }, onError: (_) {});
  }

  Future<void> _recentre() async {
    if (_map == null) return;
    _programmaticCameraMove = true;
    await _map!
        .animateCamera(CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13.5));
    _programmaticCameraMove = false;
    _centeredOnce = true;
  }

  /// "मेरो स्थानमा फर्कनुहोस्" बटन — pin drag गरेर टाढा पुगेको भए साँचो
  /// हालको GPS स्थानमा फेरि फर्कन। GPS अझै नआएको भए (दुर्लभ) पहिले नै
  /// पर्खेर लिने कोसिस गर्छ।
  Future<void> _recenterToMyLocation() async {
    var lat = _myGpsLat;
    var lng = _myGpsLng;
    if (lat == null || lng == null) {
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 8));
        lat = p.latitude;
        lng = p.longitude;
        if (mounted) {
          setState(() {
            _myGpsLat = lat;
            _myGpsLng = lng;
          });
        }
      } catch (_) {
        return;
      }
    }
    if (_map == null) return;
    _programmaticCameraMove = true;
    await _map!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
    _programmaticCameraMove = false;
    if (mounted) {
      setState(() {
        _lat = lat!;
        _lng = lng!;
      });
    }
    // यो programmatic move हो (`onCameraIdle` ले auto-geocode गर्दैन,
    // माथिको note हेर्नुहोस्) — त्यसैले यहीं स्पष्ट रूपमा ताजा गर्ने।
    _reverseGeocodePin();
  }

  // ── Ride-Hailing (Bike/Car मात्र) — pickup → destination दुई-चरण ────────────

  /// पहिलो "Confirm pickup" थिच्दा — हालको pin स्थान pickup को रूपमा freeze,
  /// अनि उही pin-drop UI लाई गन्तव्य छान्ने दोस्रो पासमा लैजाने।
  void _confirmPickupAndStartDestination() {
    HapticFeedback.mediumImpact();
    setState(() {
      _pickupLat = _lat;
      _pickupLng = _lng;
      _pickupAddress = _pinAddress;
      _pickingDestination = true;
      _routeCardOpen = true;
      _activeRouteField = 'to';
    });
  }

  /// राइड कार्ड फेरि सम्पादन गर्न खोल्ने — pickup/destination जुनसुकै
  /// पंक्तिबाट (`field` = 'from'/'to') आइपुग्न सकिन्छ। हालको destination
  /// (भए) `_pendingDest*` मा सारेर मात्र खाली गरिन्छ — ताकि "To" सक्रिय
  /// हुँदा त्यही पहिलेकै मूल्य pre-filled देखियोस्, प्रयोगकर्ताले नछोई
  /// "Confirm" थिच्दा पनि उही ठाउँ कायमै रहोस्।
  void _openRouteCardForEdit(String field) {
    setState(() {
      _pendingDestLat = _destLat;
      _pendingDestLng = _destLng;
      _pendingDestAddress = _destAddress;
      _destLat = null;
      _destLng = null;
      _destAddress = '';
      _rideRoute = null;
      _pickingDestination = true;
      _routeCardOpen = true;
      _activeRouteField = field;
    });
  }

  /// कार्डभित्रको "Confirm"/"Done" बटन — pickup + pending destination दुवै
  /// भइसकेपछि मात्र देखिने, अनि यहीँबाट साँचो route टक्राउने।
  Future<void> _confirmPendingRoute() async {
    if (_pickupLat == null || _pendingDestLat == null) return;
    // Pickup र Destination कहिल्यै एउटै बिन्दु हुन नहुने।
    final gapKm = haversineKm(
        _pickupLat!, _pickupLng!, _pendingDestLat!, _pendingDestLng!);
    if (gapKm < 0.05) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.destinationTooCloseError)),
      );
      return;
    }
    await _finalizeRoute(
      pLat: _pickupLat!,
      pLng: _pickupLng!,
      pAddr: _pickupAddress,
      dLat: _pendingDestLat!,
      dLng: _pendingDestLng!,
      dAddr: _pendingDestAddress,
    );
    if (mounted) setState(() => _routeCardOpen = false);
  }

  /// "Enter your route" कार्डभित्रको खुम्चिएको (inactive) From/To पंक्ति —
  /// tap गर्दा त्यो फिल्ड सक्रिय (पूरा खोज बक्स) बन्छ, अर्को स्वतः खुम्चिन्छ।
  Widget _compactRouteRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 10.5)),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, size: 15, color: AppColors.kmMuted),
          ],
        ),
      ),
    );
  }

  /// pickup + destination दुवै टक्रिएपछि (drag+confirm भएर वा सिधै search
  /// छानेर — दुवै बाटोले यहीं आइपुग्छन्) — state फिक्स, क्यामेरा दुवै
  /// बिन्दु देखिने गरी fit, अनि साँचो सडक route ल्याउने। यही साझा tail
  /// प्रयोग गरेर दोहोरिनबाट जोगिइएको छ।
  Future<void> _finalizeRoute({
    required double pLat,
    required double pLng,
    required String pAddr,
    required double dLat,
    required double dLng,
    required String dAddr,
  }) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _pickupLat = pLat;
      _pickupLng = pLng;
      _pickupAddress = pAddr;
      _destLat = dLat;
      _destLng = dLng;
      _destAddress = dAddr;
      _pickingDestination = false;
      _rideRouteLoading = true;
      _lat = pLat;
      _lng = pLng;
      // भाडा अनुमान अघिको (गन्तव्य-रहित) दूरीमा अडेको हुनसक्छ — नयाँ साँचो
      // यात्रा-दूरी अनुसार पुनः-गणना हुन दिने।
      _offer = null;
    });
    if (_map != null) {
      _programmaticCameraMove = true;
      final south = pLat < dLat ? pLat : dLat;
      final west = pLng < dLng ? pLng : dLng;
      final north = pLat > dLat ? pLat : dLat;
      final east = pLng > dLng ? pLng : dLng;
      await _map!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(south, west), northeast: LatLng(north, east)),
        72,
      ));
      _programmaticCameraMove = false;
    }
    final route =
        await fetchRoadRoute(LatLng(pLat, pLng), LatLng(dLat, dLng));
    if (!mounted) return;
    setState(() {
      _rideRoute = route;
      _rideRouteLoading = false;
    });
  }

  /// "Confirm destination" थिच्दा (drag-pin बाटो) — हालको pin गन्तव्यको
  /// रूपमा — `_finalizeRoute` कै साझा tail।
  Future<void> _confirmDestination() async {
    final dLat = _lat, dLng = _lng;
    // Pickup र Destination कहिल्यै एउटै बिन्दु हुन नहुने (गन्तव्य खोज्दा
    // नतिजा नभेटिए वा नक्सा नै नचलाई सिधै confirm थिचे, दुवै चुपचाप उही
    // ठाउँमा अड्किरहन्थ्यो — त्यसले route/भाडा अर्थहीन बनाउँथ्यो)।
    final gapKm = haversineKm(_pickupLat!, _pickupLng!, dLat, dLng);
    if (gapKm < 0.05) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.destinationTooCloseError)),
      );
      return;
    }
    await _finalizeRoute(
      pLat: _pickupLat!,
      pLng: _pickupLng!,
      pAddr: _pickupAddress,
      dLat: dLat,
      dLng: dLng,
      dAddr: _pinAddress,
    );
  }

  /// InDrive-शैली — माथिको "From" बक्समा सिधै खोजेर pickup छान्दा। गन्तव्य
  /// पहिल्यै छानिइसकेको भए (route सम्पादन गर्दै) — pickup बदलेर route/भाडा
  /// तुरुन्तै पुनः-गणना; नत्र (अझै pickup-चरणमै) — pin/`_pinAddress` मात्र
  /// त्यहाँ सार्ने (drag गरे जस्तै), "Confirm pickup" अझै उपलब्ध रहन्छ।
  Future<void> _pickSearchedPickup(String label, double lat, double lng) async {
    HapticFeedback.selectionClick();
    if (_destLat != null) {
      final gapKm = haversineKm(lat, lng, _destLat!, _destLng!);
      if (gapKm < 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.destinationTooCloseError)),
        );
        return;
      }
      await _finalizeRoute(
        pLat: lat,
        pLng: lng,
        pAddr: label,
        dLat: _destLat!,
        dLng: _destLng!,
        dAddr: _destAddress,
      );
      return;
    }
    _pinLiftCtrl.stop();
    _pinLiftCtrl.value = 0;
    setState(() {
      _lat = lat;
      _lng = lng;
      _pinAddress = label;
      _loadingPinAddress = false;
      // pickup पहिल्यै "Confirm pickup" थिचेर frozen भइसकेको भए (गन्तव्य
      // छान्दै गर्दा फेरि "From" सच्याएको केस) — त्यो freeze पनि साथसाथै
      // ताजा गर्ने, नत्र यो सम्पादन बेवास्ता हुन्थ्यो।
      if (_pickupLat != null) {
        _pickupLat = lat;
        _pickupLng = lng;
        _pickupAddress = label;
      }
    });
    if (_map != null) {
      _programmaticCameraMove = true;
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));
      _programmaticCameraMove = false;
    }
  }

  /// खोज-नतिजाबाट सिधै गन्तव्य छान्दा — dragging जस्तै गरी `_lat`/`_lng`/
  /// `_pinAddress` अपडेट गर्ने (Confirm destination बटन अझै थिच्नुपर्छ,
  /// यसले pin मात्र त्यहाँ सार्छ)। Ride-Hailing बाहेक (सामान्य सेवाको
  /// "Where & for how much?" search) अझै यही प्रयोग हुन्छ।
  Future<void> _pickSearchedDestination(String label, double lat, double lng) async {
    // पहिले (drag बाट) उठिरहेको/settle हुँदै गरेको पिन भए पनि सफा 0 मा
    // ल्याइदिने — नत्र `onCameraIdle` ले "प्रयोगकर्ताले आफैं pan गर्‍यो"
    // भन्ने ठान्दै यो प्रोग्रामेटिक (search-चालित) move पछि पनि फेरि
    // reverse-geocode तानिदिन्थ्यो, जसले खोजिएकै ठ्याक्कै ठेगाना (जस्तै
    // "szkolna 23") लाई सामान्य/धमिलो वा खाली जवाफले silently ओभरराइट
    // गरिदिन्थ्यो।
    _pinLiftCtrl.stop();
    _pinLiftCtrl.value = 0;
    setState(() {
      _lat = lat;
      _lng = lng;
      _pinAddress = label;
      _loadingPinAddress = false;
    });
    if (_map != null) {
      _programmaticCameraMove = true;
      // एउटै मात्र सफा animated move — पहिले यहाँ `moveCamera` (तुरुन्तै
      // "जम्प") अनि सोही ठाउँमा फेरि `animateCamera` (उही target, बेकारमा
      // दोहोरो call) दुवै एकपछि अर्को गरिँदा भिजुअल हल्का "twitch"/jerk
      // जस्तो देखिन सक्थ्यो। एउटै smooth animation ले नै ठ्याक्कै खोजिएकै
      // बिन्दुमा पुर्‍याउँछ।
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));
      _programmaticCameraMove = false;
    }
  }

  /// "Change" — फेरि गन्तव्य छान्ने पासमा फर्कने (pickup कायमै रहन्छ), कार्ड
  /// "To" सक्रिय अवस्थामा खोलेर।
  void _changeDestination() => _openRouteCardForEdit('to');

  /// Pickup row tap — कार्ड "From" सक्रिय अवस्थामा खोल्ने (destination
  /// पहिल्यै छानिएको भए त्यो pre-filled/pending कायमै रहन्छ)।
  void _editPickup() => _openRouteCardForEdit('from');

  // ── Back Navigation (Ride-Hailing मात्र) — pickup → destination → confirm
  // यी सबै यही एउटै स्क्रिनका internal चरण हुन् (Navigator route होइनन्),
  // त्यसैले system/AppBar back थिच्दा सिधै Home नजाई एक-एक चरण पछाडि
  // फर्काउनुपर्छ (`_hasRideStepToUndo` भएसम्म route कहिल्यै pop हुँदैन)।
  bool get _hasRideStepToUndo =>
      _isRide && (_pickingDestination || _destLat != null);

  void _rideBackStep() {
    if (_destLat != null) {
      // गन्तव्य/भाडा confirm भइसकेको थियो — फेरि गन्तव्य सम्पादन गर्ने
      // अवस्थामा (pickup कायमै)।
      _changeDestination();
    } else if (_pickingDestination) {
      // गन्तव्य छान्दै थियो — pickup-मात्र अवस्थामा फर्कने, कार्ड पनि लुकाउने।
      setState(() {
        _pickingDestination = false;
        _routeCardOpen = false;
      });
    }
  }

  /// online + दायरा भित्रका worker मात्र — nearest-first।
  List<({String id, Map<String, dynamic> data, double km, LatLng pos})>
      _nearbyOnline(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final rows =
        <({String id, Map<String, dynamic> data, double km, LatLng pos})>[];
    for (final d in docs) {
      final data = d.data();
      if (data['isOnline'] == false) continue; // offline लाई हटाउने
      final wp = workerPos(data, d.id, _originLat, _originLng);
      final km = haversineKm(_lat, _lng, wp.lat, wp.lng);
      if (km > _radiusKm) continue;
      rows.add((id: d.id, data: data, km: km, pos: LatLng(wp.lat, wp.lng)));
    }
    rows.sort((a, b) => a.km.compareTo(b.km));
    return rows;
  }

  // worker-अवतार pin हरू (नाम अनुसारको रङको "व्यक्ति" marker) जानाजान
  // हटाइएको — नक्सा सफा राख्ने, अनुरोध सधैँ तल्लो "Post job" प्यानलबाट
  // सबै नजिकका worker लाई broadcast हुने भएकोले map मा व्यक्तिगत pin
  // छान्नुपर्ने आवश्यकता छैन। pickup (आफ्नो) झन्डा अब native `Marker`
  // होइन — Pin Drop pattern (screen-center मा स्थिर Flutter overlay,
  // तल `_buildPickupPinOverlay()` हेर्नुहोस्) — त्यसैले यहाँ कुनै marker
  // बाँकी रहँदैन।
  Set<Marker> _buildMarkers(
      List<({String id, Map<String, dynamic> data, double km, LatLng pos})>
          rows) {
    if (!_isRide) return const {};
    // Ride-Hailing — गन्तव्य छान्दै गर्दा वा confirm भइसकेपछि मात्र pickup
    // बिन्दु static marker को रूपमा (झन्डा अझै drag हुने बित्तिकै screen-
    // center overlay नै हो, यो अलग स्थिर बिन्दु हो)।
    final markers = <Marker>{};
    // गन्तव्य अझै confirm नभई छान्दै गरेको बेला केन्द्रको ठूलो drag-pin
    // overlay कायमै देखिने भएकोले pickup सानो/सामान्य marker मात्र रहन्छ
    // (नत्र दुई ठूलो झन्डा एकैचोटि देखिने पुरानो समस्या फर्कने)। Confirm
    // भइसकेपछि (overlay लुकेको बेला) मात्र दुवै (pickup + destination) ले
    // ठ्याक्कै त्यही custom झन्डा bitmap प्रयोग गर्छन् — Google को default
    // नीलो/हरियो थोप्लोको सट्टा।
    final confirmed = _destLat != null && !_pickingDestination;
    if ((_pickingDestination || _destLat != null) &&
        _pickupLat != null &&
        _pickupLng != null) {
      final labeled = _pickupLabeledIcon;
      markers.add(Marker(
        markerId: const MarkerId('__pickup__'),
        position: LatLng(_pickupLat!, _pickupLng!),
        icon: labeled ??
            (confirmed && _flagMarkerIcon != null
                ? _flagMarkerIcon!
                : BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure)),
        anchor: labeled != null
            ? (_pickupLabeledAnchor ?? FlagPinGeometry.markerAnchorFraction)
            : (confirmed && _flagMarkerIcon != null
                ? FlagPinGeometry.markerAnchorFraction
                : const Offset(0.5, 1.0)),
        zIndexInt: 90,
      ));
    }
    if (_destLat != null && _destLng != null) {
      final labeled = _destLabeledIcon;
      markers.add(Marker(
        markerId: const MarkerId('__destination__'),
        position: LatLng(_destLat!, _destLng!),
        icon: labeled ??
            (confirmed && _flagMarkerIcon != null
                ? _flagMarkerIcon!
                : BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen)),
        anchor: labeled != null
            ? (_destLabeledAnchor ?? FlagPinGeometry.markerAnchorFraction)
            : (confirmed && _flagMarkerIcon != null
                ? FlagPinGeometry.markerAnchorFraction
                : const Offset(0.5, 1.0)),
        zIndexInt: 91,
      ));
    }
    return markers;
  }

  /// Ride-Hailing — pickup→destination बीचको साँचो सडक route (worker
  /// selection कै उही `fetchRoadRoute`/polyline pattern पुनः-प्रयोग)।
  Set<Polyline> _buildRidePolylines() {
    final route = _rideRoute;
    if (route == null) return const {};
    return {
      routePolylineCasing('ride', route),
      routePolyline('ride', route),
    };
  }

  // झन्डाको PNG भित्रको आधार-थोप्लो (साँचो GPS anchor point) झन्डाको
  // दृश्य केन्द्रमा होइन — तल-देब्रेतिर पर्छ (उही `FlagPinGeometry`, native
  // `Marker` हरूले पनि `markerAnchorFraction` मार्फत प्रयोग गर्ने)। यहाँ
  // (plain Flutter overlay भएकोले) त्यही anchor बिन्दु नै Stack को ठ्याक्कै
  // बीचमा पर्ने गरी `Transform.translate` ले सार्छ — नत्र थोप्लो (साँचो
  // "यहीं हो" बिन्दु) केन्द्रबाट पुगेर देखिन्थ्यो।
  Widget _buildPickupPinOverlay() {
    const displayHeight = 60.0;
    const scale = displayHeight / FlagPinGeometry.displayH;
    const renderedWidth = FlagPinGeometry.displayW * scale;
    final anchorPx = Offset(
      FlagPinGeometry.anchor.dx * scale,
      FlagPinGeometry.anchor.dy * scale,
    );
    final offset = Offset(
      renderedWidth / 2 - anchorPx.dx,
      displayHeight / 2 - anchorPx.dy,
    );
    return Transform.translate(
      offset: offset,
      // Pin Touch & Lift — `_pinLiftCtrl.value` (0=बिश्राम, 1=उठेको, spring
      // settle हुँदा क्षणिक रूपमा 0 भन्दा अलिक्ति तल पनि जान सक्छ — त्यही
      // प्राकृतिक overshoot ले तल "ठोक्किएको" सानो bounce feel दिन्छ) ले
      // माथि-तल translate + हल्का scale गर्छ।
      child: AnimatedBuilder(
        animation: _pinLiftCtrl,
        child: Image.memory(_pickupPinBytes!, height: displayHeight),
        builder: (context, child) {
          final t = _pinLiftCtrl.value;
          return Transform.translate(
            offset: Offset(0, -14 * t),
            child: Transform.scale(scale: 1.0 + 0.08 * t, child: child),
          );
        },
      ),
    );
  }

  /// "काम पोस्ट गर्नुहोस्" — Job Confirmation sheet खोल्छ, अनि broadcast गर्छ।
  Future<void> _openPostJob(
      List<({String id, Map<String, dynamic> data, double km, LatLng pos})>
          nearby,
      int estFare) async {
    setState(() => _postSheetOpen = true);
    final result = await showModalBottomSheet<_PostedJob>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _PostJobSheet(
        serviceType: widget.serviceType,
        lat: _lat,
        lng: _lng,
        // माथिको floating address card (`_PinAddressCard`) ले पहिल्यै
        // यही ठाउँको ठेगाना geocode गरिसकेको हुन्छ — यहाँ फेरि छुट्टै
        // (दोहोरो/race हुनसक्ने, कहिलेकाहीं फरक जवाफ दिने) network call
        // नगरी त्यही पुनः-प्रयोग गर्ने, ताकि दुवैतिर ठ्याक्कै उही ठेगाना
        // देखियोस्।
        initialAddress: _isRide ? _pickupAddress : _pinAddress,
        initialBudget: _offer ?? estFare,
        nearbyCount: nearby.length,
        isRide: _isRide,
        destinationAddress: _destAddress,
        destLat: _destLat,
        destLng: _destLng,
      ),
    );
    if (mounted) setState(() => _postSheetOpen = false);
    if (result == null || !mounted) return;
    await _submitJob(result, nearby);
  }

  Future<void> _submitJob(
      _PostedJob job,
      List<({String id, Map<String, dynamic> data, double km, LatLng pos})>
          nearby) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String employerName = user?.displayName ?? user?.email ?? 'Customer';
      // users/{uid}.phone बाट — Auth कै user.phoneNumber होइन, त्यो इमेलबाट
      // दर्ता भएकाको हकमा सधैँ खाली हुन्छ (Call बटनले फोन नम्बर नभेट्ने
      // गुनासोको मूल कारण यही थियो)।
      String employerPhone = user?.phoneNumber ?? '';
      try {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .get();
        final n = (u.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) employerName = n;
        final p = (u.data()?['phone'] ?? '').toString().trim();
        if (p.isNotEmpty) employerPhone = p;
      } catch (_) {}

      final db = FirebaseFirestore.instance;
      // नेटवर्क साँच्चै खराब भएमा पनि प्रयोगकर्ता अनिश्चित कालसम्म spinner
      // हेरेर नअड्कियोस् — बरु छिट्टै स्पष्ट त्रुटि (तलको outer catch) देखेर
      // फेरि प्रयास गर्न सकून्।
      final ref = await db.collection('serviceRequests').add({
        'service': widget.serviceType,
        'broadcast': true,
        'employerUid': user?.uid ?? '',
        'employerName': employerName,
        'employerPhone': employerPhone,
        'workerUid': '',
        'workerName': '',
        'status': 'broadcasting',
        'rejectedBy': <String>[],
        // fixed service address (जहाँ काम हुन्छ) — movement tracking होइन
        'employerLat': job.lat,
        'employerLng': job.lng,
        'address': job.address,
        // job details
        'title': job.title,
        'details': job.description,
        'preferredDate': Timestamp.fromDate(job.date),
        'timeSlot': job.slot,
        'proposedPrice': job.budget,
        // Ride-Hailing (Bike/Car) मात्र — गन्तव्य, driver ले कहाँ पुर्‍याउने
        // हो थाहा पाओस् (job_feed_screen.dart/job_route_screen.dart ले पढ्छन्)।
        if (job.destLat != null && job.destLng != null) ...{
          'isRide': true,
          'destinationLat': job.destLat,
          'destinationLng': job.destLng,
          'destinationAddress': job.destAddress ?? '',
          'autoOffer': job.autoOffer,
        },
        'nearbyCount': nearby.length,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 20));

      // ── real-time radar alert: नजिकका online matching worker लाई notification ──
      final label = job.title.isNotEmpty ? job.title : job.description;
      for (final r in nearby) {
        final wuid = (r.data['uid'] ?? '').toString();
        if (wuid.isEmpty) continue;
        try {
          await db.collection('notifications').add({
            'uid': wuid,
            'title': S.newJobNotifTitle,
            'body':
                '${S.serviceName(widget.serviceType)} · $label · Rs. ${job.budget}',
            'requestId': ref.id,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.requestSent)));
      // Ride-Hailing (Bike/Car) मात्र — `pushReplacement` ले यो स्क्रिन
      // (pickup/destination setup) stack बाटै हटाइदिन्थ्यो, त्यसैले bidding/
      // searching स्क्रिनबाट पछाडि थिच्दा सिधै Home मा पुगिन्थ्यो (destination
      // फेरि छान्ने/भाडा सच्याउने ठाउँ नै हराउँथ्यो)। यहाँ भने साधारण `push`
      // — stack मा यही स्क्रिन कायमै रहन्छ, back ले फेरि यहीं फर्काउँछ।
      // अरू सेवा (plumber/electrician) को व्यवहार यथावत।
      if (_isRide) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RequestTrackingScreen(requestId: ref.id),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RequestTrackingScreen(requestId: ref.id),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // हरेक build पछि तल्लो panel को साँचो उचाइ नाप्ने — फरक भेटिए मात्र
    // setState हुन्छ (_measurePanel भित्रैको guard), त्यसैले loop बस्दैन।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measurePanel();
    });
    return PopScope(
      canPop: !_hasRideStepToUndo,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _rideBackStep();
      },
      child: Scaffold(
      // किबोर्ड खुल्दा तल्लो panel/content हरूले माथिको महत्वपूर्ण
      // कन्टेन्ट (search bar/route card) नछोपोस् भनेर — Flutter को default
      // नै true हो, तर यहाँ स्पष्ट राखिएको ताकि भविष्यमा कसैले नियतवश/
      // अनजानमा false नराखोस्।
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.kmCtaGradient),
        ),
        title: Text(
          '${S.serviceName(widget.serviceType)} — ${S.nearbyTitle}',
          style: const TextStyle(
              color: AppColors.kmText, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      // "Home"/मेरो-स्थान बटन — अब pin drag गरेर टाढा पुगे पनि साँचो हालको
      // GPS स्थानमा फर्काउँछ (पहिले जस्तो स्थिर `_lat`/`_lng` मा मात्र
      // होइन — त्यो त अब म्यानुअली छानिएको बिन्दु नै हो)।
      floatingActionButton: FloatingActionButton.small(
        onPressed: _recenterToMyLocation,
        child: const Icon(Icons.my_location_rounded),
      ),
      // नक्सा/worker list सधैँ तुरुन्तै देखिन्छ (seed भएको वा fallback
      // स्थानबाट) — GPS पर्खेर पूरै पेज खाली spinner देखाइने अघिको ढाँचा
      // हटाइयो; ताजा GPS आएपछि _initLocation() ले चुपचाप स्थान/camera सच्याउँछ।
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('registeredWorkers')
            .where('service', isEqualTo: widget.serviceType)
            .snapshots(),
        builder: (context, snap) {
          final rows = _nearbyOnline(snap.data?.docs ?? []);
          final nearestKm = rows.isEmpty ? null : rows.first.km;
          // Ride-Hailing — भाडा अनुमान pickup→destination दूरीबाट (यात्रा
          // साँच्चै जति टाढा जाने हो त्यसैबाट), अरू सेवाहरूमा जस्तो
          // नजिकैको worker-सम्मको दूरीबाट होइन।
          final rideKm = _rideRoute?.km ??
              (_pickupLat != null && _destLat != null
                  ? haversineKm(_pickupLat!, _pickupLng!, _destLat!, _destLng!)
                  : null);
          final estFare = estimateFare(
              widget.serviceType, (_isRide ? rideKm : null) ?? nearestKm ?? 2.0);
          _offer ??= estFare;

          // प्यानल drag/spring जुनसुकै बेला (`_panelCtrl` कै हरेक tick मा)
          // तल्लो प्यानल आफैं र माथिको `_RideSummaryCard`/`_ProviderCard`/
          // "Where & for how much?" बार — तीनैवटा — एउटै frame मा, एउटै
          // स्रोतबाट फेरि rebuild होऊन् भनेर। यसैले "प्यानल तान्दा माथिको
          // ठेगाना बक्स एक फ्रेम ढिलो गएर ओभरल्याप हुने" समस्या जरैदेखि
          // हट्छ — दुवैको स्थिति गणना गर्ने सूत्र (तल हेर्नुहोस्) कहिल्यै
          // फरक-फरक frame मा मूल्याङ्कन हुँदैन।
          return AnimatedBuilder(
            animation: _panelCtrl,
            builder: (context, _) => Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(_lat, _lng),
                  zoom: 13.5,
                ),
                // Uber/inDrive-style सफा नक्सा — Google का आफ्नै default
                // POI/business marker (नामको सेतो लेबल + रातो थोप्लो, जुन
                // हाम्रो कुनै widget होइन) लुकाउने। home_screen.dart/
                // route_map_view.dart मा पहिल्यै प्रयोग हुने उही साझा style
                // — यहाँ छुटेको रहेछ।
                style: kCleanMapStyle,
                onMapCreated: (c) {
                  _map = c;
                  if (!_centeredOnce) _recentre();
                },
                // निलो थोप्लाको सट्टा हाम्रो custom झन्डा pin।
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                // Confirm sheet खुला हुँदा नक्सा नहल्लियोस्।
                scrollGesturesEnabled: !_postSheetOpen,
                zoomGesturesEnabled: !_postSheetOpen,
                // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर "उल्टो"
                // देखिने बग नआओस्।
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: !_postSheetOpen,
                padding: const EdgeInsets.only(bottom: 260, top: 118),
                markers: _buildMarkers(rows),
                polylines: _isRide ? _buildRidePolylines() : const {},
                // Uber/inDrive जस्तै — प्रयोगकर्ताले आफैं औंलाले नक्सा pan
                // गर्न थालेकै क्षण एकपटक हलुका haptic (छोयो/स्थान बदलिँदै छ
                // भन्ने feel), auto-centre/home-बटन जस्तो हाम्रै कोडले
                // चलाएको (`_programmaticCameraMove`) क्षणमा भने कहिल्यै
                // नबजोस्।
                onCameraMoveStarted: () {
                  final locked = _isRide && _destLat != null && !_pickingDestination;
                  if (!_programmaticCameraMove && !locked) {
                    HapticFeedback.selectionClick();
                    _pinLiftCtrl.forward();
                    // InDrive-शैली — पिन उठ्नेबित्तिकै (drag सुरु हुनेबित्तिकै)
                    // माथिको ठेगाना बक्स तुरुन्तै लुक्छ; पिन फेरि "ड्रप" भएपछि
                    // (तल `onCameraIdle`) मात्र नयाँ ठेगानासहित फर्किन्छ।
                    if (!_addrCardHidden) {
                      setState(() => _addrCardHidden = true);
                    }
                  }
                },
                // Pin Drop — pan गर्दा-गर्दै हरेक frame मा थाती राख्ने
                // (सस्तो), pan रोकिएपछि मात्र एकैचोटि साँचो booking
                // स्थानमा लागू (`onCameraIdle`)।
                onCameraMove: (pos) {
                  _pendingLat = pos.target.latitude;
                  _pendingLng = pos.target.longitude;
                },
                onCameraIdle: () {
                  final la = _pendingLat;
                  final ln = _pendingLng;
                  if (la == null || ln == null) return;
                  _pendingLat = null;
                  _pendingLng = null;
                  // Ride-Hailing — गन्तव्य पहिल्यै confirm भइसकेपछि pin
                  // freeze हुनुपर्छ, नत्र route हेर्दा-हेर्दै मात्रै map pan
                  // गर्दा pickup नै (`_lat`/`_lng`, nearby-driver खोजको
                  // आधार) चुपचाप बदलिन्थ्यो।
                  if (_isRide && _destLat != null && !_pickingDestination) {
                    return;
                  }
                  if (mounted) {
                    setState(() {
                      _lat = la;
                      _lng = ln;
                    });
                  }
                  // Pin बसेको नयाँ ठाउँको ठेगाना (माथिको floating card) पनि
                  // ताजा — तर प्रयोगकर्ताले आफैं pan गरेको बेला मात्र
                  // (`_pinLiftCtrl.value > 0`, नीचैको "Nail Drop" कै उही
                  // भरपर्दो जाँच — `_programmaticCameraMove` बाट होइन,
                  // किनभने त्यो flag reset हुने समय र यो `onCameraIdle`
                  // फायर हुने समयबीच race हुनसक्छ)। प्रोग्रामेटिक move
                  // (_recentre/_recenterToMyLocation/initState) हरूले
                  // आफैं छुट्टै explicit geocode गर्छन् — यहाँ दोहोरिनु
                  // पर्दैन। पहिले यहाँ सधैँ चल्थ्यो, त्यसैले सुरुमै (initState
                  // + GPS-resolve + यही onCameraIdle) एउटै ठाउँका लागि
                  // लगातार ३ वटासम्म geocode request जान्थ्यो — Nominatim
                  // (free tier) ले rate-limit गरेर बीचबीचमा खाली जवाफ
                  // दिन्थ्यो, जुन नै "ठेगाना कार्ड सधैँ 'Move the map...'
                  // मै अड्किने" गुनासोको मूल कारण थियो।
                  if (_pinLiftCtrl.value > 0) {
                    // drag सुरु हुँदा लुकाइएको ठेगाना बक्स — पिन नयाँ ठाउँमा
                    // "ड्रप" (settle) हुनेबित्तिकै फेरि देखियोस् (तलको
                    // `_scheduleReverseGeocode()` ले नयाँ ठेगाना ताजा गर्छ,
                    // बक्स आफैं `loading` अवस्थामै तुरुन्तै फर्कने भएकोले
                    // प्रयोगकर्ताले स्पिनर देख्छन्, कहिल्यै पुरानो ठेगाना
                    // होइन)।
                    if (mounted && _addrCardHidden) {
                      setState(() => _addrCardHidden = false);
                    }
                    _scheduleReverseGeocode();
                  }
                  // "Nail Drop" — पिन साँच्चै उठिसकेको भए मात्र (प्रयोगकर्ताले
                  // आफैं pan गरेको — प्रोग्रामेटिक move मा `_pinLiftCtrl`
                  // कहिल्यै उठ्दैन, त्यसैले यहाँ छुट्टै programmatic-guard
                  // नचाहिने) spring physics सहित तल फर्काउने; "ठोक्किने"
                  // (settle भइसकेको) क्षणमै मात्र कडा haptic, उठाउँदा-सारि
                  // होइन।
                  if (_pinLiftCtrl.value > 0) {
                    _pinLiftCtrl
                        .animateWith(SpringSimulation(
                          const SpringDescription(
                              mass: 1, stiffness: 500, damping: 14),
                          _pinLiftCtrl.value,
                          0,
                          0,
                        ))
                        .whenComplete(() {
                      if (mounted) HapticFeedback.heavyImpact();
                    });
                  }
                },
              ),

              // ── Pin Drop — झन्डा स्क्रिनकै ठ्याक्कै बीचमा स्थिर (नक्सा
              // कै त्यही padding प्रयोग गरेर, camera target सँग ठ्याक्कै
              // मिल्ने गरी) — नक्सा नै pan भएर मुनि सर्छ, यो कहिल्यै हल्दैन।
              // InDrive-शैली — झन्डामा tap गरेर होइन, नक्सा नै touch/drag
              // गर्न थालेकै बित्तिकै (`onCameraMoveStarted`) माथिको ठेगाना
              // बक्स लुक्छ, पिन "ड्रप" भएपछि (`onCameraIdle`) फेरि देखिन्छ
              // — त्यसैले झन्डा आफैं फेरि पास-थ्रु (IgnorePointer) मात्र।
              if (_pickupPinBytes != null &&
                  !(_isRide && _destLat != null && !_pickingDestination))
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 260, top: 118),
                    child: Center(child: _buildPickupPinOverlay()),
                  ),
                ),

              // ── पिनको ठेगाना कार्ड — झन्डाको भिजुअल टुप्पो (tip) को
              // ठ्याक्कै माथि, `bottom:` लाई pixel-सटीक गणना गरेर (Column
              // भित्र राखेर होइन — त्यसो गरे झन्डा आफैं साँचो GPS/camera
              // target बिन्दुबाट तलतिर सर्ने बग आउँथ्यो, किनभने Column ले
              // दुवै (बक्स + झन्डा) लाई सँगै केन्द्रित गर्थ्यो)।
              if (_selData == null &&
                  !_addrCardHidden &&
                  !(_isRide && _destLat != null && !_pickingDestination))
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: _pinTipBottomOffset(context) + 8,
                  child: Center(
                    child: _PinAddressCard(
                      address: _pinAddress,
                      loading: _loadingPinAddress,
                      hint: _isRide && _pickingDestination
                          ? S.whereToHint
                          : S.moveMapHint,
                      onOpenProviders: () => _animatePanelTo(1),
                    ),
                  ),
                ),

              // ── "Where & for how much?" — तल्लो "N providers nearby"
              // प्यानलको ठ्याक्कै माथि, खोजेर छिटो अर्को ठाउँमा जाने बटन
              // (Ride-Hailing बाहेक — त्यहाँ आफ्नै destination search
              // बटन/पट्टी पहिल्यै छ)।
              if (!_isRide && _selData == null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: _panelHeight + _panelExpandedHeight * _panelCtrl.value + 12,
                  child: _bottomSearchOpen
                      ? _DestinationSearchBar(
                          key: const ValueKey('browseSearchBar'),
                          biasLat: _lat,
                          biasLng: _lng,
                          onPicked: (label, lat, lng) {
                            _pickSearchedDestination(label, lat, lng);
                            setState(() => _bottomSearchOpen = false);
                          },
                        )
                      : _WhereAndHowMuchButton(
                          onTap: () =>
                              setState(() => _bottomSearchOpen = true),
                        ),
                ),

              // ── Ride-Hailing — गन्तव्य confirm भइसकेपछि pickup→destination
              // सारांश (दुई कार्डको सट्टा एउटै सानो पट्टी, माथिको live pin
              // कार्ड यहाँ hidden भइसकेको हुन्छ) — फेरि छान्ने ("Change")
              // लिंक सहित।
              if (_isRide && _destLat != null && !_pickingDestination && _selData == null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: _panelHeight + _panelExpandedHeight * _panelCtrl.value + 12,
                  child: _RideSummaryCard(
                    pickupAddress: _pickupAddress,
                    destAddress: _destAddress,
                    routeLoading: _rideRouteLoading,
                    onEditPickup: _editPickup,
                    onChangeDestination: _changeDestination,
                  ),
                ),

              // ── छानिएको worker को details card — सूचीबाट छानेपछि देखिने ──
              if (_selData != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: _panelHeight + _panelExpandedHeight * _panelCtrl.value + 12,
                  child: _ProviderCard(
                    data: _selData!,
                    workerId: _selId!,
                    distanceKm: _selKm,
                    serviceType: widget.serviceType,
                    route: _route,
                    routeLoading: _routeLoading,
                    employerLat: _lat,
                    employerLng: _lng,
                    onClose: _clearSelection,
                  ),
                ),

              // ── bottom request panel ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  key: _panelKey,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.kmSurface.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.lg)),
                    border: Border(
                      top: BorderSide(color: AppColors.kmGlassBorder),
                    ),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 20,
                          offset: Offset(0, -4)),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── drag handle + header — tap वा माथि/तल स्वाइप
                        // गरेर प्यानल पूरा खोल्ने/बन्द गर्ने। बन्द छँदा यही
                        // एउटा row मात्र देखिन्छ (peek), माथि स्वाइप गरेपछि
                        // मात्र भाडा/Post job/worker list पूरा देखिने।
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              _animatePanelTo(_panelCtrl.value > 0.5 ? 0 : 1),
                          // तान्दा हरेक फ्रेम औंलासँगै सिधै (कुनै setState/
                          // measurement-lag बिना, `AnimationController.value`
                          // सेट गर्दा आफैं listener हरूलाई notify गर्छ) —
                          // पहिले यहाँ `onVerticalDragUpdate` नै थिएन (केवल
                          // `onVerticalDragEnd` को velocity हेरेर खुला/बन्द
                          // दुई अवस्थामध्ये एक छान्ने मात्र), त्यसैले प्यानल
                          // औंलासँगै "तानिँदै" कहिल्यै देखिँदैनथ्यो — छोड्नेबित्तिकै
                          // मात्र एकैचोटि (220ms) जम्प हुन्थ्यो।
                          onVerticalDragStart: (_) => _panelCtrl.stop(),
                          onVerticalDragUpdate: (details) {
                            final range =
                                _panelExpandedHeight <= 0 ? 300.0 : _panelExpandedHeight;
                            _panelCtrl.value =
                                (_panelCtrl.value - details.delta.dy / range)
                                    .clamp(0.0, 1.0);
                          },
                          onVerticalDragEnd: (details) {
                            final range =
                                _panelExpandedHeight <= 0 ? 300.0 : _panelExpandedHeight;
                            // px/s लाई हाम्रै 0..1 scale मा — SpringSimulation
                            // लाई सुरुवाती वेगको रूपमा चाहिन्छ।
                            final velocity = -(details.primaryVelocity ?? 0) / range;
                            // छोटो/ढिलो drag भए — अहिले कति पुगिसक्यो सोही
                            // अनुसार नजिकैको छेउ; तर छिटो (निर्णायक) फ्लिक
                            // भए — त्यही बेलाको स्थिति जे भए पनि फ्लिकको
                            // दिशा नै जित्छ (सामान्य bottom-sheet UX)।
                            final target = velocity.abs() > 1.2
                                ? (velocity > 0 ? 1.0 : 0.0)
                                : (_panelCtrl.value > 0.5 ? 1.0 : 0.0);
                            _animatePanelTo(target, velocity: velocity);
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Row(
                                children: [
                                  Icon(serviceIconFor(widget.serviceType),
                                      color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${rows.length} ${S.serviceName(widget.serviceType)} ${S.providersNearby}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Icon(
                                    _panelCtrl.value > 0.5
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.keyboard_arrow_up_rounded,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                              // ── InDrive-style — सवारी छान्ने chip पट्टी +
                              // भरपर्दो ड्राइभर banner, प्यानल खुला/बन्द
                              // जुनसुकै अवस्थामा पनि सधैँ देखिने (collapsible
                              // AnimatedSize भन्दा बाहिर) — गन्तव्य confirm
                              // नभएसम्म मात्र।
                              if (_isRide && _destLat == null) ...[
                                const SizedBox(height: 10),
                                _VehicleChipRow(
                                  current: widget.serviceType,
                                  initialLat: _originLat,
                                  initialLng: _originLng,
                                ),
                                const SizedBox(height: 8),
                                // दायाँतिर थप margin — screen को तल्लो-दायाँ
                                // कुनामा सधैँ तैरिरहने Scaffold FAB (मेरो
                                // स्थान बटन) मुनि पर्ने/ओभरल्याप हुनबाट जोगाउन।
                                const Padding(
                                  padding: EdgeInsets.only(right: 52),
                                  child: _TrustBanner(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // `AnimatedSize` (implicit-duration, केवल दुई
                        // अवस्था — पूरा/खाली — बीच toggle) कै सट्टा —
                        // `Align(heightFactor:)`: यसको child (तल
                        // `key: _expandedKey`) सधैँ (जुनसुकै `_panelCtrl.value`
                        // मा पनि) पूरै/natural size मै layout हुन्छ, केवल
                        // parent ले कति देखाउने भन्ने मात्र `heightFactor`
                        // ले तय गर्छ — त्यसैले drag/spring जुनसुकै फ्रेममा
                        // यो सधैँ ठ्याक्कै `_panelCtrl.value` अनुरूप नै
                        // देखिन्छ (कुनै छुट्टै 220ms animation चलिरहनु
                        // पर्दैन, माथिकै AnimatedBuilder ले सिधै रिबिल्ड
                        // गर्छ)। `ClipRect` ले heightFactor < 1 हुँदा
                        // तल्लो भाग नदेखियोस् भनेर काट्छ।
                        ClipRect(
                          child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: _panelCtrl.value.clamp(0.0, 1.0),
                          child: Column(
                                  key: _expandedKey,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                        // ── Ride-Hailing — गन्तव्य अझै छानिएको छैन भने,
                        // सामान्य worker-सूची/भाडा प्यानलको सट्टा pickup/
                        // destination confirm गर्ने दुई-चरण CTA मात्र ──
                        if (_isRide && _destLat == null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                    _pickingDestination
                                        ? Icons.flag_rounded
                                        : Icons.my_location_rounded,
                                    color: Colors.white,
                                    size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    // खाली भएमा मात्र hint — नत्र खोजी/drag
                                    // बाट पहिल्यै छानिएको ठ्याक्कै ठेगाना
                                    // यहाँ (Confirm बटनको ठ्याक्कै माथि) पनि
                                    // देखियोस्, ताकि प्रयोगकर्ताले के
                                    // confirm गर्दैछन् भन्ने प्रस्ट देखोस्।
                                    _pinAddress.isEmpty
                                        ? (_pickingDestination
                                            ? S.whereToHint
                                            : S.moveMapHint)
                                        : _pinAddress,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          KmCtaButton(
                            onPressed: _pickingDestination
                                ? _confirmDestination
                                : _confirmPickupAndStartDestination,
                            icon: _pickingDestination
                                ? Icons.flag_rounded
                                : Icons.navigate_next_rounded,
                            label: _pickingDestination
                                ? S.confirmDestinationCta
                                : S.confirmPickupCta,
                          ),
                        ] else ...[
                        // ── तल्लो horizontal सूची — नक्सामा pin नभई यहींबाट
                        // कुनै एक worker छानेर details card खोल्ने ──
                        if (rows.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 86,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final selected = r.id == _selId;
                                final name = (r.data['name'] ?? '—').toString();
                                return _WorkerChip(
                                  key: ValueKey(r.id),
                                  uid: r.id,
                                  name: name,
                                  distanceKm: r.km,
                                  serviceType: widget.serviceType,
                                  selected: selected,
                                  onTap: () => selected
                                      ? _clearSelection()
                                      : _selectWorker(
                                          r.id, r.data, r.km, r.pos),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        // ── InDrive-style: अनुमानित भाडा + ग्राहकको प्रस्ताव ──
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.payments_rounded,
                                      color: Colors.white70, size: 16),
                                  const SizedBox(width: 8),
                                  Text(S.estimatedFare,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5)),
                                  const Spacer(),
                                  Text('Rs. $estFare',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(S.yourOfferPrice,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _StepBtn(
                                      icon: Icons.remove_rounded,
                                      onTap: () => _setOffer(
                                          (_offer ?? estFare) - _priceStep)),
                                  const SizedBox(width: 20),
                                  Column(
                                    children: [
                                      const Text('Rs.',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11)),
                                      Text('${_offer ?? estFare}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  const SizedBox(width: 20),
                                  _StepBtn(
                                      icon: Icons.add_rounded,
                                      onTap: () => _setOffer(
                                          (_offer ?? estFare) + _priceStep)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        KmCtaButton(
                          onPressed: _sending
                              ? null
                              : () => _openPostJob(rows, estFare),
                          loading: _sending,
                          icon: _isRide
                              ? Icons.local_taxi_rounded
                              : Icons.post_add_rounded,
                          label:
                              '${_isRide ? S.findOffer : S.postJob}  ·  Rs. ${_offer ?? estFare}',
                        ),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(S.noWorkersOnlineNote,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ),
                        ],
                                  ],
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                  ),
                ),
              ),

              // ── Ride-Hailing — "Enter your route" कार्ड (InDrive-style) —
              // तल्लो "Confirm pickup · Where to?" नथिचेसम्म पूर्ण रूपमा
              // लुकेको रहन्छ (`_routeCardOpen`)। भित्र एकपल्टमा एउटै फिल्ड
              // मात्र सक्रिय (पूरा खोज बक्स) — "From" tap गर्दा "To" सानो
              // सारांश-पंक्तिमा खुम्चिन्छ, र उल्टो। "To" छानेपछि सिधै
              // टक्राउँदैन — तल्लो "Confirm route" बटन थिचेपछि मात्र।
              // Stack को सबैभन्दा पछिल्लो (topmost z-order) child — तल्लो
              // "N providers nearby" panel (माथि नै) ले यसलाई कहिल्यै ढाक्न
              // नपाओस् भनेर जानाजानी अन्त्यमा राखिएको (पहिले सुरुतिर थियो,
              // panel त्यसमाथि नै चित्रित हुन्थ्यो — किबोर्ड खुल्दा/panel
              // तानिँदा "To" फिल्ड लुक्ने बग यही थियो, कार्डको उचाइले
              // कहिल्यै फरक पारेन)।
              if (_isRide && _destLat == null && _routeCardOpen)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 6,
                  left: 12,
                  right: 12,
                  // कार्डको तल्लो सीमा किबोर्ड (`viewInsets.bottom`) को
                  // ठ्याक्कै माथि — सामग्री लामो भए भित्रै scroll हुन्छ।
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
                      decoration: BoxDecoration(
                        color: AppColors.kmVoid2.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 6)),
                        ],
                      ),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(S.enterRouteTitle,
                                  style: const TextStyle(
                                      color: AppColors.kmText,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () =>
                                  setState(() => _routeCardOpen = false),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded,
                                    color: AppColors.kmMuted, size: 20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // ── "From" — सक्रिय भए पूरा खोज बक्स, नत्र सानो
                        // सारांश-पंक्ति (tap गर्दा सक्रिय बन्छ) ──
                        if (_activeRouteField == 'from')
                          _DestinationSearchBar(
                            key: const ValueKey('ridePickupSearchBar'),
                            biasLat: _lat,
                            biasLng: _lng,
                            fieldLabel: S.fromLabel,
                            hintText: S.moveMapHint,
                            initialText: _pickupLat != null
                                ? _pickupAddress
                                : _pinAddress,
                            showLiveLocationButton: true,
                            onPicked: (label, lat, lng) {
                              _pickSearchedPickup(label, lat, lng);
                              setState(() => _activeRouteField =
                                  _pendingDestLat == null ? 'to' : null);
                            },
                          )
                        else
                          _compactRouteRow(
                            icon: Icons.trip_origin_rounded,
                            iconColor: AppColors.kmTeal,
                            label: S.fromLabel,
                            value: _pickupLat != null
                                ? _pickupAddress
                                : (_pinAddress.isEmpty
                                    ? S.moveMapHint
                                    : _pinAddress),
                            onTap: () =>
                                setState(() => _activeRouteField = 'from'),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Divider(height: 1, color: AppColors.kmGlassBorder),
                        ),
                        // ── "To" — सक्रिय भए पूरा खोज बक्स, नत्र सानो
                        // सारांश-पंक्ति ──
                        if (_activeRouteField == 'to')
                          _DestinationSearchBar(
                            key: const ValueKey('rideDestinationSearchBar'),
                            biasLat: _pickupLat ?? _lat,
                            biasLng: _pickupLng ?? _lng,
                            fieldLabel: S.toLabel,
                            hintText: S.whereToHint,
                            initialText: _pendingDestAddress,
                            showLiveLocationButton: true,
                            onPicked: (label, lat, lng) {
                              setState(() {
                                _pendingDestLat = lat;
                                _pendingDestLng = lng;
                                _pendingDestAddress = label;
                                _activeRouteField = null;
                              });
                            },
                          )
                        else
                          _compactRouteRow(
                            icon: Icons.flag_rounded,
                            iconColor: AppColors.kmOrange,
                            label: S.toLabel,
                            value: _pendingDestAddress.isEmpty
                                ? S.whereToHint
                                : _pendingDestAddress,
                            onTap: () =>
                                setState(() => _activeRouteField = 'to'),
                          ),
                        // ── "Confirm route" — दुवै (pickup + pending
                        // destination) भइसकेपछि, कुनै फिल्ड सक्रिय नहुँदा ──
                        if (_activeRouteField == null &&
                            _pickupLat != null &&
                            _pendingDestLat != null) ...[
                          const SizedBox(height: 10),
                          KmCtaButton(
                            label: S.confirmRouteCta,
                            icon: Icons.check_rounded,
                            onPressed: _confirmPendingRoute,
                          ),
                        ],
                      ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          );
        },
      ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, color: AppColors.kmText, size: 20),
      ),
    );
  }
}

// ── तल्लो horizontal सूचीको एउटा worker कार्ड — नक्सामा कुनै pin नभई
// यहींबाट tap गरेर details card खोल्ने/बन्द गर्ने ──
class _WorkerChip extends StatelessWidget {
  final String uid;
  final String name;
  final double distanceKm;
  final String serviceType;
  final bool selected;
  final VoidCallback onTap;
  const _WorkerChip({
    super.key,
    required this.uid,
    required this.name,
    required this.distanceKm,
    required this.serviceType,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = serviceMarkerColor(serviceType);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: selected
                  ? AppColors.kmText
                  : Colors.white.withValues(alpha: 0.35),
              width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkerAvatar(
              uid: uid,
              size: 32,
              backgroundColor: color.withValues(alpha: 0.18),
              iconColor: color,
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected ? AppColors.kmOrange : AppColors.kmText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              S.distanceLabel(distanceKm),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected
                      ? AppColors.kmOrange.withValues(alpha: 0.7)
                      : AppColors.kmMuted,
                  fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── दायरा filter bar (map माथि) ──────────────────────────────────────────────
/// Pin Drop — बीचको झन्डाले ठ्याक्कै छोपेको ठाउँको ठेगाना देखाउने floating
/// card (location_picker_page.dart कै उस्तै भाषा) — प्रयोगकर्ताले नक्सा
/// pan गर्दा कुन ठाउँ छानिँदै छ भनेर स्पष्ट देखियोस्।
class _PinAddressCard extends StatelessWidget {
  final String address;
  final bool loading;
  final String? hint;
  // झन्डाको ठ्याक्कै माथि tap गर्दा देखिने बक्स — भित्रको यो ">" बटनले
  // तल्लो "N providers nearby" प्यानललाई एकैचोटि पूरा (expanded) अवस्थामा
  // खोल्छ।
  final VoidCallback onOpenProviders;
  const _PinAddressCard({
    required this.address,
    required this.loading,
    required this.onOpenProviders,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    // सधैँ सानो/छोटो (compact) रहोस् — पूरै स्क्रिन-चौडाइ नओगटोस्, त्यसैले
    // maxWidth कडाइका साथ सीमित; ठेगाना लामो भए एक लाइनमा नअटाई २
    // लाइनसम्म wrap हुन्छ (truncate होइन), अझ बढी भए मात्र ellipsis।
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 168),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 5, 6),
        decoration: BoxDecoration(
          // तल्लो प्यानलसँगै मिल्ने गाढा glass surface।
          color: AppColors.kmVoid2.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                loading
                    ? S.fetchingAddress
                    : (address.isEmpty ? (hint ?? S.moveMapHint) : address),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.kmText, fontWeight: FontWeight.w600, fontSize: 11.5, height: 1.25),
              ),
            ),
            if (loading) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.kmText),
              ),
            ],
            const SizedBox(width: 4),
            _OpenProvidersButton(onTap: onOpenProviders),
          ],
        ),
      ),
    );
  }
}

/// "N providers nearby" प्यानल पूरा (expanded) अवस्थामा खोल्ने सानो ">"
/// (chevron) बटन — [_PinAddressCard] भित्र।
class _OpenProvidersButton extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenProvidersButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.chevron_right_rounded,
            size: 18, color: AppColors.kmText),
      ),
    );
  }
}

/// "Where & for how much?" — तल्लो "N providers nearby" प्यानलको ठ्याक्कै
/// माथिको संक्षिप्त (collapsed) बटन, थिच्दा [_DestinationSearchBar] खुल्छ।
class _WhereAndHowMuchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _WhereAndHowMuchButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.kmVoid2.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.kmOrange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                S.whereToAndHowMuch,
                style: const TextStyle(
                    color: AppColors.kmMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// InDrive-style सवारी छान्ने horizontal chip पट्टी — Bike/Car मात्र (अरू
/// (Moto One Click/Comfort/Delivery) जस्ता category हरू worker registration/
/// Firestore schema नै बदल्नुपर्ने भएकाले हाललाई थपिएका छैनन्)। अर्को chip
/// थिच्दा यही स्क्रिनलाई नयाँ serviceType सहित pop+push गरेर बदलिन्छ (`widget.
/// serviceType` `final` भएकाले in-place बदल्न मिल्दैन)।
class _VehicleChipRow extends StatelessWidget {
  final String current;
  final double initialLat;
  final double initialLng;
  const _VehicleChipRow({
    required this.current,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String type, IconData icon, String label) {
      final active = type == current;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: active
              ? null
              : () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceMapScreen(
                        serviceType: type,
                        initialLat: initialLat,
                        initialLng: initialLng,
                      ),
                    ),
                  );
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: active ? AppColors.kmCtaGradient : null,
              color: active ? null : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: active
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 17,
                    color: active ? AppColors.kmInk : Colors.white),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: active ? AppColors.kmInk : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Bike', Icons.two_wheeler_rounded, S.bikeWord),
          chip('Car', Icons.local_taxi_rounded, S.carWord),
        ],
      ),
    );
  }
}

/// InDrive-style भरपर्दो/सुरक्षा सन्देश पट्टी — साँचो promo/discount प्रणाली
/// नभएकाले नक्कली छुट (जस्तै "15% off") दाबी गर्नुको सट्टा, सधैँ सत्य रहने
/// एउटा तटस्थ trust banner।
class _TrustBanner extends StatelessWidget {
  const _TrustBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.kmTeal.withValues(alpha: 0.18),
            AppColors.kmPurple.withValues(alpha: 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, size: 16, color: AppColors.kmTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(S.verifiedRidersBanner,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Ride-Hailing — गन्तव्य confirm भइसकेपछि माथिको live pin address कार्डको
/// ठाउँमा देखिने pickup→destination सारांश (route फेला परेसम्म "Finding
/// route…", फेरि छान्ने चाहिए "Change" लिंक)।
class _RideSummaryCard extends StatelessWidget {
  final String pickupAddress;
  final String destAddress;
  final bool routeLoading;
  final VoidCallback onEditPickup;
  final VoidCallback onChangeDestination;
  const _RideSummaryCard({
    required this.pickupAddress,
    required this.destAddress,
    required this.routeLoading,
    required this.onEditPickup,
    required this.onChangeDestination,
  });

  Widget _row(IconData icon, Color dot, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value.isEmpty ? label : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.kmVoid2.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── दुवै पंक्ति tap गर्न मिल्ने — pickup वा destination जुनसुकै
          // पुनः खोजेर/सम्पादन गर्न माथिको "Enter your route" कार्ड फेरि
          // खोल्छ (InDrive-शैली — यात्रा सुरु नभएसम्म जहिल्यै सम्पादन योग्य)।
          GestureDetector(
            onTap: onEditPickup,
            behavior: HitTestBehavior.opaque,
            child: _row(
                Icons.circle, AppColors.kmTealBlue, S.pickupLabel, pickupAddress),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: SizedBox(
              height: 10,
              child: VerticalDivider(color: AppColors.kmMuted, thickness: 1.4),
            ),
          ),
          GestureDetector(
            onTap: onChangeDestination,
            behavior: HitTestBehavior.opaque,
            child: _row(
                Icons.circle, AppColors.kmOrange, S.destinationLabel, destAddress),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                  routeLoading
                      ? Icons.hourglass_top_rounded
                      : Icons.alt_route_rounded,
                  size: 14,
                  color: AppColors.kmMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  routeLoading ? S.findingRoute : '',
                  style: const TextStyle(color: AppColors.kmMuted, fontSize: 11.5),
                ),
              ),
              GestureDetector(
                onTap: onChangeDestination,
                child: Text(S.changeDestination,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ride-Hailing — "Where to?" खोज बक्स (Nominatim forward-geocoding,
/// `location_util.dart::searchPlaces`)। नतिजामध्ये एउटा tap गर्दा पिन
/// सिधै त्यहाँ जान्छ — manual drag गर्नु नपरोस् भनेर, तर अझै drag पनि
/// उत्तिकै काम गर्छ (दुवै उही `_lat`/`_lng` लाई नै लक्षित)।
class _DestinationSearchBar extends StatefulWidget {
  final double? biasLat;
  final double? biasLng;
  final void Function(String label, double lat, double lng) onPicked;
  // InDrive-शैली — "From"/"To" प्रस्ट लेबल (बक्सको माथि) + हालको GPS
  // लाइभ-लोकेसन एकै-ट्याप बटन (दुवै वैकल्पिक — नयाँ, पहिलेका अरू कल-साइट
  // (जस्तै साधारण सेवाको "Where to?") ले नपास गरे पनि उस्तै काम गर्छन्)।
  final String? fieldLabel;
  final String? hintText;
  final bool showLiveLocationButton;
  final String? initialText;
  const _DestinationSearchBar({
    super.key,
    required this.biasLat,
    required this.biasLng,
    required this.onPicked,
    this.fieldLabel,
    this.hintText,
    this.showLiveLocationButton = false,
    this.initialText,
  });

  @override
  State<_DestinationSearchBar> createState() => _DestinationSearchBarState();
}

class _DestinationSearchBarState extends State<_DestinationSearchBar> {
  late final _controller = TextEditingController(text: widget.initialText ?? '');
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<({String label, double lat, double lng})> _results = const [];
  bool _loading = false;
  // खोजी एकपटक पूरा भइसक्यो (नतिजा भेटियोस् वा नभेटियोस्) भनेर — "अझै
  // टाइप गर्दै" र "खोजियो तर केही भेटिएन" बीच छुट्याउन।
  bool _searched = false;
  // Stale-Response Guard — पहिलेको (ढिलो) खोजी नतिजा नेटवर्कमा अझै
  // बाँकी छँदै प्रयोगकर्ताले फेरि नयाँ शब्द टाइप गरे, र त्यो पुरानो जवाफ
  // नयाँ खोजी सुरु भइसकेपछि मात्र आइपुगे — `_debounce.cancel()` ले टाइमर
  // (सुरु नै नभएको request) रोक्न सक्छ, तर पहिल्यै सुरु भइसकेको network
  // call कहिल्यै रोक्न सक्दैन। यही generation counter ले त्यो ढिलो/पुरानो
  // जवाफ चिन्छ र बेवास्ता गर्छ — नत्र "Kathmandu" खोज्दा अघिल्लो (जस्तै
  // टेस्ट गरिएको बेग्लै मुलुकको) प्रस्ताव देखिने गलत बग आउँथ्यो।
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Pin ↔ Input Sync — नक्सामा पिन तानेर छोड्दा (`onCameraIdle` →
  // `_reverseGeocodePin` → parent setState) `widget.initialText` बाहिरैबाट
  // बदलिन्छ। प्रयोगकर्ता आफैं यहीं टाइप गर्दै नभएसम्म (`!_focusNode.hasFocus`)
  // मात्र त्यो नयाँ मान यहाँ देखाउने — नत्र टाइप गर्दागर्दै cursor/text बीचमै
  // बाहिरबाट ओभरराइट हुने बग आउँथ्यो।
  @override
  void didUpdateWidget(covariant _DestinationSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialText;
    if (next != null &&
        next.isNotEmpty &&
        next != oldWidget.initialText &&
        next != _controller.text &&
        !_focusNode.hasFocus) {
      _controller.text = next;
    }
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      _searchGeneration++;
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final myGeneration = ++_searchGeneration;
    // टाइप गर्दागर्दै (नयाँ खोजी अझै पर्खिँदै) पुरानो नतिजा स्क्रिनमा
    // टाँसिएर नबसोस् भनेर तुरुन्तै खाली — Loading spinner देखिने, कहिल्यै
    // अघिल्लो (अब अप्रासंगिक) शब्दको नतिजा होइन।
    setState(() {
      _results = const [];
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || myGeneration != _searchGeneration) return;
      final r = await searchPlaces(q,
          biasLat: widget.biasLat, biasLng: widget.biasLng);
      // यो भन्दा पछि अर्को (नयाँ) खोजी सुरु भइसकेको भए यो (अब पुरानो
      // भइसकेको) जवाफ लागू नगर्ने।
      if (!mounted || myGeneration != _searchGeneration) return;
      setState(() {
        _results = r;
        _loading = false;
        _searched = true;
      });
    });
  }

  /// एउटा नतिजा (tap वा Enter/Search key दुवैबाट) छान्ने साझा तरिका।
  void _selectResult(({String label, double lat, double lng}) r) {
    FocusScope.of(context).unfocus();
    _controller.text = r.label;
    setState(() => _results = const []);
    widget.onPicked(r.label, r.lat, r.lng);
  }

  /// GPS आइकन — हालको लाइभ स्थान सिधै (search नगरी) यो बक्सको मूल्यको
  /// रूपमा एकैचोटि छान्ने। सामान्य `_selectResult` कै उही `onPicked` बाटो
  /// प्रयोग गर्छ — बाहिरबाट हेर्दा खोजी-नतिजा नै छानेको जस्तै व्यवहार हुन्छ।
  Future<void> _useLiveLocation() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      final addr = await reverseGeocode(p.latitude, p.longitude);
      if (!mounted) return;
      final label = addr.isNotEmpty ? addr : S.moveMapHint;
      _controller.text = label;
      setState(() {
        _loading = false;
        _results = const [];
      });
      widget.onPicked(label, p.latitude, p.longitude);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// किबोर्डको Search/Enter थिच्दा — inDrive-style, सूचीबाट छानेर tap
  /// गर्नै नपरोस्। अझै debounce पर्खिरहेको (`_results` अझै खाली) भए त्यो
  /// नपर्खी तुरुन्तै खोजी गरेर पहिलो/उत्तम नतिजा सिधै छान्ने।
  Future<void> _onSubmitted(String q) async {
    final query = q.trim();
    if (query.length < 2) return;
    if (_results.isNotEmpty) {
      _selectResult(_results.first);
      return;
    }
    _debounce?.cancel();
    final myGeneration = ++_searchGeneration;
    setState(() => _loading = true);
    final r = await searchPlaces(query,
        biasLat: widget.biasLat, biasLng: widget.biasLng);
    if (!mounted || myGeneration != _searchGeneration) return;
    if (r.isEmpty) {
      setState(() {
        _loading = false;
        _searched = true;
      });
      return;
    }
    setState(() => _loading = false);
    _selectResult(r.first);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // InDrive-शैली — बक्सको ठ्याक्कै माथि प्रस्ट "From"/"To" लेबल, ताकि
        // प्रयोगकर्ताले कुन बक्स कुन हो भनेर एकनजरमै छुट्याउन सकून्।
        if (widget.fieldLabel != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(widget.fieldLabel!,
                style: const TextStyle(
                    color: AppColors.kmMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.3)),
          ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.kmVoid2.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _onSubmitted,
                  style: const TextStyle(color: AppColors.kmText),
                  cursorColor: AppColors.kmOrange,
                  decoration: InputDecoration(
                    // ऐप-व्यापी `inputDecorationTheme` (light मोडमा सेतो/
                    // हल्का fill + रङ्गीन border दिने) यहाँ लागू नहोस् भनेर
                    // सबै border अवस्था + filled/fillColor स्पष्ट रूपमै
                    // हटाइएको — नत्र (light theme मा) सेतो पृष्ठभूमिमाथि
                    // हाम्रै सेतो/हल्का `kmText` अक्षर देखिँदैनथ्यो (typed
                    // text "invisible" देखिने बग यही कारणले थियो)।
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: widget.hintText ?? S.searchDestinationHint,
                    hintStyle: const TextStyle(color: AppColors.kmMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (widget.showLiveLocationButton && !_loading) ...[
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _useLiveLocation,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.my_location_rounded,
                        size: 19, color: AppColors.kmTeal),
                  ),
                ),
              ],
              if (_loading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.kmOrange)),
            ],
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: AppColors.kmVoid2.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              itemBuilder: (context, i) {
                final r = _results[i];
                return ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.place_rounded, color: AppColors.kmOrange),
                  title: Text(r.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.kmText)),
                  onTap: () => _selectResult(r),
                );
              },
            ),
          )
        else if (_searched && !_loading && _controller.text.trim().length >= 2)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.kmVoid2.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
              ],
            ),
            child: Text(S.noSearchResults,
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
          ),
      ],
    );
  }
}

// ── तल्लो सूचीबाट छानिएको worker को विवरण कार्ड — Profile हेर्ने वा सिधै
// price offer गर्ने बटन सहित ──
class _ProviderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String workerId;
  final double distanceKm;
  final String serviceType;
  final RoadRoute? route;
  final bool routeLoading;
  final double employerLat;
  final double employerLng;
  final VoidCallback onClose;

  const _ProviderCard({
    required this.data,
    required this.workerId,
    required this.distanceKm,
    required this.serviceType,
    required this.onClose,
    required this.employerLat,
    required this.employerLng,
    this.route,
    this.routeLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '—').toString();
    // '5.0' default हटाइयो — नयाँ worker सुरुमा साँच्चै ०/कुनै review
    // नभएको देखिनुपर्छ, admin approve गर्दै लेख्ने मान अब '0.0' नै हो।
    final rating = (data['rating'] ?? '0.0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();
    final experience = (data['experience'] ?? '').toString();
    final online = data['isOnline'] != false;
    const bodySmall = TextStyle(color: AppColors.kmMuted, fontSize: 12.5);

    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(14),
      fill: AppColors.kmVoid2.withValues(alpha: 0.97),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  WorkerAvatar(
                    uid: workerId,
                    size: 48,
                    backgroundColor:
                        serviceMarkerColor(serviceType).withValues(alpha: 0.15),
                    iconColor: serviceMarkerColor(serviceType),
                  ),
                  if (online)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                          radius: 6, backgroundColor: AppColors.kmTeal),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5)),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.kmAmber),
                        const SizedBox(width: 2),
                        Text(rating,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                        Text('   ${S.serviceName(serviceType)}',
                            style: bodySmall),
                      ],
                    ),
                    Text(
                        [
                          if (experience.isNotEmpty) experience,
                          S.distanceLabel(distanceKm),
                          S.fromPrice(price),
                        ].join('  ·  '),
                        style: bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 20, color: AppColors.kmMuted),
                onPressed: onClose,
              ),
            ],
          ),
          if (routeLoading || route != null) ...[
            Divider(height: 18, color: Colors.white.withValues(alpha: 0.1)),
            if (routeLoading)
              Row(
                children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.kmOrange)),
                  const SizedBox(width: 8),
                  Text(S.findingRoute, style: bodySmall),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.route_rounded,
                      size: 16, color: AppColors.kmOrange),
                  const SizedBox(width: 6),
                  Text(
                    '${route!.km.toStringAsFixed(route!.km < 10 ? 1 : 0)} km  ·  ${S.minutesShort(route!.minutes)}',
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5),
                  ),
                  const SizedBox(width: 6),
                  Text(route!.real ? S.roadRoute : S.approxRoute,
                      style: bodySmall),
                ],
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WorkerProfileScreen(worker: {
                        'uid': (data['uid'] ?? workerId).toString(),
                        'name': name,
                        'service': serviceType,
                        'experience': experience,
                        'location': (data['location'] ?? '').toString(),
                        'price': price,
                        'document': (data['document'] ?? '').toString(),
                        'phone': (data['phone'] ?? '').toString(),
                        'vehicleDetails':
                            (data['vehicleDetails'] ?? '').toString(),
                      }),
                    ),
                  ),
                  icon: const Icon(Icons.person_rounded, size: 16),
                  label: const Text('Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kmOrange,
                    side: const BorderSide(color: AppColors.kmOrange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: KmCtaButton(
                  label: S.offerYourPrice,
                  icon: Icons.gavel_rounded,
                  onPressed: () => showOfferSheet(
                    context,
                    data: data,
                    workerId: workerId,
                    distanceKm: distanceKm,
                    employerLat: employerLat,
                    employerLng: employerLng,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Job Confirmation & Details sheet ────────────────────────────────────────
class _PostedJob {
  final String title;
  final String description;
  final DateTime date;
  final String slot;
  final String address;
  final double lat;
  final double lng;
  final int budget;
  // Ride-Hailing (Bike/Car) मात्र — गन्तव्य (destination) विवरण, अरू
  // सेवाहरूमा सधैँ null।
  final String? destAddress;
  final double? destLat;
  final double? destLng;
  final bool autoOffer;
  const _PostedJob({
    required this.title,
    required this.description,
    required this.date,
    required this.slot,
    required this.address,
    required this.lat,
    required this.lng,
    required this.budget,
    this.destAddress,
    this.destLat,
    this.destLng,
    this.autoOffer = false,
  });
}

class _PostJobSheet extends StatefulWidget {
  final String serviceType;
  final double lat;
  final double lng;
  // Parent screen (pin drop) ले पहिल्यै geocode गरिसकेको ठेगाना — दिइएको
  // (खाली नभएको) भए यहाँ फेरि छुट्टै network call नगरी सिधै प्रयोग हुन्छ।
  final String initialAddress;
  final int initialBudget;
  final int nearbyCount;
  // Ride-Hailing — pickup पहिल्यै भइसकेको, गन्तव्य पनि confirm भइसकेको ride
  // भए मात्र true। यो true हुँदा date/slot/title जस्ता scheduled-job field
  // हरू देखिँदैनन् (राइड तुरुन्तै हो, कुनै भविष्यको मिति चाहिँदैन)।
  final bool isRide;
  final String destinationAddress;
  final double? destLat;
  final double? destLng;
  const _PostJobSheet({
    required this.serviceType,
    required this.lat,
    required this.lng,
    required this.initialAddress,
    required this.initialBudget,
    required this.nearbyCount,
    this.isRide = false,
    this.destinationAddress = '',
    this.destLat,
    this.destLng,
  });

  @override
  State<_PostJobSheet> createState() => _PostJobSheetState();
}

class _PostJobSheetState extends State<_PostJobSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _addr = TextEditingController();
  DateTime? _date;
  String _slot = 'anytime';
  late int _budget = widget.initialBudget;
  bool _loadingAddr = true;
  String? _error;
  // Ride-Hailing मात्र — on भए पहिलो आउने driver प्रस्ताव आफैं accept हुन्छ
  // (RequestTrackingScreen कै `_Searching` ले पढ्छ)।
  bool _autoOffer = false;

  static const _step = 50;

  @override
  void initState() {
    super.initState();
    if (widget.initialAddress.trim().isNotEmpty) {
      // Parent ले पहिल्यै geocode गरिसकेको — फेरि नगर्ने, तुरुन्तै देखिने।
      _addr.text = widget.initialAddress.trim();
      _loadingAddr = false;
    } else {
      // Parent कै geocode अझै नआएको/असफल भएको दुर्लभ अवस्थामा मात्र यहाँ
      // आफ्नै छुट्टै कोसिस (safety net) — नत्र यो field सधैंलाई खाली रहन्थ्यो।
      _fillAddress();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _addr.dispose();
    super.dispose();
  }

  Future<void> _fillAddress() async {
    final a = await reverseGeocode(widget.lat, widget.lng);
    if (!mounted) return;
    setState(() {
      if (a.isNotEmpty && _addr.text.trim().isEmpty) _addr.text = a;
      _loadingAddr = false;
    });
  }

  String _slotLabel(String s) => switch (s) {
        'morning' => S.slotMorning,
        'afternoon' => S.slotAfternoon,
        'evening' => S.slotEvening,
        _ => S.slotAnytime,
      };

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d != null) setState(() => _date = d);
  }

  void _submit() {
    // Ride-Hailing — तुरुन्तै हो, कुनै मिति/शीर्षक/वर्णन अनिवार्य छैन।
    if (!widget.isRide) {
      if (_desc.text.trim().isEmpty) {
        setState(() => _error = S.describeJobFirst);
        return;
      }
      if (_date == null) {
        setState(() => _error = S.pickDateFirst);
        return;
      }
    }
    Navigator.pop(
      context,
      _PostedJob(
        title: widget.isRide ? S.requestRide : _title.text.trim(),
        description: _desc.text.trim(),
        date: _date ?? DateTime.now(),
        slot: _slot,
        address: _addr.text.trim(),
        lat: widget.lat,
        lng: widget.lng,
        budget: _budget,
        destAddress: widget.isRide ? widget.destinationAddress : null,
        destLat: widget.isRide ? widget.destLat : null,
        destLng: widget.isRide ? widget.destLng : null,
        autoOffer: widget.isRide && _autoOffer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GestureDetector(
        // कार्डभित्रको हरेक touch/tap यहीँ सोसिन्छ — पछाडिको नक्सामा कुनै
        // pointer नपुगोस् (नक्साका gesture पनि sheet खुला हुँदा बन्द छन्)।
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
          decoration: BoxDecoration(
            color: AppColors.kmSurface.withValues(alpha: 0.94),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            border: Border(
              top: BorderSide(color: AppColors.kmGlassBorder),
              left: BorderSide(color: AppColors.kmGlassBorder),
              right: BorderSide(color: AppColors.kmGlassBorder),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        gradient: AppColors.kmCtaGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          widget.isRide
                              ? Icons.local_taxi_rounded
                              : serviceIconFor(widget.serviceType),
                          color: AppColors.kmInk, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              widget.isRide
                                  ? '${S.confirmRideTitle} — ${S.serviceName(widget.serviceType)}'
                                  : '${S.jobConfirmTitle} — ${S.serviceName(widget.serviceType)}',
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              '${widget.nearbyCount} ${S.serviceName(widget.serviceType)} ${S.providersNearby}',
                              style: const TextStyle(
                                  color: AppColors.kmMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (widget.isRide) ...[
                  // ── Pickup/Destination — यी दुवै पहिल्यै pin-drop बाट
                  // confirm भइसकेका हुन्, यहाँ फेरि सम्पादन गर्न मिल्दैन
                  // (सामान्य कामको सूची/मिति/वर्णन जस्तो केही चाहिँदैन)।
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.kmGlassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.my_location_rounded,
                                color: AppColors.kmMuted, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${S.pickupLabel}: ${widget.initialAddress}',
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                          child: SizedBox(
                            height: 8,
                            child: VerticalDivider(
                                color: Colors.white.withValues(alpha: 0.16),
                                thickness: 1.2),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.flag_rounded,
                                color: AppColors.kmMuted, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${S.destinationLabel}: ${widget.destinationAddress}',
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  _WhiteField(
                    controller: _title,
                    label: S.jobTitleLabel,
                    hint: S.jobTitleHint,
                  ),
                  const SizedBox(height: 12),
                  _WhiteField(
                    controller: _desc,
                    label: S.jobDescription,
                    hint: S.jobDescriptionHint,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                ],
                if (!widget.isRide)
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.kmGlassBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded,
                                  color: AppColors.kmMuted, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _date == null
                                    ? S.preferredDateLabel
                                    : '${_date!.day}/${_date!.month}/${_date!.year}',
                                style: const TextStyle(color: AppColors.kmText),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.kmGlassBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _slot,
                            isExpanded: true,
                            dropdownColor: AppColors.kmSurface,
                            iconEnabledColor: AppColors.kmMuted,
                            style: const TextStyle(color: AppColors.kmText),
                            items: const [
                              'anytime',
                              'morning',
                              'afternoon',
                              'evening'
                            ]
                                .map((s) => DropdownMenuItem(
                                    value: s, child: Text(_slotLabel(s))))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _slot = v ?? 'anytime'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!widget.isRide) ...[
                  const SizedBox(height: 12),
                  _WhiteField(
                    controller: _addr,
                    label: S.jobAddressLabel,
                    hint: _loadingAddr ? S.fetchingAddress : '',
                    maxLines: 2,
                    prefix: const Icon(Icons.place_outlined,
                        color: AppColors.kmMuted, size: 18),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.gps_fixed_rounded,
                          color: AppColors.kmMuted, size: 12),
                      const SizedBox(width: 4),
                      Text(
                          '${S.pinnedLocation}: ${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: AppColors.kmMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(S.serviceAddressNote,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 11)),
                ],
                const SizedBox(height: 14),
                Text(widget.isRide ? S.fareOfferLabel : S.customerBudget,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StepBtn(
                        icon: Icons.remove_rounded,
                        onTap: () => setState(() =>
                            _budget = (_budget - _step).clamp(_step, 1000000))),
                    const SizedBox(width: 18),
                    Text('Rs. $_budget',
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 18),
                    _StepBtn(
                        icon: Icons.add_rounded,
                        onTap: () => setState(() =>
                            _budget = (_budget + _step).clamp(_step, 1000000))),
                  ],
                ),
                if (widget.isRide) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(S.autoOffer,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                      Switch(
                        value: _autoOffer,
                        activeThumbColor: AppColors.kmOrange,
                        activeTrackColor: AppColors.kmOrange.withValues(alpha: 0.4),
                        onChanged: (v) => setState(() => _autoOffer = v),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.kmRose,
                          fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                KmCtaButton(
                  onPressed: _submit,
                  icon: widget.isRide
                      ? Icons.local_taxi_rounded
                      : Icons.campaign_rounded,
                  label: widget.isRide ? S.findOffer : S.confirmBroadcast,
                ),
              ],
            ),
          ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WhiteField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final Widget? prefix;
  const _WhiteField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.kmText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.kmMuted),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.kmMuted),
        prefixIcon: prefix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.kmGlassBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          borderSide: BorderSide(color: AppColors.kmOrange, width: 1.4),
        ),
      ),
    );
  }
}
