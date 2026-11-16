// screens/home_screen.dart
// inDrive-style map home: full-screen Google Map + sliding drawer + region
// status banner + bottom search + horizontal service-category selector।
import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart' show requestedMainTabIndex;
import '../config/app_config.dart' show SocialLinksConfig, kAdminEmail;
import '../l10n/strings.dart';
import '../location_util.dart' show reverseGeocode;
import '../saved_places_screen.dart';
import '../settings_page.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/spring_tap.dart';
import '../widgets/vehicle_type_picker.dart';
import '../worker_registration_page.dart';
import 'bookings_screen.dart';
import 'earnings_screen.dart';
import 'handyman_categories_screen.dart';
import 'help_support_screen.dart';
import 'hotel_search_screen.dart';
import 'salon_list_screen.dart';
import 'hotel_verification_admin_screen.dart';
import 'messages_screen.dart';
import 'admin_dashboard_screen.dart';
import 'my_reviews_screen.dart';
import 'nearby_common.dart';
import 'nearby_screen.dart';
import 'notification_screen.dart';
import 'payment_methods_screen.dart';
import '../watchlist_screen.dart';
import 'service_map_screen.dart';
import 'worker_profile_screen.dart';
import '../widgets/worker_stats.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;

  // एकपटक मात्र subscribe — प्यानल drag हुँदा नक्सा rebuild हुँदा पनि
  // Firestore stream पुनः नजोडियोस्।
  final Stream<QuerySnapshot<Map<String, dynamic>>> _workersStream =
      FirebaseFirestore.instance.collection('registeredWorkers')
          .limit(300) // पूरै collection होइन — सर्भर भार/बिल सीमित
          .snapshots();

  double _lat = fallbackLat;
  double _lng = fallbackLng;
  // प्रयोगकर्ताको वास्तविक GPS स्थान (camera सर्दा नबदलिने) — custom user pin।
  double _meLat = fallbackLat;
  double _meLng = fallbackLng;
  bool _locReady = false;
  // home screen बाट अब कुनै category chip देखिँदैन (ride-sharing hero card
  // बाहेकका सबै अरू सेवा grid हटाइएको) — यो नक्सा-फिल्टर त्यसैले सधैँ 'सबै'
  // (unfiltered) नै रहन्छ।
  final String _pickedCategory = '';

  // क्याटेगोरी → custom marker bitmap (initState मा एकपटक बन्छ)।
  final Map<String, BitmapDescriptor> _catMarkers = {};
  // ── Pin Drop (browse-only, service_map_screen.dart कै उस्तै भिजुअल) ──
  // यहाँ यो पिनले "job/booking स्थान" बदल्दैन — त्यो सधैँ `_meLat`/`_meLng`
  // (साँचो GPS) कै रहन्छ, माथि `onSendOffer` को comment हेर्नुहोस्। यो
  // केवल नक्सा pan गर्दा प्रयोगकर्ता कुन ठाउँ हेर्दैछ भनेर स्पष्ट देखाउने
  // (स्क्रिनको बीचमा स्थिर झन्डा + माथि ठेगाना कार्ड + touch-lift/nail-drop
  // haptic) — साँचो booking स्थान भने अझै GPS-आधारित नै।
  Uint8List? _browsePinBytes;
  String _browseAddress = '';
  bool _loadingBrowseAddress = false;
  Timer? _browseAddrDebounce;
  double? _pendingBrowseLat;
  double? _pendingBrowseLng;
  bool _programmaticCameraMove = false;
  late final AnimationController _pinLiftCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  // ── ठेगाना बक्स — InDrive-शैली pin-tracking tooltip ──
  // डिफल्टमा लुकेको रहन्छ; प्रयोगकर्ताले नक्सा touch/drag गर्नेबित्तिकै
  // (`onCameraMoveStarted`) देखिन्छ, पिन "ड्रप" भएपछि (`onCameraIdle`) केही
  // क्षण (~1.8s) देखिएर आफैं fade-out भई लुक्छ (`_addrHideTimer`)।
  bool _addrVisible = false;
  Timer? _addrHideTimer;

  void _scheduleBrowseGeocode() {
    _browseAddrDebounce?.cancel();
    _browseAddrDebounce =
        Timer(const Duration(milliseconds: 400), _reverseGeocodeBrowsePin);
  }

  /// झन्डाको भिजुअल टुप्पो स्क्रिनको तल्लो किनाराबाट कति माथि पर्छ —
  /// ठेगाना बक्सलाई त्यही बिन्दुको ठ्याक्कै माथि टाँस्न (service_map_screen.dart
  /// कै `_pinTipBottomOffset` सँगै उही सूत्र — यहाँ नक्सा/पिन overlay दुवैले
  /// `padding: top: 70` मात्र प्रयोग गर्ने भएकोले `bottomPad = 0`)।
  double _pinTipBottomOffset(BuildContext context) {
    const topPad = 70.0;
    const displayHeight = 60.0;
    const scale = displayHeight / FlagPinGeometry.displayH;
    final tipAboveCenter = FlagPinGeometry.anchor.dy * scale;
    final h = MediaQuery.of(context).size.height;
    return (h - topPad) / 2 + tipAboveCenter;
  }

  Future<void> _reverseGeocodeBrowsePin() async {
    final lat = _lat, lng = _lng;
    if (mounted) setState(() => _loadingBrowseAddress = true);
    final addr = await reverseGeocode(lat, lng);
    if (!mounted || _lat != lat || _lng != lng) return;
    setState(() {
      _browseAddress = addr;
      _loadingBrowseAddress = false;
    });
  }

  // नक्सामा marker थिचेपछि देखिने preview card को worker।
  String? _selectedWorkerId;
  Map<String, dynamic>? _selectedWorker;
  double _selectedKm = 0;

  // worker preview card (अब practically अप्रयुक्त, माथि `_markers()` हेर्नुहोस्)
  // लाई तल्लो किनाराबाट कति माथि राख्ने भन्ने अनुमानित offset — पहिले यहाँ
  // देखिने Primary Action Bar/"मेरो स्थान" बटनको उचाइसँग मिलाइएको थियो, अब
  // ती दुवै पूरा-स्क्रिन `_HomeServiceOverlay` ले replace गरिसकेकोले यो मान
  // अब केवल legacy spacing का लागि मात्र बाँकी छ।
  static const double _kActionBarHeight = 108.0;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadCategoryMarkers();
    destinationFlagPinBytes().then((b) {
      if (mounted) setState(() => _browsePinBytes = b);
    });
    _reverseGeocodeBrowsePin();
  }

  /// सबै custom pin bitmap (क्याटेगोरी) पृष्ठभूमिमा तयार पार्ने।
  Future<void> _loadCategoryMarkers() async {
    for (final s in serviceFilters) {
      final name = (s['name'] as String);
      try {
        final bd = await categoryPinMarker(name);
        if (!mounted) return;
        _catMarkers[name.toLowerCase()] = bd;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _browseAddrDebounce?.cancel();
    _addrHideTimer?.cancel();
    _pinLiftCtrl.dispose();
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
        if (!mounted) return;
        setState(() => _locReady = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showLocationModal());
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _meLat = p.latitude;
        _meLng = p.longitude;
        _locReady = true;
      });
      _programmaticCameraMove = true;
      await _map
          ?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13.5));
      _programmaticCameraMove = false;
      _reverseGeocodeBrowsePin();
      _startTracking();
    } catch (_) {
      if (mounted) setState(() => _locReady = true);
    }
  }

  // Pin Drop — live GPS ले अब `_lat`/`_lng` (browse-pin/camera स्थान) लाई
  // कहिल्यै ओभरराइट गर्दैन, नत्र प्रयोगकर्ताले pin सारेको केही सेकेन्डमै
  // हिँडाइले फेरि आफ्नो हालको स्थानमा तानिन्थ्यो। `_meLat`/`_meLng` (साँचो
  // booking स्थान, "मेरो स्थान" marker) चाहिँ पहिलेकै जस्तो सधैँ live रहन्छ।
  void _startTracking() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30,
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() {
        _meLat = p.latitude;
        _meLng = p.longitude;
      });
    }, onError: (_) {});
  }

  void _showLocationModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.kmSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                tween: Tween(begin: 0.6, end: 1),
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.kmOrange.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded,
                      size: 40, color: AppColors.kmOrange),
                ),
              ),
              const SizedBox(height: 16),
              Text(S.locationOffTitle,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(S.locationOffBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 20),
              KmCtaButton(
                label: S.enableLocation,
                icon: Icons.my_location_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  _initLocation();
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.kmMuted),
                child: Text(S.notNow),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 'Driver' आफैं कहिल्यै साँचो bookable service होइन — InDrive-Style
  /// Ride-Sharing: tap गर्नेबित्तिकै Bike/Car popup देखिन्छ, त्यसपछि मात्र
  /// छानिएको (Bike वा Car) वास्तविक service भएर अगाडि बढ्छ। अरू कुनै
  /// category (Plumber/Electrician/...) मा यो popup छुँदैन।
  Future<String?> _resolveServiceName(String name) async {
    if (name != 'Driver') return name;
    return showVehicleTypePicker(context);
  }

  void _openService(String name) async {
    final resolved = await _resolveServiceName(name);
    if (resolved == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        // यो होमपेजले पहिल्यै GPS fetch गरिसकेको छ — नयाँ पेजले फेरि सोही
        // fetch दोहोर्‍याएर बल्ल देखिनु (spinner सहित) भन्दा, यहीँको
        // हालको स्थान सिधै सिड गरेर तुरुन्तै नक्सा देखाउने, अनि पछाडि
        // आफ्नै ताजा GPS ले चाहिँदा सच्याउने।
        builder: (_) => ServiceMapScreen(
          serviceType: resolved,
          initialLat: _locReady ? _meLat : null,
          initialLng: _locReady ? _meLng : null,
        ),
      ),
    );
  }

  /// मुख्य ग्रिडको "Handyman" कार्ड — सबै trade (Mechanic/Plumber/
  /// Electrician/Carpenter/Painter/Cleaner/Tutor/...) छान्ने छुट्टै
  /// category-selection पेज खोल्छ (`HandymanCategoriesScreen`) — त्यहाँ
  /// हरेक trade आफ्नै icon कार्डमा, थिचेपछि सोही trade मा फिल्टर भएको
  /// `NearbyScreen(initialFilter: ...)` provider directory मा पुग्छ।
  void _openHandymanCategories() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HandymanCategoriesScreen()),
    );
  }

  /// मुख्य ग्रिडको "Hotel Booking" कार्ड — खोजी फारम (destination/date/
  /// guest/filter) देखाउने `HotelSearchScreen` खोल्छ (Hotel Booking System
  /// Phase 2)।
  void _openHotelSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HotelSearchScreen()),
    );
  }

  /// मुख्य ग्रिडको "Salon & Beauty" कार्ड — salon/barber/beauty provider
  /// browse गर्ने `SalonListScreen` (Booksy-style appointment booking)।
  void _openSalonList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SalonListScreen()),
    );
  }

  /// Global Search — maathiko search bar थिच्दा खुल्ने bottom sheet।
  /// तीनै category (Services/Places/Settings) `_SearchSheet` भित्रै
  /// filter/render हुन्छन्; सेवा मात्र यहाँको `_openService`/`_openHotelSearch`/
  /// `_openHandymanCategories` (यो screen कै state-निर्भर) प्रयोग गर्छ,
  /// बाँकी दुई category आफैं self-contained (उनको गन्तव्य screen state-
  /// स्वतन्त्र)।
  void _openGlobalSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(
        onPickService: (name) {
          Navigator.pop(context);
          // सवारी (Bike/Car/Auto/Driver) मात्र सिधै नक्सामा; Plumber/Electrician/
          // Mechanic जस्ता trade पहिले कामदार-सूची (asking price सहित) मा जान्छन्,
          // नक्सा (live tracking) त्यहाँबाट चाहिएमा मात्र।
          const rideNames = {'Bike', 'Car', 'Auto', 'Driver'};
          if (rideNames.contains(name)) {
            _openService(name);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NearbyScreen(initialFilter: name)),
            );
          }
        },
        onPickHotel: () {
          Navigator.pop(context);
          _openHotelSearch();
        },
        onPickHandyman: () {
          Navigator.pop(context);
          _openHandymanCategories();
        },
        onPickSalon: () {
          Navigator.pop(context);
          _openSalonList();
        },
      ),
    );
  }

  void _selectWorker(
      String id, Map<String, dynamic> data, ({double lat, double lng}) wp) {
    setState(() {
      _selectedWorkerId = id;
      _selectedWorker = data;
      _selectedKm = haversineKm(_meLat, _meLng, wp.lat, wp.lng);
    });
    _map?.animateCamera(CameraUpdate.newLatLng(LatLng(wp.lat, wp.lng)));
  }

  void _clearSelection() => setState(() {
        _selectedWorkerId = null;
        _selectedWorker = null;
      });

  Map<String, String> _workerMap(String id, Map<String, dynamic> d) => {
        'uid': (d['uid'] ?? id).toString(),
        'name': (d['name'] ?? '—').toString(),
        'service': (d['service'] ?? '').toString(),
        'price': (d['price'] ?? 'Rs. 500').toString(),
        'experience': (d['experience'] ?? 'N/A').toString(),
        'location': (d['location'] ?? 'N/A').toString(),
        'phone': (d['phone'] ?? '').toString(),
        'vehicleDetails': (d['vehicleDetails'] ?? '').toString(),
      };

  Set<Marker> _markers(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Marker>{};

    // ── प्रयोगकर्ताको current-location झन्डा हटाइयो — यो जहिल्यै नक्सा
    // खुल्दा screen-center को "pick location" (Pin Drop) overlay झन्डा
    // सँगै ठ्याक्कै उही ठाउँमा देखिने भएकोले दुईवटा झन्डा (एउटा ठूलो,
    // ओभरल्यापिङ) देखिने बग हुन्थ्यो। अब यो नक्सा जहिल्यै
    // `_HomeServiceOverlay` ले नै छोपिएको हुन्छ (कुनै सेवा नछानेसम्म user ले
    // नक्सा कहिल्यै देख्दैनन्), त्यसैले छुट्टै current-location marker
    // आवश्यक थिएन।
    final filter = _pickedCategory.toLowerCase().trim();

    // ── नक्सा default मा सफा राख्ने ──
    // प्रयोगकर्ताले तल्लो प्यानलबाट कुनै क्याटेगोरी नछानेसम्म म्यापमा एउटै पनि
    // worker pin देखिँदैन (आफ्नो location pin मात्र)। यसले पुरानो जथाभाबी
    // गाडी/क्लिनर आदि marker पूर्ण रूपमा हटाउँछ।
    if (filter.isEmpty) return out;

    // custom pin अझै load भएको छैन भने केही देखाउँदैनौँ (गलत pin होइन)।
    if (_catMarkers.isEmpty) return out;

    final known = _catMarkers.keys.toSet(); // ठ्याक्कै ८ ज्ञात क्याटेगोरी

    for (final d in docs) {
      final data = d.data();
      // उपलब्ध (online) कामदार मात्र।
      if (data['isOnline'] == false) continue;

      final svc = (data['service'] ?? '').toString().toLowerCase().trim();
      // ज्ञात क्याटेगोरीमध्ये नपर्ने / service नभएका worker म्यापमा आउँदैनन्।
      if (!known.contains(svc)) continue;
      // ठ्याक्कै छानिएको क्याटेगोरीका worker मात्र।
      if (svc != filter) continue;

      // नक्कली स्थान होइन — असली र ताजा (५ मिनेटभित्र) मात्र; नत्र नदेखाउने।
      final wp = realWorkerPos(data);
      if (wp == null) continue;
      final selected = d.id == _selectedWorkerId;
      out.add(Marker(
        markerId: MarkerId(d.id),
        position: LatLng(wp.lat, wp.lng),
        anchor: const Offset(0.5, 1.0),
        zIndexInt: selected ? 10 : 1,
        icon: _catMarkers[svc]!,
        onTap: () => _selectWorker(d.id, data, wp),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // `const` हटाइयो — `_HomeDrawer.build()` ले `S.*` (locale) प्रयोग गर्छ,
      // `const` ले भाषा बदलिँदा पनि कहिल्यै rebuild नहुने बग निम्त्याउँथ्यो।
      // ignore: prefer_const_constructors
      drawer: _HomeDrawer(),
      body: Stack(
        children: [
          // ── Map ──
          // नक्सा सधैँ पूरै स्क्रिन ओगटेर पूर्णतया स्थिर रहन्छ — तल्लो "Drag up
          // for more" शीट drag गर्दा (live भए पनि settle भएपछि भए पनि)
          // नक्साको bounds/camera कहिल्यै बदलिँदैन, त्यसैले center coordinate
          // र zoom level जहिल्यै उस्तै रहन्छ। शीट यसमाथि केवल दृश्य overlay
          // हो (तल हेर्नुहोस्, आफ्नै `HitTestBehavior.opaque` GestureDetector
          // ले शीट क्षेत्रभित्रको touch/drag आफैं सोस्छ, नक्सासम्म पुग्न
          // दिँदैन)।
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Stack(
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _workersStream,
                  builder: (context, snap) {
                    return GoogleMap(
                          initialCameraPosition: CameraPosition(
                              target: LatLng(_lat, _lng), zoom: 13),
                          mapId: kCloudMapId,
                          onMapCreated: (c) {
                            _map = c;
                            if (_locReady) {
                              _programmaticCameraMove = true;
                              c
                                  .animateCamera(CameraUpdate.newLatLngZoom(
                                      LatLng(_lat, _lng), 13.5))
                                  .whenComplete(
                                      () => _programmaticCameraMove = false);
                            }
                          },
                          // Pin Drop — pan गर्न थालेकै क्षण हलुका haptic +
                          // पिन माथि उठ्ने (प्रयोगकर्ताले आफैं गरेको बेला
                          // मात्र, प्रोग्रामेटिक recenter मा होइन)।
                          onCameraMoveStarted: () {
                            if (!_programmaticCameraMove) {
                              HapticFeedback.selectionClick();
                              _pinLiftCtrl.forward();
                              // Drag सुरु हुनेबित्तिकै ठेगाना बक्स तुरुन्तै
                              // देखिने — अघिल्लो auto-hide timer (यदि चलिरहेको
                              // भए) रद्द गरेर।
                              _addrHideTimer?.cancel();
                              if (!_addrVisible) {
                                setState(() => _addrVisible = true);
                              }
                            }
                          },
                          // hरेक frame मा सस्तो थाती राख्ने मात्र, pan
                          // रोकिएपछि (`onCameraIdle`) एकैचोटि लागू।
                          onCameraMove: (p) {
                            _pendingBrowseLat = p.target.latitude;
                            _pendingBrowseLng = p.target.longitude;
                          },
                          onCameraIdle: () {
                            final la = _pendingBrowseLat;
                            final ln = _pendingBrowseLng;
                            if (la == null || ln == null) return;
                            _pendingBrowseLat = null;
                            _pendingBrowseLng = null;
                            if (mounted) {
                              setState(() {
                                _lat = la;
                                _lng = ln;
                              });
                            }
                            // प्रयोगकर्ताले आफैं pan गरेको बेला मात्र ठेगाना
                            // ताजा गर्ने — programmatic move हरूले आफैं
                            // छुट्टै explicit geocode गर्छन् (माथि हेर्नुहोस्)।
                            if (_pinLiftCtrl.value > 0) {
                              _scheduleBrowseGeocode();
                              // पिन "ड्रप" भएको ~1.8 सेकेन्डपछि ठेगाना बक्स
                              // आफैं fade-out भई लुक्ने — बीचमै फेरि pan
                              // गरे (`onCameraMoveStarted`) माथि नै रद्द हुन्छ।
                              _addrHideTimer?.cancel();
                              _addrHideTimer =
                                  Timer(const Duration(milliseconds: 1800), () {
                                if (mounted) setState(() => _addrVisible = false);
                              });
                            }
                            // "Nail Drop" — spring physics सहित तल फर्काउने,
                            // settle भएकै क्षणमा कडा haptic।
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
                          onTap: (_) {
                            if (_selectedWorker != null) _clearSelection();
                          },
                          // निलो थोप्लाको सट्टा हाम्रो custom झन्डा pin।
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर
                          // "उल्टो" देखिने बग नआओस्।
                          rotateGesturesEnabled: false,
                          padding: const EdgeInsets.only(top: 70),
                          markers: _markers(snap.data?.docs ?? []),
                        );
                      },
                    ),

                    // ── Pin Drop overlay — स्क्रिनको बीचमा स्थिर झन्डा
                    // (browse-only, "मेरो स्थान" marker फरक — त्यो GPS मै
                    // native marker रहन्छ) ──
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 70),
                        child: Center(
                          child: _browsePinBytes == null
                              ? const SizedBox.shrink()
                              : _BrowsePinIcon(
                                  bytes: _browsePinBytes!,
                                  liftCtrl: _pinLiftCtrl,
                                ),
                        ),
                      ),
                    ),

                    // ── ठेगाना कार्ड — झन्डाको भिजुअल टुप्पोको ठ्याक्कै माथि,
                    // सानो/compact पिल — डिफल्टमा लुकेको, drag गर्दा देखिने,
                    // "ड्रप" भएपछि केही क्षणमै आफैं fade-out (माथिको
                    // `_addrVisible`/`_addrHideTimer` हेर्नुहोस्)।
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: _pinTipBottomOffset(context) + 8,
                      child: Center(
                        child: IgnorePointer(
                          ignoring: !_addrVisible,
                          child: AnimatedOpacity(
                            opacity: _addrVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: _BrowseAddressCard(
                              address: _browseAddress,
                              loading: _loadingBrowseAddress,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Marker थिचेपछिको worker preview card ──
          if (_selectedWorker != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 20 +
                  MediaQuery.of(context).padding.bottom +
                  _kActionBarHeight +
                  14,
              child: _WorkerPreviewCard(
                data: _selectedWorker!,
                km: _selectedKm,
                onClose: _clearSelection,
                onViewDetails: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorkerProfileScreen(
                      worker:
                          _workerMap(_selectedWorkerId ?? '', _selectedWorker!),
                    ),
                  ),
                ),
                onSendOffer: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => OfferSheet(
                    data: _selectedWorker!,
                    workerId: _selectedWorkerId ?? '',
                    distanceKm: _selectedKm,
                    // _meLat/_meLng = साँचो GPS स्थान (job हुने ठाउँ) —
                    // _lat/_lng त map pan गर्दा मात्र बदलिन्छ, त्यो होइन।
                    employerLat: _meLat,
                    employerLng: _meLng,
                  ),
                ),
              ),
            ),

          // ── Full-Screen Service Picker Overlay ── नक्सा (माथि) र
          // MainContainer को तल्लो ट्याब बार दुवै यो overlay ले नदेखाएसम्म
          // पर्दा पछाडि नै रहन्छन् (नक्सा धैरहन्छ/चलिरहन्छ, केवल पर्दामाथि
          // छोपिएको — तल्लो ट्याब बार भने MainContainer कै Scaffold मा
          // अलग्गै रहेकोले, यहाँबाट छुन मिल्दैन, तर यो overlay पूरै स्क्रिन
          // ओगट्ने भएकोले दृश्यात्मक रूपमा त्यही प्रभाव दिन्छ)। कुनै एउटा
          // सक्रिय सेवा कार्ड थिचेपछि मात्र (`_openService`/`_openHandymanCategories`
          // ले छुट्टै पूरा-स्क्रिन route खोल्छ, जसले यो overlay सहित
          // तल्लो ट्याब बार दुवै स्वतः छोप्छ) अघि बढिन्छ — पछाडि फर्किंदा
          // (pop) यही overlay नै फेरि देखिन्छ, किनभने यो homescreen को सधैँको
          // default/स्थिर अवस्था हो (कुनै toggle/close-button छैन)।
          //
          // नयाँ सक्रिय सेवा थप्न `activeServices` मा, र नयाँ "Coming Soon"
          // सेवा थप्न `comingSoonServices` मा एउटै थप entry मात्र पर्याप्त छ
          // — दुवै grid आफ्नै सूची अनुसार विस्तार हुन्छन्, कुनै नयाँ
          // layout/widget लेख्नु पर्दैन।
          Positioned.fill(
            child: _HomeServiceOverlay(
              // image_18.png कै ५ neon रङ: Bike=cyan, Car=blue, Auto=green,
              // Hotel=purple, Handyman=orange — यी सबै `serviceMarkerColor`
              // (nearby_common.dart) कै उस्तै brand रङ, नयाँ arbitrary
              // hex होइन।
              activeServices: [
                _HomeQuickService(
                    name: 'Bike',
                    icon: Icons.two_wheeler_rounded,
                    glow: const Color(0xFF00BCD4),
                    imageAsset: 'assets/images/home_bike.png',
                    onTap: () => _openService('Bike')),
                _HomeQuickService(
                    name: 'Car',
                    icon: Icons.directions_car_rounded,
                    glow: const Color(0xFF3B82F6),
                    imageAsset: 'assets/images/home_car.png',
                    imageFit: BoxFit.cover,
                    onTap: () => _openService('Car')),
                _HomeQuickService(
                    name: 'Auto',
                    icon: Icons.electric_rickshaw_rounded,
                    glow: const Color(0xFF2ED573),
                    imageAsset: 'assets/images/home_auto.png',
                    onTap: () => _openService('Auto')),
                _HomeQuickService(
                    name: 'Hotel Booking',
                    icon: Icons.hotel_rounded,
                    glow: AppColors.kmPurple,
                    imageAsset: 'assets/images/home_hotel.png',
                    onTap: _openHotelSearch),
                _HomeQuickService(
                    name: 'Handyman',
                    icon: Icons.handyman_rounded,
                    glow: AppColors.kmOrange,
                    imageAsset: 'assets/images/home_handyman.png',
                    onTap: _openHandymanCategories),
                // Salon & Beauty — "Sahyatri Salon" poster (assets/images/
                // home_salon.png, पोस्टरबाट वर्गाकार crop)। grid ३×२ भएकोले
                // यसले पहिले "+ More" (Coming Soon: Rental/City to City/
                // Parcel) को ठाउँ लिएको छ — ती आउँदा grid ३ पङ्क्तिमा
                // बढाउनुपर्छ (banner को उचाइ जाँचेर)।
                _HomeQuickService(
                    name: 'Salon & Beauty',
                    icon: Icons.content_cut_rounded,
                    glow: AppColors.kmPink,
                    imageAsset: 'assets/images/home_salon.png',
                    imageFit: BoxFit.cover,
                    onTap: _openSalonList),
              ],
            ),
          ),

          // ── Top bar (search + bell) — माथिको overlay भन्दा पनि माथि,
          // सधैँ छुन मिल्ने (drawer/notification कहिल्यै नछोपियोस् भनेर)।
          // image_18.png मा search bar + bell मात्र देखिन्छ (menu icon
          // छैन) — तर menu/drawer (City/Request history/Providers/...)
          // खोल्ने अर्को कुनै उपाय नभएकोले त्यो हटाउनु functionality
          // भाँच्नु हुन्थ्यो; त्यसैले सानो menu icon search bar को ठीक
          // अगाडि नै राखिएको — भिजुअल आशय (search prominent, bell दायाँ)
          // त्यही रहन्छ, navigation कहीं हराउँदैन।
          //
          // BUG FIX — यो header यो outer `Stack` को नै एकमात्र
          // non-`Positioned` direct child थियो (map/overlay दुवै
          // `Positioned`/`Positioned.fill` मै छन्)। `Stack` ले आफ्नो
          // `fit` नतोकिएमा (default `StackFit.loose`) आफ्नै साइज
          // non-positioned child बाट लिन्छ — त्यसैले पूरै Stack (र
          // त्यसभित्रको नक्सा/overlay दुवै) यही सानो header-matra-जति
          // (~90 logical px) मा खुम्चिएर grid/banner पूरै "disappear"
          // भएको देखिन्थ्यो (LayoutBuilder diagnostic ले यही पुष्टि
          // गर्‍यो)। अब `Positioned` मा बेरेर यसले Stack को size
          // निर्धारण नगरोस् भनेर।
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  _RoundBtn(
                    icon: Icons.menu_rounded,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SpringTap(
                      onTap: _openGlobalSearch,
                      pressedScale: 0.97,
                      child: RepaintBoundary(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: glassBackdrop(sigma: 16, child: Container(
                              height: 46,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.kmGlass2Fill,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: AppColors.kmGlass2Border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.search_rounded,
                                      size: 19, color: AppColors.kmMuted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(S.homeSearchHint,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.kmMuted,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RoundBtn(
                    icon: Icons.notifications_none_rounded,
                    dot: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationScreen()),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// घर-पेजको पूरा-स्क्रिन सेवा-छनोट overlay — नक्सा/तल्लो ट्याब बार दुवैलाई
/// छोप्ने यही एउटै स्थिर तह (माथि `build()` मा z-order हेर्नुहोस्)। "सुपर
/// एप" संरचना: (१) सक्रिय सेवाको मुख्य grid, (२) बीचमा promo banner, (३)
/// तल "Coming Soon" सेवाहरू — सबै सूची-driven भएकोले भविष्यमा थप सेवा
/// (सक्रिय वा आउँदो दुवै) थप्न यहाँ कुनै नयाँ widget/layout लेख्नु पर्दैन,
/// `HomeScreen.build()` मा एउटै थप entry मात्र पुग्छ।
class _HomeQuickService {
  final String name;
  final IconData icon;
  final Color glow;
  final VoidCallback onTap;
  // Full-Bleed Illustration Override — दिइएमा `_NeonServiceTile` ले
  // साधारण glyph+glass-panel शैलीको सट्टा यही तस्बिर पूरै tile भरिने गरी
  // देखाउँछ (Bike/Car/Auto-मात्र, हाल)। `null` भए (Hotel/Handyman/More)
  // पुरानै glyph शैली अपरिवर्तित।
  final String? imageAsset;
  final BoxFit imageFit;
  const _HomeQuickService({
    required this.name,
    required this.icon,
    required this.glow,
    required this.onTap,
    this.imageAsset,
    this.imageFit = BoxFit.contain,
  });
}

class _HomeServiceOverlay extends StatelessWidget {
  final List<_HomeQuickService> activeServices;
  const _HomeServiceOverlay({
    required this.activeServices,
  });

  @override
  Widget build(BuildContext context) {
    // image_18.png कै निरन्तर गहिरो बैजनी gradient — माथि बीचतिर हल्का
    // बैजनी glow, तल/किनारातिर झन्डै कालो। पहिले यहाँ साधारण `DecoratedBox`
    // प्रयोग हुन्थ्यो — त्यसले `Positioned.fill` बाट आउने tight constraint
    // सिधै `SafeArea`/content मा pass-through गर्छ भन्ने अनुमान गरिएको
    // थियो, तर व्यवहारमा grid/banner पूरै खाली/कालो देखिने गरायो (content
    // नै render नभएको जस्तो — screenshot/uiautomator दुवैले पुष्टि गरे)।
    // `AuroraBackground` भने `Stack(fit: StackFit.expand)` प्रयोग गरेर
    // आफ्नो child लाई जबरजस्ती पूरै स्क्रिन साइजमा तन्काउँछ — यही app भरि
    // (home screen आफैंले अघि पनि) प्रमाणित/काम गरिरहेको बाटो, त्यसैले अब
    // त्यही पुनः प्रयोग गरेर मात्र रङ/grid अनुकूलित गरिएको।
    return AuroraBackground(
      grid: false,
      orbs: const [
        KmOrb(Alignment.topLeft, Color(0xFF6B3FD4), size: 560),
        KmOrb(Alignment.topRight, Color(0xFF6B3FD4), size: 560),
      ],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 76, 20, 20),
          // Bottom Tiles Removed — "Coming Soon" (Rental/City to City/Parcel)
          // हटाइएपछि फुर्सद भएको ठाउँ `_PremiumBanner` ले नै (Expanded)
          // तल bottom-nav सम्मै भरोस् भनेर — अब यो `SingleChildScrollView`
          // होइन, स्थिर `Column`: grid (intrinsic height) + banner
          // (बाँकी सबै जति ठाउँ)। grid + banner दुवैको content सानो/
          // सीमित भएकोले (coming-soon हटेपछि) कुनै सामान्य फोनमा overflow
          // हुँदैन।
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.count(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
                children: [
                  for (final s in activeServices)
                    _NeonServiceTile(
                      label: S.serviceName(s.name),
                      icon: s.icon,
                      glow: s.glow,
                      onTap: s.onTap,
                      imageAsset: s.imageAsset,
                      imageFit: s.imageFit,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              // नोट: `const` राख्नु हुँदैन — `S.*` (locale) मा निर्भर भएकोले,
              // भाषा बदलिँदा यो subtree पनि पुनः-build हुनैपर्छ। `const` ले
              // Dart-कै canonicalization/identical() शर्टकटका कारण build()
              // फेरि कहिल्यै नचल्ने (पहिलोपटक भाषा जे थियो त्यहीं "अड्किने")
              // बग निम्त्याउँछ।
              // ignore: prefer_const_constructors
              Expanded(child: _PremiumBanner()),
            ],
          ),
        ),
      ),
    );
  }
}

/// नयाँ premium grid tile — neon-glow रेखाचित्र शैली। कुनै फोटो/illustration
/// होइन, `glow` रङमै outline icon + border + glow shadow। `glow == null`
/// भएमा ("+ More") बेग्लै muted/gray शैली (image_18.png कै "+" tile जस्तै)।
///
/// Full-Bleed Illustration Variant — `imageAsset` दिइएमा (हाल Bike/Car/Auto/
/// Hotel Booking/Handyman — सबै ५ मुख्य सेवा) माथिकै glyph+glass-panel
/// छोडेर illustration आफैं tile भरि (frame भित्रै, border/glow भने उस्तै
/// brand रङमा कायम राखेर अरू tile सँग दृश्यात्मक तालमेल मिलोस् भनेर)
/// देखाउँछ। "+ More" (imageAsset == null, एकमात्र बाँकी) मा पुरानै
/// glyph शैली अपरिवर्तित।
class _NeonServiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? glow;
  final VoidCallback onTap;
  final String? imageAsset;
  final BoxFit imageFit;
  const _NeonServiceTile({
    required this.label,
    required this.icon,
    required this.glow,
    required this.onTap,
    this.imageAsset,
    this.imageFit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final color = glow ?? AppColors.kmMuted;
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.95,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: imageAsset != null
                  ? _buildImageTile(color)
                  : _buildGlyphTile(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.kmText)),
        ],
      ),
    );
  }

  Widget _buildGlyphTile(Color color) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: color.withValues(alpha: glow == null ? 0.3 : 0.8),
              width: 1.4),
          boxShadow: glow == null
              ? null
              : [
                  BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 0.5),
                ],
        ),
        child: Icon(icon, color: color, size: 30),
      );

  Widget _buildImageTile(Color color) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: 0.5),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              border: Border.all(color: color.withValues(alpha: 0.7), width: 1.4),
            ),
            child: Image.asset(imageAsset!, fit: imageFit),
          ),
        ),
      );
}

