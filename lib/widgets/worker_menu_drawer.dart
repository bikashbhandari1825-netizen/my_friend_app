// widgets/worker_menu_drawer.dart
//
// Worker/Driver dashboard (job_feed_screen.dart, driver_dashboard_screen.dart)
// दुवैले साझा गर्ने hamburger-menu drawer — home_screen.dart कै employer
// `_HomeDrawer` को उही glass दृश्य ढाँचा, तर worker-सान्दर्भिक items सहित।
//
// यहाँका सबै item ले खोल्ने screen (Notifications, Help & Support, Settings)
// पहिल्यै employer-तर्फ पनि प्रयोग भइरहेका छन् र आफैंमा role-agnostic छन् —
// उही एउटा स्रोत (Firestore `config` collection — SupportConfig/
// HelpContentConfig, owner_dashboard_screen.dart कै Help Content Editor
// बाट सम्पादन हुने) बाट देखिने भएकोले worker/driver ले देख्ने Help/Support
// सामग्री स्वतः पूर्ण रूपमा Admin panel बाट नियन्त्रित हुन्छ — छुट्टै नयाँ
// admin-control code नचाहिने।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../screens/earnings_screen.dart';
import '../screens/help_support_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/my_reviews_screen.dart';
import '../screens/notification_screen.dart';
import '../screens/admin_dashboard_screen.dart';
import '../screens/hotel_verification_admin_screen.dart';
import '../screens/wallet_screen.dart';
import '../settings_page.dart';
import '../theme/app_theme.dart';
import '../worker_requests_page.dart';
import 'worker_avatar.dart';
import 'worker_stats.dart';

class WorkerMenuDrawer extends StatelessWidget {
  const WorkerMenuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final isOwner = user?.email == kAdminEmail;

    // Drawer बाट खोलिएको sub-screen बाट back थिच्दा फेरि यही Drawer मा
    // फर्कियोस् भनेर — home_screen.dart कै `_HomeDrawer::go()` उस्तै ढाँचा।
    void go(Widget page) {
      final scaffold = Scaffold.of(context);
      scaffold.closeDrawer();
      Navigator.push(context, MaterialPageRoute(builder: (_) => page))
          .then((_) {
        if (scaffold.mounted) scaffold.openDrawer();
      });
    }

    Widget item(IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 18, color: AppColors.kmLilac),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w500,
                              fontSize: 14.5)),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.kmMuted, size: 17),
                  ],
                ),
              ),
            ),
          ),
        );

    return Drawer(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(34)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
              decoration: BoxDecoration(color: AppColors.kmVoid)),
          Positioned(
            right: -140,
            top: 120,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.kmTeal.withValues(alpha: 0.30),
                    AppColors.kmTeal.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: uid == null
                  ? null
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final name = (data['name'] ??
                        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
                    .toString()
                    .trim();
                final service = (data['service'] ?? '').toString();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      child: Row(
                        children: [
                          WorkerAvatar(
                              uid: uid ?? '',
                              size: 54,
                              iconColor: AppColors.kmInk),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isEmpty ? S.workerRoleWord : name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.kmText,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                WorkerRatingBadge(uid: uid ?? '', onDark: true),
                                if (service.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(S.serviceName(service),
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.kmMuted)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x1AFFFFFF), height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          if (isOwner) ...[
                            item(
                                Icons.admin_panel_settings_rounded,
                                'Admin Dashboard',
                                // अब सिधै comprehensive Multi-Role Dashboard
                                // (Driver/Worker-Handyman/Hotel tabs) मा —
                                // पहिले संकुचित worker-मात्र OwnerDashboardScreen
                                // मा गइरहेको थियो।
                                () => go(const AdminDashboardScreen())),
                            item(Icons.verified_rounded, 'Hotel Verification',
                                () => go(const HotelVerificationAdminScreen())),
                          ],
                          item(Icons.assignment_rounded, S.navRequests,
                              () => go(const WorkerRequestsPage())),
                          item(
                              Icons.notifications_none_rounded,
                              S.menuNotifications,
                              () => go(const NotificationScreen())),
                          item(
                              Icons.account_balance_wallet_rounded,
                              S.earningsSummarySection,
                              () => go(const EarningsScreen())),
                          item(
                              Icons.account_balance_wallet_outlined,
                              S.walletLabel,
                              () => go(const WalletScreen())),
                          item(Icons.star_border_rounded, S.myReviews,
                              () => go(const MyReviewsScreen())),
                          item(Icons.message_rounded, S.messages,
                              () => go(const MessagesScreen())),
                          item(Icons.settings_rounded, S.settings,
                              () => go(const SettingsPage())),
                          item(Icons.help_outline_rounded, S.helpSupport,
                              () => go(const HelpSupportScreen())),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
