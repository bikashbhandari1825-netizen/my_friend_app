// screens/worker_profile_screen.dart
// ग्राहकले Watchlist बाट tap गरेर कामदारको विवरण हेर्ने स्क्रिन — गन्तव्य/gradient
// hero header + सेतो "sheet" कार्डमा स्थान/अनुभव/मूल्य/verified/सम्पर्क, र तल
// सधैँ स्थिर (sticky) "Send Request" बटन। CTA `bottomNavigationBar` मा भएकोले
// content जतिसुकै लामो भए पनि माथि नै scroll हुन्छ — अघि यहाँ Column +
// `Spacer()` भित्र सबै एकैचोटि कोर्दा सानो स्क्रिनमा कार्ड बटनभन्दा अग्लो भई
// "BOTTOM OVERFLOWED BY 47 PIXELS" देखिन्थ्यो, अब त्यो सम्भवै छैन।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_avatar.dart';
import '../widgets/worker_stats.dart';
import 'chat_screen.dart';
import 'portfolio_screen.dart';

/// Pre-Acceptance Security — worker ले Send Request Accept नगरेसम्म call/
/// message features off। यही एउटै सूचीलाई active-job watcher (main_
/// container.dart) र request/booking screen हरूले पनि "काम अब सक्रिय छ"
/// भन्न प्रयोग गर्छन्, यहाँ पनि सोही convention।
const _kActiveRequestStatuses = {'accepted', 'confirmed', 'in_progress'};

class WorkerProfileScreen extends StatelessWidget {
  final Map<String, String> worker;
  const WorkerProfileScreen({super.key, required this.worker});