/// Neon glass promo banner — top dashboard tile (`_NeonServiceTile`) कै
/// उस्तै cyan/blue glow-border भाषा। ठूलो/crisp SY logo + ३ वटा सक्रिय
/// feature-tag chip (Instant Rides/Verified Hotels/Local Handymen —
/// Hotel/Rental/Parcel जस्ता अझै नआएका कुरा यहाँ छैनन्)। "Coming Soon"
/// section हटाइसकेपछि फुर्सद भएको ठाउँ यही card ले (caller मा `Expanded`
/// भित्र राखिएर) तल bottom-nav सम्मै भर्छ — `Spacer()` ले तल सामाजिक-
/// सञ्जाल बटन (`_SocialLinksSection`) लाई card कै पिँधमा टाँस्छ।
class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner();

  Widget _tag(Color dot, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: glassBackdrop(sigma: 22, child: Container(
          // Social-Icon-Row Overflow Fix — यो card कै fixed/bounded उचाइ
          // (parent Expanded) पहिले `_SocialLinksSection` सधैं खाली
          // (SizedBox.shrink, कुनै URL सेट नभएको) हुँदा मात्र ठीक्क
          // अट्थ्यो। अब साँचो icon row देखिनेबित्तिकै (admin ले URL सेटेपछि)
          // "BOTTOM OVERFLOWED" हुन्थ्यो — त्यसैले यहाँभित्रका padding/gap/
          // आकार अलिकति कसिएको, logo/branding भने दृश्यगत रूपमा उस्तै नै
          // रहन्छ, बस अलि सानो।
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.kmTealBlue.withValues(alpha: 0.18),
                AppColors.kmTeal.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppColors.kmTealBlue.withValues(alpha: 0.55), width: 1.4),
            boxShadow: [
              BoxShadow(
                  color: AppColors.kmTealBlue.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: 1),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Text(S.homeBannerBrandLabel,
                          style: const TextStyle(
                              color: AppColors.kmMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Container(
                        width: 84,
                        height: 84,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.kmTealBlue.withValues(alpha: 0.6),
                              width: 1.2),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.kmTealBlue.withValues(alpha: 0.4),
                                blurRadius: 14,
                                spreadRadius: 0.5),
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Image.asset(
                          'assets/icon/app_icon_foreground.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.workspace_premium_rounded,
                              color: AppColors.kmOrangeDeep,
                              size: 40),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      // Logo-matching purple→coral brand gradient — `srcIn`
                      // tints the text glyphs' alpha with the shader, so the
                      // underlying TextStyle colour below just needs to be
                      // fully opaque (white) for the gradient to show true.
                      child: ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.kmPurple, AppColors.kmOrangeDeep],
                        ).createShader(bounds),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontFamily: 'Cinzel',
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                height: 1.3),
                            children: [
                              TextSpan(text: '${S.homeBannerTitlePrefix} '),
                              TextSpan(text: S.homeBannerTitleRest),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _tag(AppColors.kmTeal, S.homeTagInstantRides),
                  _tag(AppColors.kmPurple, S.homeTagVerifiedHotels),
                  _tag(AppColors.kmOrange, S.homeTagLocalHandymen),
                ],
              ),
              const Spacer(),
              // ignore: prefer_const_constructors
              _SocialLinksSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Facebook/Instagram/TikTok/X बटन (माथि divider सहित) — `config/socialLinks`
