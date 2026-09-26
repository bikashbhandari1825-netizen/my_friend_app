// screens/home_screen.dart
// inDrive-style map home: full-screen Google Map + sliding drawer + region
// status banner + bottom search + horizontal service-category selector।
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

import '../config/app_config.dart' show kAdminEmail;
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
import 'help_support_screen.dart';
import 'messages_screen.dart';
import 'my_reviews_screen.dart';
import 'nearby_common.dart';
import 'nearby_screen.dart';
import 'notification_screen.dart';
import 'owner_dashboard_screen.dart';
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
      FirebaseFirestore.instance.collection('registeredWorkers').snapshots();

  // तल्लो शीट release पछि नजिकको snap मा सहज रूपमा पुर्‍याउने animation।
  late final AnimationController _sheetCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(() {
      final t = Curves.easeOutCubic.transform(_sheetCtrl.value);
      _sheetExtent.value = _sheetFrom + (_sheetTarget - _sheetFrom) * t;
    });
  double _sheetFrom = _sheetInitial;
  double _sheetTarget = _sheetInitial;

  double _lat = fallbackLat;
  double _lng = fallbackLng;
  double _originLat = fallbackLat;
  double _originLng = fallbackLng;
  // प्रयोगकर्ताको वास्तविक GPS स्थान (camera सर्दा नबदलिने) — custom user pin।
  double _meLat = fallbackLat;
  double _meLng = fallbackLng;
  bool _locReady = false;
  bool _locating = false;
  // category chip थिच्दा अब सिधै `NearbyScreen` खुल्ने भएकोले (माथि
  // `_openCategory` हेर्नुहोस्) यो home screen कै आफ्नै नक्सा-फिल्टर अब
  // कहिल्यै बदलिँदैन — सधैँ 'सबै' (unfiltered) नै रहन्छ।
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

  void _scheduleBrowseGeocode() {
    _browseAddrDebounce?.cancel();
    _browseAddrDebounce =
        Timer(const Duration(milliseconds: 400), _reverseGeocodeBrowsePin);
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

  // ड्र्यागेबल तल्लो प्यानलको अहिलेको उचाइ (screen अनुपात) — floating button
  // सधैँ प्यानलभन्दा माथि राख्न।
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(0.36);
  static const double _sheetInitial = 0.36;
  static const double _sheetMin = 0.16;
  static const double _sheetMax = 0.82;

  // Ride hero card को अनुमानित उचाइ — "मेरो स्थान" बटनलाई त्यसमाथि नै
  // राख्न (माथि हेर्नुहोस्)। card कै content स्थिर (कहिल्यै dynamic worker
  // list जस्तो नबढ्ने) भएकोले fixed constant नै पर्याप्त — GlobalKey
  // measurement (service_map_screen.dart मा पहिले भएको जस्तो lag) चाहिँदैन।
  static const double _kRideHeroCardHeight = 132.0;

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
    _pinLiftCtrl.dispose();
    _sheetCtrl.dispose();
    _sheetExtent.dispose();
    _map?.dispose();
    super.dispose();
  }

  // ── तल्लो draggable शीट: कहीँ पनि समातेर माथि-तल तान्दा सहज स्लाइड ────────
  static const List<double> _sheetSnaps = [
    _sheetMin,
    _sheetInitial,
    _sheetMax,
  ];

  void _onSheetDrag(DragUpdateDetails d) {
    if (_sheetCtrl.isAnimating) _sheetCtrl.stop();
    final h = MediaQuery.of(context).size.height;
    // माथि तान्दा (primaryDelta ऋणात्मक) शीट ठूलो हुन्छ।
    _sheetExtent.value =
        (_sheetExtent.value - d.primaryDelta! / h).clamp(_sheetMin, _sheetMax);
  }

  void _onSheetDragEnd(DragEndDetails d) {
    final vy = d.velocity.pixelsPerSecond.dy; // <0 = माथि, >0 = तल
    final cur = _sheetExtent.value;
    double target;
    if (vy < -350) {
      target = _sheetSnaps.firstWhere((s) => s > cur + 0.005,
          orElse: () => _sheetMax);
    } else if (vy > 350) {
      target = _sheetSnaps.lastWhere((s) => s < cur - 0.005,
          orElse: () => _sheetMin);
    } else {
      target = _sheetSnaps
          .reduce((a, b) => (a - cur).abs() <= (b - cur).abs() ? a : b);
    }
    _animateSheetTo(target);
  }

  void _animateSheetTo(double target) {
    _sheetFrom = _sheetExtent.value;
    _sheetTarget = target;
    final dist = (_sheetTarget - _sheetFrom).abs();
    _sheetCtrl.duration =
        Duration(milliseconds: (140 + dist * 460).clamp(140, 460).round());
    _sheetCtrl.forward(from: 0);
  }

  /// Pathao-style: location icon थिच्दा GPS बाट current location म्यापमा केन्द्र।
  Future<void> _recenterToCurrent() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) _showLocationModal();
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _meLat = p.latitude;
        _meLng = p.longitude;
      });
      _programmaticCameraMove = true;
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_meLat, _meLng), 15.5),
      );
      _programmaticCameraMove = false;
      _reverseGeocodeBrowsePin();
      if (_posSub == null) _startTracking();
    } catch (_) {
      _programmaticCameraMove = true;
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 15),
      );
      _programmaticCameraMove = false;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
        _originLat = p.latitude;
        _originLng = p.longitude;
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

  /// क्याटेगोरी चिपमा थिच्दा — पूरा (rating/price/review सहित) provider
  /// directory (`NearbyScreen`, त्यही सेवामा पहिल्यै फिल्टर भएर) सिधै
  /// खुल्छ। पहिले यहाँ home screen कै आफ्नै सानो नक्सामा inline marker-फिल्टर
  /// मात्र हुन्थ्यो — 'Driver' चिपले भने कहिल्यै यो प्रयोग गर्दैन —
  /// ride-hailing (Bike/Car) को booking+bidding UI सधैँ छुट्टै समर्पित
  /// screen (`_openService` कै जस्तो, ServiceMapScreen) मार्फत मात्र
  /// खुल्नुपर्छ, सामान्य home screen को आफ्नै map/directory मा कहिल्यै
  /// नआओस् भनेर।
  void _openCategory(String name) async {
    if (name == 'Driver') {
      _openService(name);
      return;
    }
    final resolved = await _resolveServiceName(name);
    if (resolved == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NearbyScreen(initialFilter: resolved),
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

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchSheet(onPick: (name) {
        Navigator.pop(ctx);
        _openService(name);
      }),
    );
  }

  Set<Marker> _markers(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Marker>{};

    // ── प्रयोगकर्ताको current-location झन्डा हटाइयो — यो जहिल्यै नक्सा
    // खुल्दा screen-center को "pick location" (Pin Drop) overlay झन्डा
    // सँगै ठ्याक्कै उही ठाउँमा देखिने भएकोले दुईवटा झन्डा (एउटा ठूलो,
    // ओभरल्यापिङ) देखिने बग हुन्थ्यो। "मेरो स्थान" मा फर्कने माथिको
    // round FAB बटन (`_MyLocationBtn` → `_recenterToCurrent`) ले नै
    // यो काम गर्छ, त्यसैले छुट्टै marker आवश्यक थिएन।
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

      final wp = workerPos(data, d.id, _originLat, _originLng);
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
      drawer: const _HomeDrawer(),
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
                          style: kCleanMapStyle,
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

                    // ── ठेगाना floating card — टप बारको मुनि ──
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 66, 14, 0),
                        child: _BrowseAddressCard(
                          address: _browseAddress,
                          loading: _loadingBrowseAddress,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Top bar (hamburger + bell) ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _RoundBtn(
                        icon: Icons.menu_rounded,
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      const Spacer(),
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
                ],
              ),
            ),
          ),

          // ── Ride-sharing hero card — प्यानलभन्दा ठ्याक्कै माथि, त्यसैसँगै
          // (live extent, कुनै lag बिना) तान्दा/खुल्दा-बन्द हुँदा सर्दै।
          // Worker preview card (तल) देखिएको बेला यही ठाउँमा भिड्ने भएकोले
          // त्यसबेला लुक्छ। थिच्नेबित्तिकै सिधै ride booking (Bike/Car)
          // बाहेक अरू कुनै सेवासँग कहिल्यै मिसिँदैन — `_openService('Driver')`
          // ले नै (माथि हेर्नुहोस्) सधैँ त्यही isolated बाटो प्रयोग गर्छ।
          if (_selectedWorker == null)
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, ext, __) {
                final h = MediaQuery.of(context).size.height;
                return Positioned(
                  left: 14,
                  right: 14,
                  bottom: h * ext + 12,
                  child: _RideHeroCard(onTap: () => _openService('Driver')),
                );
              },
            ),

          // ── Floating "my location" button — प्यानल र (देखिएमा) माथिको
          // ride hero card दुवैभन्दा माथि सर्दै, कहिल्यै नछोपियोस् भनेर।
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, ext, __) {
              final h = MediaQuery.of(context).size.height;
              final heroOffset =
                  _selectedWorker == null ? _kRideHeroCardHeight + 12 : 0.0;
              return Positioned(
                right: 14,
                bottom: h * ext + 12 + heroOffset,
                child: _MyLocationBtn(
                  loading: _locating,
                  onTap: _recenterToCurrent,
                ),
              );
            },
          ),

          // ── Draggable bottom panel: कहीँ पनि समातेर माथि/तल तान्न मिल्ने ──
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, ext, child) {
              final h = MediaQuery.of(context).size.height;
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: (h * ext).clamp(0.0, h),
                child: GestureDetector(
                  // प्यानलको पूरै क्षेत्रले touch/drag यहीँ समात्छ: vertical pan
                  // ले शीट सार्छ, tap सोसिन्छ। `opaque` + नक्सा प्यानलमुनि
                  // नभएकाले तल Google Map मा कुनै pointer bleed हुँदैन।
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  onVerticalDragUpdate: _onSheetDrag,
                  onVerticalDragEnd: _onSheetDragEnd,
                  child: child,
                ),
              );
            },
            child: _SheetBody(
              pickedCategory: _pickedCategory,
              onSearch: _openSearch,
              onCategory: _openCategory,
            ),
          ),

          // ── Marker थिचेपछिको worker preview card ──
          if (_selectedWorker != null)
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, ext, __) {
                final h = MediaQuery.of(context).size.height;
                return Positioned(
                  left: 12,
                  right: 12,
                  bottom: h * ext + 14,
                  child: _WorkerPreviewCard(
                    data: _selectedWorker!,
                    km: _selectedKm,
                    onClose: _clearSelection,
                    onViewDetails: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkerProfileScreen(
                          worker: _workerMap(
                              _selectedWorkerId ?? '', _selectedWorker!),
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
                );
              },
            ),
        ],
      ),
    );
  }
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
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(color, Colors.white, 0.35)!,
                        color,
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.5), blurRadius: 12),
                    ],
                  ),
                  child: Icon(serviceIconFor(service),
                      color: Colors.white, size: 24),
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

