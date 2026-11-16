// widgets/complete_job_sheet.dart
// Job Completion & Rating Control — काम "completed" मार्क गर्ने अधिकार
// EMPLOYER-मात्र हो, worker होइन (नगद कारोबार employer-worker बीचै प्रत्यक्ष
// हुने भएकोले — worker आफैंले एकतर्फी रूपमा "भुक्तानी भइसक्यो" भनेर काम बन्द
// गर्न नपाओस्)।
//
// Cash-Only Redesign — पहिले यहाँ eSewa/Khalti/Bank-ConnectIPS/QR गरी ५
// विकल्पको flat selector थियो। अब बाहिरी gateway/QR पूर्ण रूपमा हटाइएको —
// Cash नै एक्लो, सधैं auto-selected विकल्प (dark glassmorphism + emerald
// green theme सहित)। Commission/wallet ledger गणना तर्क (तल `_confirm()`)
// उही पुरानै cash-branch नै हो, अरू कुनै bाटो (company-collected online)
// अब सम्भव नभएकोले हटाइयो — driver-side real-time completion trigger
// (status: 'completed' Firestore लेखाइ, job_route_screen.dart को
// `_statusSub` StreamBuilder ले नै सिधा समात्छ) र walletBalance/walletLedger
// commission-deduction दुवै पहिलेकै अपरिवर्तित transaction बाट नै हुन्छ।
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../screens/job_actions.dart'
    show purgeSensitiveDataOnCompletion;
import '../theme/app_theme.dart';
import 'app_ui.dart';
import 'futuristic_ui.dart';
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
  // Dark Glassmorphism + Emerald Theme — यस modal-भित्र मात्र प्रयोग हुने
  // स्थिर रङ (ambient Theme जे भए पनि, cash card सधैं यही अँध्यारो/हरियो
  // ढाँचामा देखियोस् भनेर)।
  static const _glassBg1 = Color(0xFF0A0E17);
  static const _glassBg2 = Color(0xFF121824);
  static const _emerald = Color(0xFF00E676);
  static const _darkTeal = Color(0xFF059669);
  static const _gold = Color(0xFFFFD700);

  // Ride (Bike/Car/Auto) मा "Job" होइन "Ride" शब्दावली देखियोस् भनेर — अरू
  // सीपयुक्त सेवा (Plumber/Electrician आदि) मा भने "Job" नै यथावत्।
  bool get _isRide =>
      widget.service == 'Bike' ||
      widget.service == 'Car' ||
      widget.service == 'Auto';

  // Interactive 0-Star Rating — डिफल्ट खाली (०) बाट सुरु हुन्छ, `_canSubmit`
  // (तल) ले नै कम्तिमा १ star नदिई submit हुनै नदिने।
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  bool get _canSubmit => _rating >= 1;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_canSubmit || _saving) return;
    setState(() => _saving = true);
    try {
      // रेटिङ, commission/वालेट, review, ledger र status='completed' सबै अब
      // Cloud Function (`completeJob`, Admin SDK, transaction) ले मात्र लेख्छ —
      // रकम पनि सर्भरमा भएको मूल्यबाट; यो फोनले कमिसन वा रेटिङ बदल्न सक्दैन।
      await FirebaseFunctions.instance.httpsCallable('completeJob').call({
        'requestId': widget.docId,
        'rating': _rating,
        'comment': _commentCtrl.text.trim(),
      }).timeout(const Duration(seconds: 30));
      // काम completed भएपछि तुरुन्तै संवेदनशील chat/phone data सफा — यो
      // UI लाई कुनै हालतमा block नगरोस् (fire-and-forget)।
      unawaited(purgeSensitiveDataOnCompletion(widget.docId));
      // Payment Success Card + Auto Navigate Home
      if (!mounted) return;
      await showPaymentSuccessCard(context, isRide: _isRide);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  /// Ultra-Premium Cash Payment Card — एक्लो, auto-selected विकल्प।
  /// Emerald glow border + corner checkmark badge ले "cash नै तयार छ"
  /// भन्ने स्पष्ट देखाउँछ — tap गर्नु पर्दैन, छनोट गर्न केही बाँकी छैन।
  Widget _cashCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _emerald.withValues(alpha: 0.18),
            const Color(0xFF05080F),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _emerald, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: _emerald.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
       borderRadius: BorderRadius.circular(AppRadius.lg),
       child: Stack(
        children: [
          const Positioned.fill(child: NeonGridBackground(color: _emerald)),
          Padding(
           padding: const EdgeInsets.all(18),
           child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _emerald.withValues(alpha: 0.18),
                  boxShadow: [
                    BoxShadow(
                      color: _emerald.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.payments_rounded,
                    color: _emerald, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.cashPaymentLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    const SizedBox(height: 3),
                    Text('Rs. ${widget.amount} · pay the driver directly',
                        style:
                            const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ],
           ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _emerald,
                boxShadow: [
                  BoxShadow(
                      color: _emerald.withValues(alpha: 0.7), blurRadius: 10),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.black, size: 15),
            ),
          ),
        ],
       ),
      ),
    );
  }

  /// Gold/Amber Animated Star — tap गर्नेबित्तिकै bounce (elastic scale-pop)
  /// सहित भरिन्छ।
  Widget _star(int index) {
    final filled = index < _rating;
    return GestureDetector(
      onTap: () => setState(() => _rating = index + 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TweenAnimationBuilder<double>(
          key: ValueKey('star_${index}_$filled'),
          tween: Tween(begin: filled ? 0.5 : 1.0, end: 1.0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 38,
            color: _gold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_glassBg2, _glassBg1],
          ),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          boxShadow: [
            BoxShadow(
              color: _emerald.withValues(alpha: 0.12),
              blurRadius: 30,
              spreadRadius: -4,
            ),
          ],
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
                    color: Colors.white24,
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
                        Text(S.completeJobTitleFor(_isRide),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5)),
                        Text('${S.amountDue}: Rs. ${widget.amount}',
                            style: const TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(S.paymentMethodLabel,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _cashCard(),
              const SizedBox(height: 22),
              Text(S.rateWorkerTitle(widget.workerName),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, _star),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                cursorColor: _emerald,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _glassBg2,
                  hintText: S.addCommentOptional,
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: _emerald, width: 1.6),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
              const SizedBox(height: 20),
              // Primary CTA — Emerald → Dark Teal gradient (directive-तोकिएको
              // रङ), बोल्ड सेतो अक्षर। साझा `PrimaryButton` (widgets/app_ui.dart)
              // ले per-instance gradient दिँदैन भनेर यो modal-भित्रै छुट्टै।
              SizedBox(
                width: double.infinity,
                height: 52,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: _canSubmit && !_saving ? _confirm : null,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        gradient: LinearGradient(
                          colors: _canSubmit
                              ? const [_emerald, _darkTeal]
                              : [
                                  Colors.white24,
                                  Colors.white24,
                                ],
                        ),
                      ),
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(S.completeAndFinish,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15.5)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
