// screens/hotel_common.dart
//
// Hotel Booking System — सबै hotel screen (search/results/detail) ले साझा
// प्रयोग गर्ने सानो helper/widget — nearby_common.dart ले बाँकी app का
// service-provider screen लाई दिने भूमिका यहाँ hotel domain का लागि।
import 'package:flutter/material.dart';

import '../models/hotel_models.dart' show Hotel;
import '../theme/app_theme.dart';
import 'nearby_common.dart' show haversineKm;

export 'nearby_common.dart' show haversineKm;

/// Filter/amenity-grid मा देखिने होटल amenity को निश्चित सूची — hotel
/// partner UI (भविष्य) ले यही सूचीबाट मात्र छान्ने भएकोले UI/आइकन सधैँ
/// predictable रहन्छ।
const List<String> kHotelAmenities = [
  'WiFi',
  'Parking',
  'Pool',
  'AC',
  'Breakfast',
  'Gym',
  'Restaurant',
  'Spa',
];

/// Hotel-level amenity (`kHotelAmenities`) देखि Dynamic Smart Room Amenities
/// (room-level, `HotelRoomType.defaultAmenities` — "Wi-Fi", "AC/Heater",
/// "Smart TV", "Jacuzzi/Bathtub" जस्ता लामो/variant label) सम्म — दुवैका
/// लागि एकै icon-mapper। Exact-match switch होइन, keyword-`contains` (case/
/// hyphen-insensitive) प्रयोग गरिएको — ताकि "Wi-Fi"/"High-speed Wi-Fi"/"wifi"
/// जस्ता भिन्न-भिन्न wording भएका मानले पनि उही icon भेट्टाउन सकोस्।
IconData hotelAmenityIcon(String amenity) {
  final a = amenity.toLowerCase().replaceAll('-', '').replaceAll('/', ' ');
  bool has(String k) => a.contains(k);
  if (has('wifi')) return Icons.wifi_rounded;
  if (has('parking')) return Icons.local_parking_rounded;
  if (has('pool')) return Icons.pool_rounded;
  if (has('jacuzzi') || has('bathtub') || has('bathroom')) {
    return Icons.bathtub_rounded;
  }
  if (has('ac') || has('climate') || has('heater')) {
    return Icons.ac_unit_rounded;
  }
  if (has('breakfast')) return Icons.free_breakfast_rounded;
  if (has('coffee') || has('tea')) return Icons.coffee_rounded;
  if (has('fridge')) return Icons.kitchen_rounded;
  if (has('mini bar') || has('minibar')) return Icons.local_bar_rounded;
  if (has('balcony')) return Icons.balcony_rounded;
  if (has('living area') || has('sofa')) return Icons.weekend_rounded;
  if (has('tv')) return Icons.tv_rounded;
  if (has('desk') || has('workspace')) return Icons.work_outline_rounded;
  if (has('gym')) return Icons.fitness_center_rounded;
  if (has('restaurant')) return Icons.restaurant_rounded;
  if (has('spa')) return Icons.spa_rounded;
  return Icons.check_circle_outline_rounded;
}

/// Booked-amenities display — Guest Booking Pass ("Selected Amenities &
/// Included Services"), Partner Dashboard booking row, र QR Scan
/// Verification Dialog तीनै ठाउँले उस्तै चिप शैली देखाउनका लागि साझा
/// (`HotelBooking.amenities` स्नैपशट प्रयोग गरेर) — duplicate markup नहोस्
/// भनेर।
Widget hotelAmenityChips(List<String> amenities,
    {double fontSize = 11.5, double iconSize = 14, double padV = 6}) {
  if (amenities.isEmpty) return const SizedBox.shrink();
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: amenities
        .map((a) => Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: padV),
              decoration: BoxDecoration(
                color: AppColors.kmOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: AppColors.kmOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(hotelAmenityIcon(a),
                      size: iconSize, color: AppColors.kmOrange),
                  const SizedBox(width: 4),
                  Text(a,
                      style: TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w700,
                          fontSize: fontSize)),
                ],
              ),
            ))
        .toList(),
  );
}

