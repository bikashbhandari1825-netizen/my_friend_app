// screens/salon_list_screen.dart
//
// Salon / Beauty Appointment Booking — browse screen (home को "Salon & Beauty"
// कार्डको गन्तव्य)। नाम खोजी + category filter, रेटिङ अनुसार क्रमबद्ध।
// माथिको icon ले "My Appointments" खोल्छ।
import 'package:flutter/material.dart';

import '../models/salon_models.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_common.dart';
import 'salon_detail_screen.dart';
import 'salon_my_appointments_screen.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

class SalonListScreen extends StatefulWidget {
  const SalonListScreen({super.key});

  @override
  State<SalonListScreen> createState() => _SalonListScreenState();
}

class _SalonListScreenState extends State<SalonListScreen> {
  // build() मा `activeSalons()` बोलाउँदा हरेक rebuild मा नयाँ stream बन्थ्यो।
  final _stream = activeSalons();
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _category = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(
                  title: 'Salon & Beauty',
                  actions: [
                    GlassIconButton(
                      icon: Icons.event_available_rounded,
                      tooltip: 'My appointments',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SalonMyAppointmentsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: AppColors.kmText),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: kmInputDecoration('Search salons',
                      hint: 'Name or area',
                      suffixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.kmMuted)),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  children: [
                    for (final c in ['All', ...kSalonCategories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                          selectedColor: AppColors.kmOrange,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          labelStyle: TextStyle(
                              color: _category == c
                                  ? AppColors.kmInk
                                  : AppColors.kmText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Salon>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const _Message(
                          icon: Icons.error_outline_rounded,
                          text: 'Could not load salons. Please try again.');
                    }
                    if (!snap.hasData) {
                      return const SkeletonList();
                    }
                    final list = snap.data!.where((s) {
                      if (_category != 'All' && s.category != _category) {
                        return false;
                      }
                      if (_query.isEmpty) return true;
                      return s.name.toLowerCase().contains(_query) ||
                          s.address.toLowerCase().contains(_query);
                    }).toList();
                    if (list.isEmpty) {
                      return const _Message(
                          icon: Icons.content_cut_rounded,
                          text: 'No salons found yet.');
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _SalonCard(salon: list[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.kmMuted),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: AppColors.kmMuted)),
          ],
        ),
      );
}

class _SalonCard extends StatelessWidget {
  final Salon salon;
  const _SalonCard({required this.salon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeonCard(
        radius: 22,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SalonDetailScreen(salon: salon)),
        ),
        child: Row(
          children: [
            SalonAvatar(
              url: salon.logoUrl,
              icon: salonCategoryIcon(salon.category),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(salon.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(
                      salon.address.isEmpty
                          ? salon.category
                          : '${salon.category} · ${salon.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  salonRatingLine(salon),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.kmMuted),
          ],
        ),
      ),
    );
  }
}