/// तल्लो draggable शीटको सामग्री — handle + "Drag up for more" + search pill +
/// horizontal category strip। शीट drag हुँदा rebuild नहोस् भनेर छुट्टै widget
/// (ValueListenableBuilder को स्थिर `child`)। भित्री vertical scroll छैन —
/// जुनसुकै ठाउँ तान्दा शीट आफैँ सर्छ; सानो हुँदा सामग्री काटिन्छ।
class _SheetBody extends StatelessWidget {
  final String pickedCategory;
  final VoidCallback onSearch;
  final void Function(String) onCategory;

  const _SheetBody({
    required this.pickedCategory,
    required this.onSearch,
    required this.onCategory,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.kmSurface.withValues(alpha: 0.92),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 4),
              Text(S.dragForMore,
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 10.5)),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      14, 0, 14, 14 + MediaQuery.of(context).padding.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search pill — gradient CTA
                      GestureDetector(
                        onTap: onSearch,
                        child: Container(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: AppColors.kmCtaGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6)),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.search_rounded,
                                  color: AppColors.kmInk),
                              SizedBox(width: 12),
                              Expanded(child: _SearchHint()),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 18, color: AppColors.kmInk),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Horizontal service selector — real profession photo cards
                      SizedBox(
                        height: 114,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: serviceFilters.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final s = serviceFilters[i];
                            final name = s['name'] as String;
                            // 'Driver' ले home screen को map filter कहिल्यै
                            // छुँदैन (छुट्टै screen मा जान्छ) — त्यसैले यो
                            // chip कहिल्यै "active" देखिँदैन, अरू category
                            // जस्तै toggle-highlight हुँदैन।
                            final active =
                                name != 'Driver' && pickedCategory == name;
                            return GestureDetector(
                              onTap: () => onCategory(name),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                width: 88,
                                transform: Matrix4.diagonal3Values(
                                    active ? 1.06 : 1.0,
                                    active ? 1.06 : 1.0,
                                    1.0),
                                transformAlignment: Alignment.center,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                      color: active
                                          ? AppColors.kmOrange
                                          : Colors.white.withValues(alpha: 0.14),
                                      width: active ? 2.2 : 1),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(13),
                                        child: Image.asset(
                                          serviceImageFor(name),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            child: Icon(s['icon'] as IconData,
                                                color: AppColors.kmOrange),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      S.serviceName(name),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: active
                                              ? AppColors.kmOrange
                                              : AppColors.kmText),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
/// स्थान बदल्दैन) — dark glass pill, नयाँ डिजाइनसँग मिल्ने।
class _BrowseAddressCard extends StatelessWidget {
  final String address;
  final bool loading;
  const _BrowseAddressCard({required this.address, required this.loading});

  @override
  Widget build(BuildContext context) {
    return GlassPanel2(
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.place_rounded,
                size: 18, color: AppColors.kmOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loading
                    ? S.fetchingAddress
                    : (address.isEmpty ? S.moveMapHint : address),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5),
              ),
            ),
            if (loading) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
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

/// Ride-hailing (Bike/Car) मात्रका लागि समर्पित floating hero card — premium
/// gradient + shadow, थिच्दा (कार्ड जुनसुकै ठाउँमा वा "BOOK NOW" बटन दुवैले)
/// सिधै त्यही isolated ride-booking बाटो (`_openService('Driver')`) खोल्छ,
/// अरू कुनै (Plumber/Electrician/...) सेवासँग कहिल्यै मिसिँदैन।
class _RideHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RideHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.kmPurpleDeep,
              AppColors.kmPurple,
              AppColors.kmTealBlue,
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
                color: AppColors.kmTealBlue.withValues(alpha: 0.35),
                blurRadius: 26,
                offset: const Offset(0, 12)),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(S.rideHeroTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7)),
                  const SizedBox(height: 5),
                  Text(S.rideHeroSubtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.25)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Text(S.bookNowCta,
                        style: const TextStyle(
                            color: AppColors.kmPurpleDeep,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.two_wheeler_rounded,
                  color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pathao-style current-location button (map मा current location केन्द्र गर्ने)।
class _MyLocationBtn extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _MyLocationBtn({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.85,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.kmGlassBorder),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.kmOrange),
                  )
                : const Icon(Icons.my_location_rounded,
                    size: 22, color: AppColors.kmOrange),
          ),
        ),
      ),
    );
  }
}