/// Room/Hotel Photo Preview — कुनै पनि room-card carousel thumbnail (वा
/// भविष्यमा अन्य gallery) ट्याप गर्दा खुल्ने full-screen, swipeable preview।
/// Guest ले checkout अघि room interior/bathroom राम्ररी हेर्न सकोस् भनेर
/// (Room Card Photo Carousel, hotel_detail_screen.dart) — माथिकै top-banner
/// `_gallery` (hotel.images) कै dot-indicator शैली दोहोर्याइएको, तर पूरा
/// स्क्रिन + pinch-zoom (`InteractiveViewer`) सहित।
Future<void> showPhotoGalleryPreview(
  BuildContext context,
  List<String> images, {
  int initialIndex = 0,
}) {
  if (images.isEmpty) return Future<void>.value();
  return Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _PhotoGalleryPreview(images: images, initialIndex: initialIndex),
    ),
  );
}

class _PhotoGalleryPreview extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _PhotoGalleryPreview(
      {required this.images, required this.initialIndex});

  @override
  State<_PhotoGalleryPreview> createState() => _PhotoGalleryPreviewState();
}

class _PhotoGalleryPreviewState extends State<_PhotoGalleryPreview> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: widget.initialIndex),
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                child: Center(
                  child: Image.network(
                    widget.images[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
            if (widget.images.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.images.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.kmOrange
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Guest Quote Cards — review मा guest आफैंले भरेको देश-नाम (self-declared
/// caption, `HotelReview.country`) बाट flag emoji। ठूलो ISO-3166 तालिका
/// होइन, यो app मा वास्तवमै आउने (seed + सम्भावित भविष्यका) मुख्य देशहरू
/// मात्र — नचिनेको नाम भए तटस्थ globe emoji (कुनै गलत झण्डा नदेखियोस्)।
String countryFlagEmoji(String country) {
  const flags = {
    'nepal': '🇳🇵',
    'india': '🇮🇳',
    'united kingdom': '🇬🇧',
    'uk': '🇬🇧',
    'united states': '🇺🇸',
    'usa': '🇺🇸',
    'australia': '🇦🇺',
    'japan': '🇯🇵',
    'germany': '🇩🇪',
    'france': '🇫🇷',
    'china': '🇨🇳',
    'canada': '🇨🇦',
    'netherlands': '🇳🇱',
    'south korea': '🇰🇷',
    'singapore': '🇸🇬',
    'thailand': '🇹🇭',
  };
  return flags[country.trim().toLowerCase()] ?? '🌐';
}

/// यो app मा छुट्टाछुट्टै category review कहिल्यै collect हुँदैन — Super Admin
/// ले कुनै होटलको `categoryRatings` नसेट गरेसम्म, overall rating बाटै
/// deterministic estimate (random होइन, स्थिर offset — उही होटलले सधैं
/// उही breakdown देखाओस् भनेर)।
const Map<String, double> kCategoryRatingOffsets = {
  'Cleanliness': 0.3,
  'Comfort': 0.1,
  'Facilities': -0.2,
  'Host': 0.5,
  'Location': 0.6,
  'Value for money': -0.4,
  'WiFi': -0.1,
};

/// [avgRatingOutOf5] (Hotel.starRating/HotelReview average, 0-5 scale) बाट
/// [category] को /10 estimate।
double estimatedCategoryRating(double avgRatingOutOf5, String category) {
  final base = (avgRatingOutOf5 / 5 * 10).clamp(0, 10).toDouble();
  return (base + (kCategoryRatingOffsets[category] ?? 0))
      .clamp(0, 10)
      .toDouble();
}

/// Admin ले साँचो सेट गरेको `h.categoryRatings[category]` भए त्यही, नत्र
/// estimate मा fallback — guest/partner/admin तीनैले यही एउटा साझा function
/// बाटै category score पढ्ने (आ-आफ्नै छुट्टै logic होइन)।
double categoryRatingFor(Hotel h, double avgRatingOutOf5, String category) =>
    h.categoryRatings[category] ?? estimatedCategoryRating(avgRatingOutOf5, category);

/// Detailed Rating Breakdown bar — guest Hotel Details (read-only), Partner
/// Dashboard (read-only), र Super Admin panel (editable form, त्यहाँ यो
/// widget होइन सिधै TextField प्रयोग हुन्छ) तीनैले साझा देखिने शैली।
Widget hotelRatingBar(String label, double score) => Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: score / 10,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(AppColors.kmTeal),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(score.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppColors.kmMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );

/// बाँकी app भरिको `'Rs. $amount'` ढाँचा (l10n/strings.dart भित्रका सबै
/// भाडा/मूल्य string हेर्नुहोस्) सँगै मिल्ने गरी — दशमलव बिनाको round मूल्य।
String formatHotelPrice(num amount) => 'Rs. ${amount.round()}';

/// ५-तारे rating — भरिएको/खाली star icon row, `S.distanceLabel` कै शैलीमा
/// compact।
class HotelStarRow extends StatelessWidget {
  final double rating;
  final double size;
  final Color color;
  const HotelStarRow({
    super.key,
    required this.rating,
    this.size = 14,
    this.color = AppColors.kmOrange,
  });

  @override
  Widget build(BuildContext context) {
    final full = rating.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < full ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: color,
        );
      }),
    );
  }
}

/// खोजी-फारम देखि नतिजा/विवरण पेजसम्म साथै बोकिने एउटै मात्र स्थिर query
/// object — destination/date/guest/filter जे-जति पनि यही एउटा class मा।
class HotelSearchQuery {
  final String destinationLabel;
  final double? destinationLat;
  final double? destinationLng;
  final DateTime checkIn;
  final DateTime checkOut;
  final int adults;
  final int children;
  final int rooms;
  final RangeValues priceRange;
  final int minStarRating; // 0 = कुनै सीमा छैन
  final Set<String> amenities;
  final double maxDistanceKm; // 0/अधिकतम = कुनै सीमा छैन

  const HotelSearchQuery({
    required this.destinationLabel,
    this.destinationLat,
    this.destinationLng,
    required this.checkIn,
    required this.checkOut,
    this.adults = 2,
    this.children = 0,
    this.rooms = 1,
    this.priceRange = const RangeValues(0, 50000),
    this.minStarRating = 0,
    this.amenities = const {},
    this.maxDistanceKm = 50,
  });

  int get nights => checkOut.difference(checkIn).inDays.clamp(1, 1000000);
  int get guestsCount => adults + children;

  HotelSearchQuery copyWith({
    String? destinationLabel,
    double? destinationLat,
    double? destinationLng,
    DateTime? checkIn,
    DateTime? checkOut,
    int? adults,
    int? children,
    int? rooms,
    RangeValues? priceRange,
    int? minStarRating,
    Set<String>? amenities,
    double? maxDistanceKm,
  }) {
    return HotelSearchQuery(
      destinationLabel: destinationLabel ?? this.destinationLabel,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      adults: adults ?? this.adults,
      children: children ?? this.children,
      rooms: rooms ?? this.rooms,
      priceRange: priceRange ?? this.priceRange,
      minStarRating: minStarRating ?? this.minStarRating,
      amenities: amenities ?? this.amenities,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
    );
  }
}

double? distanceKmFromQuery(HotelSearchQuery q, double lat, double lng) {
  if (q.destinationLat == null || q.destinationLng == null) return null;
  return haversineKm(q.destinationLat!, q.destinationLng!, lat, lng);
}
