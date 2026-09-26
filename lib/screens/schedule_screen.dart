// screens/schedule_screen.dart
// कामदारको कामको तालिका — महिना क्यालेन्डर view। जुन दिन काम छ त्यसमा dot;
// दिन थिच्दा तल त्यस दिनका कामहरू (सेवा, समय, ठेगाना, मूल्य) देखिन्छन्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'nearby_common.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateTime.now();

  static const _statuses = {
    'accepted',
    'confirmed',
    'in_progress',
    'completed'
  };

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthName(int m) {
    const en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    const ne = [
      'जनवरी',
      'फेब्रुअरी',
      'मार्च',
      'अप्रिल',
      'मे',
      'जुन',
      'जुलाई',
      'अगस्ट',
      'सेप्टेम्बर',
      'अक्टोबर',
      'नोभेम्बर',
      'डिसेम्बर'
    ];
    return (S.isNepali ? ne : en)[m - 1];
  }

  String _slotLabel(String s) => switch (s) {
        'morning' => S.slotMorning,
        'afternoon' => S.slotAfternoon,
        'evening' => S.slotEvening,
        _ => S.slotAnytime,
      };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: KmScreenHeader(title: S.scheduleTitle),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmMuted)))
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('serviceRequests')
                            .where('workerUid', isEqualTo: uid)
                            .snapshots(),
                        builder: (context, snap) {
                          final jobs = <(DateTime, Map<String, dynamic>)>[];
                          for (final d in snap.data?.docs ?? []) {
                            final data = d.data();
                            if (!_statuses
                                .contains((data['status'] ?? '').toString())) {
                              continue;
                            }
                            final pd = data['preferredDate'];
                            if (pd is! Timestamp) continue;
                            jobs.add((pd.toDate(), data));
                          }

                          final dayJobs = jobs
                              .where((j) => _sameDay(j.$1, _selected))
                              .map((j) => j.$2)
                              .toList();

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: [
                              _calendarCard(jobs),
                              const SizedBox(height: 16),
                              Text(
                                '${_selected.day} ${_monthName(_selected.month)} — ${S.upcomingJobs}',
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              if (dayJobs.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    jobs.isEmpty
                                        ? S.noScheduledJobs
                                        : S.noJobsThisDay,
                                    style: const TextStyle(
                                        color: AppColors.kmMuted),
                                  ),
                                )
                              else
                                ...dayJobs.map(_jobTile),
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

  Widget _calendarCard(List<(DateTime, Map<String, dynamic>)> jobs) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadBlanks = first.weekday % 7; // Sun=0
    final today = DateTime.now();

    bool hasJobs(int day) => jobs.any((j) =>
        j.$1.year == _month.year &&
        j.$1.month == _month.month &&
        j.$1.day == day);

    final cells = <Widget>[];
    for (var i = 0; i < leadBlanks; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isSel = _sameDay(date, _selected);
      final isToday = _sameDay(date, today);
      cells.add(GestureDetector(
        onTap: () => setState(() => _selected = date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: isSel ? AppColors.kmCtaGradient : null,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !isSel
                ? Border.all(color: AppColors.kmOrange, width: 1.4)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isSel ? AppColors.kmInk : AppColors.kmText)),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasJobs(day)
                      ? (isSel ? AppColors.kmInk : AppColors.kmPink)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ));
    }

    const wk = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    const wkNe = ['आ', 'सो', 'मं', 'बु', 'बि', 'शु', 'श'];

    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.kmText),
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text(
                  '${_monthName(_month.month)} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w800,
                      fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.kmText),
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text((S.isNepali ? wkNe : wk)[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.kmMuted)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.82,
            children: cells,
          ),
        ],
      ),
    );
  }

  Widget _jobTile(Map<String, dynamic> d) {
    final service = (d['service'] ?? '').toString();
    final slot = _slotLabel((d['timeSlot'] ?? 'anytime').toString());
    final address = (d['address'] ?? '').toString();
    final price = d['finalPrice'] ?? d['proposedPrice'];
    final status = (d['status'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        radius: AppRadius.md,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.kmOrange.withValues(alpha: 0.16),
              child: Icon(serviceIconFor(service),
                  color: AppColors.kmOrange, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${S.serviceName(service)}  ·  $slot',
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  if (address.isNotEmpty)
                    Text(address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.kmMuted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (price != null)
                  Text('Rs. $price',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.kmPink)),
                Text(
                    status == 'completed'
                        ? (S.isNepali ? 'पूरा' : 'done')
                        : (S.isNepali ? 'तय' : 'booked'),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.kmMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
