// widgets/complete_job_sheet.dart
// Job Completion & Rating Control — काम "completed" मार्क गर्ने अधिकार
// EMPLOYER-मात्र हो, worker होइन (नगद कारोबार employer-worker बीचै प्रत्यक्ष
// हुने भएकोले — worker आफैंले एकतर्फी रूपमा "भुक्तानी भइसक्यो" भनेर काम बन्द
// गर्न नपाओस्)।
//
// दुई प्रस्ट बाटो:
//   1. Cash — छान्नेबित्तिकै सिधै "Payment received — mark complete" बटन।
//   2. Online — eSewa / Khalti / QR (worker ले payment_methods_screen.dart
//      मा बचत गरेको wallet ID/QR) मध्ये एउटा छान्नुपर्छ; eSewa/Khalti ले
//      हाल कुनै साँचो merchant credential नभएकोले स्पष्ट लेबल गरिएको
//      "Sandbox mode" देखाउँछ (कुनै साँचो पैसा चल्दैन) — "Simulate
//      successful payment" ले नै अघि बढाउँछ; production मा जाँदा त्यो
//      एउटै function (`_simulateOnlinePayment`) लाई साँचो gateway
//      API/SDK कल ले सजिलै साट्न मिल्ने गरी छुट्याइएको छ। QR भने worker
//      कै बचत गरेको ठ्याक्कै QR/wallet ID नै देखाउँछ — real payment
//      त्यही QR स्क्यान गरेर हुन्छ, employer आफैंले "I've paid" थिचेर
//      पुष्टि गर्छ।
// दुवै बाटोमा 5-star rating + optional comment अनिवार्य, र submit गर्दा
// मात्र (कुनै "half-completed" अवस्था बिना) `status` एकैचोटि 'completed'
// मा लेखिन्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_config.dart' show kCommissionRate;
import '../l10n/strings.dart';
import '../screens/job_actions.dart'
    show myWorkerName, purgeSensitiveDataOnCompletion, releaseWorkerActiveJob;
import '../theme/app_theme.dart';
import 'app_ui.dart';
import 'success_feedback.dart';

Future<void> showCompleteJobSheet(
  BuildContext context, {
  required String docId,
  required num amount,
  required String workerUid,
  required String workerName,
  required String service,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CompleteJobSheet(
      docId: docId,
      amount: amount,
      workerUid: workerUid,
      workerName: workerName,
      service: service,
    ),
  );
}

class _CompleteJobSheet extends StatefulWidget {
  final String docId;
  final num amount;
  final String workerUid;
  final String workerName;
  final String service;
  const _CompleteJobSheet({
    required this.docId,
    required this.amount,
    required this.workerUid,
    required this.workerName,
    required this.service,
  });

  @override
  State<_CompleteJobSheet> createState() => _CompleteJobSheetState();
}

class _CompleteJobSheetState extends State<_CompleteJobSheet> {
  // null = अझै छानिएको छैन। 'cash' | 'online'.
  String? _paymentType;
  // 'esewa' | 'khalti' | 'qr' — `_paymentType == 'online'` मात्रै अर्थपूर्ण।
  String? _onlineMethod;
  bool _onlinePaymentConfirmed = false;
  bool _processingOnlinePayment = false;

  // Default 5 — तुरुन्तै "5-star" popup तयार; employer चाहेमा घटाउन सक्छ,
  // तर शून्यमा जान मिल्दैन (कम्तिमा १ नदिई submit गर्न सकिँदैन)।
  int _rating = 5;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  String? _workerEsewaId;
  String? _workerKhaltiId;
  bool _walletIdsLoading = false;

