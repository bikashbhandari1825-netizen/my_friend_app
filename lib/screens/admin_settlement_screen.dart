// screens/admin_settlement_screen.dart
// Admin Settlement Dashboard — Wallet & Commission Ledger हेर्ने/settle गर्ने
// ठाउँ (हेर्नुहोस् widgets/complete_job_sheet.dart::_confirm() — हरेक काम
// completed हुँदा त्यहीं `users/{workerUid}.walletBalance` अपडेट हुन्छ र
// एउटा `walletLedger` doc लेखिन्छ)।
//
// walletBalance ऋणात्मक (< 0) भए त्यो worker ले प्रणालीलाई cash-job
// commission तिर्न बाँकी छ; धनात्मक (> 0) भए प्रणालीले त्यो worker लाई
// online-job payout दिन बाँकी छ। यो screen ले दुवै अवस्थाका worker सूचीबद्ध
// गर्छ, तिनका unsettled ledger entry देखाउँछ, र admin ले "Mark Settled"
// थिचेपछि (साँचो पैसा यहाँबाट कहिल्यै transfer हुँदैन — त्यो admin आफैंले
// बैंक/eSewa/khalti मार्फत छुट्टै वास्तविक रूपमा गर्नुपर्छ) ती entry हरू
// settled मार्क गरी एउटा `settlements` doc लेख्छ र walletBalance मा त्यही
// settle भएको रकम मात्र घटाउँछ (पूरै शून्य होइन — बीचमा नयाँ काम completed
// भइसकेको भए त्यो नयाँ delta असर नपरोस् भनेर)।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/skeleton.dart';

class AdminSettlementScreen extends StatelessWidget {
  const AdminSettlementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: 'Wallet Settlement'),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('walletBalance', isNotEqualTo: 0)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const SkeletonList();
                    }
                    final docs = (snap.data?.docs ?? []).toList()
                      ..sort((a, b) {
                        final av =
                            ((a.data()['walletBalance'] as num?) ?? 0).abs();
                        final bv =
                            ((b.data()['walletBalance'] as num?) ?? 0).abs();
                        return bv.compareTo(av);
                      });
                    if (docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No outstanding wallet balances — every worker '
                            'is fully settled.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.kmMuted),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final data = doc.data();
                        final balance =
                            ((data['walletBalance'] as num?) ?? 0).toDouble();
                        final name = (data['name'] ?? 'Worker').toString();
                        final owed = balance < 0;
                        return KmListTile(
                          icon: owed
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          iconBg: LinearGradient(
                              colors: owed
                                  ? [AppColors.kmRose, AppColors.kmPink]
                                  : [AppColors.kmTeal, AppColors.kmTealBlue]),
                          title: name,
                          subtitle: owed
                              ? 'Owes platform Rs. ${(-balance).toStringAsFixed(0)}'
                              : 'Payout pending Rs. ${balance.toStringAsFixed(0)}',
                          onTap: () => _openDetail(context, doc.id, name),
                        );
                      },
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

  void _openDetail(BuildContext context, String workerUid, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettlementDetailSheet(workerUid: workerUid, name: name),
    );
  }
}

class _SettlementDetailSheet extends StatefulWidget {
  final String workerUid;
  final String name;
  const _SettlementDetailSheet({required this.workerUid, required this.name});

  @override
  State<_SettlementDetailSheet> createState() => _SettlementDetailSheetState();
}

class _SettlementDetailSheetState extends State<_SettlementDetailSheet> {
  bool _settling = false;
  bool _justSettled = false;
  double _settledAmount = 0;