/// (`SocialLinksConfig`, config/app_config.dart) बाट live पढ्छ; URL
/// खाली/नसेट भएको प्लेटफर्म देखिँदैन, र कुनै पनि URL नभए (admin ले अझै
/// नसेट गरेको) divider+row दुवै सँगै लुक्छन् — banner को तल्लो किनारामा
/// नीरस/खाली divider रेखा मात्र बाँकी नरहोस् भनेर।
class _SocialLinksSection extends StatelessWidget {
  const _SocialLinksSection();

  static const _platforms = [
    _SocialPlatform(key: 'facebook', color: Color(0xFF1877F2)),
    _SocialPlatform(key: 'instagram', color: Color(0xFFE1306C)),
    _SocialPlatform(key: 'tiktok', color: Color(0xFF25F4EE)),
    _SocialPlatform(key: 'twitter', color: Colors.white),
  ];

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>>(
      stream: SocialLinksConfig.stream(),
      builder: (context, snap) {
        final links = snap.data;
        if (links == null) return const SizedBox.shrink();
        final visible =
            _platforms.where((p) => (links[p.key] ?? '').isNotEmpty).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final p in visible) ...[
                  _SocialIconButton(
                    platformKey: p.key,
                    color: p.color,
                    onTap: () => _open(context, links[p.key]!),
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SocialPlatform {
  final String key;
  final Color color;
  const _SocialPlatform({required this.key, required this.color});
}

class _SocialIconButton extends StatelessWidget {
  final String platformKey;
  final Color color;
  final VoidCallback onTap;
  const _SocialIconButton(
      {required this.platformKey, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 10,
                spreadRadius: 0.5),
          ],
        ),
        child: _BrandGlyph(platformKey: platformKey, color: color, size: 18),
      ),
    );
  }
}

