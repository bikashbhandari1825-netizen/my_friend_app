// screens/nearby_map_screen.dart
// inDrive-style: "नजिकका कामदार" थिच्दा सिधै interactive Google Map खुल्छ।
// नजिकका worker हरू म्यापमै marker/pin भएर देखिन्छन् (registeredWorkers live stream)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/worker_avatar.dart';
import 'nearby_common.dart';
import 'nearby_screen.dart';

class NearbyMapScreen extends StatefulWidget {
  const NearbyMapScreen({super.key});

  @override
  State<NearbyMapScreen> createState() => _NearbyMapScreenState();
}

class _NearbyMapScreenState extends State<NearbyMapScreen> {
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;

  // origin: scatter गर्ने fixed centre (एकपटक मात्र सेट); live: distance को लागि।
  double _originLat = fallbackLat;
  double _originLng = fallbackLng;
  double _lat = fallbackLat;
  double _lng = fallbackLng;
  bool _ready = false;
  bool _approx = false;
  bool _centeredOnce = false;

  String? _selId;
  Map<String, dynamic>? _selData;
  double _selKm = 0;

  @override
  void initState() {
    super.initState();
    _initLocation();
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
        _approx = false;
        _ready = true;
      });
      _recentre();
      _startTracking();
    } catch (_) {
      _useFallback();
    }
  }

  void _useFallback() {
    if (!mounted) return;
    setState(() {
      _originLat = fallbackLat;
      _originLng = fallbackLng;
      _lat = fallbackLat;
      _lng = fallbackLng;
      _approx = true;
      _ready = true;
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
        _approx = false;
      });
    }, onError: (_) {});
  }

  Future<void> _recentre() async {
    if (_map == null) return;
    await _map!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13.5),
    );
    _centeredOnce = true;
  }

  Set<Marker> _buildMarkers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final markers = <Marker>{};
    for (final d in docs) {
      final data = d.data();
      final wp = workerPos(data, d.id, _originLat, _originLng);
      final km = haversineKm(_lat, _lng, wp.lat, wp.lng);
      final name = (data['name'] ?? '—').toString();
      final service = (data['service'] ?? '').toString();
      markers.add(
        Marker(
          markerId: MarkerId(d.id),
          position: LatLng(wp.lat, wp.lng),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: name,
            snippet: '${S.serviceName(service)} · ${S.distanceLabel(km)}',
          ),
          onTap: () => setState(() {
            _selId = d.id;
            _selData = data;
            _selKm = km;
          }),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.nearbyTitle),
        actions: [
          IconButton(
            tooltip: 'List',
            icon: const Icon(Icons.view_list_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NearbyScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: _ready
          ? FloatingActionButton.small(
              onPressed: _recentre,
              child: const Icon(Icons.my_location_rounded),
            )
          : null,
      body: !_ready
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(S.enableLocation, style: theme.textTheme.bodyMedium),
                ],
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('registeredWorkers')
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
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
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर
                      // "उल्टो" देखिने बग नआओस्।
                      rotateGesturesEnabled: false,
                      markers: _buildMarkers(docs),
                      onTap: (_) => setState(() {
                        _selId = null;
                        _selData = null;
                      }),
                    ),
                    if (_approx)
                      Positioned(
                        top: 12,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.lime.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_off,
                                  size: 16, color: AppColors.lime),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(S.approxLocation,
                                    style: const TextStyle(fontSize: 12.5)),
                              ),
                              TextButton(
                                  onPressed: _initLocation,
                                  child: Text(S.enableLocation)),
                            ],
                          ),
                        ),
                      ),
                    if (docs.isEmpty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 20,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Text(S.noWorkersNearby,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium),
                        ),
                      ),
                    if (_selData != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 16,
                        child: _WorkerSheet(
                          data: _selData!,
                          workerId: _selId!,
                          distanceKm: _selKm,
                          employerLat: _lat,
                          employerLng: _lng,
                          onClose: () => setState(() {
                            _selId = null;
                            _selData = null;
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _WorkerSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String workerId;
  final double distanceKm;
  final double employerLat;
  final double employerLng;
  final VoidCallback onClose;

  const _WorkerSheet({
    required this.data,
    required this.workerId,
    required this.distanceKm,
    required this.employerLat,
    required this.employerLng,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (data['name'] ?? '—').toString();
    final service = (data['service'] ?? '').toString();
    final rating = (data['rating'] ?? '5.0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.dividerColor),
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
              WorkerAvatar(uid: workerId, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15.5)),
                    Text('${S.serviceName(service)}  ·  ⭐ $rating',
                        style: theme.textTheme.bodySmall),
                    Text(
                        '${S.distanceLabel(distanceKm)}  ·  ${S.fromPrice(price)}',
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
          const SizedBox(height: 10),
          PrimaryButton(
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
        ],
      ),
    );
  }
}
