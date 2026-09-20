// screens/home_work_route_screen.dart
// सेभ गरेको घर ↔ कार्यस्थल बीचको मार्ग नक्सामा — दुई marker + polyline + दूरी/समय।
// सडक मार्ग OSRM (नि:शुल्क, key नचाहिने) बाट; असफल भए सीधा रेखा + haversine।
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'nearby_common.dart' show haversineKm;

class HomeWorkRouteScreen extends StatefulWidget {
  final Map<String, dynamic> home;
  final Map<String, dynamic> work;
  const HomeWorkRouteScreen({
    super.key,
    required this.home,
    required this.work,
  });

  @override
  State<HomeWorkRouteScreen> createState() => _HomeWorkRouteScreenState();
}

class _HomeWorkRouteScreenState extends State<HomeWorkRouteScreen> {
  GoogleMapController? _map;
  List<LatLng> _route = const [];
  double _km = 0;
  int _minutes = 0;
  bool _realRoute = false;
  bool _loading = true;

  late final LatLng _from = LatLng((widget.home['lat'] as num).toDouble(),
      (widget.home['lng'] as num).toDouble());
  late final LatLng _to = LatLng((widget.work['lat'] as num).toDouble(),
      (widget.work['lng'] as num).toDouble());

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    // straight-line fallback पहिले तयार
    final straightKm = haversineKm(
        _from.latitude, _from.longitude, _to.latitude, _to.longitude);
    _route = [_from, _to];
    _km = straightKm;
    _minutes = _estMinutes(straightKm);

    try {
      final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${_from.longitude},${_from.latitude};${_to.longitude},${_to.latitude}'
          '?overview=full&geometries=geojson');
      final res = await http.get(uri, headers: {
        'User-Agent': 'KaamMitra/1.0'
      }).timeout(const Duration(seconds: 9));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = (body['routes'] as List?) ?? const [];
        if (routes.isNotEmpty) {
          final r = routes.first as Map<String, dynamic>;
          final coords = ((r['geometry']?['coordinates']) as List?) ?? const [];
          final pts = <LatLng>[];
          for (final c in coords) {
            pts.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
          }
          if (pts.length >= 2) {
            _route = pts;
            _km = (r['distance'] as num).toDouble() / 1000.0;
            _minutes = ((r['duration'] as num).toDouble() / 60).round();
            _realRoute = true;
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loading = false);
    _fitBounds();
  }

  int _estMinutes(double km) => (km / 22 * 60).round().clamp(1, 600); // ~22km/h

  void _fitBounds() {
    if (_map == null) return;
    final sw = LatLng(
      min(_from.latitude, _to.latitude),
      min(_from.longitude, _to.longitude),
    );
    final ne = LatLng(
      max(_from.latitude, _to.latitude),
      max(_from.longitude, _to.longitude),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _map?.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: sw, northeast: ne), 80));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(S.routeTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _from, zoom: 12),
            onMapCreated: (c) {
              _map = c;
              _fitBounds();
            },
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर "उल्टो"
            // देखिने बग नआओस्।
            rotateGesturesEnabled: false,
            padding: const EdgeInsets.only(bottom: 170, top: 20),
            markers: {
              Marker(
                markerId: const MarkerId('home'),
                position: _from,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRose),
                infoWindow: InfoWindow(
                    title: S.homeLabelShort,
                    snippet: (widget.home['address'] ?? '').toString()),
              ),
              Marker(
                markerId: const MarkerId('work'),
                position: _to,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueViolet),
                infoWindow: InfoWindow(
                    title: S.workplaceLabelShort,
                    snippet: (widget.work['address'] ?? '').toString()),
              ),
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('route'),
                points: _route,
                color: AppColors.igViolet,
                width: 5,
                patterns: _realRoute
                    ? const []
                    : [PatternItem.dash(24), PatternItem.gap(14)],
              ),
            },
          ),
          if (_loading)
            const Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              ),
            ),

          // ── ride-sharing style summary card ──
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.home_rounded,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (widget.home['label'] ?? S.homeLabelShort).toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: Colors.black38),
                      const SizedBox(width: 6),
                      const Icon(Icons.work_rounded,
                          size: 18, color: AppColors.igViolet),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (widget.work['label'] ?? S.workplaceLabelShort)
                              .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _stat(
                          Icons.straighten_rounded,
                          S.distanceWord,
                          '${_km.toStringAsFixed(_km < 10 ? 1 : 0)} km',
                        ),
                      ),
                      Container(
                          width: 1, height: 34, color: theme.dividerColor),
                      Expanded(
                        child: _stat(
                          Icons.schedule_rounded,
                          S.estTravelTime,
                          S.minutesShort(_minutes),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _realRoute ? S.roadRoute : S.approxRoute,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.igViolet),
              const SizedBox(width: 5),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}