/// Real vector brand marks — no new package dependency (pubspec.yaml stays
/// untouched), built purely from Flutter primitives (Icon/Container/
/// Transform.rotate), so they scale cleanly at any size like a true SVG.
/// Facebook uses Flutter's own bundled `Icons.facebook` glyph; Instagram/
/// TikTok/X are composed from simple shapes that closely mirror each
/// platform's official mark silhouette.
class _BrandGlyph extends StatelessWidget {
  final String platformKey;
  final Color color;
  final double size;
  const _BrandGlyph(
      {required this.platformKey, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    switch (platformKey) {
      case 'facebook':
        return Icon(Icons.facebook, color: color, size: size + 4);
      case 'instagram':
        return _instagramMark();
      case 'tiktok':
        return _tiktokMark();
      case 'twitter':
        return _xMark();
      default:
        return SizedBox(width: size, height: size);
    }
  }

  // Rounded-square camera outline + lens circle + flash dot — Instagram's
  // classic simplified glyph.
  Widget _instagramMark() => SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.32),
                border: Border.all(color: color, width: size * 0.11),
              ),
            ),
            Center(
              child: Container(
                width: size * 0.46,
                height: size * 0.46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: size * 0.11),
                ),
              ),
            ),
            Positioned(
              top: size * 0.14,
              right: size * 0.14,
              child: Container(
                width: size * 0.12,
                height: size * 0.12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      );

  // TikTok's real note-mark silhouette — notehead + stem + curling flag
  // unioned into ONE solid vector path (not stacked primitives), painted
  // twice with the brand's signature cyan/red offset ("glitch") accent
  // behind a crisp white/teal top layer, same as the official mark.
  Widget _tiktokMark() => CustomPaint(
        size: Size(size, size),
        painter: _TikTokNotePainter(primary: color),
      );

  // Two bold crossing diagonal bars — X's geometric wordmark.
  Widget _xMark() => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: 0.7853981634, // 45°
              child: Container(
                  width: size * 0.95,
                  height: size * 0.17,
                  color: color),
            ),
            Transform.rotate(
              angle: -0.7853981634, // -45°
              child: Container(
                  width: size * 0.95,
                  height: size * 0.17,
                  color: color),
            ),
          ],
        ),
      );
}