  Future<void> _sendServiceRequest(BuildContext context) async {
    final TextEditingController detailsController = TextEditingController();
    final name = worker['name'] ?? '';
    final service = worker['service'] ?? '';

    await showKmDialog(
      context: context,
      title: S.requestServiceFrom(name),
      icon: Icons.send_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.serviceName(service),
              style: const TextStyle(
                  color: AppColors.kmOrange, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: detailsController,
            style: const TextStyle(color: AppColors.kmText),
            decoration:
                kmInputDecoration(S.describeYourTask, hint: S.describeTaskHint),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context),
        ),
        KmDialogAction(
          label: S.sendRequest,
          filled: true,
          onPressed: () async {
            if (detailsController.text.trim().isEmpty) return;

            final priceStr = (worker['price'] ?? 'Rs. 500')
                .replaceAll(RegExp(r'[^0-9]'), '');
            final price = num.tryParse(priceStr) ?? 500;

            final currentUser = FirebaseAuth.instance.currentUser;

            await FirebaseFirestore.instance.collection('serviceRequests').add({
              'workerUid': worker['uid'] ?? '',
              'employerUid': currentUser?.uid ?? '',
              'employerName': currentUser?.email ?? 'Employer',
              'workerName': name,
              'service': service,
              'details': detailsController.text.trim(),
              'proposedPrice': price,
              'status': 'pending_worker',
              'createdAt': FieldValue.serverTimestamp(),
            });

            if (!context.mounted) return;
            Navigator.pop(context);

            await showKmDialog(
              context: context,
              title: S.serviceRequestSentTitle,
              message: S.serviceRequestSentBody,
              icon: Icons.check_circle_rounded,
              iconBg: const LinearGradient(
                  colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
              actions: [
                KmDialogAction(
                  label: S.ok,
                  filled: true,
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final name = worker['name'] ?? '';
    final service = worker['service'] ?? '';
    final location = worker['location'] ?? '';
    final experience = worker['experience'] ?? '';
    final price = worker['price'] ?? '';
    final phone = (worker['phone'] ?? '').trim();
    final uid = worker['uid'] ?? '';
    final vehicleDetails = (worker['vehicleDetails'] ?? '').toString();

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          gradient: AppColors.kmCtaGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 18,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        padding: const EdgeInsets.all(3),
                        child: WorkerAvatar(
                          uid: uid,
                          size: 98,
                          backgroundColor: AppColors.kmSurface,
                          iconColor: AppColors.kmOrange,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.kmText)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: Text(S.serviceName(service),
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                      ),
                      const SizedBox(height: 10),
                      WorkerRatingBadge(uid: uid, onDark: true),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.kmSurface.withValues(alpha: 0.92),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28)),
                          border: Border(
                            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _StatTile(
                                  icon: Icons.work_rounded,
                                  value: experience.isEmpty
                                      ? '—'
                                      : experience,
                                  label: S.experienceLabel,
                                ),
                                const SizedBox(width: 12),
                                _StatTile(
                                  icon: Icons.payments_rounded,
                                  value: price.isEmpty ? '—' : price,
                                  label: S.startingPrice,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _InfoRow(
                              icon: Icons.place_rounded,
                              label: S.locationRowLabel,
                              value: location.isEmpty ? '—' : location,
                            ),
                            if (vehicleDetails.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _InfoRow(
                                icon: Icons.two_wheeler_rounded,
                                label: S.vehicleDetails,
                                value: vehicleDetails,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.kmTeal.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                                border: Border.all(color: AppColors.kmTeal.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded,
                                      size: 18, color: AppColors.kmTeal),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${S.kycVerified} · ${S.documentAvailable}',
                                    style: const TextStyle(
                                        color: AppColors.kmTeal,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            _ContactSection(
                              workerUid: uid,
                              workerName: name,
                              phone: phone,
                            ),
                            const SizedBox(height: 12),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PortfolioScreen(workerUid: uid),
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.1)),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.photo_library_rounded,
                                          color: AppColors.kmOrange),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(S.workPortfolio,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: AppColors.kmText)),
                                      ),
                                      const Icon(Icons.chevron_right_rounded,
                                          color: AppColors.kmMuted),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            color: AppColors.kmSurface.withValues(alpha: 0.94),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: KmCtaButton(
              label: S.sendRequest,
              icon: Icons.send_rounded,
              onPressed: () => _sendServiceRequest(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pre-Acceptance Security — यो employer र worker बीच हाल कुनै accepted/
/// confirmed/in_progress request छ कि भनेर live जाँच्ने (StreamBuilder,
/// worker accept गर्नेबित्तिकै आफैं unlock हुन्छ)। नभएसम्म फोन नम्बर
/// लुकाइन्छ/masked, र Call/Message दुवै निष्क्रिय — भेटिएपछि मात्र साँचो
/// नम्बर देखिने + दुवै फिचर अन हुन्छन् (Message ले त्यही active request कै
/// ChatScreen खोल्छ)।
class _ContactSection extends StatelessWidget {
  final String workerUid;
  final String workerName;
  final String phone;
  const _ContactSection({
    required this.workerUid,
    required this.workerName,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (workerUid.isEmpty || me.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // single-equality query (employerUid==me) — कुनै composite index
      // नचाहिने; workerUid/status भने client-side मात्र फिल्टर गरिन्छ।
      stream: FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('employerUid', isEqualTo: me)
          .snapshots(),
      builder: (context, snap) {
        String? activeRequestId;
        for (final d in snap.data?.docs ?? const []) {
          final data = d.data();
          if ((data['workerUid'] ?? '').toString() == workerUid &&
              _kActiveRequestStatuses
                  .contains((data['status'] ?? '').toString())) {
            activeRequestId = d.id;
            break;
          }
        }
        final unlocked = activeRequestId != null;

        return Column(
          children: [
            const SizedBox(height: 18),
            _ContactRow(
              icon: Icons.call_rounded,
              label: S.phone,
              value: unlocked
                  ? (phone.isEmpty ? '—' : phone)
                  : '•••• ••• ••••',
              locked: !unlocked,
              onTap: (unlocked && phone.isNotEmpty)
                  ? () => _launchTel(phone)
                  : null,
            ),
            if (unlocked) ...[
              const SizedBox(height: 10),
              _ContactRow(
                icon: Icons.chat_bubble_rounded,
                label: S.messageWord,
                value: S.openChatLabel,
                locked: false,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      requestId: activeRequestId!,
                      workerName: workerName,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 13, color: AppColors.kmMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(S.contactLockedCaption,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.kmMuted)),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

Future<void> _launchTel(String phone) async {
  if (phone.trim().isEmpty) return;
  try {
    await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
  } catch (_) {}
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool locked;
  final VoidCallback? onTap;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Opacity(
          opacity: locked ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient:
                        locked ? null : AppColors.kmCtaGradient,
                    color: locked ? Colors.white.withValues(alpha: 0.08) : null,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(locked ? Icons.lock_rounded : icon,
                      color: locked ? AppColors.kmMuted : AppColors.kmInk,
                      size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.kmMuted,
                              fontWeight: FontWeight.w600)),
                      Text(value,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.kmText)),
                    ],
                  ),
                ),
                if (!locked)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.kmMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatTile(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.kmOrange, size: 22),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppColors.kmText)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.kmMuted)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.kmOrange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.kmMuted,
                        fontWeight: FontWeight.w600)),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.kmText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
