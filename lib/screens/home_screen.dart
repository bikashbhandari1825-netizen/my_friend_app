// screens/home_screen.dart
// inDrive-style map home: full-screen Google Map + sliding drawer + region
// status banner + bottom search + horizontal service-category selector।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../saved_places_screen.dart';
import '../settings_page.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
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
import 'saved_workers_screen.dart';
import 'service_map_screen.dart';
import 'worker_profile_screen.dart';
import '../widgets/worker_stats.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
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
  bool _inRegion = true;
  bool _bannerVisible = false;
  bool _locating = false;
  String _pickedCategory = ''; // '' = सबै; नत्र नक्सामा त्यही सेवा मात्र फिल्टर
  Timer? _bannerTimer;

  // क्याटेगोरी → custom marker bitmap (initState मा एकपटक बन्छ)।
  final Map<String, BitmapDescriptor> _catMarkers = {};
  // प्रयोगकर्ताको current-location — पोल+झन्डा+थोप्लो सबै एउटै static bitmap
  // भित्र (Uber-style) — नक्सा pan/zoom गर्दा यो अरू marker सँगै native रूपमा
  // सर्छ, छुट्टै overlay भएकोमा जस्तो कहिल्यै लड्खडाउँदैन।
  BitmapDescriptor? _userPin;
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

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadCategoryMarkers();
  }

  /// सबै custom pin bitmap (क्याटेगोरी + user location) पृष्ठभूमिमा तयार पार्ने।
  Future<void> _loadCategoryMarkers() async {
    try {
      final me = await destinationFlagPin();
      if (mounted) _userPin = me;
    } catch (_) {}
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
    _bannerTimer?.cancel();
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
      _setRegion(p.latitude, p.longitude);
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_meLat, _meLng), 15.5),
      );
      if (_posSub == null) _startTracking();
    } catch (_) {
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 15),
      );
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
      _setRegion(p.latitude, p.longitude);
      _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13.5));
      _startTracking();
    } catch (_) {
      if (mounted) setState(() => _locReady = true);
    }
  }

  void _setRegion(double lat, double lng) {
    // KaamMitra सेवा क्षेत्र — नेपालको मोटो bounding box
    final inNepal = lat >= 26.3 && lat <= 30.6 && lng >= 79.9 && lng <= 88.3;
    setState(() {
      _inRegion = inNepal;
      _bannerVisible = true;
    });
    _bannerTimer?.cancel();
    if (inNepal) {
      _bannerTimer = Timer(const Duration(seconds: 4),
          () => mounted ? setState(() => _bannerVisible = false) : null);
    }
  }

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
        _lat = p.latitude;
        _lng = p.longitude;
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
        final theme = Theme.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
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
                    color: AppColors.lime.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded,
                      size: 40, color: AppColors.lime),
                ),
              ),
              const SizedBox(height: 16),
              Text(S.locationOffTitle,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(S.locationOffBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              PrimaryButton(
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

  /// क्याटेगोरी चिपमा थिच्दा नक्साका marker त्यही सेवामा फिल्टर हुन्छन्;
  /// फेरि उही थिच्दा फिल्टर हट्छ। 'Driver' चिप भने पहिले नै सक्रिय (Bike/Car
  /// मध्ये कुनै एउटामा फिल्टर भइसकेको) भए फेरि popup नखोली सिधै हटाउँछ —
  /// त्यो नै "फेरि थिच्दा हट्ने" toggle व्यवहार हो।
  void _openCategory(String name) async {
    if (name == 'Driver' &&
        (_pickedCategory == 'Bike' || _pickedCategory == 'Car')) {
      setState(() {
        _pickedCategory = '';
        _selectedWorkerId = null;
        _selectedWorker = null;
      });
      return;
    }
    final resolved = await _resolveServiceName(name);
    if (resolved == null || !mounted) return;
    setState(() {
      _pickedCategory = _pickedCategory == resolved ? '' : resolved;
      _selectedWorkerId = null;
      _selectedWorker = null;
    });
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

    // ── प्रयोगकर्ताको current location — झन्डा marker (पोल+थोप्लो मात्र;
    // एनिमेटेड झन्डा माथि overlay बाट) ──
    if (_userPin != null && _locReady) {
      out.add(Marker(
        markerId: const MarkerId('__me__'),
        position: LatLng(_meLat, _meLng),
        anchor: FlagPinGeometry.markerAnchorFraction,
        icon: _userPin!,
        zIndexInt: 100,
        consumeTapEvents: true,
        onTap: _recenterToCurrent,
      ));
    }

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
          // नक्सालाई तल्लो gradient प्यानलमुनि नफैलिने गरी सीमित गरिएको छ:
          // प्यानलको अहिलेको उचाइ (_sheetExtent) अनुसार तल्लो किनारा सर्छ।
          // यसरी Google Map को platform-view element प्यानल क्षेत्रमा हुँदै
          // हुँदैन — त्यसैले web/native दुवैमा प्यानलभित्रको touch/drag कहिल्यै
          // नक्सामा पुग्दैन (opaque GestureDetector भन्दा यो पक्का उपाय हो;
          // web मा नक्साले browser का native pointer event सिधै लिने भएकाले)।
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, ext, __) {
              final h = MediaQuery.of(context).size.height;
              // प्यानलको rounded माथिल्लो कुनाभित्र नक्सा अलिकति पस्न दिने।
              final mapBottom = (h * ext - 24).clamp(0.0, h);
              return Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: mapBottom,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _workersStream,
                  builder: (context, snap) {
                    return GoogleMap(
                      initialCameraPosition:
                          CameraPosition(target: LatLng(_lat, _lng), zoom: 13),
                      style: kCleanMapStyle,
                      onMapCreated: (c) {
                        _map = c;
                        if (_locReady) {
                          c.animateCamera(CameraUpdate.newLatLngZoom(
                              LatLng(_lat, _lng), 13.5));
                        }
                      },
                      onCameraMove: (p) => _lat = p.target.latitude,
                      onTap: (_) {
                        if (_selectedWorker != null) _clearSelection();
                      },
                      // निलो थोप्लाको सट्टा हाम्रो custom झन्डा pin।
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      padding: const EdgeInsets.only(top: 70),
                      markers: _markers(snap.data?.docs ?? []),
                    );
                  },
                ),
              );
            },
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
                  const SizedBox(height: 10),
                  // ── Region status banner ──
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOut,
                    offset:
                        _bannerVisible ? Offset.zero : const Offset(0, -0.4),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 320),
                      opacity: _bannerVisible ? 1 : 0,
                      child: _RegionBanner(
                        inRegion: _inRegion,
                        onClose: () => setState(() => _bannerVisible = false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Floating "my location" button — प्यानलभन्दा माथि सर्दै ──
          ValueListenableBuilder<double>(
            valueListenable: _sheetExtent,
            builder: (context, ext, __) {
              final h = MediaQuery.of(context).size.height;
              return Positioned(
                right: 14,
                bottom: h * ext + 12,
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
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.igGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: [
          BoxShadow(
              color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white70,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Text(S.dragForMore,
              style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  14, 0, 14, 14 + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search — Instagram-gradient pill
                  GestureDetector(
                    onTap: onSearch,
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: AppColors.buttonGradient,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55)),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 14,
                              offset: Offset(0, 4)),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search_rounded, color: Colors.white),
                          SizedBox(width: 12),
                          Expanded(child: _SearchHint()),
                          Icon(Icons.arrow_forward_rounded,
                              size: 18, color: Colors.white),
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
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final s = serviceFilters[i];
                        final name = s['name'] as String;
                        // 'Driver' tile आफैं कहिल्यै सिधै filter हुँदैन —
                        // Bike/Car मध्ये छानिएको बेला पनि यही tile "active"
                        // देखियोस् भनेर।
                        final active = pickedCategory == name ||
                            (name == 'Driver' &&
                                (pickedCategory == 'Bike' ||
                                    pickedCategory == 'Car'));
                        return GestureDetector(
                          onTap: () => onCategory(name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            width: 88,
                            transform: Matrix4.diagonal3Values(
                                active ? 1.06 : 1.0, active ? 1.06 : 1.0, 1.0),
                            transformAlignment: Alignment.center,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                  color: active
                                      ? AppColors.igViolet
                                      : Colors.white.withValues(alpha: 0.4),
                                  width: active ? 2.6 : 1),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 3)),
                              ],
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.asset(
                                      serviceImageFor(name),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0x11833AB4),
                                        child: Icon(s['icon'] as IconData,
                                            color: AppColors.igViolet),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  S.serviceName(name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.igViolet),
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
    final theme = Theme.of(context);
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.85,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: AppColors.igViolet),
              )
            : const Icon(Icons.my_location_rounded,
                size: 22, color: AppColors.igViolet),
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
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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
    final theme = Theme.of(context);
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.85,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
          ),
          if (dot)
            const Positioned(
              right: 3,
              top: 3,
              child: CircleAvatar(radius: 5, backgroundColor: AppColors.lime),
            ),
        ],
      ),
    );
  }
}