/// एउटै solid Path (notehead + stem + curling flag, `Path.combine` ले
/// fuse गरिएको — छुट्टाछुट्टै आकृति होइन) दुईपटक, TikTok कै साँचो cyan/red
/// दुई-रङ "glitch" offset सहित — `_BrandGlyph._tiktokMark()` ले प्रयोग गर्छ।
class _TikTokNotePainter extends CustomPainter {
  final Color primary;
  static const _cyan = Color(0xFF25F4EE);
  static const _red = Color(0xFFFE2C55);

  const _TikTokNotePainter({required this.primary});

  Path _notePath(Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(w * 0.35, h * 0.76), width: w * 0.56, height: h * 0.42))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.55, h * 0.06, w * 0.74, h * 0.80),
        Radius.circular(w * 0.09),
      ));
    final flag = Path()
      ..moveTo(w * 0.74, h * 0.06)
      ..cubicTo(w * 0.92, h * 0.06, w * 0.98, h * 0.18, w * 0.92, h * 0.30)
      ..cubicTo(w * 0.87, h * 0.38, w * 0.78, h * 0.38, w * 0.70, h * 0.32)
      ..lineTo(w * 0.70, h * 0.20)
      ..cubicTo(w * 0.75, h * 0.24, w * 0.84, h * 0.22, w * 0.86, h * 0.17)
      ..cubicTo(w * 0.88, h * 0.11, w * 0.82, h * 0.07, w * 0.74, h * 0.07)
      ..close();
    return Path.combine(PathOperation.union, body, flag);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final note = _notePath(size);
    final dx = size.width * 0.05;
    final dy = size.height * 0.035;

    canvas.save();
    canvas.translate(-dx, dy);
    canvas.drawPath(note, Paint()..color = _cyan.withValues(alpha: 0.9));
    canvas.restore();

    canvas.save();
    canvas.translate(dx, -dy);
    canvas.drawPath(note, Paint()..color = _red.withValues(alpha: 0.75));
    canvas.restore();

    canvas.drawPath(note, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(covariant _TikTokNotePainter oldDelegate) =>
      oldDelegate.primary != primary;
}

