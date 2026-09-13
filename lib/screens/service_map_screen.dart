// screens/service_map_screen.dart
// Pathao/InDrive-style: होमपेजको सर्च वा category थिच्दा यो MAP खुल्छ।
// नक्सा जानाजान सफा राखिएको — व्यक्तिगत worker pin देखिँदैनन्, आफ्नो
// (pickup) झन्डा मात्र। तल "Post job" बटनले नजिकका सबै worker लाई
// एकैचोटि अनुरोध पठाउँछ (broadcast), अनि tracking स्क्रिन खुल्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
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

class _ServiceMapScreenState extends State<ServiceMapScreen> {
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
  bool _sending = false;
  // "Confirm job details" sheet खुला हुँदा नक्साका gesture निष्क्रिय — नत्र
  // web मा बटनको tap पछाडिको Google Map ले खोस्थ्यो।
  bool _postSheetOpen = false;

  // InDrive-style: ग्राहकको प्रस्तावित मूल्य (अनुमानित भाडाबाट सुरु)।
  int? _offer;
  static const int _priceStep = 50;
  void _setOffer(int v) =>
      setState(() => _offer = v.clamp(_priceStep, 1000000));

  // दायरा filter (किमी) — null = सबै
  int? _radiusKm = 10;
  // प्रयोगकर्ताको आफ्नै स्थान — पोल+झन्डा+थोप्लो सबै एउटै static bitmap
  // भित्र (Uber-style, निलो थोप्लाको सट्टा) — नक्सा pan/zoom गर्दा native
  // marker भएकाले कहिल्यै अलग-अलग लड्खडाउँदैन।
  BitmapDescriptor? _pickupPin;

