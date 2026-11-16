// screens/hotel_detail_screen.dart
//
// Hotel Booking System — होटल विवरण — फोटो ग्यालरी, amenities grid,
// कोठा-छनोट सूची (छानिएको मिति/guest अनुसार live मूल्य गणना + real-time
// inventory availability — "X left"/"Sold out"), cancellation policy, र
// समीक्षा खण्ड। कोठा छान्दा `HotelCheckoutScreen` खुल्छ (guest details +
// payment + booking सिर्जना — services/hotel_booking_service.dart)।
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hotel_mock_data.dart';
import '../models/hotel_models.dart';
import '../services/hotel_booking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_ui.dart';
import 'hotel_checkout_screen.dart';
import 'hotel_common.dart';
import '../widgets/futuristic_ui.dart';

class HotelDetailScreen extends StatefulWidget {
  final Hotel hotel;
  final HotelSearchQuery? query;
  const HotelDetailScreen({super.key, required this.hotel, this.query});

  @override
  State<HotelDetailScreen> createState() => _HotelDetailScreenState();
}

/// Property Surroundings — साँचो, सर्वविदित Kathmandu Valley landmark (real
/// coordinates), हरेक होटलको आफ्नै `location` (GeoPoint) बाट `haversineKm`
/// (nearby_common.dart, पहिल्यैदेखि यो app भरि प्रयोगमा) ले साँचो दूरी
/// गणना गरिन्छ — कुनै विशेष restaurant/pasal जस्ता साना व्यवसायको नाम
/// fabricate गरिएको छैन (त्यस्तो real POI डेटा यो app मा छैन, त्यसैले
/// "Eat and drink" ले केवल सर्वविदित दायरा/क्षेत्र मात्र देखाउँछ, काल्पनिक
/// विशेष पसलको नाम होइन)।
class _Landmark {
  final String category; // 'Transport' वा 'Attractions'
  final String name;
  final double lat;
  final double lng;
  const _Landmark(this.category, this.name, this.lat, this.lng);
}

const _kLandmarks = [
  _Landmark('Transport', 'Tribhuvan International Airport', 27.6966, 85.3591),
  _Landmark('Transport', 'Ratna Park Bus Station', 27.7049, 85.3137),
  _Landmark('Attractions', 'Kathmandu Durbar Square', 27.7040, 85.3070),
  _Landmark('Attractions', 'Pashupatinath Temple', 27.7106, 85.3486),
  _Landmark('Attractions', 'Boudhanath Stupa', 27.7215, 85.3620),
  _Landmark('Attractions', 'Swayambhunath (Monkey Temple)', 27.7149, 85.2903),
  _Landmark('Attractions', 'Garden of Dreams', 27.7139, 85.3139),
];

class _HotelDetailScreenState extends State<HotelDetailScreen> {
  int _galleryIndex = 0;
  String _surroundingsTab = 'Eat and drink';
  // roomId -> बाँकी खाली युनिट — query भएमा मात्र। पहिले `initState` मा
  // एकपटक मात्र (स्थिर room list माथि) गणना हुन्थ्यो; अब `_roomsSection`
  // कै live stream बाट जुनसुकै बेला नयाँ/अपरिचित room देखिए लगत्तै lazily
  // (हेर्नुहोस् `_ensureAvailabilityChecked`)।
  final Map<String, int> _availability = {};
  final Set<String> _checkingAvailabilityFor = {};

