// screens/hotel_admin_control_screen.dart
// Super-Admin Hotel Partner Control Dashboard — नयाँ, स्वतन्त्र hub screen।
// app.dart को Admin Home (4-card grid) बाट मात्र पुगिने, अरू कुनै existing
// screen/file छोइएको छैन। Roadmap (previous directive) का ५ वटा क्षेत्र
// यहीँ एउटै ठाउँमा:
//   a) Partner Onboarding & Document Approval  → existing
//      HotelVerificationAdminScreen (hotel_verification_admin_screen.dart)
//      सिधै खोल्ने — त्यो screen पहिल्यै पूरा काम गर्छ, यहाँ दोहोर्‍याइएको
//      छैन।
//   b) Commission Rate per hotel/region          → अझै backend/data-model
//      तयार नभएकोले स्पष्ट "Coming soon" — झूटो/mock UI होइन।
//   c) Room Category & Amenities Master Catalog  → साँचो existing data
//      (models/hotel_models.dart::HotelRoomType + screens/hotel_common.dart::
//      kHotelAmenities) read-only देखाउने — भविष्यमा editable बनाउन सकिने
//      पहिलो step।
//   d) Booking Revenue (live)                     → साँचो `hotel_bookings`
//      collection बाट live sum/count (StreamBuilder) — Payout/Settlement
//      ledger चाहिं अझै schema नभएकोले "Coming soon"।
//   e) Review Moderation (existing screen, अर्को tab) + Dark Map ID
//      (हालको साझा kCloudMapId read-only देखाउने, in-app editable अझै
//      होइन)।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/hotel_models.dart' show HotelRoomType;
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'hotel_common.dart' show kHotelAmenities, hotelAmenityIcon;
import 'hotel_verification_admin_screen.dart';
import 'nearby_common.dart' show kCloudMapId;
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

class HotelAdminControlScreen extends StatelessWidget {
  const HotelAdminControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: 'होटल नियन्त्रण'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    _SectionCard(
                      icon: Icons.fact_check_rounded,
                      gradient: const LinearGradient(
                          colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
                      title: 'Partner Onboarding & Approval',
                      subtitle:
                          'Document verification, approve/reject new hotel partners',
                      countStream: FirebaseFirestore.instance
                          .collection('hotels')
                          .where('status', isEqualTo: 'pending')
                          .snapshots()
                          .map((s) => s.docs.length),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HotelVerificationAdminScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.percent_rounded,
                      gradient: const LinearGradient(
                          colors: [AppColors.kmOrange, AppColors.kmOrangeDeep]),
                      title: 'Commission Rate (per hotel/region)',
                      subtitle: 'Coming soon',
                      badge: 'SOON',
                      onTap: () => _comingSoon(context,
                          'Per-hotel/region commission assignment is planned — not wired up yet.'),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.category_rounded,
                      gradient: const LinearGradient(
                          colors: [AppColors.kmPurple, AppColors.kmPurpleDeep]),
                      title: 'Room Category & Amenities Catalog',
                      subtitle: 'Master list used across all hotel partners',
                      onTap: () => _showCatalogSheet(context),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.payments_rounded,
                      gradient: const LinearGradient(
                          colors: [AppColors.kmPink, AppColors.kmPinkDeep]),
                      title: 'Booking Revenue & Payout Ledger',
                      subtitle: 'Live booking/revenue tracking',
                      onTap: () => _showRevenueSheet(context),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.reviews_rounded,
                      gradient: const LinearGradient(
                          colors: [AppColors.kmRose, AppColors.kmPink]),
                      title: 'Review Moderation',
                      subtitle: 'Ratings & reviews oversight',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HotelVerificationAdminScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.map_rounded,
                      gradient: const LinearGradient(
                          colors: [AppColors.kmTealBlue, AppColors.kmTeal]),
                      title: 'Dark Theme Map ID',
                      subtitle: 'Current Cloud Map ID: $kCloudMapId',
                      badge: 'SOON',
                      onTap: () => _comingSoon(context,
                          'In-app Map ID editing is planned — currently set via the shared kCloudMapId constant.'),
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

  void _comingSoon(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.kmSurface,
        icon: const Icon(Icons.schedule_rounded, color: AppColors.kmOrange),
        title: const Text('Coming soon',
            style: TextStyle(color: AppColors.kmText)),
        content: Text(message,
            style: const TextStyle(color: AppColors.kmMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCatalogSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CatalogSheet(),
    );
  }

  void _showRevenueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RevenueSheet(),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final String title;
  final String subtitle;
  final String? badge;
  final Stream<int>? countStream;
  final VoidCallback onTap;

  const _SectionCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.countStream,
  });

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(gradient: gradient, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.kmInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.kmMuted)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.kmOrange.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      color: AppColors.kmOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 10)),
            )
          else if (countStream != null)
            StreamBuilder<int>(
              stream: countStream,
              builder: (context, snap) {
                final n = snap.data ?? 0;
                if (n <= 0) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.kmRose,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(n > 99 ? '99+' : '$n',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                );
              },
            )
          else
            const Icon(Icons.chevron_right_rounded, color: AppColors.kmMuted),
        ],
      ),
    );
  }
}

/// Room Category + Amenities Master Catalog — साँचो existing data
/// (HotelRoomType.presets/defaultAmenities + kHotelAmenities) read-only।
class _CatalogSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.kmSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            const Text('Room Category & Amenities Catalog',
                style: TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Master list shared across every hotel partner',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 12)),
            const SizedBox(height: 16),
            const Text('Hotel-Level Amenities',
                style: TextStyle(
                    color: AppColors.kmMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in kHotelAmenities)
                  Chip(
                    avatar: Icon(hotelAmenityIcon(a),
                        size: 16, color: AppColors.kmTeal),
                    label: Text(a,
                        style: const TextStyle(color: AppColors.kmText)),
                    backgroundColor: AppColors.kmGlassFill,
                    side: BorderSide(color: AppColors.kmGlassBorder),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Room Categories',
                style: TextStyle(
                    color: AppColors.kmMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
            const SizedBox(height: 8),
            for (final category in HotelRoomType.presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NeonCard(
                  radius: 14,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category,
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final a
                              in HotelRoomType.defaultAmenities[category] ??
                                  const <String>[])
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.kmGlassFill,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.kmGlassBorder),
                              ),
                              child: Text(a,
                                  style: const TextStyle(
                                      color: AppColors.kmMuted, fontSize: 11)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Booking Revenue (live) — साँचो `hotel_bookings` collection बाट
/// StreamBuilder ले count/sum(totalPrice) देखाउने। Payout/settlement ledger
/// अझै schema नभएकोले "Coming soon" नोट मात्र।
class _RevenueSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(
        color: AppColors.kmSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Booking Revenue (live)',
                  style: TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              const SizedBox(height: 4),
              const Text('All hotel_bookings documents, every status',
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 12)),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('hotel_bookings')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: SkeletonList(),
                    );
                  }
                  final docs = snap.data!.docs;
                  final total = docs.fold<double>(
                      0,
                      (a, d) =>
                          a + ((d.data()['totalPrice'] as num?)?.toDouble() ?? 0));
                  return Row(
                    children: [
                      Expanded(
                        child: _statTile(
                            'Total bookings', '${docs.length}', Icons.event_rounded),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile('Gross revenue',
                            'Rs. ${total.toStringAsFixed(0)}',
                            Icons.payments_rounded),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 16, color: AppColors.kmOrange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Partner payout management & settlement ledger — coming soon',
                        style: TextStyle(
                            color: AppColors.kmOrange, fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return NeonCard(
      radius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.kmTeal, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
