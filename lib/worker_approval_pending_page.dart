// worker_approval_pending_page.dart
// Worker ले दर्ता पेश गरेपछि Admin को स्वीकृति पर्खने screen।
// verificationStatus live सुन्छ — approved भए dashboard, rejected भए फेरि दर्ता।
// जुनसुकै अवस्थामा "लगआउट" बटन छ ताकि प्रयोगकर्ता lock नहोस्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth/dev_login.dart';
import 'l10n/strings.dart';
import 'screens/document_resync_page.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';
import 'worker_registration_page.dart';

class WorkerApprovalPendingPage extends StatefulWidget {
  const WorkerApprovalPendingPage({super.key});

  @override
  State<WorkerApprovalPendingPage> createState() =>
      _WorkerApprovalPendingPageState();
}

class _WorkerApprovalPendingPageState extends State<WorkerApprovalPendingPage> {
  // approved हुँदा transition + celebration app.dart gate ले सम्हाल्छ
  // (WorkerApprovedCelebration मार्फत)। यो page ले बस् static _approved()
  // देखाउँछ — gate ले तुरुन्तै अर्को screen मा लैजान्छ।

  Future<void> _logout() async {
    await signOutClean();
    if (!mounted) return;
    // नयाँ KaamMitraApp() नबनाउने — same rootNavigatorKey collision bug
    // (देख्नुहोस् email_auth_page.dart मा विस्तृत note)।
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _reRegister() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WorkerRegistrationPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Login गर्नुहोस्')));
    }

    return Scaffold(
      body: AppGradientBackground(
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }

              final data = snapshot.data!.data() ?? {};
              final status = (data['verificationStatus'] ??
                      data['workerVerificationStatus'] ??
                      'pending')
                  .toString();

              if (status == 'approved') {
                return _approved();
              }
              if (status == 'rejected' || status == 'declined') {
                return _rejected((data['rejectionReason'] ?? '').toString());
              }
              return _pending(docsPending: data['documentsPending'] == true);
            },
          ),
        ),
      ),
    );
  }

  // ── states ────────────────────────────────────────────────────────────────

  Widget _shell({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
    List<Widget> extra = const [],
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, size: 58, color: iconColor),
            ),
            const SizedBox(height: 26),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 10)])),
            const SizedBox(height: 12),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.45)),
            const SizedBox(height: 28),
            ...extra,
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, color: Colors.white70),
              label:
                  Text(S.logOut, style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pending({bool docsPending = false}) => _shell(
        icon: Icons.hourglass_top_rounded,
        iconColor: AppColors.igOrange,
        title: S.isNepali
            ? 'तपाईंको दर्ता पेश गरियो'
            : 'Your registration is submitted',
        body: S.isNepali
            ? 'Admin ले हेरेर स्वीकृत गरेपछि तपाईं काम लिन सक्नुहुनेछ। कृपया पर्खनुहोस् — स्वीकृत हुनेबित्तिकै यो पेज आफै अगाडि बढ्नेछ।'
            : 'Once the admin reviews and approves, you can start taking jobs. This page will move forward automatically once approved.',
        extra: [
          if (docsPending) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      color: AppColors.danger, size: 28),
                  const SizedBox(height: 8),
                  Text(S.docsNotUploadedTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: Colors.black87)),
                  const SizedBox(height: 6),
                  Text(S.docsNotUploadedBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black54)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: S.reuploadDocuments,
                      icon: Icons.cloud_upload_rounded,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DocumentResyncPage()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ] else
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: Colors.white),
            ),
        ],
      );

  Widget _rejected(String reason) => _shell(
        icon: Icons.cancel_rounded,
        iconColor: AppColors.danger,
        title: S.isNepali
            ? 'तपाईंको दर्ता अस्वीकृत गरियो'
            : 'Your registration was rejected',
        body: reason.isEmpty
            ? (S.isNepali
                ? 'कृपया सही विवरण र कागजातसहित फेरि दर्ता गर्नुहोस्।'
                : 'Please register again with correct details and documents.')
            : '${S.reasonLabel}: $reason',
        extra: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: S.isNepali ? 'फेरि दर्ता गर्नुहोस्' : 'Register again',
              icon: Icons.refresh_rounded,
              onPressed: _reRegister,
            ),
          ),
        ],
      );

  Widget _approved() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          children: [
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.white.withValues(alpha: 0.45),
                            blurRadius: 34,
                            spreadRadius: 2),
                      ],
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 100, color: AppColors.success),
                  ),
                  const SizedBox(height: 24),
                  Text(S.isNepali ? 'स्वीकृत भयो!' : 'Approved!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(color: Colors.black38, blurRadius: 10)
                          ])),
                  const SizedBox(height: 8),
                  Text(
                      S.isNepali
                          ? 'तपाईं अब KaamMitra मा काम गर्न सक्नुहुन्छ'
                          : 'You can now take jobs on KaamMitra',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14)),
                ],
              ),
            ),
            const Spacer(),
            // तल सानो helper — आवेदन सुरक्षित रहेको सूक्ष्म आश्वासन
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_rounded,
                    size: 13, color: Colors.white.withValues(alpha: 0.55)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    S.applicationSafeHelper,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
