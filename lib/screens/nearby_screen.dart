// screens/nearby_screen.dart
// "Nearby workers" को list view — GPS दूरी + filter + आफ्नो मूल्य offer (bidding)।
// Geo helper र offer sheet `nearby_common.dart` मा साझा छन् (map view ले पनि प्रयोग गर्छ)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_avatar.dart';
import 'nearby_common.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  double _lat = fallbackLat;
  double _lng = fallbackLng;
  bool _loadingLoc = true;
  bool _approx = false;
  String _filter = 'all';
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    setState(() => _loadingLoc = true);
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
        _loadingLoc = false;
      });
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
      _loadingLoc = false;
    });
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

  Query<Map<String, dynamic>> get _query {
    final base = FirebaseFirestore.instance.collection('registeredWorkers');
    if (_filter == 'all') return base;
    return base.where('service', isEqualTo: _filter);
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: S.nearbyTitle),
              ),
              Expanded(
                child: _loadingLoc
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: AppColors.kmOrange),
                            const SizedBox(height: 16),
                            Text(S.enableLocation,
                                style: const TextStyle(
                                    color: AppColors.kmMuted)),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          if (_approx) _ApproxBanner(onEnable: _initLocation),
                          _FilterBar(
                            selected: _filter,
                            onSelect: (f) => setState(() => _filter = f),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _initLocation,
                              color: AppColors.kmOrange,
                              backgroundColor: AppColors.kmSurface,
                              child: StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>>(
                                stream: _query.snapshots(),
                                builder: (context, snap) {
                                  if (snap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                        child: CircularProgressIndicator(
                                            color: AppColors.kmOrange));
                                  }
                                  final docs = snap.data?.docs ?? [];
                                  if (docs.isEmpty) {
                                    return _EmptyNearby();
                                  }

                                  final workers = docs.map((d) {
                                    final data = d.data();
                                    final wp =
                                        workerPos(data, d.id, _lat, _lng);
                                    final km = haversineKm(
                                        _lat, _lng, wp.lat, wp.lng);
                                    return (data: data, id: d.id, km: km);
                                  }).toList()
                                    ..sort((a, b) => a.km.compareTo(b.km));

                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 12, 16, 24),
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    itemCount: workers.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, i) {
                                      final w = workers[i];
                                      return _WorkerCard(
                                        data: w.data,
                                        workerId: w.id,
                                        distanceKm: w.km,
                                        employerLat: _lat,
                                        employerLng: _lng,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ApproxBanner extends StatelessWidget {
  final VoidCallback onEnable;
  const _ApproxBanner({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.kmOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.kmOrange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off, size: 18, color: AppColors.kmOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(S.approxLocation,
                style: const TextStyle(
                    color: AppColors.kmText, fontSize: 12.5)),
          ),
          TextButton(
              onPressed: onEnable,
              child: Text(S.enableLocation,
                  style: const TextStyle(color: AppColors.kmOrange))),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _FilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label, IconData? icon) {
      final active = value == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSelect(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: active ? AppColors.kmCtaGradient : null,
              color: active ? null : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: active
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: active ? AppColors.kmInk : AppColors.kmMuted),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.kmInk : AppColors.kmMuted,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
        children: [
          chip('all', S.filterAll, null),
          for (final s in serviceFilters)
            chip(s['name'] as String, S.serviceName(s['name'] as String),
                s['icon'] as IconData),
        ],
      ),
    );
  }
}

class _EmptyNearby extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 90),
        const Icon(Icons.person_search_rounded,
            size: 56, color: AppColors.kmMuted),
        const SizedBox(height: 14),
        Center(
          child: Text(S.noWorkersNearby,
              style: const TextStyle(color: AppColors.kmMuted)),
        ),
      ],
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String workerId;
  final double distanceKm;
  final double employerLat;
  final double employerLng;

  const _WorkerCard({
    required this.data,
    required this.workerId,
    required this.distanceKm,
    required this.employerLat,
    required this.employerLng,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final service = (data['service'] ?? '').toString();
    // '5.0' default हटाइयो — नयाँ worker सुरुमा साँच्चै ०/कुनै review
    // नभएको देखिनुपर्छ, admin approve गर्दै लेख्ने मान अब '0.0' नै हो।
    final rating = (data['rating'] ?? '0.0').toString();
    final reviews = (data['reviews'] ?? '0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WorkerAvatar(uid: workerId, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(S.serviceName(service),
                        style: const TextStyle(color: AppColors.kmMuted)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.kmOrange),
                        const SizedBox(width: 3),
                        Text('$rating  ($reviews)',
                            style:
                                const TextStyle(color: AppColors.kmMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              KmTag(S.distanceLabel(distanceKm),
                  color: AppColors.kmTealBlue, icon: Icons.near_me_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              S.fromPrice(price),
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
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