class _RegionBanner extends StatelessWidget {
  final bool inRegion;
  final VoidCallback onClose;
  const _RegionBanner({required this.inRegion, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = inRegion
        ? AppColors.lime.withValues(alpha: 0.18)
        : AppColors.warning.withValues(alpha: 0.20);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(inRegion ? Icons.check_circle_rounded : Icons.info_rounded,
              size: 16, color: inRegion ? AppColors.lime : AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              inRegion ? S.regionAvailable : S.regionUnavailable,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Icon(Icons.close_rounded,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
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
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.igGradient, // Instagram जस्तै — same to same
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
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
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                TextField(
                  controller: _c,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: S.searchHint,
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: Colors.white),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.18),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide:
                          const BorderSide(color: Colors.white, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...results.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              serviceImageFor(s['name'] as String),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                  s['icon'] as IconData,
                                  color: AppColors.igViolet,
                                  size: 20),
                            ),
                          ),
                          title: Text(S.serviceName(s['name'] as String),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(s['name'] as String,
                              style: const TextStyle(color: Colors.white70)),
                          onTap: () => widget.onPick(s['name'] as String),
                        ),
                      ),
                    )),
              ],
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

  static const String _ownerEmail = 'bikashbhandari1825@gmail.com';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final isOwner = user?.email == _ownerEmail;

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

    // gradient panel माथिको glass menu button
    Widget item(IconData icon, String label, VoidCallback onTap,
            {Color? tint}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Material(
            color: (tint ?? Colors.white).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 21, color: Colors.white),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white54, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );

    return Drawer(
      backgroundColor: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
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
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: selfieUrl.isEmpty
                              ? const Icon(Icons.person_rounded,
                                  color: Colors.white, size: 30)
                              : Image.network(
                                  selfieUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person_rounded,
                                      color: Colors.white,
                                      size: 30),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isEmpty ? 'KaamMitra' : name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              const Row(
                                children: [
                                  Icon(Icons.star_rounded,
                                      size: 15, color: Colors.white),
                                  SizedBox(width: 3),
                                  Text('5.0',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 8),
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
                            () => go(const SavedWorkersScreen())),
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
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.workspace_premium_rounded,
                            color: Colors.white),
                        label: Text(
                            isWorker ? S.providerMode : S.becomeProvider,
                            style: const TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white70),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill)),
                        ),
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
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