  bool get _canSubmit =>
      _paymentType == 'cash' ||
      (_paymentType == 'online' &&
          _onlineMethod != null &&
          _onlinePaymentConfirmed);

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWorkerWalletIds() async {
    if (_workerEsewaId != null || _walletIdsLoading) return;
    setState(() => _walletIdsLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.workerUid)
          .get();
      final data = doc.data();
      if (mounted) {
        setState(() {
          _workerEsewaId = (data?['esewaId'] ?? '').toString();
          _workerKhaltiId = (data?['khaltiId'] ?? '').toString();
          _walletIdsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _walletIdsLoading = false);
    }
  }

  void _chooseOnlineMethod(String method) {
    setState(() {
      _onlineMethod = method;
      _onlinePaymentConfirmed = false;
    });
    if (method == 'qr') _loadWorkerWalletIds();
  }

  /// eSewa/Khalti — हाल कुनै साँचो merchant credential/API integration
  /// नभएकोले (owner ले चाहेमा पछि यहीँ साँचो gateway SDK/redirect-checkout
  /// ले साट्न मिल्ने), स्पष्ट "Sandbox" label सहितको simulate-भुक्तानी।
  /// कुनै साँचो पैसा यहाँबाट कहिल्यै चल्दैन।
  Future<void> _simulateOnlinePayment() async {
    setState(() => _processingOnlinePayment = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _processingOnlinePayment = false);
    await _markOnlinePaymentConfirmed();
  }

  /// Online भुक्तानी पुष्टि भएको एकै ठाउँ — QR "Confirm Payment Received"
  /// र eSewa/Khalti sandbox simulate दुवैले यही बोलाउँछन्। पुष्टि हुनेबित्तिकै
  /// काम आफैं तुरुन्तै complete हुन्छ — employer ले छुट्टै "Complete Job"
  /// फेरि थिच्नु पर्दैन (Cash मा भने अझै छुट्टै/मत्तनुतक थिच्नुपर्छ, किनकि
  /// त्यो employer आफैंले "मैले नगद दिएँ" भनेर स्वयं-पुष्टि गर्ने कदम हो)।
  Future<void> _markOnlinePaymentConfirmed() async {
    if (!mounted) return;
    setState(() => _onlinePaymentConfirmed = true);
    playSuccessFeedback();
    await _confirm();
  }

  Future<void> _confirm() async {
    if (!_canSubmit || _saving) return;
    setState(() => _saving = true);
    try {
      final me = FirebaseAuth.instance.currentUser;
      final employerName = await myWorkerName(me?.uid);
      final paymentMethod =
          _paymentType == 'cash' ? 'cash' : (_onlineMethod ?? 'online');

      // Automatic Commission Split — Online भुक्तानी (eSewa/Khalti/QR) मा
      // मात्र, किनकि त्यो पैसा प्रणाली/company कै खाता हुँदै (वा त्यसैको
      // हिसाबमा) आउँछ — त्यसैबाट कम्पनीको १०% commission र worker को ९०%
      // payout स्वचालित रूपमा गणना गरी doc मा नै लेखिन्छ (real gateway
      // जोडिँदा यही field हरूले नै actual payout/settlement लाई खुवाउने)।
      // Cash मा भने पैसा सिधै worker को हातमा जान्छ, प्रणालीले छुनै पाउँदैन
      // — त्यसैले त्यहाँ automatic split हुँदैन (commission शून्य, पूरै
      // रकम worker कै, हिसाब/history मा स्पष्ट देखियोस् भनेर explicit रूपमा)।
      final isOnline = _paymentType == 'online';
      final commissionAmount =
          isOnline ? (widget.amount * kCommissionRate) : 0;
      final workerPayoutAmount = widget.amount - commissionAmount;

      final batch = FirebaseFirestore.instance.batch();
      final reviewRef = FirebaseFirestore.instance.collection('reviews').doc();
      batch.set(reviewRef, {
        'targetUid': widget.workerUid,
        'authorUid': me?.uid ?? '',
        'authorName': employerName.isEmpty ? S.customerWord : employerName,
        'rating': _rating,
        'comment': _commentCtrl.text.trim(),
        'service': widget.service,
        'requestId': widget.docId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(
        FirebaseFirestore.instance
            .collection('serviceRequests')
            .doc(widget.docId),
        {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'paymentConfirmed': true,
          'paymentMethod': paymentMethod,
          'paidAmount': widget.amount,
          'commissionAmount': commissionAmount,
          'workerPayoutAmount': workerPayoutAmount,
          'commissionRate': isOnline ? kCommissionRate : 0,
        },
      );
      await batch.commit();
      // काम completed भएपछि तुरुन्तै संवेदनशील chat/phone data सफा — यो
      // UI लाई कुनै हालतमा block नगरोस् (fire-and-forget)।
      unawaited(purgeSensitiveDataOnCompletion(widget.docId));
      // Single Active Job Restriction — काम completed भएपछि worker फेरि
      // अर्को नयाँ काम accept गर्न मिल्ने बनाउने (पोइन्टर खाली)।
      unawaited(releaseWorkerActiveJob(widget.workerUid, widget.docId));
      playSuccessFeedback();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(S.jobMarkedComplete)),
        ]),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  Widget _typeCard(ThemeData theme, String value, String label, IconData icon) {
    final selected = _paymentType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _paymentType = value;
          _onlineMethod = null;
          _onlinePaymentConfirmed = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.igViolet.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: selected ? AppColors.igViolet : theme.dividerColor,
                width: selected ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? AppColors.igViolet : theme.iconTheme.color),
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

  Widget _onlineMethodChip(
      ThemeData theme, String value, String label, Color accent) {
    final selected = _onlineMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _chooseOnlineMethod(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: selected ? accent : theme.dividerColor,
                width: selected ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Icon(
                  value == 'qr'
                      ? Icons.qr_code_2_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: selected ? accent : theme.iconTheme.color,
                  size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? accent : null)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _onlinePaymentPanel(ThemeData theme) {
    final method = _onlineMethod;
    if (method == null) return const SizedBox.shrink();

    if (method == 'qr') {
      final esewa = _workerEsewaId ?? '';
      final khalti = _workerKhaltiId ?? '';
      final payload = esewa.isNotEmpty
          ? 'esewa:$esewa'
          : khalti.isNotEmpty
              ? 'khalti:$khalti'
              : '';
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: _walletIdsLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            : payload.isEmpty
                ? Text(S.notSetYet, style: theme.textTheme.bodySmall)
                : Column(
                    children: [
                      Text(S.scanToPay,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: QrImageView(data: payload, size: 150),
                      ),
                      const SizedBox(height: 10),
                      if (!_onlinePaymentConfirmed)
                        SecondaryButton(
                          label: S.confirmPaymentReceived,
                          icon: Icons.check_circle_outline_rounded,
                          onPressed: _markOnlinePaymentConfirmed,
                        )
                      else
                        _onlineConfirmedBadge(theme),
                    ],
                  ),
      );
    }

    // eSewa / Khalti — sandbox simulate।
    final accent =
        method == 'esewa' ? const Color(0xFF60BB46) : const Color(0xFF5C2D91);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(S.sandboxModeNotice,
                    style: TextStyle(fontSize: 11.5, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_onlinePaymentConfirmed)
            _onlineConfirmedBadge(theme)
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _processingOnlinePayment ? null : _simulateOnlinePayment,
                icon: _processingOnlinePayment
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.bolt_rounded, size: 18),
                label: Text(S.simulatePayment),
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent, foregroundColor: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _onlineConfirmedBadge(ThemeData theme) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 18),
          const SizedBox(width: 6),
          Text(S.paymentSuccessful,
              style: const TextStyle(
                  color: AppColors.success, fontWeight: FontWeight.w800)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
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
                        Text(S.completeJobTitle,
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
                  _typeCard(theme, 'online', S.onlinePaymentLabel,
                      Icons.account_balance_wallet_rounded),
                  const SizedBox(width: 10),
                  _typeCard(theme, 'cash', S.cashPaymentLabel,
                      Icons.payments_outlined),
                ],
              ),
              if (_paymentType == 'online') ...[
                const SizedBox(height: 14),
                Text(S.selectOnlineMethod,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _onlineMethodChip(
                        theme, 'esewa', S.payEsewa, const Color(0xFF60BB46)),
                    const SizedBox(width: 8),
                    _onlineMethodChip(
                        theme, 'khalti', S.payKhalti, const Color(0xFF5C2D91)),
                    const SizedBox(width: 8),
                    _onlineMethodChip(theme, 'qr', S.payQr, AppColors.igViolet),
                  ],
                ),
                _onlinePaymentPanel(theme),
              ],
              const SizedBox(height: 22),
              Text(S.rateWorkerTitle(widget.workerName),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = i < _rating;
                    return GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 38,
                          color: AppColors.igYellow,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: S.addCommentOptional,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _paymentType == 'cash'
                    ? S.confirmPaymentReceived
                    : S.completeAndFinish,
                icon: Icons.check_circle_rounded,
                loading: _saving,
                onPressed: _canSubmit ? _confirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
