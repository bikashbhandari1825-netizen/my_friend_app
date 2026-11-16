// screens/hotel_verification_admin_screen.dart
//
// Hotel Registration/Onboarding — Super-Admin verification। Standalone
// screen (owner_dashboard_screen.dart कै ठूलो worker-verification tab
// संरचना जानाजानी नछोइकनै) — pending होटलको सूची, Approve/Reject, र
// अपलोड गरेको proof document हेर्ने। firestore.rules ले `status` field
// लाई admin-मात्र लेख्न दिने भएकोले, यहाँको UI-गेट (kAdminEmail जाँच)
// केवल UX सुविधाका लागि हो — साँचो सुरक्षा rules मै छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart' show kAdminEmail;
import '../data/hotel_mock_data.dart';
import '../models/hotel_models.dart';
import '../services/kyc_url.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'hotel_common.dart';
import '../widgets/skeleton.dart';

class HotelVerificationAdminScreen extends StatefulWidget {
  const HotelVerificationAdminScreen({super.key});

  @override
  State<HotelVerificationAdminScreen> createState() =>
      _HotelVerificationAdminScreenState();
}

class _HotelVerificationAdminScreenState
    extends State<HotelVerificationAdminScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = FirebaseAuth.instance.currentUser?.email == kAdminEmail;
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'Hotel Admin'),
              ),
              if (isAdmin)
                TabBar(
                  controller: _tabs,
                  labelColor: AppColors.kmOrange,
                  unselectedLabelColor: AppColors.kmMuted,
                  indicatorColor: AppColors.kmOrange,
                  tabs: const [
                    Tab(text: 'Pending Verification'),
                    Tab(text: 'Ratings & Reviews'),
                  ],
                ),
              Expanded(
                child: !isAdmin
                    ? const Center(
                        child: Text('Admin access only.',
                            style: TextStyle(color: AppColors.kmMuted)))
                    : TabBarView(
                        controller: _tabs,
                        children: const [
                          _PendingVerificationTab(),
                          _RatingsAdminTab(),
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

class _PendingVerificationTab extends StatelessWidget {
  const _PendingVerificationTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('hotels')
          .where('status', isEqualTo: HotelVerificationStatus.pending)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SkeletonList();
        }
        final hotels = snap.data!.docs.map(Hotel.fromDoc).toList();
        if (hotels.isEmpty) {
          return const Center(
            child: Text('No hotels awaiting verification.',
                style: TextStyle(color: AppColors.kmMuted)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          itemCount: hotels.length,
          itemBuilder: (context, i) => _PendingHotelCard(hotel: hotels[i]),
        );
      },
    );
  }
}

class _PendingHotelCard extends StatefulWidget {
  final Hotel hotel;
  const _PendingHotelCard({required this.hotel});

  @override
  State<_PendingHotelCard> createState() => _PendingHotelCardState();
}

class _PendingHotelCardState extends State<_PendingHotelCard> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('hotels')
          .doc(widget.hotel.id)
          .update({'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.hotel.name} marked $status.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDocument(String stored) async {
    String url;
    try {
      // नयाँ दर्ताको Storage path (वा पुरानो URL) लाई admin अनुमतिले resolve।
      url = await resolveKycUrl(stored);
    } catch (_) {
      url = '';
    }
    final uri = Uri.tryParse(url);
    final ok = uri != null &&
        uri.hasScheme &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open document.')),
      );
    }
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$label: ${value.isEmpty ? '—' : value}',
            style: const TextStyle(color: AppColors.kmText, fontSize: 12.5)),
      );

  @override
  Widget build(BuildContext context) {
    final h = widget.hotel;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(h.name,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text(h.address,
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          _infoRow('Business Reg. No.', h.businessRegNumber),
          _infoRow('PAN/VAT No.', h.panVatNumber),
          if (h.documentUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < h.documentUrls.length; i++)
                  OutlinedButton.icon(
                    onPressed: () => _openDocument(h.documentUrls[i]),
                    icon: const Icon(Icons.description_rounded, size: 16),
                    label: Text('Document ${i + 1}'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.kmTealBlue,
                        side: BorderSide(
                            color:
                                AppColors.kmTealBlue.withValues(alpha: 0.5))),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _setStatus(HotelVerificationStatus.rejected),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.kmRose,
                      side: BorderSide(
                          color: AppColors.kmRose.withValues(alpha: 0.5))),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: KmCtaButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy
                      ? null
                      : () => _setStatus(HotelVerificationStatus.approved),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two-Tier Admin Control — Super Admin tab। `mockHotels` (in-memory
/// catalog, `hydrateHotelsFromFirestore` ले पहिल्यै Firestore बाट overlay
/// गरिसकेको) बाटै सूची — seed होटल (htl_1..htl_6, जसको कहिल्यै साँचो
/// Firestore doc नभए पनि) सुरुदेखि नै admin ले सम्पादन गर्न पाओस् भनेर,
/// सिधै Firestore stream (जसले त्यस्ता doc-नभएका होटल कहिल्यै फर्काउँदैन)
/// होइन।
class _RatingsAdminTab extends StatelessWidget {
  const _RatingsAdminTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: hotelCatalogVersion,
      builder: (context, _, __) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: mockHotels.length,
        itemBuilder: (context, i) =>
            _HotelRatingsAdminCard(hotel: mockHotels[i]),
      ),
    );
  }
}

class _HotelRatingsAdminCard extends StatefulWidget {
  final Hotel hotel;
  const _HotelRatingsAdminCard({required this.hotel});

  @override
  State<_HotelRatingsAdminCard> createState() =>
      _HotelRatingsAdminCardState();
}

class _HotelRatingsAdminCardState extends State<_HotelRatingsAdminCard> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final c in kHotelRatingCategories)
      c: TextEditingController(
          text: categoryRatingFor(
                  widget.hotel, averageRating(widget.hotel.id), c)
              .toStringAsFixed(1)),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final ratings = <String, double>{};
    for (final entry in _ctrls.entries) {
      final v = double.tryParse(entry.value.text.trim());
      if (v != null) ratings[entry.key] = v.clamp(0, 10).toDouble();
    }
    updateHotelCategoryRatings(widget.hotel.id, ratings);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.hotel.name} ratings updated.')),
    );
  }

  Future<void> _confirmDelete(HotelReview r) async {
    final ok = await showKmDialog<bool>(
      context: context,
      title: 'Delete this review?',
      message: 'This permanently removes the review for everyone. This '
          'cannot be undone.',
      icon: Icons.delete_forever_rounded,
      actions: [
        KmDialogAction(
            label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
        KmDialogAction(
            label: 'Delete',
            destructive: true,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true) return;
    await deleteHotelReview(r.id);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hotel;
    final reviews = mockReviewsForHotel(h.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(h.name,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          subtitle: Text('${reviews.length} review${reviews.length == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
          iconColor: AppColors.kmOrange,
          collapsedIconColor: AppColors.kmMuted,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Category scores (/10)',
                  style: TextStyle(
                      color: AppColors.kmMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5)),
            ),
            const SizedBox(height: 8),
            for (final category in kHotelRatingCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(category,
                          style: const TextStyle(
                              color: AppColors.kmText, fontSize: 12.5)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrls[category],
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                            color: AppColors.kmText, fontSize: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Ratings'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.kmOrange,
                  side: const BorderSide(color: AppColors.kmOrange),
                ),
              ),
            ),
            if (reviews.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Reviews',
                    style: TextStyle(
                        color: AppColors.kmMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5)),
              ),
              const SizedBox(height: 8),
              for (final r in reviews)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (r.country.isNotEmpty) ...[
                                  Text(countryFlagEmoji(r.country),
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                    r.reviewerName.isEmpty
                                        ? 'Guest'
                                        : r.reviewerName,
                                    style: const TextStyle(
                                        color: AppColors.kmText,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(r.comment,
                                style: const TextStyle(
                                    color: AppColors.kmMuted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: r.featured ? 'Unfeature' : 'Feature',
                        onPressed: () => setReviewFeatured(r.id, !r.featured),
                        icon: Icon(
                            r.featured
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 18,
                            color: r.featured
                                ? AppColors.kmOrange
                                : AppColors.kmMuted),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete review',
                        onPressed: () => _confirmDelete(r),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.kmRose),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