  // ── तल्लो सूचीबाट छानिएको worker (नक्सामा कुनै pin छैन — सूचीको कार्डबाटै
  // छनौट हुन्छ) ──
  String? _selId;
  Map<String, dynamic>? _selData;
  double _selKm = 0;
  RoadRoute? _route;
  bool _routeLoading = false;

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
    destinationFlagPin().then((p) {
      if (mounted) setState(() => _pickupPin = p);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
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
      });
      _recentre();
      _startTracking();
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
        _lat = p.latitude;
        _lng = p.longitude;
      });
    }, onError: (_) {});
  }

  Future<void> _recentre() async {
    if (_map == null) return;
    await _map!
        .animateCamera(CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13.5));
    _centeredOnce = true;
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
      if (_radiusKm != null && km > _radiusKm!) continue;
      rows.add((id: d.id, data: data, km: km, pos: LatLng(wp.lat, wp.lng)));
    }
    rows.sort((a, b) => a.km.compareTo(b.km));
    return rows;
  }

  // worker-अवतार pin हरू (नाम अनुसारको रङको "व्यक्ति" marker) जानाजान
  // हटाइएको — नक्सा सफा राख्ने, अनुरोध सधैँ तल्लो "Post job" प्यानलबाट
  // सबै नजिकका worker लाई broadcast हुने भएकोले map मा व्यक्तिगत pin
  // छान्नुपर्ने आवश्यकता छैन। pickup (आफ्नो) झन्डा मात्र देखिन्छ।
  Set<Marker> _buildMarkers(
      List<({String id, Map<String, dynamic> data, double km, LatLng pos})>
          rows) {
    return {
      if (_pickupPin != null)
        Marker(
          markerId: const MarkerId('__pickup__'),
          position: LatLng(_lat, _lng),
          icon: _pickupPin!,
          anchor: FlagPinGeometry.markerAnchorFraction,
          zIndexInt: 100,
        ),
    };
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
        initialBudget: _offer ?? estFare,
        nearbyCount: nearby.length,
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
      try {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .get();
        final n = (u.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) employerName = n;
      } catch (_) {}

      final db = FirebaseFirestore.instance;
      final ref = await db.collection('serviceRequests').add({
        'service': widget.serviceType,
        'broadcast': true,
        'employerUid': user?.uid ?? '',
        'employerName': employerName,
        'employerPhone': user?.phoneNumber ?? '',
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
        'nearbyCount': nearby.length,
        'createdAt': FieldValue.serverTimestamp(),
      });

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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RequestTrackingScreen(requestId: ref.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
        title: Text(
          '${S.serviceName(widget.serviceType)} — ${S.nearbyTitle}',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _recentre,
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
          final estFare = estimateFare(widget.serviceType, nearestKm ?? 2.0);
          _offer ??= estFare;

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(_lat, _lng),
                  zoom: 13.5,
                ),
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
                rotateGesturesEnabled: !_postSheetOpen,
                tiltGesturesEnabled: !_postSheetOpen,
                padding: const EdgeInsets.only(bottom: 260, top: 118),
                markers: _buildMarkers(rows),
              ),

              // ── दायरा filter + online count ──
              Positioned(
                top: 96,
                left: 12,
                right: 12,
                child: _RadiusBar(
                  radiusKm: _radiusKm,
                  onlineCount: rows.length,
                  serviceType: widget.serviceType,
                  onPick: (v) => setState(() => _radiusKm = v),
                ),
              ),

              // ── छानिएको worker को details card — सूचीबाट छानेपछि देखिने ──
              if (_selData != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 270,
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
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.igGradient,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppRadius.lg)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 20,
                          offset: Offset(0, -4)),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                          ],
                        ),
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
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _sending
                                ? null
                                : () => _openPostJob(rows, estFare),
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.igViolet),
                                  )
                                : const Icon(Icons.post_add_rounded),
                            label: Text(
                                '${S.postJob}  ·  Rs. ${_offer ?? estFare}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.igViolet,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill)),
                            ),
                          ),
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
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── तल्लो horizontal सूचीको एउटा worker कार्ड — नक्सामा कुनै pin नभई
// यहींबाट tap गरेर details card खोल्ने/बन्द गर्ने ──
class _WorkerChip extends StatelessWidget {
  final String name;
  final double distanceKm;
  final String serviceType;
  final bool selected;
  final VoidCallback onTap;
  const _WorkerChip({
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
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(Icons.engineering_rounded, color: color, size: 18),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected ? AppColors.igViolet : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              S.distanceLabel(distanceKm),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected
                      ? AppColors.igViolet.withValues(alpha: 0.7)
                      : Colors.white70,
                  fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── दायरा filter bar (map माथि) ──────────────────────────────────────────────
class _RadiusBar extends StatelessWidget {
  final int? radiusKm;
  final int onlineCount;
  final String serviceType;
  final ValueChanged<int?> onPick;
  const _RadiusBar({
    required this.radiusKm,
    required this.onlineCount,
    required this.serviceType,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool active, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.igViolet : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Text(label,
                style: TextStyle(
                    color: active ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 9, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                '$onlineCount ${S.serviceName(serviceType)} ${S.providersNearby}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            chip(S.isNepali ? 'सबै' : 'All', radiusKm == null,
                () => onPick(null)),
            for (final km in [5, 10, 15])
              chip(S.kmRadius(km), radiusKm == km, () => onPick(km)),
          ],
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
    final theme = Theme.of(context);
    final name = (data['name'] ?? '—').toString();
    final rating = (data['rating'] ?? '5.0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();
    final experience = (data['experience'] ?? '').toString();
    final online = data['isOnline'] != false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor:
                        serviceMarkerColor(serviceType).withValues(alpha: 0.15),
                    child: Icon(Icons.engineering_rounded,
                        color: serviceMarkerColor(serviceType), size: 26),
                  ),
                  if (online)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                          radius: 6, backgroundColor: AppColors.success),
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
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.igYellow),
                        const SizedBox(width: 2),
                        Text(rating,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        Text('   ${S.serviceName(serviceType)}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                    Text(
                        [
                          if (experience.isNotEmpty) experience,
                          S.distanceLabel(distanceKm),
                          S.fromPrice(price),
                        ].join('  ·  '),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onClose,
              ),
            ],
          ),
          if (routeLoading || route != null) ...[
            const Divider(height: 18),
            if (routeLoading)
              Row(
                children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(S.findingRoute, style: theme.textTheme.bodySmall),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.route_rounded,
                      size: 16, color: Color(0xFF111111)),
                  const SizedBox(width: 6),
                  Text(
                    '${route!.km.toStringAsFixed(route!.km < 10 ? 1 : 0)} km  ·  ${S.minutesShort(route!.minutes)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                  const SizedBox(width: 6),
                  Text(route!.real ? S.roadRoute : S.approxRoute,
                      style: theme.textTheme.bodySmall),
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
                      }),
                    ),
                  ),
                  icon: const Icon(Icons.person_rounded, size: 16),
                  label: const Text('Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.igViolet,
                    side: const BorderSide(color: AppColors.igViolet),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PrimaryButton(
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
  const _PostedJob({
    required this.title,
    required this.description,
    required this.date,
    required this.slot,
    required this.address,
    required this.lat,
    required this.lng,
    required this.budget,
  });
}

class _PostJobSheet extends StatefulWidget {
  final String serviceType;
  final double lat;
  final double lng;
  final int initialBudget;
  final int nearbyCount;
  const _PostJobSheet({
    required this.serviceType,
    required this.lat,
    required this.lng,
    required this.initialBudget,
    required this.nearbyCount,
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

  static const _step = 50;

  @override
  void initState() {
    super.initState();
    _fillAddress();
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
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = S.describeJobFirst);
      return;
    }
    if (_date == null) {
      setState(() => _error = S.pickDateFirst);
      return;
    }
    Navigator.pop(
      context,
      _PostedJob(
        title: _title.text.trim(),
        description: _desc.text.trim(),
        date: _date!,
        slot: _slot,
        address: _addr.text.trim(),
        lat: widget.lat,
        lng: widget.lng,
        budget: _budget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GestureDetector(
        // कार्डभित्रको हरेक touch/tap यहीँ सोसिन्छ — पछाडिको नक्सामा कुनै
        // pointer नपुगोस् (नक्साका gesture पनि sheet खुला हुँदा बन्द छन्)।
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.igGradient,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
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
                      color: Colors.white70,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(serviceIconFor(widget.serviceType),
                        color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${S.jobConfirmTitle} — ${S.serviceName(widget.serviceType)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              '${widget.nearbyCount} ${S.serviceName(widget.serviceType)} ${S.providersNearby}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_rounded,
                                  color: Colors.white70, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _date == null
                                    ? S.preferredDateLabel
                                    : '${_date!.day}/${_date!.month}/${_date!.year}',
                                style: const TextStyle(color: Colors.white),
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
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _slot,
                            isExpanded: true,
                            dropdownColor: AppColors.igViolet,
                            iconEnabledColor: Colors.white,
                            style: const TextStyle(color: Colors.white),
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
                const SizedBox(height: 12),
                _WhiteField(
                  controller: _addr,
                  label: S.jobAddressLabel,
                  hint: _loadingAddr ? S.fetchingAddress : '',
                  maxLines: 2,
                  prefix: const Icon(Icons.place_outlined,
                      color: Colors.white70, size: 18),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.gps_fixed_rounded,
                        color: Colors.white60, size: 12),
                    const SizedBox(width: 4),
                    Text(
                        '${S.pinnedLocation}: ${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(S.serviceAddressNote,
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 14),
                Text(S.customerBudget,
                    style: const TextStyle(
                        color: Colors.white,
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
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 18),
                    _StepBtn(
                        icon: Icons.add_rounded,
                        onTap: () => setState(() =>
                            _budget = (_budget + _step).clamp(_step, 1000000))),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: TextStyle(
                          color: theme.colorScheme.error == Colors.transparent
                              ? Colors.white
                              : const Color(0xFFFFE0E0),
                          fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text(S.confirmBroadcast,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.igViolet,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill)),
                  ),
                ),
              ],
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: prefix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: Colors.white, width: 1.4),
        ),
      ),
    );
  }
}
