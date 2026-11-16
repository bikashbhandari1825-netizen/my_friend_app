// screens/salon_my_appointments_screen.dart
//
// Salon / Beauty Appointment Booking — ग्राहकका सबै अपोइन्टमेन्ट (आउँदो / बितेका)।
// card ट्याप → Booking Pass; बितेकामा एक-ट्याप "Book again"।
import 'package:flutter/material.dart';

import '../models/salon_models.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_booking_screen.dart';
import 'salon_common.dart';
import 'salon_pass_screen.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

class SalonMyAppointmentsScreen extends StatefulWidget {
  const SalonMyAppointmentsScreen({super.key});

  @override
  State<SalonMyAppointmentsScreen> createState() =>
      _SalonMyAppointmentsScreenState();
}

class _SalonMyAppointmentsScreenState extends State<SalonMyAppointmentsScreen> {
  final _stream = myAppointments();

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: 'My appointments'),
              ),
              Expanded(
                child: StreamBuilder<List<SalonAppointment>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Center(
                          child: Text('Could not load your appointments.',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }
                    if (!snap.hasData) {
                      return const SkeletonList();
                    }
                    final all = snap.data!;
                    if (all.isEmpty) {
                      return const Center(
                          child: Text('No appointments yet.',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }
                    final now = DateTime.now();
                    final upcoming = all
                        .where((a) => a.isActive && a.endAt.isAfter(now))
                        .toList()
                      ..sort((a, b) => a.startAt.compareTo(b.startAt));
                    final past = all.where((a) => !upcoming.contains(a)).toList();
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                      children: [
                        if (upcoming.isNotEmpty) ...[
                          salonSectionLabel('UPCOMING'),
                          for (final a in upcoming) _tile(a, canRebook: false),
                        ],
                        if (past.isNotEmpty) ...[
                          salonSectionLabel('PAST'),
                          for (final a in past) _tile(a, canRebook: true),
                        ],
                      ],
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

  Widget _tile(SalonAppointment a, {required bool canRebook}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NeonCard(
        radius: 20,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SalonPassScreen(appointmentId: a.id)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(a.salonName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
                salonStatusTag(a.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                '${salonDateLabel(a.startAt, null)}, ${salonClock(a.startAt, null)} · ${formatHotelPrice(a.totalPrice)}',
                style: const TextStyle(color: AppColors.kmOrange, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(a.serviceNames.join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
            if (canRebook) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => rebookSalonAppointment(context, a),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Book again'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.kmTeal),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