  // Drift-proof settle — netAmount अब unsettled ledger entry हरूको sum
  // बाट होइन, बरु worker doc को हालको साँचो `walletBalance` बाट नै लिइन्छ
  // (transaction भित्रै fresh read), र नयाँ balance जहिले पनि ठ्याक्कै ०
  // सेट गरिन्छ। पहिले netAmount लाई ledger entry हरूको sum मात्र मानिँदा,
  // कुनै पुरानो/बाहिरी कारणले walletBalance ledger-sum भन्दा फरक (drift)
  // भइसकेको अवस्थामा — जस्तै entries सबै पहिल्यै settled भइसकेको तर
  // walletBalance अझै ऋणात्मक रहेको केस — settle button नै नदेखिने
  // (entries.isEmpty भए button render नै हुँदैनथ्यो) र त्यो drift कहिल्यै
  // सुधार नहुने बग थियो। अब settle ले सधैं हालको walletBalance लाई
  // authoritative मानेर पूरै शून्य बनाउँछ, चाहे ledger entry भए/नभए।
  Future<void> _markSettled(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> entries) async {
    if (_settling) return;
    setState(() => _settling = true);
    try {
      final admin = FirebaseAuth.instance.currentUser;
      final settlementRef =
          FirebaseFirestore.instance.collection('settlements').doc();
      final ledgerSum = entries.fold<double>(
          0, (a, e) => a + ((e.data()['amount'] as num?)?.toDouble() ?? 0));
      final workerRef =
          FirebaseFirestore.instance.collection('users').doc(widget.workerUid);
      final settledAmount = await FirebaseFirestore.instance
          .runTransaction<double>((tx) async {
        final workerSnap = await tx.get(workerRef);
        final currentBalance =
            (workerSnap.data()?['walletBalance'] as num?)?.toDouble() ?? 0;
        if (currentBalance == 0) return 0;
        for (final e in entries) {
          tx.update(e.reference, {
            'settled': true,
            'settledAt': FieldValue.serverTimestamp(),
            'settlementId': settlementRef.id,
          });
        }
        tx.set(settlementRef, {
          'workerUid': widget.workerUid,
          'adminUid': admin?.uid ?? '',
          'netAmount': currentBalance,
          'ledgerSum': ledgerSum,
          'ledgerEntryIds': entries.map((e) => e.id).toList(),
          'status': 'paid',
          'createdAt': FieldValue.serverTimestamp(),
        });
        // हालको balance जति पनि होस्, settle पछि सधैं ठ्याक्कै शून्य —
        // यसले कुनै पनि ledger-untracked drift लाई समेत स्थायी रूपमा
        // सुधार्छ (increment(-netAmount) भन्दा बढी भरपर्दो)।
        tx.set(
          workerRef,
          {'walletBalance': 0, 'isEligibleForJobs': true},
          SetOptions(merge: true),
        );
        return currentBalance;
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      setState(() {
        _settling = false;
        _justSettled = true;
        _settledAmount = settledAmount;
      });
      // चेकमार्क animation देखाउने समय दिएर मात्र sheet बन्द गर्ने — तुरुन्तै
      // pop गरे "Settled ✓" देखिनेबित्तिकै हराउँथ्यो।
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Settled Rs. ${settledAmount.abs().toStringAsFixed(0)} for ${widget.name}'),
          backgroundColor: AppColors.success,
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _settling = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _typeLabel(String type) => switch (type) {
        'cash_commission_due' => 'Cash job — commission owed',
        'p2p_commission_due' => 'QR (P2P wallet) job — commission owed',
        'online_payout_pending' => 'Online job — payout pending',
        _ => type,
      };

  Widget _settledView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, v, child) =>
                Transform.scale(scale: v, child: child),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 56),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('Settled ✓',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                      fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Rs. ${_settledAmount.abs().toStringAsFixed(0)} settled for ${widget.name}',
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _justSettled
                ? _settledView()
                : Column(
                    key: const ValueKey('detail'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(widget.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Unsettled ledger entries',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Flexible(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.workerUid)
                      .snapshots(),
                  builder: (context, userSnap) {
                    final liveBalance = ((userSnap.data?.data()?['walletBalance']
                                as num?) ??
                            0)
                        .toDouble();
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('walletLedger')
                          .where('workerUid', isEqualTo: widget.workerUid)
                          .where('settled', isEqualTo: false)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: SkeletonList(),
                          );
                        }
                        final entries = (snap.data?.docs ?? []).toList()
                          ..sort((a, b) {
                            final at = a.data()['createdAt'];
                            final bt = b.data()['createdAt'];
                            if (at is Timestamp && bt is Timestamp) {
                              return bt.compareTo(at);
                            }
                            return 0;
                          });
                        if (liveBalance == 0) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Already fully settled.'),
                          );
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entries.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                    'No itemized ledger entries — settling '
                                    'the outstanding balance directly.'),
                              )
                            else
                              Flexible(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: entries.length,
                                  itemBuilder: (context, i) {
                                    final d = entries[i].data();
                                    final amount =
                                        ((d['amount'] as num?) ?? 0).toDouble();
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    _typeLabel((d['type'] ?? '')
                                                        .toString()),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13)),
                                                Text(
                                                    'Gross Rs. ${((d['grossAmount'] as num?) ?? 0).toStringAsFixed(0)}',
                                                    style: theme
                                                        .textTheme.bodySmall),
                                                if ((d['payerWalletId'] ?? '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Text(
                                                      'Payer: ${d['payerWalletId']}',
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                              fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            (amount >= 0 ? '+' : '') +
                                                amount.toStringAsFixed(0),
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: amount >= 0
                                                    ? AppColors.success
                                                    : Colors.red),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                const Text('Net',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Text(
                                  'Rs. ${liveBalance.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _settling
                                    ? null
                                    : () => _markSettled(entries),
                                icon: _settling
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.check_circle_rounded,
                                        size: 18),
                                label: Text(
                                    _settling ? 'Settling…' : 'Mark Settled'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.kmOrange,
                                    foregroundColor: Colors.white),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
