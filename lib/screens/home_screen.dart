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
import '../widgets/pulsing_location_marker.dart';
import '../worker_registration_page.dart';
import 'bookings_screen.dart';
import 'help_support_screen.dart';
import 'messages_screen.dart';
import 'my_reviews_screen.dart';
import 'nearby_common.dart';
import 'nearby_screen.dart';
import 'notification_screen.dart';
import 'payment_methods_screen.dart';
import 'saved_workers_screen.dart';
import 'worker_list_screen.dart';

const double _kHomePulseSize = 120;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;

  double _lat = fallbackLat;
  double _lng = fallbackLng;
  double _originLat = fallbackLat;
  double _originLng = fallbackLng;
  // साँचो device GPS स्थिति — onCameraMove ले _lat लाई pan गर्दा mutate
  // गर्छ, तर pulsing marker सधैं यूजरको वास्तविक location मै टाँसिएको
  // हुनुपर्ने भएकाले यी छुट्टै राखिएका।
  double _gpsLat = fallbackLat;
  double _gpsLng = fallbackLng;
  bool _locReady = false;
  bool _inRegion = true;
  bool _bannerVisible = false;
  String _pickedCategory = '';
  Timer? _bannerTimer;

  Offset? _userScreenPos;
  bool _posLookupBusy = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _bannerTimer?.cancel();
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
        _originLat = p.latitude;
        _originLng = p.longitude;
        _gpsLat = p.latitude;
        _gpsLng = p.longitude;
        _locReady = true;
      });
      _setRegion(p.latitude, p.longitude);
      _map?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13.5));
      _startTracking();
      _syncUserMarkerPos();
    } catch (_) {
      if (mounted) setState(() => _locReady = true);
    }
  }

  void _setRegion(double lat, double lng) {
    // KaamMitra सेवा क्षेत्र — नेपालको मोटो bounding box
    final inNepal =
        lat >= 26.3 && lat <= 30.6 && lng >= 79.9 && lng <= 88.3;
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
        _gpsLat = p.latitude;
        _gpsLng = p.longitude;
      });
      _syncUserMarkerPos();
    }, onError: (_) {});
  }

  // Google Map माथि पुलसिंग रिप्पल overlay लाई user को live location मार्कर
  // को ठ्याक्कै पछाडि राख्नको लागि screen (pixel) position निकाल्छ।
  Future<void> _syncUserMarkerPos() async {
    final map = _map;
    if (map == null || !mounted || _posLookupBusy) return;
    _posLookupBusy = true;
    try {
      final sc = await map.getScreenCoordinate(LatLng(_gpsLat, _gpsLng));
      if (!mounted) return;
      final ratio = MediaQuery.of(context).devicePixelRatio;
      setState(() {
        _userScreenPos = Offset(sc.x / ratio, sc.y / ratio);
      });
    } catch (_) {
      // map disposed भइसकेको वा platform error — silently ignore।
    } finally {
      _posLookupBusy = false;
    }
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
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg)),
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
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

  void _openCategory(String name) {
    setState(() => _pickedCategory = name);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      setState(() => _pickedCategory = '');
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => WorkerListScreen(serviceName: name)),
      );
    });
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SearchSheet(onPick: (name) {
        Navigator.pop(ctx);
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => WorkerListScreen(serviceName: name)),
        );
      }),
    );
  }

  Set<Marker> _markers(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Marker>{};
    for (final d in docs) {
      final data = d.data();
      final wp = workerPos(data, d.id, _originLat, _originLng);
      final km = haversineKm(_lat, _lng, wp.lat, wp.lng);
      out.add(Marker(
        markerId: MarkerId(d.id),
        position: LatLng(wp.lat, wp.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: (data['name'] ?? '—').toString(),
          snippet:
              '${S.serviceName((data['service'] ?? '').toString())} · ${S.distanceLabel(km)}',
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const _HomeDrawer(),
      body: Stack(
        children: [
          // ── Map ──
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('registeredWorkers')
                .snapshots(),
            builder: (context, snap) {
              return GoogleMap(
                initialCameraPosition: CameraPosition(
                    target: LatLng(_lat, _lng), zoom: 13),
                onMapCreated: (c) {
                  _map = c;
                  if (_locReady) {
                    c.animateCamera(CameraUpdate.newLatLngZoom(
                        LatLng(_lat, _lng), 13.5));
                  }
                  _syncUserMarkerPos();
                },
                onCameraMove: (p) {
                  _lat = p.target.latitude;
                  _syncUserMarkerPos();
                },
                onCameraIdle: _syncUserMarkerPos,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                padding: const EdgeInsets.only(bottom: 220, top: 70),
                markers: _markers(snap.data?.docs ?? []),
              );
            },
          ),

          // ── User/pickup location: pulsating radar ripple ──
          if (_userScreenPos != null)
            Positioned(
              left: _userScreenPos!.dx - _kHomePulseSize / 2,
              top: _userScreenPos!.dy - _kHomePulseSize / 2,
              child: const PulsingLocationMarker(size: _kHomePulseSize),
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
                    offset: _bannerVisible
                        ? Offset.zero
                        : const Offset(0, -0.4),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 320),
                      opacity: _bannerVisible ? 1 : 0,
                      child: _RegionBanner(
                        inRegion: _inRegion,
                        onClose: () =>
                            setState(() => _bannerVisible = false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom panel: search + categories ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, -4)),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search
                    GestureDetector(
                      onTap: _openSearch,
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded,
                                color: AppColors.lime),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(S.whereAndPrice,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Icon(Icons.arrow_forward_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Horizontal category selector
                    SizedBox(
                      height: 82,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: serviceFilters.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final s = serviceFilters[i];
                          final name = s['name'] as String;
                          final active = _pickedCategory == name;
                          return GestureDetector(
                            onTap: () => _openCategory(name),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              width: 78,
                              transform: Matrix4.diagonal3Values(
                                  active ? 1.06 : 1.0,
                                  active ? 1.06 : 1.0,
                                  1.0),
                              transformAlignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.lime
                                    : theme
                                        .colorScheme.surfaceContainerHighest,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                border: Border.all(
                                    color: active
                                        ? AppColors.lime
                                        : theme.dividerColor),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(s['icon'] as IconData,
                                      size: 24,
                                      color: active
                                          ? AppColors.onLime
                                          : AppColors.lime),
                                  const SizedBox(height: 6),
                                  Text(
                                    S.serviceName(name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: active
                                            ? AppColors.onLime
                                            : theme.colorScheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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

// ─────────────────────────────────────────────────────────────────────────────

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  const _RoundBtn({required this.icon, required this.onTap, this.dot = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
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
              size: 16,
              color: inRegion ? AppColors.lime : AppColors.warning),
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
    final theme = Theme.of(context);
    final results = serviceFilters.where((s) {
      final n = (s['name'] as String).toLowerCase();
      final np = S.serviceName(s['name'] as String);
      return _q.isEmpty ||
          n.contains(_q.toLowerCase()) ||
          np.contains(_q);
    }).toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _c,
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: S.searchHint,
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppColors.lime),
              ),
            ),
            const SizedBox(height: 12),
            ...results.map((s) => ListTile(
                  leading: LimeIconBadge(s['icon'] as IconData, size: 38),
                  title: Text(S.serviceName(s['name'] as String)),
                  subtitle: Text(s['name'] as String,
                      style: theme.textTheme.bodySmall),
                  onTap: () => widget.onPick(s['name'] as String),
                )),
          ],
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
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    void go(Widget page) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon, size: 22),
          title: Text(label),
          onTap: onTap,
          dense: true,
        );

    return Drawer(
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile header
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      const LimeIconBadge(Icons.person, size: 54, solid: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isEmpty ? 'KaamMitra' : name,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            const Row(
                              children: [
                                Icon(Icons.star_rounded,
                                    size: 15, color: AppColors.lime),
                                SizedBox(width: 3),
                                Text('5.0',
                                    style: TextStyle(
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
                Divider(color: theme.dividerColor, height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
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
                      item(Icons.notifications_none_rounded,
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
                  child: SecondaryButton(
                    label: isWorker ? S.providerMode : S.becomeProvider,
                    icon: Icons.workspace_premium_rounded,
                    onPressed: () {
                      Navigator.pop(context);
                      if (!isWorker) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const WorkerRegistrationPage()),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NearbyScreen()),
                        );
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