/// नक्साको custom marker थिच्दा देखिने preview card — avatar glyph, नाम, rating,
/// दूरी + "Offer पठाउनुहोस्" / "विवरण हेर्नुहोस्" बटन। तल-बाट slide-in।
class _WorkerPreviewCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final double km;
  final VoidCallback onClose;
  final VoidCallback onViewDetails;
  final VoidCallback onSendOffer;

  const _WorkerPreviewCard({
    required this.data,
    required this.km,
    required this.onClose,
    required this.onViewDetails,
    required this.onSendOffer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = (data['service'] ?? '').toString();
    final name = (data['name'] ?? '—').toString();
    final uid = (data['uid'] ?? '').toString();
    final color = serviceMarkerColor(service);

    return TweenAnimationBuilder<double>(
      key: ValueKey(name + service),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ServiceIconBadge(
                  service: service,
                  size: 46,
                  iconColor: Colors.white,
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(color, Colors.white, 0.35)!,
                      color,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15.5)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${S.serviceName(service)}  ·  ${S.distanceLabel(km)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (uid.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        WorkerRatingBadge(uid: uid, compact: true),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewDetails,
                    icon: const Icon(Icons.person_rounded, size: 16),
                    label: Text(S.viewDetails,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientActionButton(
                    icon: Icons.local_offer_rounded,
                    label: S.sendOffer,
                    expand: true,
                    onPressed: onSendOffer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pin Drop — स्क्रिनको बीचमा स्थिर झन्डा, touch-lift/nail-drop animation
/// सहित (service_map_screen.dart कै उही भिजुअल, यहाँ browse-only प्रयोग)।
class _BrowsePinIcon extends StatelessWidget {
  final Uint8List bytes;
  final AnimationController liftCtrl;
  const _BrowsePinIcon({required this.bytes, required this.liftCtrl});

  @override
  Widget build(BuildContext context) {
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
      child: AnimatedBuilder(
        animation: liftCtrl,
        child: Image.memory(bytes, height: displayHeight),
        builder: (context, child) {
          final t = liftCtrl.value;
          return Transform.translate(
            offset: Offset(0, -14 * t),
            child: Transform.scale(scale: 1.0 + 0.08 * t, child: child),
          );
        },
      ),
    );
  }
}

/// Pin Drop — बीचको झन्डाले छोपेको ठाउँको ठेगाना (browse-only, booking
/// स्थान बदल्दैन) — सानो/compact dark-glass pill (service_map_screen.dart
/// कै `_PinAddressCard` सँगै उही आकार/शैली), पूरै स्क्रिन-चौडाइ कहिल्यै
/// नओगट्ने गरी `maxWidth` ले सीमित।
class _BrowseAddressCard extends StatelessWidget {
  final String address;
  final bool loading;
  const _BrowseAddressCard({required this.address, required this.loading});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
        decoration: BoxDecoration(
          color: AppColors.kmVoid2.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_rounded,
                size: 15, color: AppColors.kmOrange),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                loading
                    ? S.fetchingAddress
                    : (address.isEmpty ? S.moveMapHint : address),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.25),
              ),
            ),
            if (loading) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.kmOrange),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  const _RoundBtn({required this.icon, required this.onTap, this.dot = false});

  @override
  Widget build(BuildContext context) {
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.85,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // यो बटन नक्साको माथि tair-रहेको हुन्छ — blur (BackdropFilter)
          // लाई RepaintBoundary ले नक्सा pan/pin-lift/sheet-drag जस्ता
          // छेउछाउका ऐनिमेसनबाट isolate गर्छ, हरेक frame फेरि नदोहोरियोस्।
          RepaintBoundary(
            child: ClipOval(
              child: glassBackdrop(sigma: 16, child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.kmGlass2Fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.kmGlass2Border),
                  ),
                  child: Icon(icon, size: 22, color: AppColors.kmText),
                ),
              ),
            ),
          ),
          if (dot)
            const Positioned(
              right: 3,
              top: 3,
              child: CircleAvatar(
                  radius: 5, backgroundColor: AppColors.kmPink),
            ),
        ],
      ),
    );
  }
}

