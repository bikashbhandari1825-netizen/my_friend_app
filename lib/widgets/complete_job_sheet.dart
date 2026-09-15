// widgets/complete_job_sheet.dart
// Job Completion & Rating Control — काम "completed" मार्क गर्ने अधिकार अब
// EMPLOYER-मात्र हो, worker होइन (नगद कारोबार employer-worker बीचै प्रत्यक्ष
// हुने भएकोले — worker आफैंले एकतर्फी रूपमा "भुक्तानी भइसक्यो" भनेर काम बन्द
// गर्न नपाओस्)। "Complete Job" थिचेपछि यही sheet मा भुक्तानी विधि + 5-star
// rating (default 5, घटाउन मिल्ने) एकैचोटि देखिन्छ — employer ले rating
// साथै submit नगरेसम्म `status` कहिल्यै 'completed' मा लेखिँदैन (submit
// आफैं नै त्यो transition हो, बीचमा कुनै "half-completed" अवस्था छैन)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../screens/job_actions.dart'
    show myWorkerName, purgeSensitiveDataOnCompletion, releaseWorkerActiveJob;
import '../theme/app_theme.dart';
import 'app_ui.dart';

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
  String _method = 'cash';
  // Default 5 — तुरुन्तै "5-star" popup तयार; employer चाहेमा घटाउन सक्छ,
  // तर शून्यमा जान मिल्दैन (कम्तिमा १ नदिई submit गर्न सकिँदैन)।
  int _rating = 5;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final me = FirebaseAuth.instance.currentUser;
      final employerName = await myWorkerName(me?.uid);

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
          'paymentMethod': _method,
          'paidAmount': widget.amount,
        },
      );
      await batch.commit();
      // काम completed भएपछि तुरुन्तै संवेदनशील chat/phone data सफा — यो
      // UI लाई कुनै हालतमा block नगरोस् (fire-and-forget)।
      unawaited(purgeSensitiveDataOnCompletion(widget.docId));
      // Single Active Job Restriction — काम completed भएपछि worker फेरि
      // अर्को नयाँ काम accept गर्न मिल्ने बनाउने (पोइन्टर खाली)।
      unawaited(releaseWorkerActiveJob(widget.workerUid, widget.docId));
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

  Widget _methodChip(
      ThemeData theme, String value, String label, IconData icon) {
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
                color: selected ? AppColors.igViolet : theme.dividerColor),
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
                  _methodChip(
                      theme, 'cash', S.cashWord, Icons.payments_outlined),
                  const SizedBox(width: 10),
                  _methodChip(theme, 'digital', S.digitalWord,
                      Icons.account_balance_wallet),
                ],
              ),
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
                label: S.confirmCompleteJob,
                icon: Icons.check_circle_rounded,
                loading: _saving,
                onPressed: _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
