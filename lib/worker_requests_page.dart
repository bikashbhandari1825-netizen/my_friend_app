// worker_requests_page.dart
// कामदारको "अनुरोध" tab — आफूले लिएका / bid गरेका कामहरू मात्र।
//  • pending_worker (सिधा अनुरोध) → यही मूल्यमा Accept वा मूल्य बदल्ने
//  • pending_employer_approval → ग्राहकको जवाफ पर्खँदै
//  • accepted / confirmed → सक्रिय काम (Message + स्थान हेर्ने)
// नयाँ खुला कामहरू "कामको सूची" (JobFeedScreen) मा देखिन्छन्।
// कुनै live location tracking छैन (ride-style हटाइयो)।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/strings.dart';
import 'screens/chat_screen.dart';
import 'screens/earnings_screen.dart';
import 'screens/job_actions.dart';
import 'screens/job_feed_screen.dart';
import 'screens/schedule_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';
import 'widgets/counter_offer_card.dart';
import 'widgets/status_badge.dart';

class WorkerRequestsPage extends StatefulWidget {
  const WorkerRequestsPage({super.key});

  @override
  State<WorkerRequestsPage> createState() => _WorkerRequestsPageState();
}

class _WorkerRequestsPageState extends State<WorkerRequestsPage> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  // stream एकपटक मात्र — tab फर्किंदा spinner नआओस्; sort client-side।
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('workerUid', isEqualTo: _uid)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(S.jobRequests,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
        actions: [
          IconButton(
            tooltip: S.scheduleTitle,
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScheduleScreen()),
            ),
          ),
          IconButton(
            tooltip: S.earningsTitle,
            icon: const Icon(Icons.account_balance_wallet_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EarningsScreen()),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: uid == null
            ? const Center(
                child: Text('Login गर्नुहोस्',
                    style: TextStyle(color: Colors.white)))
            : SafeArea(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white));
                    }
                    final docs = (snap.data?.docs ?? []).toList()
                      ..sort((a, b) {
                        // ग्राहकले पठाएको live counter-offer सधैँ सबैभन्दा माथि।
                        final pa =
                            a.data()['status'] == 'pending_worker_counter'
                                ? 0
                                : 1;
                        final pb =
                            b.data()['status'] == 'pending_worker_counter'
                                ? 0
                                : 1;
                        if (pa != pb) return pa - pb;
                        final ta = a.data()['createdAt'];
                        final tb = b.data()['createdAt'];
                        if (ta is Timestamp && tb is Timestamp) {
                          return tb.compareTo(ta);
                        }
                        return 0;
                      });

                    if (docs.isEmpty) {
                      return const _EmptyState();
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _RequestCard(
                        key: ValueKey(docs[i].id),
                        docId: docs[i].id,
                        data: docs[i].data(),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_outlined,
                size: 60, color: Colors.white70),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(S.onlineForJobs,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
}

class _RequestCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _RequestCard({super.key, required this.docId, required this.data});

  Future<void> _callEmployer(BuildContext context) async {
    final phone = (data['employerPhone'] ?? '').toString().trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.noPhoneOnFile)));
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  Future<void> _acceptAtListedPrice(BuildContext context, num price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'accepted',
      'finalPrice': price,
      'acceptedAt': FieldValue.serverTimestamp(),
      // route-map तुरुन्तै काम गरोस् भनेर accept गर्ने क्षणमै worker को
      // स्थान लेख्ने — job_actions.dart कै साझा function (JobRouteScreen
      // खोलेपछि मात्र पर्खनुपर्दैन)।
      ...await workerLocationForWrite(uid),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.jobAccepted)));
    // MainContainer कै active-job watcher ले यो status बदलिएको देखेर आफैं
    // route screen खोल्छ — यहाँबाट छुट्टै नखोल्ने (double-open नहोस् भनेर)।
  }

  /// "काम सकियो" अब सिधै थिच्न मिल्दैन — पहिले भुक्तानी settlement sheet
  /// (नगद/डिजिटल) देखाइन्छ; भुक्तानी confirm भएपछि मात्र status='completed'
  /// लेखिन्छ (Step 3: Job Completion & Payment)।
  Future<void> _collectPaymentAndComplete(BuildContext context) async {
    final amount = (data['finalPrice'] ?? data['proposedPrice'] ?? 0) as num;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSettlementSheet(docId: docId, amount: amount),
    );
  }

  Future<void> _startWork(BuildContext context) async {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.workStarted)));
  }

  Future<void> _counterDialog(BuildContext context, num current) async {
    final controller = TextEditingController(text: current.toString());
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('नयाँ मूल्य प्रस्ताव गर्नुहोस्'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'तपाईंको मूल्य (Rs.)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.igViolet),
            onPressed: () async {
              final newPrice = num.tryParse(controller.text.trim());
              if (newPrice == null) return;
              Navigator.of(dialogContext).pop();
              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'status': 'pending_employer_approval',
                'workerCounterPrice': newPrice,
              });
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('नयाँ मूल्य ग्राहकलाई पठाइयो।')),
              );
            },
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── ग्राहकको live counter-offer मा जवाफ ─────────────────────
  Future<void> _acceptEmployerCounter(BuildContext context, num price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'accepted',
      'finalPrice': price,
      'acceptedAt': FieldValue.serverTimestamp(),
      ...await workerLocationForWrite(uid),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.jobAccepted)));
    // MainContainer कै active-job watcher ले यो status बदलिएको देखेर आफैं
    // route screen खोल्छ — यहाँबाट छुट्टै नखोल्ने (double-open नहोस् भनेर)।
  }

  Future<void> _declineFromCounter(BuildContext context) async {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.decline), backgroundColor: AppColors.danger),
    );
  }

  /// "Decline / Counter back" — कामदारले आफ्नो नयाँ मूल्य ग्राहकलाई फिर्ता
  /// पठाउँछ, वा काम अस्वीकार गर्छ।
  Future<void> _counterBackToEmployer(BuildContext context, num current) async {
    final controller = TextEditingController(text: current.toString());
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.counterBack),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.yourPriceRs,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _declineFromCounter(context);
            },
            child: Text(S.declineJob,
                style: const TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.igViolet),
            onPressed: () async {
              final newPrice = num.tryParse(controller.text.trim());
              if (newPrice == null) return;
              Navigator.of(dialogContext).pop();
              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'status': 'pending_employer_approval',
                'workerCounterPrice': newPrice,
                'counterFrom': 'worker',
                'counteredAt': FieldValue.serverTimestamp(),
              });
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(S.newPriceSentToCustomer)),
              );
            },
            child: Text(S.sendNewPrice,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending_worker').toString();
    final service = (data['service'] ?? '').toString();
    final price = data['proposedPrice'] ?? 0;
    final desc = (data['details'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final lat = (data['employerLat'] as num?)?.toDouble();
    final lng = (data['employerLng'] as num?)?.toDouble();
    final employer = (data['employerName'] ?? 'Customer').toString();
    final active = status == 'accepted' ||
        status == 'confirmed' ||
        status == 'in_progress';

    // ग्राहकले मूल्य काउन्टर गरेको छ → सामान्य कार्डको सट्टा high-impact
    // animated alert देखाउने।
    if (status == 'pending_worker_counter') {
      final prev =
          (data['workerCounterPrice'] ?? data['proposedPrice'] ?? 0) as num;
      final theirOffer = (data['employerCounterPrice'] ?? 0) as num;
      return CounterOfferCard(
        heading: '$employer  ·  ${S.serviceName(service)}',
        previousPrice: prev,
        newPrice: theirOffer,
        onAccept: () => _acceptEmployerCounter(context, theirOffer),
        onCounterBack: () => _counterBackToEmployer(context, prev),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active) ...[
            Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 15, color: AppColors.igViolet),
                const SizedBox(width: 4),
                Text(S.activeJobTitle,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.igViolet)),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: Text('$employer  ·  ${S.serviceName(service)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              StatusBadge(status: status),
            ],
          ),
          if (active || status == 'completed') ...[
            const SizedBox(height: 10),
            JobProgressBar(status: status),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc, style: const TextStyle(fontSize: 13)),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined,
                    size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(address,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text('प्रस्तावित मूल्य: Rs. $price',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (data['workerCounterPrice'] != null)
            Text('तपाईंको मूल्य: Rs. ${data['workerCounterPrice']}',
                style: const TextStyle(
                    color: AppColors.warning, fontWeight: FontWeight.w700)),
          if (data['finalPrice'] != null)
            Text('अन्तिम मूल्य: Rs. ${data['finalPrice']}',
                style: const TextStyle(
                    color: AppColors.success, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (active)
                GradientActionButton(
                  icon: Icons.call_rounded,
                  label: S.callWord,
                  onPressed: () => _callEmployer(context),
                ),
              // सक्रिय काम (accept भइसकेको) भए — साझा RouteMapView कै
              // JobRouteScreen (सडक मार्ग + दूरी/समय + live tracking), स्थिर
              // pin मात्र देखाउने पुरानो JobLocationScreen होइन। अझै स्वीकार
              // नगरेको (browsing मात्र) भए स्थिर pin नै ठीक हो।
              if (active && lat != null && lng != null)
                GradientActionButton(
                  icon: Icons.route_rounded,
                  label: S.viewJobLocation,
                  onPressed: () => openJobRoute(context, docId, data),
                )
              else if (lat != null && lng != null)
                GradientActionButton(
                  icon: Icons.place_rounded,
                  label: S.viewJobLocation,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JobLocationScreen(
                        lat: lat,
                        lng: lng,
                        title: S.serviceName(service),
                        address: address,
                      ),
                    ),
                  ),
                ),
              if (active || status == 'completed')
                GradientActionButton(
                  icon: Icons.chat_bubble_rounded,
                  label: S.messageWord,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        requestId: docId,
                        workerName: employer,
                      ),
                    ),
                  ),
                ),
              if (status == 'accepted' || status == 'confirmed')
                ElevatedButton.icon(
                  onPressed: () => _startWork(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(S.startWork),
                ),
              if (status == 'in_progress')
                ElevatedButton.icon(
                  onPressed: () => _collectPaymentAndComplete(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.payments_rounded, size: 16),
                  label: Text(S.collectPayment),
                ),
              if (status == 'pending_worker') ...[
                OutlinedButton(
                  onPressed: () => _counterDialog(context, price),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.igViolet,
                    side: const BorderSide(color: AppColors.igViolet),
                  ),
                  child: Text(S.offerPrice),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white),
                  onPressed: () => _acceptAtListedPrice(context, price),
                  child: Text(S.accept),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// भुक्तानी settlement sheet — नगद/डिजिटल छानेर confirm गरेपछि मात्र काम
/// "completed" मा जान्छ (Step 3: Job Completion & Payment)।
class _PaymentSettlementSheet extends StatefulWidget {
  final String docId;
  final num amount;
  const _PaymentSettlementSheet({required this.docId, required this.amount});

  @override
  State<_PaymentSettlementSheet> createState() =>
      _PaymentSettlementSheetState();
}

class _PaymentSettlementSheetState extends State<_PaymentSettlementSheet> {
  String _method = 'cash';
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.docId)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'paymentConfirmed': true,
        'paymentMethod': _method,
        'paidAmount': widget.amount,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.jobMarkedComplete)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget methodChip(String value, String label, IconData icon) {
      final selected = _method == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _method = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.igViolet.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: selected
                      ? AppColors.igViolet
                      : theme.dividerColor),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color:
                        selected ? AppColors.igViolet : theme.iconTheme.color),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.igViolet : null)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const LimeIconBadge(Icons.payments_rounded, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.collectPayment,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15.5)),
                      Text('${S.amountDue}: Rs. ${widget.amount}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(S.paymentMethodLabel,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                methodChip('cash', S.cashWord, Icons.payments_outlined),
                const SizedBox(width: 10),
                methodChip(
                    'digital', S.digitalWord, Icons.account_balance_wallet),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: S.confirmPaymentReceived,
              icon: Icons.check_circle_rounded,
              loading: _saving,
              onPressed: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
