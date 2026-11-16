// screens/hotel_results_screen.dart
//
// Hotel Booking System — Phase 2: खोजी-परिणाम — List/Map दुवै view, query
// अनुसार मिल्दा होटल मात्र (price/star/amenity/distance filter लागू भएर)।
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/hotel_mock_data.dart';
import '../l10n/strings.dart';
import '../models/hotel_models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_ui.dart';
import 'hotel_common.dart';
import 'hotel_detail_screen.dart';
import 'nearby_common.dart' show kCloudMapId;
import '../widgets/futuristic_ui.dart';

class HotelResultsScreen extends StatefulWidget {
  final HotelSearchQuery query;
  const HotelResultsScreen({super.key, required this.query});

  @override
  State<HotelResultsScreen> createState() => _HotelResultsScreenState();
}

class _HotelResultsScreenState extends State<HotelResultsScreen> {
  bool _mapView = false;

  /// "Destination" फिल्डमा टाइप गरेको text (ठाउँ खोज्न geocode गर्न पनि
  /// उही `destinationLabel` प्रयोग हुन्छ) लाई होटलको नामसँग दाँज्दा — ठ्याक्कै
  /// उस्तै भए सबैभन्दा माथि, त्यसपछि starts-with/contains/word-overlap, कुनै
  /// मेल नखाए 0। Filter होइन, केवल ranking — अरू सबै होटल अझै देखिनेछन्,
  /// नाम खोजेको भए मिल्ने एउटा माथि (Position 1) मात्र आउँछ।
  int _nameMatchScore(String hotelName, String query) {
    final name = hotelName.trim().toLowerCase();
    final q = query.trim().toLowerCase();
    if (q.isEmpty || name.isEmpty) return 0;
    if (name == q) return 100;
    if (name.startsWith(q)) return 80;
    if (name.contains(q)) return 60;
    final nameWords = name.split(RegExp(r'\s+'));
    final qWords = q.split(RegExp(r'\s+'));
    if (qWords.any((w) => w.isNotEmpty && nameWords.contains(w))) return 40;
    return 0;
  }

  List<Hotel> get _matches {
    final q = widget.query;
    final nameQuery = q.destinationLabel;
    return mockHotels.where((h) {
      // Super-Admin verification — pending/rejected होटल guest search मा
      // कहिल्यै नदेखियोस् (owner आफैंले Partner Dashboard मा मात्र हेर्छ)।
      if (h.status != HotelVerificationStatus.approved) return false;
      final price = cheapestActiveRoomPrice(h.id);
      if (price != null &&
          (price < q.priceRange.start || price > q.priceRange.end)) {
        return false;
      }
      if (h.starRating < q.minStarRating) return false;
      if (q.amenities.isNotEmpty &&
          !q.amenities.every((a) => h.amenities.contains(a))) {
        return false;
      }
      final km = distanceKmFromQuery(q, h.location.latitude, h.location.longitude);
      if (km != null && km > q.maxDistanceKm) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final scoreCmp = _nameMatchScore(b.name, nameQuery)
            .compareTo(_nameMatchScore(a.name, nameQuery));
        if (scoreCmp != 0) return scoreCmp;
        return (cheapestActiveRoomPrice(a.id) ?? 0)
            .compareTo(cheapestActiveRoomPrice(b.id) ?? 0);
      });
  }

  void _openDetail(Hotel h) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HotelDetailScreen(hotel: h, query: widget.query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hotel Partner Dashboard बाट कोठाको status/मूल्य बदलिएमा तुरुन्तै
    // यो सूची पनि ताजा होस् भनेर — `hotelCatalogVersion` हेर्नुहोस्।
    return ValueListenableBuilder<int>(
      valueListenable: hotelCatalogVersion,
      builder: (context, _, __) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final results = _matches;
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: KmScreenHeader(
                title: '${results.length} hotels found',
                actions: [
                  IconButton(
                    onPressed: () => setState(() => _mapView = !_mapView),
                    icon: Icon(
                        _mapView ? Icons.list_rounded : Icons.map_rounded,
                        color: AppColors.kmOrange),
                    tooltip: _mapView ? 'List view' : 'Map view',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.query.destinationLabel} · '
                  '${widget.query.nights} night${widget.query.nights > 1 ? 's' : ''} · '
                  '${widget.query.guestsCount} guest${widget.query.guestsCount > 1 ? 's' : ''} · '
                  '${widget.query.rooms} room${widget.query.rooms > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: AppColors.kmMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.hotel_class_rounded,
                                size: 40, color: AppColors.kmMuted),
                            const SizedBox(height: 12),
                            const Text('No hotels match your filters.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.kmMuted)),
                            if (widget.query.destinationLat != null) ...[
                              const SizedBox(height: 6),
                              const Text(
                                'Our current listings are in Nepal (Kathmandu, Lalitpur, Pokhara). '
                                'Try widening the distance filter or searching a Nepal destination.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.kmMuted, fontSize: 11.5),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : (_mapView
                      ? _MapResults(hotels: results, onTap: _openDetail)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                          itemCount: results.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _HotelCard(
                              hotel: results[i],
                              query: widget.query,
                              onTap: () => _openDetail(results[i]),
                            ),
                          ),
                        )),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  final Hotel hotel;
  final HotelSearchQuery query;
  final VoidCallback onTap;
  const _HotelCard(
      {required this.hotel, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final price = cheapestActiveRoomPrice(hotel.id);
    final km = distanceKmFromQuery(
        query, hotel.location.latitude, hotel.location.longitude);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        decoration: neonDecoration(accent: kNeonTeal, radius: AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              child: hotel.images.isEmpty
                  ? Container(color: AppColors.kmSurface)
                  : PageView(
                      children: hotel.images
                          .map((url) => Image.network(url, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: AppColors.kmSurface)))
                          .toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(hotel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                      ),
                      HotelStarRow(rating: hotel.starRating),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          size: 13, color: AppColors.kmMuted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(hotel.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 12)),
                      ),
                      if (km != null) ...[
                        const SizedBox(width: 6),
                        Text('· ${S.distanceLabel(km)}',
                            style: const TextStyle(
                                color: AppColors.kmMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        price != null
                            ? 'from ${formatHotelPrice(price)}/night'
                            : 'Sold out',
                        style: const TextStyle(
                            color: AppColors.kmOrange,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                      GradientActionButton(
                        icon: Icons.arrow_forward_rounded,
                        label: 'Book Now',
                        onPressed: onTap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapResults extends StatelessWidget {
  final List<Hotel> hotels;
  final ValueChanged<Hotel> onTap;
  const _MapResults({required this.hotels, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final center = hotels.isNotEmpty
        ? LatLng(hotels.first.location.latitude, hotels.first.location.longitude)
        : const LatLng(27.7172, 85.3240);
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 13),
      mapId: kCloudMapId,
      markers: hotels.map((h) {
        final price = cheapestActiveRoomPrice(h.id);
        return Marker(
          markerId: MarkerId(h.id),
          position: LatLng(h.location.latitude, h.location.longitude),
          infoWindow: InfoWindow(
            title: h.name,
            snippet: price != null ? formatHotelPrice(price) : 'Sold out',
            onTap: () => onTap(h),
          ),
          onTap: () => onTap(h),
        );
      }).toSet(),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}