/// Search bar भित्रको placeholder text (const बनाउन छुट्टै widget)।
class _SearchHint extends StatelessWidget {
  const _SearchHint();
  @override
  Widget build(BuildContext context) => Text(
        S.whereAndPrice,
        style: const TextStyle(
            color: AppColors.kmInk, fontSize: 15, fontWeight: FontWeight.w700),
      );
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
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.kmGlassBorder),
                ),
                child: Icon(icon, size: 22, color: AppColors.kmText),
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

class _SearchSheet extends StatefulWidget {
  final void Function(String serviceName) onPick;
  const _SearchSheet({required this.onPick});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = serviceFilters.where((s) {
      final n = (s['name'] as String).toLowerCase();
      final np = S.serviceName(s['name'] as String);
      return _q.isEmpty || n.contains(_q.toLowerCase()) || np.contains(_q);
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
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(2),
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
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide:
                              BorderSide(color: AppColors.kmOrange, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...results.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  serviceImageFor(s['name'] as String),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                      s['icon'] as IconData,
                                      color: AppColors.kmOrange,
                                      size: 20),
                                ),
                              ),
                              title: Text(S.serviceName(s['name'] as String),
                                  style: const TextStyle(
                                      color: AppColors.kmText,
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(s['name'] as String,
                                  style: const TextStyle(
                                      color: AppColors.kmMuted)),
                              onTap: () => widget.onPick(s['name'] as String),
                            ),
                          ),
                        )),
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
                          // Owner-only: Admin Dashboard entry
                          if (isOwner)
                            item(
                                Icons.admin_panel_settings_rounded,
                                'Admin Dashboard',
                                () => go(const OwnerDashboardScreen())),
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