  /// दिइएको [rooms] (room stream को हालको snapshot) मध्ये अझै availability
  /// नजाँचिएका/जाँचिरहेका बाहेकका सबैको लागि एकपटक मात्र `remainingRoomUnits`
  /// कल गर्ने — स्ट्रिम हरेक rebuild मा फेरि-फेरि दोहोर्‍याउन नपरोस् भनेर।
  void _ensureAvailabilityChecked(List<HotelRoom> rooms) {
    final q = widget.query;
    if (q == null) return;
    for (final r in rooms) {
      if (_availability.containsKey(r.id) ||
          _checkingAvailabilityFor.contains(r.id)) {
        continue;
      }
      _checkingAvailabilityFor.add(r.id);
      remainingRoomUnits(r, q.checkIn, q.checkOut).then((remaining) {
        if (!mounted) return;
        setState(() {
          _availability[r.id] = remaining;
          _checkingAvailabilityFor.remove(r.id);
        });
      }).catchError((_) {
        // एउटा कोठाको availability जाँच असफल भए पनि (network/permission)
        // बाँकी कोठाको जाँच जारी राख्ने — "X left" badge त्यो एउटा कोठामा
        // मात्र नदेखिने, पूरै पेज अड्किने होइन। साँचो गेट checkout कै
        // `createHotelBooking()` भित्रको फेरि-जाँचले नै गर्छ।
        if (mounted) setState(() => _checkingAvailabilityFor.remove(r.id));
      });
    }
  }

