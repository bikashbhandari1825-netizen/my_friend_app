// screens/salon_detail_screen.dart
//
// Salon / Beauty Appointment Booking — provider profile + service menu।
// service (मूल्य + अवधि) छानेपछि "Book" ले staff/मिति/समय छान्ने
// `SalonBookingScreen` मा लैजान्छ। तल verified (completed-बुकिङ) review हरू।
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/salon_models.dart';
import '../services/salon_chat_service.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import 'salon_booking_screen.dart';
import 'salon_common.dart';
import '../widgets/skeleton.dart';

class SalonDetailScreen extends StatefulWidget {
  final Salon salon;
  const SalonDetailScreen({super.key, required this.salon});

  @override
  State<SalonDetailScreen> createState() => _SalonDetailScreenState();
}

class _SalonDetailScreenState extends State<SalonDetailScreen> {
  late final _salonStream = salonStream(widget.salon.id);
  late final _servicesStream = salonServices(widget.salon.id);
  late final _staffStream = salonStaff(widget.salon.id);
  late final _reviewsStream = salonReviews(widget.salon.id);
  final Set<String> _selected = {};
  int _tab = 0;

  /// माथिको फुल-विथ banner (कभर, नभए logo, नभए gradient) + back बटन + logo।
  Widget _cover(Salon salon) {
    final bannerUrl = salon.coverUrl.isNotEmpty ? salon.coverUrl : salon.logoUrl;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SalonCover(
            url: bannerUrl,
            icon: salonCategoryIcon(salon.category),
            height: 230),
        // पढ्न सजिलो होस् भनेर तलतिर हल्का अँध्यारो ढाल।
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: GlassIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        if (salon.logoUrl.isNotEmpty && salon.coverUrl.isNotEmpty)
          Positioned(
            left: 20,
            bottom: -26,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.kmSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SalonAvatar(
                  url: salon.logoUrl,
                  icon: salonCategoryIcon(salon.category),
                  size: 60,
                  radius: 17),
            ),
          ),
      ],
    );
  }

  /// Booksy जस्तै underline ट्याब: Services · Team · Reviews · Portfolio।
  Widget _tabBar(Salon salon) {
    final labels = [
      'Services',
      'Team',
      'Reviews${salon.ratingCount > 0 ? ' (${salon.ratingCount})' : ''}',
      'Portfolio',
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (_, i) {
          final sel = _tab == i;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = i),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: sel ? AppColors.kmOrange : Colors.transparent,
                      width: 2.5),
                ),
              ),
              child: Text(labels[i],
                  style: TextStyle(
                      color: sel ? AppColors.kmText : AppColors.kmMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
          );
        },
      ),
    );
  }

  Widget _servicesTab(bool loaded, List<SalonService> services) {
    if (!loaded) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: SkeletonList(),
      );
    }
    if (services.isEmpty) {
      return salonCard(
        child: const Text('This salon has not added any services yet.',
            style: TextStyle(color: AppColors.kmMuted)),
      );
    }
    return Column(children: [for (final s in services) _serviceTile(s)]);
  }

  /// Portfolio — सैलुन/कामका फोटो ग्रिड; ट्याप गर्दा ठूलो हेर्न मिल्छ।
  Widget _portfolio(Salon salon) {
    if (salon.photos.isEmpty) {
      return salonCard(
        child: const Text('This salon has not added portfolio photos yet.',
            style: TextStyle(color: AppColors.kmMuted)),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final url in salon.photos)
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(12),
                child: InteractiveViewer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                        imageUrl: url, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            child: SalonAvatar(
                url: url, icon: Icons.image_rounded, size: 200, radius: 12),
          ),
      ],
    );
  }

  Future<void> _call(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  void _book(Salon salon, List<SalonService> all) {
    final picked = all.where((s) => _selected.contains(s.id)).toList();
    if (picked.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SalonBookingScreen(salon: salon, services: picked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          top: false, // कभर फोटो status-bar सम्मै फैलिन्छ
          child: StreamBuilder<Salon?>(
            stream: _salonStream,
            initialData: widget.salon,
            builder: (context, salonSnap) {
              final salon = salonSnap.data ?? widget.salon;
              return StreamBuilder<List<SalonService>>(
                stream: _servicesStream,
                builder: (context, svcSnap) {
                  final services = svcSnap.data ?? const <SalonService>[];
                  // मेटिएको/निष्क्रिय भएको service को छनोट पनि हटाउने।
                  _selected.removeWhere((id) => !services.any((s) => s.id == id));
                  final picked =
                      services.where((s) => _selected.contains(s.id)).toList();
                  final total = picked.fold<double>(0, (a, s) => a + s.price);
                  final mins = picked.fold<int>(0, (a, s) => a + s.durationMin);
                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _cover(salon),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child: _header(salon),
                            ),
                            _tabBar(salon),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: switch (_tab) {
                                0 => _servicesTab(svcSnap.hasData, services),
                                1 => _team(),
                                2 => _reviews(),
                                _ => _portfolio(salon),
                              },
                            ),
                          ],
                        ),
                      ),
                      if (picked.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                          child: KmCtaButton(
                            label:
                                'Book ${picked.length} service${picked.length > 1 ? 's' : ''} · ${formatHotelPrice(total)} · ${salonDurationLabel(mins)}',
                            icon: Icons.event_available_rounded,
                            onPressed: () => _book(salon, services),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(Salon salon) {
    return salonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // कभर माथि ओभरल्याप हुने logo को ठाउँ।
          if (salon.logoUrl.isNotEmpty && salon.coverUrl.isNotEmpty)
            const SizedBox(height: 22),
          Text(salon.name,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  height: 1.2)),
          const SizedBox(height: 8),
          Row(
            children: [
              salonRatingLine(salon, size: 15),
              const SizedBox(width: 10),
              KmTag(salon.category, color: AppColors.kmPurple),
            ],
          ),
          if (salon.address.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.place_rounded,
                    size: 15, color: AppColors.kmMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(salon.address,
                      style: const TextStyle(
                          color: AppColors.kmText, fontSize: 13)),
                ),
              ],
            ),
          ],
          if (salon.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(salon.description,
                style: const TextStyle(
                    color: AppColors.kmMuted, fontSize: 12.5, height: 1.4)),
          ],
          // Message / Call / Video — राइडको साझा chat+call मोड्युल पुन:प्रयोग।
          // आफ्नै salon (मालिक) लाई देखाउँदैन।
          if (FirebaseAuth.instance.currentUser != null &&
              FirebaseAuth.instance.currentUser!.uid != salon.ownerId) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _contactButton(Icons.chat_bubble_rounded, 'Message',
                    () => openSalonChat(context, salon)),
                const SizedBox(width: 8),
                _contactButton(Icons.call_rounded, 'Call',
                    () => openSalonChat(context, salon, callVideo: false)),
                const SizedBox(width: 8),
                _contactButton(Icons.videocam_rounded, 'Video',
                    () => openSalonChat(context, salon, callVideo: true)),
              ],
            ),
          ],
          if (salon.phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _call(salon.phone),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_rounded,
                      size: 15, color: AppColors.kmTeal),
                  const SizedBox(width: 6),
                  Text(salon.phone,
                      style: const TextStyle(
                          color: AppColors.kmTeal,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactButton(IconData icon, String label, VoidCallback onTap) {
    final color = switch (label) {
      'Call' => kNeonBlue,
      'Video' => kNeonPink,
      _ => kNeonTeal,
    };
    return Expanded(
      child: NeonGlassButton(
          icon: icon, label: label, color: color, onTap: onTap),
    );
  }

  Widget _serviceTile(SalonService s) {
    final selected = _selected.contains(s.id);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => setState(() {
        selected ? _selected.remove(s.id) : _selected.add(s.id);
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.kmOrange.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: selected
                  ? AppColors.kmOrange
                  : Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  if (s.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(s.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.kmMuted, fontSize: 12)),
                    ),
                  const SizedBox(height: 4),
                  Text(salonDurationLabel(s.durationMin),
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatHotelPrice(s.price),
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5)),
                const SizedBox(height: 8),
                // Booksy-शैलीको "Book" बटन — छानेपछि "Added ✓"; तलको बारले
                // एकसाथ धेरै सेवा बुक गर्न दिन्छ।
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? Colors.transparent : AppColors.kmOrange,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.kmOrange),
                  ),
                  child: Text(selected ? 'Added ✓' : 'Book',
                      style: TextStyle(
                          color: selected ? AppColors.kmOrange : AppColors.kmInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _team() {
    return StreamBuilder<List<SalonStaff>>(
      stream: _staffStream,
      builder: (context, snap) {
        final staff = snap.data ?? const <SalonStaff>[];
        if (staff.isEmpty) {
          return salonCard(
            child: const Text('No team members listed yet.',
                style: TextStyle(color: AppColors.kmMuted)),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in staff)
              // Booksy-शैलीको टिम कार्ड — ठूलो गोलो फोटो, तल नाम र भूमिका।
              SizedBox(
                width: 96,
                child: Column(
                  children: [
                    SalonAvatar(
                        url: s.photoUrl,
                        icon: Icons.person_rounded,
                        size: 72,
                        radius: 36),
                    const SizedBox(height: 6),
                    Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5)),
                    if (s.title.isNotEmpty)
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.kmMuted, fontSize: 11)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _reviews() {
    return StreamBuilder<List<SalonReview>>(
      stream: _reviewsStream,
      builder: (context, snap) {
        final reviews = snap.data ?? const <SalonReview>[];
        if (reviews.isEmpty) {
          return salonCard(
            child: const Text(
                'No reviews yet. Reviews come only from customers who completed an appointment.',
                style: TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
          );
        }
        return Column(
          children: [
            for (final r in reviews)
              salonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HotelStarRow(rating: r.rating, size: 15),
                        const SizedBox(width: 8),
                        Text(r.reviewerName,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            size: 14, color: AppColors.kmTeal),
                      ],
                    ),
                    if (r.comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.comment,
                          style: const TextStyle(
                              color: AppColors.kmMuted,
                              fontSize: 12.5,
                              height: 1.35)),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
