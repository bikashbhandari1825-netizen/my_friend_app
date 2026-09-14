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
import '../widgets/app_ui.dart';
import '../widgets/worker_stats.dart';
import 'portfolio_screen.dart';

class WorkerProfileScreen extends StatelessWidget {
  final Map<String, String> worker;
  const WorkerProfileScreen({super.key, required this.worker});

  Future<void> _sendServiceRequest(BuildContext context) async {
    final TextEditingController detailsController = TextEditingController();
    final name = worker['name'] ?? '';
    final service = worker['service'] ?? '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(S.requestServiceFrom(name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.serviceName(service),
                style: const TextStyle(
                    color: AppColors.igViolet, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: detailsController,
              decoration: InputDecoration(
                labelText: S.describeYourTask,
                border: const OutlineInputBorder(),
                hintText: S.describeTaskHint,
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.igViolet,
                foregroundColor: Colors.white),
            onPressed: () async {
              if (detailsController.text.trim().isEmpty) return;

              final priceStr = (worker['price'] ?? 'Rs. 500')
                  .replaceAll(RegExp(r'[^0-9]'), '');
              final price = num.tryParse(priceStr) ?? 500;

              final currentUser = FirebaseAuth.instance.currentUser;

              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .add({
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

              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                  title: Text(S.serviceRequestSentTitle),
                  content: Text(S.serviceRequestSentBody),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: Text(S.ok),
                    ),
                  ],
                ),
              );
            },
            child: Text(S.sendRequest,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    if (phone.trim().isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
    } catch (_) {}
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

    return Scaffold(
      backgroundColor: AppColors.igViolet,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
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
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: const Icon(Icons.person_rounded,
                            size: 58, color: AppColors.igViolet),
                      ),
                      const SizedBox(height: 14),
                      Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(S.serviceName(service),
                            style: const TextStyle(
                                color: Colors.white,
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
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28)),
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
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.igViolet.withValues(alpha: 0.10),
                                    AppColors.igYellow.withValues(alpha: 0.10),
                                  ],
                                ),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded,
                                      size: 18, color: AppColors.igViolet),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${S.kycVerified} · ${S.documentAvailable}',
                                    style: const TextStyle(
                                        color: AppColors.igViolet,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            if (phone.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  onTap: () => _call(context, phone),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: const Color(0xFFEDEDF2)),
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.md),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: const BoxDecoration(
                                            gradient:
                                                AppColors.buttonGradient,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.call_rounded,
                                              color: Colors.white,
                                              size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(S.phone,
                                                  style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: Colors.black54,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              Text(phone,
                                                  style: const TextStyle(
                                                      fontSize: 14.5,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right_rounded,
                                            color: Colors.black38),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                                        color: const Color(0xFFEDEDF2)),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.photo_library_rounded,
                                          color: AppColors.igViolet),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(S.workPortfolio,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                      ),
                                      const Icon(Icons.chevron_right_rounded,
                                          color: Colors.black38),
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
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: PrimaryButton(
            label: S.sendRequest,
            icon: Icons.send_rounded,
            onPressed: () => _sendServiceRequest(context),
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
          color: AppColors.igViolet.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.igViolet, size: 22),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 11, color: Colors.black54)),
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
        color: const Color(0xFFF7F6FA),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.igViolet, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600)),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