/// Global Search — सेवा (Bike/Car/Auto/Hotel/Handyman/Plumber/...), सेभ
/// गरिएका ठेगाना (Home/Work/अन्य), र app settings/navigation link (Profile/
/// Earnings/Security/Language/...) तीनै एकै ठाउँबाट खोज्ने। टाइप गर्नेबित्तिकै
/// तीनै category आफ्नो-आफ्नो section मा (matching भए मात्र) देखिन्छन् —
/// सेवा-सूची मात्र खाली query मा पनि (पुरानै व्यवहार, पूरै सेवा-ग्रिड) देखिने।
class _SearchSheet extends StatefulWidget {
  final void Function(String serviceName) onPickService;
  final VoidCallback onPickHotel;
  final VoidCallback onPickHandyman;
  final VoidCallback onPickSalon;
  const _SearchSheet({
    required this.onPickService,
    required this.onPickHotel,
    required this.onPickHandyman,
    required this.onPickSalon,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

/// App settings/navigation link — ठेगाना (Places) बाहेक बाँकी सबै static,
/// गन्तव्य screen आफैं state-स्वतन्त्र भएकोले सिधै यहीँबाट push गर्न मिल्छ।
class _NavSearchEntry {
  final String label;
  final IconData icon;

  /// नाम बाहेक थप खोज्न मिल्ने शब्द (synonym) — lowercase, space-separated।
  final String keywords;
  final void Function(BuildContext context) onTap;
  const _NavSearchEntry(this.label, this.icon, this.keywords, this.onTap);
}

final List<_NavSearchEntry> _navSearchEntries = [
  _NavSearchEntry('Profile', Icons.person_rounded, 'account my profile', (ctx) {
    // Profile MainContainer कै tab हो (छुट्टै पेज होइन) — त्यही tab मा
    // फर्काउने (job_feed_screen.dart कै DashboardExitBar सँगै प्रयोग हुने
    // साझा global, app_globals.dart हेर्नुहोस्)।
    requestedMainTabIndex.value = 4;
    Navigator.of(ctx).popUntil((r) => r.isFirst);
  }),
  _NavSearchEntry(
      'Earnings', Icons.account_balance_wallet_rounded, 'wallet income payouts money',
      (ctx) => Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const EarningsScreen()))),
  _NavSearchEntry(
      'Security', Icons.lock_rounded, 'biometric passkey fingerprint lock',
      (ctx) => Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const SettingsPage()))),
  _NavSearchEntry(
      'Language', Icons.language_rounded, 'nepali english bhasa', (ctx) =>
          Navigator.push(
              ctx, MaterialPageRoute(builder: (_) => const SettingsPage()))),
  _NavSearchEntry('Settings', Icons.settings_rounded, 'preferences', (ctx) =>
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const SettingsPage()))),
  _NavSearchEntry(
      'My Bookings', Icons.history_rounded, 'booking history requests orders',
      (ctx) => Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const BookingsScreen()))),
  _NavSearchEntry('Messages', Icons.message_rounded, 'chat inbox', (ctx) =>
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const MessagesScreen()))),
  _NavSearchEntry('Payment Methods', Icons.payment_rounded,
      'card wallet khalti esewa', (ctx) => Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()))),
  _NavSearchEntry(
      'My Reviews', Icons.star_border_rounded, 'ratings feedback', (ctx) =>
          Navigator.push(
              ctx, MaterialPageRoute(builder: (_) => const MyReviewsScreen()))),
  _NavSearchEntry(
      'Notifications', Icons.notifications_none_rounded, 'alerts', (ctx) =>
          Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => const NotificationScreen()))),
  _NavSearchEntry('Help & Support', Icons.help_outline_rounded,
      'contact faq support', (ctx) => Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const HelpSupportScreen()))),
  _NavSearchEntry('Saved Places', Icons.place_rounded,
      'home work address location manage', (ctx) => Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const SavedPlacesScreen()))),
];

class _SearchSheetState extends State<_SearchSheet> {
  final _c = TextEditingController();
  String _q = '';