  void _selectRoom(HotelRoom room, int unitsCount) {
    final q = widget.query;
    if (q == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please search with your travel dates first.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HotelCheckoutScreen(
          hotel: widget.hotel,
          room: room,
          query: q,
          unitsCount: unitsCount,
        ),
      ),
    );
  }

  /// Real-Time Room Status Synchronization — `roomsStreamForHotel` (live
  /// Firestore listener, hotel_mock_data.dart) प्रयोग गर्छ, स्थिर
  /// `mockRoomsForHotel` होइन — partner ले (फरक device/session बाटै) कोठाको
  /// status (Available/Occupied/Needs Cleaning/Out of Order) बदल्नेबित्तिकै
  /// यो guest स्क्रिनले app पुनः नखोली नै तुरुन्तै देख्छ। Partner ले
  /// Occupied/Cleaning/Out-of-Order राखेको कोठा सिधै लुक्छ (`HotelRoom.
  /// isActive`); छानिएको मिति-दायराका लागि सोल्ड-आउट भएको कोठा पनि (हालको
  /// availability जाँच पूरा भइसकेपछि मात्र) त्यसरी नै हराउँछ।
  Widget _roomsSection(Hotel h, HotelSearchQuery? q, int nights) {
    return StreamBuilder<List<HotelRoom>>(
      stream: roomsStreamForHotel(h.id),
      initialData: mockRoomsForHotel(h.id),
      builder: (context, snap) {
        final rooms = snap.data ?? const <HotelRoom>[];
        _ensureAvailabilityChecked(rooms);
        final activeRooms = rooms.where((r) => r.isActive).toList();
        final stillChecking = q != null &&
            activeRooms.any((r) => !_availability.containsKey(r.id));
        final visibleRooms = activeRooms.where((r) {
          if (q == null) return true;
          final remaining = _availability[r.id];
          return remaining == null || remaining > 0;
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (visibleRooms.isEmpty && !stillChecking && activeRooms.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'All rooms are booked for these dates. Try different dates.',
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5),
                ),
              ),
            ...visibleRooms.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RoomTile(
                    room: r,
                    nights: nights,
                    remaining: _availability[r.id],
                    checkingAvailability:
                        q != null && !_availability.containsKey(r.id),
                    onSelect: (units) => _selectRoom(r, units),
                  ),
                )),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hotel Partner Dashboard बाट कोठाको status/मूल्य बदलिएमा तुरुन्तै यो
    // पेज पनि ताजा होस् भनेर — `hotelCatalogVersion` हेर्नुहोस्।
    return ValueListenableBuilder<int>(
      valueListenable: hotelCatalogVersion,
      builder: (context, _, __) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final h = widget.hotel;
    final q = widget.query;
    final reviews = mockReviewsForHotel(h.id);
    final avgRating = averageRating(h.id);
    final nights = q?.nights ?? 1;

    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: KmScreenHeader(title: h.name),
                ),
              ),
              SliverToBoxAdapter(child: _gallery(h)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        Expanded(
                          child: Text(h.name,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ),
                        HotelStarRow(rating: h.starRating, size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 14, color: AppColors.kmMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(h.address,
                              style: const TextStyle(
                                  color: AppColors.kmMuted, fontSize: 13)),
                        ),
                      ],
                    ),
                    // Hotel Contact Numbers — होटलकै आधिकारिक मोबाइल/
                    // landline, सिधा tap-to-dial, Booking Pass कै उस्तै।
                    if (h.officialMobileNumber.isNotEmpty ||
                        h.landlinePhone.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          if (h.officialMobileNumber.isNotEmpty)
                            _contactNumberChip(Icons.phone_iphone_rounded,
                                h.officialMobileNumber),
                          if (h.landlinePhone.isNotEmpty)
                            _contactNumberChip(
                                Icons.phone_rounded, h.landlinePhone),
                        ],
                      ),
                    ],
                    if (reviews.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 15, color: AppColors.kmOrange),
                          const SizedBox(width: 4),
                          Text(avgRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                          Text(' (${reviews.length} reviews)',
                              style: const TextStyle(
                                  color: AppColors.kmMuted, fontSize: 12)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(h.description,
                        style: const TextStyle(
                            color: AppColors.kmText, fontSize: 13.5, height: 1.4)),
                    const SizedBox(height: 20),
                    _heading('Amenities'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: h.amenities
                          .map((a) => _amenityChip(a))
                          .toList(),
                    ),
                    if (reviews.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _ratingBreakdownCard(h, avgRating, reviews),
                    ],
                    if (reviews.any((r) => r.featured)) ...[
                      const SizedBox(height: 22),
                      _featuredGuestQuotes(reviews),
                    ],
                    const SizedBox(height: 22),
                    _heading('Select a room'),
                    if (q != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 10),
                        child: Text(
                          '${_fmt(q.checkIn)} → ${_fmt(q.checkOut)} · $nights night${nights > 1 ? 's' : ''} · ${q.guestsCount} guests',
                          style: const TextStyle(
                              color: AppColors.kmMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 6),
                    _roomsSection(h, q, nights),
                    const SizedBox(height: 10),
                    _heading('Hotel rules & cancellation policy'),
                    const SizedBox(height: 10),
                    _policyCard(h),
                    const SizedBox(height: 22),
                    _heading('Property surroundings'),
                    const SizedBox(height: 10),
                    _surroundingsSection(h),
                    const SizedBox(height: 22),
                    _heading('Reviews'),
                    const SizedBox(height: 10),
                    if (reviews.isEmpty)
                      const Text('No reviews yet.',
                          style: TextStyle(color: AppColors.kmMuted))
                    else
                      ...reviews.map((r) => _reviewTile(r)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _heading(String text) => Text(text,
      style: const TextStyle(
          color: AppColors.kmText, fontWeight: FontWeight.w800, fontSize: 16));

  Widget _amenityChip(String a) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hotelAmenityIcon(a), size: 15, color: AppColors.kmOrange),
            const SizedBox(width: 6),
            Text(a,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _contactNumberChip(IconData icon, String number) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () async {
          try {
            await launchUrl(Uri(scheme: 'tel', path: number));
          } catch (_) {}
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.kmTeal),
            const SizedBox(width: 4),
            Text(number,
                style: const TextStyle(
                    color: AppColors.kmTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ],
        ),
      );

  /// "HH:mm" (24-घण्टा, Hotel.checkInTime/checkOutTime को storage format)
  /// लाई "h:mm AM/PM" मा — hotel_partner_dashboard_screen.dart कै
  /// `_GuestLogbookRow._fmtDateTime` मा भएकै उस्तै 12-घण्टा गणना, यहाँ
  /// `DateTime` होइन time-only string माथि।
  String _formatTime12h(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour24 = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour24 == null || minute == null) return hhmm;
    final h = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final ampm = hour24 >= 12 ? 'PM' : 'AM';
    final mm = minute.toString().padLeft(2, '0');
    return '$h:$mm $ampm';
  }

  Widget _featureChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.kmTeal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.kmTeal.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.kmTeal),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _policyCardTitle(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.kmOrange),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5)),
        ],
      );

  Widget _policyRule(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ),
      );

  /// Booking.com जस्तै संरचित कार्ड — check-in/out, house rules, र
  /// cancellation policy छुट्टाछुट्टै `GlassPanel` मा (एउटै मात्र लामो
  /// paragraph होइन)। Policy text अझै app-व्यापी नै हो — per-hotel
  /// configurable बनाउन hotel registration form मै नयाँ field चाहिन्छ,
  /// यो refactor को दायरा भन्दा बाहिर।
  Widget _policyCard(Hotel h) => Column(
        children: [
          NeonCard(
            padding: const EdgeInsets.all(14),
            radius: AppRadius.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _policyCardTitle(Icons.schedule_rounded, 'Check-in / Check-out'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.login_rounded,
                        size: 16, color: AppColors.kmMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Check-in — From ${_formatTime12h(h.checkInTime)}',
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.logout_rounded,
                        size: 16, color: AppColors.kmMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Check-out — Until ${_formatTime12h(h.checkOutTime)}',
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _featureChip(Icons.support_agent_rounded, '24/7 Front Desk'),
                    _featureChip(Icons.bolt_rounded, 'Express Check-in/Check-out'),
                    _featureChip(Icons.badge_rounded, 'Govt ID Required at Check-in'),
                    _featureChip(Icons.event_available_rounded,
                        'Free Cancellation Available'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          NeonCard(
            padding: const EdgeInsets.all(14),
            radius: AppRadius.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _policyCardTitle(Icons.rule_rounded, 'House Rules'),
                const SizedBox(height: 10),
                Text(h.rules,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          NeonCard(
            padding: const EdgeInsets.all(14),
            radius: AppRadius.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _policyCardTitle(
                    Icons.policy_rounded, 'Cancellation Policy'),
                _policyRule(Icons.check_circle_rounded, Colors.greenAccent,
                    'Free cancellation up to 24 hours before check-in.'),
                _policyRule(Icons.cancel_rounded, Colors.redAccent,
                    'First night is non-refundable if cancelled within 24 hours of check-in.'),
              ],
            ),
          ),
        ],
      );

  /// "Fabulous"/"Excellent"/... — Booking.com कै उस्तै शब्द-तह, /10 scale।
  String _ratingWord(double score) {
    if (score >= 9) return 'Exceptional';
    if (score >= 8) return 'Fabulous';
    if (score >= 7) return 'Very Good';
    if (score >= 6) return 'Good';
    return 'Pleasant';
  }

  Widget _ratingBreakdownCard(
      Hotel h, double avgRating, List<HotelReview> reviews) {
    final base = (avgRating / 5 * 10).clamp(0, 10).toDouble();
    // Guest Quote Chips — वास्तविक review comment बाटै (फेरि लेखिएको/
    // fabricated होइन), खाली comment भएका बाहेक, बढीमा ४ वटा।
    final quotes = reviews
        .map((r) => r.comment.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .take(4)
        .toList();
    return NeonCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(base.toStringAsFixed(1),
                  style: const TextStyle(
                      color: AppColors.kmOrange,
                      fontWeight: FontWeight.w900,
                      fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_ratingWord(base),
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5)),
                    Text(
                        '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Detailed Rating Breakdown — Super Admin ले सेट गरेको साँचो
          // `h.categoryRatings[category]` भए त्यही, नत्र overall rating बाट
          // deterministic estimate मा fallback (हेर्नुहोस् `_categoryOffsets`
          // doc-comment)।
          for (final category in kHotelRatingCategories) ...[
            hotelRatingBar(
                category, categoryRatingFor(h, avgRating, category)),
            const SizedBox(height: 8),
          ],
          if (quotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quotes.map((q) => _guestQuoteChip(q)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// "Guests who stayed here loved" — केवल `featured == true` review (Super
  /// Admin/Partner ले छानेका, `setReviewFeatured`)। कुनै review featured
  /// नभए पनि खण्ड नै नदेखिने (fabricated placeholder होइन, खाली/absent
  /// नै इमानदार डिफल्ट)।
  Widget _featuredGuestQuotes(List<HotelReview> reviews) {
    final featured = reviews.where((r) => r.featured).toList();
    if (featured.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Guests who stayed here loved'),
        const SizedBox(height: 10),
        SizedBox(
          height: 128,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: featured.length,
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsets.only(
                  right: i == featured.length - 1 ? 0 : 10),
              child: _featuredQuoteCard(featured[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _featuredQuoteCard(HotelReview r) {
    final name = r.reviewerName.isEmpty ? 'Guest' : r.reviewerName;
    return Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text('“${r.comment}”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    height: 1.3)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (r.country.isNotEmpty) ...[
                Text(countryFlagEmoji(r.country),
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.kmOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              HotelStarRow(rating: r.rating, size: 11),
            ],
          ),
        ],
      ),
    );
  }

  Widget _guestQuoteChip(String quote) {
    final text = quote.length > 60 ? '${quote.substring(0, 57)}…' : quote;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: AppColors.kmOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.kmOrange.withValues(alpha: 0.25)),
      ),
      child: Text('“$text”',
          style: const TextStyle(
              color: AppColors.kmText,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.3)),
    );
  }

  /// हिँड्दा ~4.5 km/h, गाडीमा ~20 km/h (सहरी ट्राफिक मान्यता) — दुवै
  /// सामान्य अनुमान मात्र हुन्, प्रत्येक दूरी भने साँचो `haversineKm` बाट।
  String _travelEstimate(double km) {
    if (km <= 1.5) {
      final mins = (km / 4.5 * 60).round().clamp(1, 999);
      return '${km.toStringAsFixed(1)} km · $mins min walk';
    }
    final mins = (km / 20 * 60).round().clamp(1, 999);
    return '${km.toStringAsFixed(1)} km · $mins min drive';
  }

  Widget _surroundingsSection(Hotel h) {
    const tabs = ['Eat and drink', 'Transport', 'Attractions'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: tabs.map((t) {
            final selected = _surroundingsTab == t;
            return ChoiceChip(
              label: Text(t),
              selected: selected,
              onSelected: (_) => setState(() => _surroundingsTab = t),
              selectedColor: AppColors.kmOrange,
              labelStyle: TextStyle(
                  color: selected ? AppColors.kmInk : AppColors.kmText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        NeonCard(
          padding: const EdgeInsets.all(14),
          radius: AppRadius.lg,
          child: _surroundingsTab == 'Eat and drink'
              ? _eatAndDrinkPanel(h)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _kLandmarks
                      .where((l) => l.category == _surroundingsTab)
                      .map((l) {
                    final km = haversineKm(h.location.latitude,
                        h.location.longitude, l.lat, l.lng);
                    return _surroundingRow(
                        _surroundingsTab == 'Transport'
                            ? Icons.directions_bus_filled_rounded
                            : Icons.attractions_rounded,
                        l.name,
                        _travelEstimate(km));
                  }).toList(),
                ),
        ),
      ],
    );
  }

  /// "Eat and drink" — यो app मा कुनै real restaurant/café POI डेटा छैन
  /// (fabricate गर्नु गलत हुन्थ्यो), त्यसैले हल्का, इमानदार fallback:
  /// होटलकै आफ्नै "Restaurant" amenity (भए) + सामान्य क्षेत्र-सूचना मात्र।
  Widget _eatAndDrinkPanel(Hotel h) {
    final hasRestaurant = h.amenities.contains('Restaurant');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasRestaurant)
          _surroundingRow(Icons.restaurant_rounded, 'On-site Restaurant',
              'Inside the property'),
        if (hasRestaurant) const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 15, color: AppColors.kmMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Explore cafés and restaurants around ${h.address}.',
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _surroundingRow(IconData icon, String name, String meta) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.kmTeal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(meta,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _reviewTile(HotelReview r) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HotelStarRow(rating: r.rating, size: 13),
                const Spacer(),
                Text(_fmt(r.createdAt),
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            Text(r.comment,
                style: const TextStyle(color: AppColors.kmText, fontSize: 13)),
          ],
        ),
      );

  // Top banner — `hotel.images[]` मात्र (hotel exterior/lobby); कुनै पनि
  // room-specific photo (`room.images[]`, _RoomTile को आफ्नै carousel) यहाँ
  // कहिल्यै मिसिँदैन।
  Widget _gallery(Hotel h) {
    if (h.images.isEmpty) {
      return Container(height: 220, color: AppColors.kmSurface);
    }
    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: h.images.length,
            onPageChanged: (i) => setState(() => _galleryIndex = i),
            itemBuilder: (context, i) => Image.network(
              h.images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppColors.kmSurface),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(h.images.length, (i) {
                final active = i == _galleryIndex;
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
          // Photo Gallery Counter — Booking.com जस्तै "1 / 12" overlay,
          // माथि-दायाँ कुनामा।
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text('${_galleryIndex + 1} / ${h.images.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Room Specifications — यो app मा कोठाको भौतिक क्षेत्रफल/ओछ्यान-प्रकारको
/// छुट्टै field कहिल्यै collect हुँदैन (केवल roomType/capacity/amenities)।
/// त्यसैले यी दुवै roomType/capacity बाटै deterministic रूपमा estimate
/// गरिएको (Booking.com-style display मात्र, partner-input साँचो डेटा होइन)।
String roomBedType(HotelRoom room) {
  final type = room.roomType.toLowerCase();
  if (type.contains('suite')) {
    return room.capacity >= 3 ? '1 King Bed + 1 Sofa Bed' : '1 King Bed';
  }
  if (type.contains('deluxe')) {
    return room.capacity >= 3 ? '2 Double Beds' : '1 Double Bed';
  }
  return room.capacity >= 2 ? '1 Double Bed' : '1 Single Bed';
}

int roomAreaSqm(HotelRoom room) {
  final type = room.roomType.toLowerCase();
  if (type.contains('suite')) return 38;
  if (type.contains('deluxe')) return 25;
  return 18;
}

class _RoomTile extends StatefulWidget {
  final HotelRoom room;
  final int nights;
  final int? remaining;
  final bool checkingAvailability;
  final void Function(int units) onSelect;
  const _RoomTile({
    required this.room,
    required this.nights,
    required this.onSelect,
    this.remaining,
    this.checkingAvailability = false,
  });

  @override
  State<_RoomTile> createState() => _RoomTileState();
}

class _RoomTileState extends State<_RoomTile> {
  int _units = 1;

  @override
  void didUpdateWidget(covariant _RoomTile old) {
    super.didUpdateWidget(old);
    // Unit Selector — availability फेरि-लोड भएर `remaining` घट्यो भने
    // (जस्तै अर्को guest ले बीचमा बुक गरिहाल्यो) छानिएको units त्यो भन्दा
    // बढी नरहोस्।
    final max = _maxUnits();
    if (_units > max) setState(() => _units = max.clamp(1, max));
  }

  int _maxUnits() {
    final cap = widget.remaining ?? widget.room.totalInventory;
    return cap.clamp(1, widget.room.totalInventory == 0 ? 1 : widget.room.totalInventory);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final nights = widget.nights;
    final remaining = widget.remaining;
    final checkingAvailability = widget.checkingAvailability;
    final onSelect = widget.onSelect;
    final total = room.pricePerNight * nights * _units;
    final soldOut = remaining != null && remaining <= 0;
    final maxUnits = _maxUnits();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room Card Photo Carousel — यो कोठाको आफ्नै `room.images[]` मात्र
          // (hotel-level `hotel.images` कहिल्यै यहाँ मिसिँदैन, माथिको
          // `_gallery(h)` top banner ले त्यो छुट्टै देखाउन्छ)। ट्याप गर्दा
          // full-screen preview (`showPhotoGalleryPreview`, hotel_common.dart)।
          if (room.images.isNotEmpty) ...[
            SizedBox(
              height: 86,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: room.images.length,
                itemBuilder: (context, i) => Padding(
                  padding: EdgeInsets.only(
                      right: i == room.images.length - 1 ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => showPhotoGalleryPreview(
                        context, room.images,
                        initialIndex: i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        room.images[i],
                        width: 120,
                        height: 86,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 120,
                            height: 86,
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.roomType,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5)),
                    if (room.roomNumber.isNotEmpty)
                      Text(room.roomNumber,
                          style: const TextStyle(
                              color: AppColors.kmMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              const Icon(Icons.people_alt_rounded,
                  size: 15, color: AppColors.kmMuted),
              const SizedBox(width: 3),
              Text('${room.capacity}',
                  style: const TextStyle(
                      color: AppColors.kmMuted, fontSize: 12.5)),
            ],
          ),
          if (checkingAvailability) ...[
            const SizedBox(height: 6),
            const Text('Checking availability…',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 11)),
          ] else if (remaining != null) ...[
            const SizedBox(height: 8),
            _availabilityBadge(soldOut, remaining),
          ],
          // Room Specifications — area/bed type (estimate, हेर्नुहोस्
          // `roomAreaSqm`/`roomBedType` कै doc-comment) + Private Bathroom
          // (यो app का सबै कोठामा सधैं true — कुनै shared-bathroom concept
          // कहिल्यै मोडेल गरिएको छैन)।
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _specChip(Icons.square_foot_rounded, '${roomAreaSqm(room)} m²'),
              _specChip(Icons.bed_rounded, roomBedType(room)),
              _specChip(Icons.bathtub_rounded, 'Private Bathroom'),
            ],
          ),
          if (room.amenities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: room.amenities
                  .map((a) => Icon(hotelAmenityIcon(a),
                      size: 14, color: AppColors.kmMuted))
                  .toList(),
            ),
          ],
          // Unit Selector — बढीमा हालको उपलब्ध इकाई (`maxUnits`) सम्म मात्र
          // छान्न मिल्ने, ताकि UI आफैंले नै overbooking सिर्जना नगरोस्
          // (साँचो गेट चाहिँ checkout/createHotelBooking को फेरि-जाँच)।
          if (!soldOut && maxUnits > 1) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Units',
                    style: TextStyle(
                        color: AppColors.kmMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _units,
                      dropdownColor: AppColors.kmSurface,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700),
                      items: List.generate(maxUnits, (i) => i + 1)
                          .map((u) => DropdownMenuItem(
                                value: u,
                                child: Text('$u unit${u > 1 ? 's' : ''}'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _units = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatHotelPrice(total),
                      style: const TextStyle(
                          color: AppColors.kmOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  Text(
                      '${formatHotelPrice(room.pricePerNight)}/night × $nights'
                      '${_units > 1 ? ' × $_units units' : ''}',
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 11)),
                ],
              ),
              soldOut
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Text('Sold out',
                          style: TextStyle(
                              color: AppColors.kmMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5)),
                    )
                  : GradientActionButton(
                      icon: Icons.check_rounded,
                      label: 'Select',
                      onPressed: () => onSelect(_units),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _availabilityBadge(bool soldOut, int remaining) {
    final scarce = !soldOut && remaining <= 3;
    final color = soldOut
        ? AppColors.kmPink
        : (scarce ? AppColors.kmOrange : AppColors.kmTeal);
    final label = soldOut
        ? 'Sold out for these dates'
        : scarce
            ? 'Only $remaining unit${remaining == 1 ? '' : 's'} left on our site'
            : 'Available';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }

  Widget _specChip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.kmMuted),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.kmMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      );
}
