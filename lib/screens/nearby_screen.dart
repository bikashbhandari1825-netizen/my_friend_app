// screens/nearby_screen.dart
// "Nearby workers" को list view — GPS दूरी + filter + आफ्नो मूल्य offer (bidding)।
// Geo helper र offer sheet `nearby_common.dart` मा साझा छन् (map view ले पनि प्रयोग गर्छ)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_avatar.dart';
import 'nearby_common.dart';
import '../widgets/skeleton.dart';

class NearbyScreen extends StatefulWidget {
  // होम स्क्रिनको कुनै एक category chip (जस्तै Plumber) थिचेर सिधै यहाँ
  // आउँदा सुरुमै त्यही सेवामा फिल्टर भएर देखियोस् भनेर — नदिए (null) सधैँ
  // जस्तै 'सबै' बाट सुरु हुन्छ (side-menu "Providers" कै उस्तै)।
  final String? initialFilter;
  const NearbyScreen({super.key, this.initialFilter});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  double _lat = fallbackLat;
  double _lng = fallbackLng;
  bool _loadingLoc = true;
  bool _approx = false;
  late String _filter = widget.initialFilter ?? 'all';
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
    if (_filter == 'all') return base.limit(200);
    return base.where('service', isEqualTo: _filter).limit(200);
  }

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
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
                          // Category tile (जस्तै "Mechanic") बाट सिधै
                          // आएको भए (`initialFilter` दिइएको) — strict
                          // single-category isolation: "All"/अरू trade
                          // chip नै नदेखाउने, switch गर्ने उपाय नै नदिने।
                          // Side-menu "Providers" बाट (initialFilter
                          // नदिई) आएको साधारण "सबै" directory मा मात्र
                          // chip बार देखिने।
                          if (widget.initialFilter == null)
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
                                    return const SkeletonList();
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
                                        nearest: i == 0,
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
  final bool nearest;

  const _WorkerCard({
    required this.data,
    required this.workerId,
    required this.distanceKm,
    required this.employerLat,
    required this.employerLng,
    this.nearest = false,
  });

  Widget _stat(IconData icon, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final service = (data['service'] ?? '').toString();
    // '5.0' default हटाइयो — नयाँ worker सुरुमा साँच्चै ०/कुनै review
    // नभएको देखिनुपर्छ, admin approve गर्दै लेख्ने मान अब '0.0' नै हो।
    final rating = (data['rating'] ?? '0.0').toString();
    final reviews = (data['reviews'] ?? '0').toString();
    final price = (data['price'] ?? 'Rs. 500').toString();
    final accent = nearest ? kNeonTeal : kNeonViolet;

    return Container(
      padding: const EdgeInsets.all(1.3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.85),
            kNeonBlue.withValues(alpha: 0.18),
            kNeonPink.withValues(alpha: 0.55),
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 18,
              spreadRadius: -2),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C1118), Color(0xFF070A0F)],
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                        colors: [kNeonTeal, kNeonViolet, kNeonPink, kNeonTeal]),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFF05070A)),
                    child: WorkerAvatar(
                        uid: (data['uid'] ?? workerId).toString(), size: 50),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? '—' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          NeonChip(
                              label: S.serviceName(service), color: kNeonBlue),
                          if (nearest)
                            const NeonChip(label: 'NEAREST', color: kNeonTeal),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat(Icons.star_rounded, '$rating ($reviews)',
                    const Color(0xFFFFC145)),
                const SizedBox(width: 8),
                _stat(Icons.near_me_rounded, S.distanceLabel(distanceKm),
                    kNeonBlue),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [
                  kNeonTeal.withValues(alpha: 0.14),
                  kNeonViolet.withValues(alpha: 0.10),
                ]),
                border: Border.all(color: kNeonTeal.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sell_rounded, size: 17, color: kNeonTeal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(S.fromPrice(price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kNeonTeal,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.3)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            NeonActionButton(
              label: S.offerYourPrice,
              icon: Icons.gavel_rounded,
              color: kNeonTeal,
              color2: kNeonViolet,
              filled: true,
              onTap: () => showOfferSheet(
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
      ),
    );
  }
}