  // सेवा-सूची — serviceFilters (Mechanic/Plumber/Electrician/.../Tutor) कै
  // trade हरू + Bike/Car/Auto/Hotel Booking/Handyman (यी serviceFilters मा
  // छैनन्, home screen कै मुख्य 3x2 grid बाट) सबै एकै search index मा।
  late final List<({String label, IconData icon, String image, VoidCallback onTap})>
      _serviceEntries = [
    (
      label: 'Bike',
      icon: Icons.two_wheeler_rounded,
      image: serviceImageFor('Bike'),
      onTap: () => widget.onPickService('Bike'),
    ),
    (
      label: 'Car',
      icon: Icons.directions_car_rounded,
      image: serviceImageFor('Car'),
      onTap: () => widget.onPickService('Car'),
    ),
    (
      label: 'Auto',
      icon: Icons.electric_rickshaw_rounded,
      image: serviceImageFor('Car'),
      onTap: () => widget.onPickService('Auto'),
    ),
    (
      label: 'Hotel Booking',
      icon: Icons.hotel_rounded,
      image: serviceImageFor('Handyman'),
      onTap: widget.onPickHotel,
    ),
    (
      label: 'Handyman',
      icon: Icons.handyman_rounded,
      image: serviceImageFor('Handyman'),
      onTap: widget.onPickHandyman,
    ),
    (
      label: 'Salon & Beauty',
      icon: Icons.content_cut_rounded,
      image: serviceImageFor('Handyman'),
      onTap: widget.onPickSalon,
    ),
    for (final s in serviceFilters)
      (
        label: s['name'] as String,
        icon: s['icon'] as IconData,
        image: serviceImageFor(s['name'] as String),
        onTap: () => widget.onPickService(s['name'] as String),
      ),
  ];

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid ?? '__none__')
          .snapshots();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<({String label, String address})> _places(Map<String, dynamic> data) {
    final out = <({String label, String address})>[];
    final home = data['homePlace'];
    if (home is Map && (home['address'] ?? '').toString().isNotEmpty) {
      out.add((label: 'Home', address: home['address'].toString()));
    }
    final work = data['workPlace'];
    if (work is Map && (work['address'] ?? '').toString().isNotEmpty) {
      out.add((label: 'Work', address: work['address'].toString()));
    }
    final others = data['otherPlaces'];
    if (others is List) {
      for (final o in others) {
        if (o is Map && (o['address'] ?? '').toString().isNotEmpty) {
          out.add((
            label: (o['label'] ?? 'Place').toString(),
            address: o['address'].toString(),
          ));
        }
      }
    }
    return out;
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.4)),
      );

  Widget _resultTile({
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: leading,
            title: Text(title,
                style: const TextStyle(
                    color: AppColors.kmText, fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.kmMuted)),
            onTap: onTap,
          ),
        ),
      );

  Widget _iconLeading(IconData icon, {String? image}) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Image.asset(image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(icon, color: AppColors.kmOrange, size: 20))
            : Icon(icon, color: AppColors.kmOrange, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();

    final serviceResults = _serviceEntries.where((s) {
      final n = s.label.toLowerCase();
      final np = S.serviceName(s.label).toLowerCase();
      return q.isEmpty || n.contains(q) || np.contains(q);
    }).toList();

    // किबोर्ड खुल्दा (विशेष गरी सानो फोन/landscape मा) search box + ८ वटै
    // category row जोड्दा उपलब्ध उचाइभन्दा बढी हुन सक्छ — Column ले आफैं
    // खुम्च्याउन नसक्ने भएकोले अघि यहाँ RenderFlex bottom-overflow आउँथ्यो।
    // अब सिट कहिल्यै स्क्रिनको उचाइ (किबोर्ड घटाएर) भन्दा बढी नबढ्ने गरी
    // बाँधिएको छ, र भित्र बढी परे स्क्रोल हुन्छ, overflow कहिल्यै हुँदैन।
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.9 -
        MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: maxSheetHeight.clamp(200, double.infinity)),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: glassBackdrop(sigma: 26, child: Container(
              decoration: BoxDecoration(
                color: AppColors.kmSurface.withValues(alpha: 0.94),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userDocStream,
                builder: (context, snap) {
                  final data = snap.data?.data() ?? const {};
                  final placeResults = q.isEmpty
                      ? const <({String label, String address})>[]
                      : _places(data)
                          .where((p) =>
                              p.label.toLowerCase().contains(q) ||
                              p.address.toLowerCase().contains(q))
                          .toList();
                  final navResults = q.isEmpty
                      ? const <_NavSearchEntry>[]
                      : _navSearchEntries
                          .where((e) =>
                              e.label.toLowerCase().contains(q) ||
                              e.keywords.contains(q))
                          .toList();

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        TextField(
                          controller: _c,
                          autofocus: true,
                          style: const TextStyle(color: AppColors.kmText),
                          onChanged: (v) => setState(() => _q = v),
                          decoration: InputDecoration(
                            hintText: S.searchHint,
                            hintStyle:
                                const TextStyle(color: AppColors.kmMuted),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppColors.kmOrange),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.14)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(16)),
                              borderSide: BorderSide(
                                  color: AppColors.kmOrange, width: 1.4),
                            ),
                          ),
                        ),
                        if (q.isNotEmpty &&
                            serviceResults.isEmpty &&
                            placeResults.isEmpty &&
                            navResults.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('No results found',
                                  style: TextStyle(color: AppColors.kmMuted)),
                            ),
                          ),
                        if (serviceResults.isNotEmpty) ...[
                          _sectionHeader('Services'),
                          ...serviceResults.map((s) => _resultTile(
                                leading: _iconLeading(s.icon, image: s.image),
                                title: S.serviceName(s.label),
                                subtitle: s.label,
                                onTap: s.onTap,
                              )),
                        ],
                        if (placeResults.isNotEmpty) ...[
                          _sectionHeader(S.savedPlacesTitle),
                          ...placeResults.map((p) => _resultTile(
                                leading:
                                    _iconLeading(Icons.place_rounded),
                                title: p.label,
                                subtitle: p.address,
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const SavedPlacesScreen()),
                                  );
                                },
                              )),
                        ],
                        if (navResults.isNotEmpty) ...[
                          _sectionHeader(S.settings),
                          ...navResults.map((e) => _resultTile(
                                leading: _iconLeading(e.icon),
                                title: e.label,
                                subtitle: e.keywords,
                                onTap: () {
                                  Navigator.pop(context);
                                  e.onTap(context);
                                },
                              )),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final isOwner = user?.email == kAdminEmail;

    // Drawer बाट खोलिएको जुनसुकै sub-screen (City, Bookings, Settings,
    // Help & Support, आदि) बाट back थिच्दा सिधै "खाली" नक्सामा नखसेर, फेरि
    // यही menu (Drawer) मा नै फर्कियोस् भनेर — pop गर्नुअघि यो Home Scaffold
    // को ScaffoldState समातेर राख्ने, अनि pushed page pop भएपछि (Future
    // complete हुँदा) त्यही Drawer फेरि खोल्ने। यसरी "sub-menu बाट back ->
    // सिधै home map मा पुग्ने" गुनासो हट्छ — प्रयोगकर्ताले सधैं अघिल्लो
    // menu मै फर्किएको महसुस गर्छन्, नक्सा होइन।
    void go(Widget page) {
      final scaffold = Scaffold.of(context);
      scaffold.closeDrawer();
      Navigator.push(context, MaterialPageRoute(builder: (_) => page))
          .then((_) {
        if (scaffold.mounted) scaffold.openDrawer();
      });
    }

    // गाढा glass menu item row (मोकअप कै `.mi`)।
    Widget item(IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 18, color: AppColors.kmLilac),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w500,
                              fontSize: 14.5)),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.kmMuted, size: 17),
                  ],
                ),
              ),
            ),
          ),
        );

    return Drawer(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(34)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(decoration: BoxDecoration(color: AppColors.kmVoid)),
          Positioned(
            right: -140,
            top: 120,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.kmOrangeDeep.withValues(alpha: 0.34),
                    AppColors.kmOrangeDeep.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: uid == null
                  ? null
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final name = (data['name'] ??
                        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
                    .toString()
                    .trim();
                final role = (data['role'] ?? '').toString();
                final isWorker = role == 'worker';
                final selfieUrl = (data['selfieUrl'] ?? '').toString();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(colors: [
                                AppColors.kmOrange,
                                AppColors.kmPink,
                                AppColors.kmPurple,
                                AppColors.kmTeal,
                                AppColors.kmOrange,
                              ]),
                            ),
                            child: ClipOval(
                              child: Container(
                                color: AppColors.kmSurface,
                                child: selfieUrl.isEmpty
                                    ? const Icon(Icons.person_rounded,
                                        color: AppColors.kmLilac, size: 28)
                                    : Image.network(
                                        selfieUrl,
                                        key: ValueKey(selfieUrl),
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.person_rounded,
                                                color: AppColors.kmLilac,
                                                size: 28),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isEmpty ? 'सहयात्री' : name,
                                    style: const TextStyle(
                                        color: AppColors.kmText,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                const Row(
                                  children: [
                                    Icon(Icons.star_rounded,
                                        size: 15, color: AppColors.kmOrange),
                                    SizedBox(width: 4),
                                    Text('5.0',
                                        style: TextStyle(
                                            color: AppColors.kmOrange,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x1AFFFFFF), height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          // Owner-only: Admin Dashboard entry — अब सिधै
                          // comprehensive Multi-Role Dashboard (Driver/
                          // Worker-Handyman/Hotel tabs) मा, पहिले संकुचित
                          // worker-मात्र OwnerDashboardScreen मा गइरहेको थियो।
                          if (isOwner) ...[
                            item(
                                Icons.admin_panel_settings_rounded,
                                'Admin Dashboard',
                                () => go(const AdminDashboardScreen())),
                            item(
                                Icons.verified_rounded,
                                'Hotel Verification',
                                () => go(const HotelVerificationAdminScreen())),
                          ],
                          item(Icons.location_city_rounded, S.menuCity,
                              () => go(const SavedPlacesScreen())),
                          item(Icons.history_rounded, S.menuRequestHistory,
                              () => go(const BookingsScreen())),
                          item(Icons.groups_rounded, S.menuProviders,
                              () => go(const NearbyScreen())),
                          item(Icons.bookmark_border_rounded, S.savedWorkers,
                              () => go(const WatchlistScreen())),
                          item(Icons.place_rounded, S.savedPlacesTitle,
                              () => go(const SavedPlacesScreen())),
                          item(
                              Icons.notifications_none_rounded,
                              S.menuNotifications,
                              () => go(const NotificationScreen())),
                          item(Icons.star_border_rounded, S.myReviews,
                              () => go(const MyReviewsScreen())),
                          item(Icons.payment_rounded, S.paymentMethods,
                              () => go(const PaymentMethodsScreen())),
                          item(Icons.message_rounded, S.messages,
                              () => go(const MessagesScreen())),
                          item(Icons.settings_rounded, S.settings,
                              () => go(const SettingsPage())),
                          item(Icons.help_outline_rounded, S.helpSupport,
                              () => go(const HelpSupportScreen())),
                          item(Icons.support_agent_rounded, S.menuSupport,
                              () => go(const HelpSupportScreen())),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                      child: KmCtaButton(
                        icon: Icons.workspace_premium_rounded,
                        label: isWorker ? S.providerMode : S.becomeProvider,
                        height: 54,
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => isWorker
                                  ? const NearbyScreen()
                                  : const WorkerRegistrationPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
