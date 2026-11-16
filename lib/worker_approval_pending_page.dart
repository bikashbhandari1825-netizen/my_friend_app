// worker_approval_pending_page.dart
// Worker ले दर्ता पेश गरेपछि Admin को स्वीकृति पर्खने screen।
// verificationStatus live सुन्छ — approved भए dashboard, rejected भए फेरि दर्ता।
// जुनसुकै अवस्थामा "लगआउट" बटन छ ताकि प्रयोगकर्ता lock नहोस्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_globals.dart' show activeTestPhone;
import 'auth/dev_login.dart';
import 'driver_registration_flow.dart';
import 'l10n/strings.dart';
import 'screens/document_resync_page.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart' show SecondaryButton;
import 'widgets/glass_ui.dart';
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

  bool _startingFresh = false;

  Future<void> _logout() async {
    await signOutClean();
    if (!mounted) return;
    // नयाँ KaamMitraApp() नबनाउने — same rootNavigatorKey collision bug
    // (देख्नुहोस् email_auth_page.dart मा विस्तृत note)।
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// "Start Fresh" — rejected भएपछि worker/driver role मा नै फेरि फस्नु
  /// नपरोस् भनेर, पूरै account (users/providers/pendingWorkers/
  /// registeredWorkers/notifications + phoneAccounts index + Firebase
  /// Auth) मेटाएर landing page बाट फेरि कुनै पनि role (Worker/Rider/
  /// Employer) छान्न दिने।
  Future<void> _startFresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    final confirm = await showKmDialog<bool>(
      context: context,
      title: 'फेरि सुरु गर्ने?',
      message:
          'यो दर्ता र account पूर्ण रूपमा मेटिनेछ। तपाईं फेरि फोन नम्बरबाट '
          'login गरेर जुनसुकै प्रकार (Worker, Rider/Driver, Employer) '
          'छान्न सक्नुहुन्छ।',
      icon: Icons.restart_alt_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
            label: 'रद्द गर्नुहोस्', onPressed: () => Navigator.pop(context, false)),
        KmDialogAction(
          label: 'मेटाएर फेरि सुरु गर्नुहोस्',
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirm != true) return;
    setState(() => _startingFresh = true);
    try {
      await deleteAccountCascade(uid, phone: phone ?? activeTestPhone);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _startingFresh = false);
      final msg = e.code == 'requires-recent-login'
          ? 'सुरक्षा कारणले, कृपया लगआउट गरेर फेरि लगइन गरी प्रयास गर्नुहोस्।'
          : '${S.errorWord}: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingFresh = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  void _reRegister({bool driverEntry = false}) {
    // BUG FIX: पहिले यहाँ `pushAndRemoveUntil(..., (_) => false)` थियो —
    // यसले Navigator stack का ALL route (यो WorkerApprovalPendingPage पनि
    // root gate को content नै हो, कुनै push बाट होइन) हटाउँथ्यो — root कै
    // auth/users-doc StreamBuilder (गेट) सहित। त्यसपछि registration पेजका
    // `_submit()` हरूले गर्ने `popUntil((route) => route.isFirst)` ले (गेट
    // route नै नष्ट भइसकेकोले) केही फर्काउन नसकी उपयोगकर्ता उहीँ फारममा
    // अड्किन्थ्यो/फेरि दर्ता स्क्रिनमै फर्किन्थ्यो (sign-in पछिको navigation
    // loop)। `push` ले गेट route लाई तल्लो जीवितै राख्छ, ताकि पछि
    // `popUntil(isFirst)` ले सही तरिकाले गेटमै फर्कोस्।
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => driverEntry
              ? const DriverRegistrationFlow()
              : const WorkerRegistrationPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const AuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
              child: Text('Login गर्नुहोस्',
                  style: TextStyle(color: AppColors.kmMuted))),
        ),
      );
    }

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.kmOrange));
              }

              // ROBUSTNESS FIX: Firestore listener त्रुटि (network/permission/
              // offline-with-no-cache) आउँदा पहिले silently `{}` मानेर status
              // 'pending' देखाइदिन्थ्यो — भर्खरै साँच्चै approved भएको worker
              // लाई पनि नेटवर्क हिच्किचाउँदा फेरि "pending" देखिन सक्थ्यो। अब
              // स्पष्ट retry UI।
              if (snapshot.hasError && !snapshot.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 48, color: AppColors.kmMuted),
                        const SizedBox(height: 16),
                        const Text(
                          'डाटा लोड गर्न सकिएन — इन्टरनेट जाँच्नुहोस्।\nCould not load status — check your connection.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.kmText),
                        ),
                        const SizedBox(height: 16),
                        KmCtaButton(
                          expand: false,
                          label: 'फेरि प्रयास गर्नुहोस्',
                          icon: Icons.refresh_rounded,
                          onPressed: () => setState(() {}),
                        ),
                        TextButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout_rounded,
                              color: AppColors.kmMuted),
                          label: const Text('Logout',
                              style: TextStyle(color: AppColors.kmMuted)),
                        ),
                      ],
                    ),
                  ),
                );
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
                final existingService = data['service']?.toString();
                final wasDriver = existingService == 'Bike' ||
                    existingService == 'Car' ||
                    existingService == 'Auto' ||
                    existingService == 'Driver';
                return _rejected(
                    (data['rejectionReason'] ?? '').toString(),
                    driverEntry: wasDriver);
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
              decoration: BoxDecoration(
                color: AppColors.kmSurface.withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                boxShadow: [
                  BoxShadow(
                      color: iconColor.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 1),
                ],
              ),
              child: Icon(icon, size: 58, color: iconColor),
            ),
            const SizedBox(height: 26),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.kmMuted, fontSize: 14, height: 1.45)),
            const SizedBox(height: 28),
            ...extra,
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, color: AppColors.kmMuted),
              label:
                  Text(S.logOut, style: const TextStyle(color: AppColors.kmMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pending({bool docsPending = false}) => _shell(
        icon: Icons.hourglass_top_rounded,
        iconColor: AppColors.kmAmber,
        title: S.isNepali
            ? 'तपाईंको दर्ता पेश गरियो'
            : 'Your registration is submitted',
        body: S.isNepali
            ? 'Admin ले हेरेर स्वीकृत गरेपछि तपाईं काम लिन सक्नुहुनेछ। कृपया पर्खनुहोस् — स्वीकृत हुनेबित्तिकै यो पेज आफै अगाडि बढ्नेछ।'
            : 'Once the admin reviews and approves, you can start taking jobs. This page will move forward automatically once approved.',
        extra: [
          if (docsPending) ...[
            GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      color: AppColors.kmRose, size: 28),
                  const SizedBox(height: 8),
                  Text(S.docsNotUploadedTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.kmText)),
                  const SizedBox(height: 6),
                  Text(S.docsNotUploadedBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.kmMuted)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: KmCtaButton(
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
                  strokeWidth: 2.6, color: AppColors.kmOrange),
            ),
        ],
      );

  Widget _rejected(String reason, {bool driverEntry = false}) => _shell(
        icon: Icons.cancel_rounded,
        iconColor: AppColors.kmRose,
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
            child: KmCtaButton(
              label: S.isNepali ? 'फेरि दर्ता गर्नुहोस्' : 'Register again',
              icon: Icons.refresh_rounded,
              onPressed: () => _reRegister(driverEntry: driverEntry),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: S.isNepali
                  ? 'खाता मेटाएर भूमिका बदल्नुहोस्'
                  : 'Delete & change account type',
              color: AppColors.kmRose,
              onPressed: _startingFresh ? null : _startFresh,
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
                      color: AppColors.kmSurface.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.kmTeal.withValues(alpha: 0.4),
                            blurRadius: 34,
                            spreadRadius: 2),
                      ],
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 100, color: AppColors.kmTeal),
                  ),
                  const SizedBox(height: 24),
                  Text(S.isNepali ? 'स्वीकृत भयो!' : 'Approved!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      S.isNepali
                          ? 'तपाईं अब Sahayatri मा काम गर्न सक्नुहुन्छ'
                          : 'You can now take jobs on Sahayatri',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 14)),
                ],
              ),
            ),
            const Spacer(),
            // तल सानो helper — आवेदन सुरक्षित रहेको सूक्ष्म आश्वासन
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user_rounded,
                    size: 13, color: AppColors.kmMuted),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    S.applicationSafeHelper,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
