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
import '../widgets/glass_ui.dart';
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
      // नक्कली स्थान होइन — असली र ताजा मात्र (`realWorkerPos`)।
      final wp = realWorkerPos(data);
      if (wp == null) continue;
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
    return Scaffold(
      backgroundColor: AppColors.kmVoid,
      floatingActionButton: _ready
          ? FloatingActionButton.small(
              onPressed: _recentre,
              backgroundColor: AppColors.kmSurface,
              foregroundColor: AppColors.kmText,
              child: const Icon(Icons.my_location_rounded),
            )
          : null,
      body: !_ready
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.kmOrange),
                  const SizedBox(height: 16),
                  Text(S.enableLocation,
                      style: const TextStyle(color: AppColors.kmMuted)),
                ],
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('registeredWorkers')
                  .limit(300)
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
                      mapId: kCloudMapId,
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
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: GlassPanel2(
                            radius: 18,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            child: Row(
                              children: [
                                GlassIconButton(
                                  icon: Icons.arrow_back_ios_new_rounded,
                                  onTap: () => Navigator.of(context).maybePop(),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(S.nearbyTitle,
                                      style: const TextStyle(
                                          color: AppColors.kmText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                ),
                                GlassIconButton(
                                  icon: Icons.view_list_rounded,
                                  tooltip: 'List',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const NearbyScreen()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_approx)
                      Positioned(
                        top: 76,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.kmOrange.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color:
                                    AppColors.kmOrange.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_off,
                                  size: 16, color: AppColors.kmOrange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(S.approxLocation,
                                    style: const TextStyle(
                                        color: AppColors.kmText,
                                        fontSize: 12.5)),
                              ),
                              TextButton(
                                  onPressed: _initLocation,
                                  child: Text(S.enableLocation,
                                      style: const TextStyle(
                                          color: AppColors.kmOrange))),
                            ],
                          ),
                        ),
                      ),
                    if (docs.isEmpty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 20,
                        child: GlassPanel(
                          padding: const EdgeInsets.all(14),
                          child: Text(S.noWorkersNearby,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.kmText)),
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
    final name = (data['name'] ?? '—').toString();
    final service = (data['service'] ?? '').toString();
    // '5.0' default हटाइयो — नयाँ worker सुरुमा साँच्चै ०/कुनै review
    // नभएको देखिनुपर्छ, admin approve गर्दै लेख्ने मान अब '0.0' नै हो।
    final rating = (data['rating'] ?? '0.0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WorkerAvatar(
                  uid: (data['uid'] ?? workerId).toString(), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5)),
                    Text('${S.serviceName(service)}  ·  ⭐ $rating',
                        style: const TextStyle(color: AppColors.kmMuted)),
                    Text(
                        '${S.distanceLabel(distanceKm)}  ·  ${S.fromPrice(price)}',
                        style: const TextStyle(color: AppColors.kmMuted)),
                  ],
                ),
              ),
              GlassIconButton(
                icon: Icons.close_rounded,
                size: 36,
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 10),
          KmCtaButton(
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
