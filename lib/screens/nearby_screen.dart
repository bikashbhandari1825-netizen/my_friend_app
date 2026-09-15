// screens/nearby_screen.dart
// "Nearby workers" को list view — GPS दूरी + filter + आफ्नो मूल्य offer (bidding)।
// Geo helper र offer sheet `nearby_common.dart` मा साझा छन् (map view ले पनि प्रयोग गर्छ)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.nearbyTitle)),
      body: _loadingLoc
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
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _query.snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final docs = snap.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return _EmptyNearby();
                        }

                        final workers = docs.map((d) {
                          final data = d.data();
                          final wp = workerPos(data, d.id, _lat, _lng);
                          final km = haversineKm(_lat, _lng, wp.lat, wp.lng);
                          return (data: data, id: d.id, km: km);
                        }).toList()
                          ..sort((a, b) => a.km.compareTo(b.km));

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          physics: const AlwaysScrollableScrollPhysics(),
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
        color: AppColors.lime.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off, size: 18, color: AppColors.lime),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(S.approxLocation, style: const TextStyle(fontSize: 12.5)),
          ),
          TextButton(onPressed: onEnable, child: Text(S.enableLocation)),
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
    final theme = Theme.of(context);
    Widget chip(String value, String label, IconData? icon) {
      final active = value == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSelect(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.lime
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: active ? AppColors.lime : theme.dividerColor),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: active
                          ? AppColors.onLime
                          : theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? AppColors.onLime
                          : theme.colorScheme.onSurface,
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
        Icon(Icons.person_search_rounded,
            size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Center(
          child: Text(S.noWorkersNearby,
              style: Theme.of(context).textTheme.bodyMedium),
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
    final theme = Theme.of(context);
    final name = (data['name'] ?? '').toString();
    final service = (data['service'] ?? '').toString();
    final rating = (data['rating'] ?? '5.0').toString();
    final reviews = (data['reviews'] ?? '0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();

    return AppCard(
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
                            fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(S.serviceName(service),
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.lime),
                        const SizedBox(width: 3),
                        Text('$rating  ($reviews)',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              Pill(S.distanceLabel(distanceKm), icon: Icons.near_me_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              S.fromPrice(price),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
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
