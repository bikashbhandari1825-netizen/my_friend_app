// screens/earnings_screen.dart
// कामदारको डिजिटल वालेट + आम्दानी विश्लेषण।
//  • वालेट ब्यालेन्स = कुल (net) आम्दानी  [gross − कमिसन]
//  • जम्मा / यो हप्ता / यो महिना toggle
//  • पछिल्ला ७ दिनको bar chart
//  • हरेक पूरा भएको कामको gross / कमिसन / net breakdown
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'nearby_common.dart';

enum _Range { all, week, month }

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  _Range _range = _Range.all;

  DateTime _dateOf(Map<String, dynamic> d) {
    for (final k in ['completedAt', 'acceptedAt', 'createdAt']) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return DateTime.now();
  }

  num _amountOf(Map<String, dynamic> d) =>
      (d['finalPrice'] ?? d['proposedPrice'] ?? 0) as num;

  bool _inRange(DateTime dt) {
    final now = DateTime.now();
    switch (_range) {
      case _Range.all:
        return true;
      case _Range.week:
        return dt.isAfter(now.subtract(const Duration(days: 7)));
      case _Range.month:
        return dt.isAfter(DateTime(now.year, now.month - 1, now.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pct = (kCommissionRate * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text(S.earningsTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
          child: uid == null
              ? const Center(
                  child: Text('Login गर्नुहोस्',
                      style: TextStyle(color: Colors.white)))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('serviceRequests')
                      .where('workerUid', isEqualTo: uid)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white));
                    }
                    final completed = (snap.data?.docs ?? [])
                        .map((d) => d.data())
                        .where((d) =>
                            (d['status'] ?? '').toString() == 'completed')
                        .toList()
                      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));

                    if (completed.isEmpty) {
                      return _empty();
                    }

                    final inRange =
                        completed.where((d) => _inRange(_dateOf(d))).toList();
                    final gross =
                        inRange.fold<num>(0, (a, d) => a + _amountOf(d));
                    final commission = gross * kCommissionRate;
                    final net = gross - commission;

                    // पछिल्ला ७ दिनको net
                    final today = DateTime.now();
                    final days = List.generate(7, (i) {
                      final day = DateTime(
                          today.year, today.month, today.day - (6 - i));
                      return day;
                    });
                    final perDay = days.map((day) {
                      final g = completed.where((d) {
                        final dt = _dateOf(d);
                        return dt.year == day.year &&
                            dt.month == day.month &&
                            dt.day == day.day;
                      }).fold<num>(0, (a, d) => a + _amountOf(d));
                      return g * (1 - kCommissionRate);
                    }).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        _walletCard(
                            net, gross, commission, pct, inRange.length),
                        const SizedBox(height: 14),
                        _rangeToggle(),
                        const SizedBox(height: 16),
                        _chartCard(days, perDay),
                        const SizedBox(height: 16),
                        Text(S.perJobBreakdown,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        const SizedBox(height: 8),
                        ...inRange.map((d) => _jobRow(d, pct)),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 60, color: Colors.white70),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(S.noEarningsYet,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _walletCard(num net, num gross, num commission, int pct, int jobs) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.igViolet),
              const SizedBox(width: 8),
              Text(S.walletBalance,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Rs. ${net.round()}',
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87)),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat(S.grossEarnings, 'Rs. ${gross.round()}'),
              _miniStat(
                  S.commissionPctLabel(pct), '− Rs. ${commission.round()}'),
              _miniStat(S.jobsCompletedLabel, '$jobs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13.5)),
            Text(label,
                style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          ],
        ),
      );

  Widget _rangeToggle() {
    Widget seg(String label, _Range r) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _range = r),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: _range == r
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _range == r ? AppColors.igViolet : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ),
        );
    return Row(
      children: [
        seg(S.allTime, _Range.all),
        const SizedBox(width: 8),
        seg(S.thisWeek, _Range.week),
        const SizedBox(width: 8),
        seg(S.thisMonth, _Range.month),
      ],
    );
  }

  Widget _chartCard(List<DateTime> days, List<num> perDay) {
    final maxV = perDay.fold<num>(1, (a, b) => b > a ? b : a);
    const wk = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.last7Days,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.black54)),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          perDay[i] > 0 ? perDay[i].round().toString() : '',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.black45),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 6 + (perDay[i] / maxV) * 84,
                          decoration: BoxDecoration(
                            gradient: AppColors.buttonGradient,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(wk[days[i].weekday % 7],
                            style: const TextStyle(
                                fontSize: 9.5, color: Colors.black45)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobRow(Map<String, dynamic> d, int pct) {
    final gross = _amountOf(d);
    final commission = gross * kCommissionRate;
    final net = gross - commission;
    final dt = _dateOf(d);
    final service = (d['service'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0x11833AB4),
            child: Icon(serviceIconFor(service),
                color: AppColors.igViolet, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${S.serviceName(service)} · ${d['employerName'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text(
                    '${dt.day}/${dt.month}/${dt.year}  ·  Rs. ${gross.round()} − ${commission.round()} ($pct%)',
                    style:
                        const TextStyle(fontSize: 10.5, color: Colors.black45)),
              ],
            ),
          ),
          Text('Rs. ${net.round()}',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: AppColors.success)),
        ],
      ),
    );
  }
}
