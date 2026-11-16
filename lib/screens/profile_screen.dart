// screens/profile_screen.dart
// वास्तविक User Data + Session Photo Upload सहितको Profile स्क्रिन।
import '../widgets/profile_hero_card.dart';
import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_globals.dart';
import '../auth/dev_login.dart';
import '../l10n/strings.dart';
import '../report_page.dart';
import '../saved_places_screen.dart';
import '../services/hotel_partner_service.dart' show myPartnerHotelIds;
import '../settings_page.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_stats.dart';
import '../worker_registration_page.dart';
import 'bookings_screen.dart';
import 'document_resync_page.dart';
import 'driver_dashboard_screen.dart';
import 'edit_profile_page.dart';
import 'earnings_screen.dart';
import 'help_support_screen.dart';
import '../services/salon_partner_service.dart' show mySalons;
import 'salon_partner_dashboard_screen.dart';
import 'salon_registration_screen.dart';
import 'hotel_partner_dashboard_screen.dart';
import 'hotel_registration_screen.dart';
import 'messages_screen.dart';
import 'my_reviews_screen.dart';
import 'payment_methods_screen.dart';
import 'portfolio_screen.dart';
import '../watchlist_screen.dart';
import 'schedule_screen.dart';
import 'vehicle_registration_screens.dart';
import 'wallet_screen.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

// 12. Profile Screen (वास्तविक User Data + Photo Upload सहित)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Uint8List? _pendingPhoto; // छानेको तर अझै Save नगरेको फोटो

  final _uid = FirebaseAuth.instance.currentUser?.uid;

  // profile doc live stream, एकपटक मात्र subscribe — फोटो छान्दा/setState मा
  // पूरा screen spinner मा नफर्कियोस्; admin ले role/status बदल्दा live update।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? '__none__')
          .snapshots();

  @override
  void initState() {
    super.initState();
    unawaited(_logPartnerRoleReport());
  }

  /// Partner Role Integrity Check — Profile खुल्नेबित्तिकै एकपटक console
  /// मा यो account कै साँचो (live Firestore) role state देखाउने: worker
  /// (role/service/verification) `users/{uid}` बाटै, hotel partnership
  /// `users/{uid}.partnerHotelIds` बाटै — दुवै स्वतन्त्र field, त्यसैले
  /// एकैचोटि दुवै (cross-category, जस्तै Hotel Owner + Plumber Worker)
  /// हुन सक्छन्, कतै hardcoded fallback छैन (नपाए खाली/false मात्र)।
  Future<void> _logPartnerRoleReport() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? const {};
      final role = (data['role'] ?? '').toString();
      final service = (data['service'] ?? '').toString();
      final workerStatus = (data['verificationStatus'] ??
              data['workerVerificationStatus'] ??
              '')
          .toString();
      final rawHotelIds = data['partnerHotelIds'];
      final hotelIds =
          rawHotelIds is List ? List<String>.from(rawHotelIds) : const [];
      final isWorkerActive =
          role == 'worker' && (workerStatus == 'approved' || workerStatus == 'pending');
      final isHotelPartner = hotelIds.isNotEmpty;
      debugPrint(
        '[PartnerRoleCheck] uid=$uid | '
        'worker=${isWorkerActive ? "$service ($workerStatus)" : "none"} | '
        'hotelPartner=${isHotelPartner ? "${hotelIds.length} hotel(s): $hotelIds" : "none"} | '
        'crossCategory=${isWorkerActive && isHotelPartner} | '
        'source=Firestore users/$uid (no hardcoded fallback)',
      );
    } catch (e) {
      debugPrint('[PartnerRoleCheck] failed: $e');
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.kmSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: AppColors.kmOrange),
                title: const Text('क्यामेराबाट फोटो खिच्ने',
                    style: TextStyle(color: AppColors.kmText)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: AppColors.kmTealBlue),
                title: const Text('फाइलबाट छान्ने',
                    style: TextStyle(color: AppColors.kmText)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() => _pendingPhoto = bytes);
        _showConfirmDialog();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.cameraOpenFailed(e))),
      );
    }
  }

  Future<void> _pickFromFile() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() => _pendingPhoto = bytes);
        _showConfirmDialog();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.filePickFailed(e))),
      );
    }
  }

  void _showConfirmDialog() {
    showKmDialog(
      context: context,
      title: S.keepProfilePhotoTitle,
      content: SizedBox(
        width: 150,
        height: 150,
        child: ClipOval(
          child: Image.memory(_pendingPhoto!, fit: BoxFit.cover),
        ),
      ),
      actions: [
        KmDialogAction(
          label: 'Cancel',
          onPressed: () {
            setState(() => _pendingPhoto = null);
            Navigator.pop(context);
          },
        ),
        KmDialogAction(
          label: 'Save',
          filled: true,
          onPressed: () {
            setState(() {
              sessionProfilePhoto = _pendingPhoto;
              _pendingPhoto = null;
            });
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.profilePhotoSaved)),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showKmDialog<bool>(
      context: context,
      title: S.logoutConfirmTitle,
      icon: Icons.logout_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: S.logOut,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (ok != true) return;
    await signOutClean();
    if (!mounted) return;
    // नयाँ PhoneLandingPage() push नगर्ने — root StreamBuilder<User?>
    // (app.dart) लाई नै signOut() पछिको auth state अनुसार देखाउन दिने।
    // पहिले यहाँ pushAndRemoveUntil ले त्यो reactive root route नै
    // हटाएर एउटा static PhoneLandingPage राख्दिन्थ्यो — त्यसपछि फेरि
    // नयाँ नम्बरले OTP verify सफल भए पनि otp_verification_page.dart कै
    // `popUntil((route) => route.isFirst)` त्यही static page मै फर्केर
    // अडिन्थ्यो (login सफल भए पनि welcome screen मै फर्किएको जस्तो)।
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(
                  title: 'My Profile',
                  showBack: false,
                  actions: [
                    GlassIconButton(
                      icon: Icons.more_vert_rounded,
                      onTap: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: AppColors.kmSurface,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(28))),
                        builder: (context) => SafeArea(
                          child: ListTile(
                            leading: const Icon(Icons.flag_outlined,
                                color: AppColors.kmRose),
                            title: const Text('Report a Problem',
                                style: TextStyle(color: AppColors.kmText)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const ReportOptionsPage()),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmText)))
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _userStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SkeletonList();
                          }

                          final data = snapshot.data?.data() ?? {};

                          final firstName = data['firstName'] ?? '';
                          final lastName = data['lastName'] ?? '';
                          final fullName = '$firstName $lastName'.trim();
                          final email = data['email'] ??
                              FirebaseAuth.instance.currentUser?.email ??
                              '';
                          final dob = data['dob'] ?? '';
                          final role = data['role'] ?? '';
                          final service =
                              (data['service'] ?? '').toString().trim();
                          final isDriver = service == 'Bike' ||
                              service == 'Car' ||
                              service == 'Auto';
                          final workerVerified = (data['verificationStatus'] ??
                                      data['workerVerificationStatus'] ??
                                      '')
                                  .toString() ==
                              'approved';
                          final experience = data['experience'];
                          final selfieUrl =
                              (data['selfieUrl'] ?? '').toString();

                          String dobFormatted = '';
                          if (dob.toString().isNotEmpty) {
                            try {
                              final parsed = DateTime.parse(dob);
                              dobFormatted =
                                  '${parsed.day}/${parsed.month}/${parsed.year}';
                            } catch (_) {
                              dobFormatted = dob.toString();
                            }
                          }

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                            children: [
                              ProfileHeroCard(
                                data: data,
                                fullName: fullName,
                                email: email.toString(),
                                dobFormatted: dobFormatted,
                                isWorker: role == 'worker',
                                experience: experience?.toString() ?? '',
                                selfieUrl: selfieUrl,
                                workerVerified: workerVerified,
                                roleBadge: role.toString().isEmpty
                                    ? null
                                    : _RoleBadge(
                                        isWorker: role == 'worker',
                                        service: service),
                                ratingBadge: role == 'worker'
                                    ? WorkerRatingBadge(uid: uid, compact: true, onDark: true)
                                    : null,
                                onPhoto: _showPhotoOptions,
                                onEdit: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EditProfilePage(
                                      firstName: firstName.toString(),
                                      lastName: lastName.toString(),
                                      email: email.toString(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const _BecomePartnerBanner(),
                              const _HotelPartnerBanner(),
                              const _SalonPartnerBanner(),
                              if (role == 'worker' && workerVerified)
                                _WorkerDashboardBanner(
                                    isDriver: isDriver, service: service),
                              if (role == 'worker') ...[
                                const SizedBox(height: 14),
                                _KycCard(
                                  status: (data['verificationStatus'] ??
                                          data['workerVerificationStatus'] ??
                                          '')
                                      .toString(),
                                  documentsPending:
                                      data['documentsPending'] == true,
                                  reason: (data['rejectionReason'] ?? '')
                                      .toString(),
                                ),
                              ],
                              if (role == 'worker') ...[
                                const SizedBox(height: 14),
                                _WalletCard(uid: uid),
                              ],
                              const SizedBox(height: 14),
                              _rowsPanel([
                                if (role == 'worker' && isDriver)
                                  // Driver का लागि माथिका ३ छुट्टाछुट्टै
                                  // विकल्पको साटो एकै ठाउँमा सबै नियन्त्रण
                                  // दिने Driver Dashboard।
                                  _ProfileRow(
                                    icon: Icons.dashboard_rounded,
                                    label: S.driverDashboardTitle,
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DriverDashboardScreen())),
                                  )
                                else if (role == 'worker') ...[
                                  _ProfileRow(
                                    icon: Icons.account_balance_wallet_rounded,
                                    label: S.myEarnings,
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const EarningsScreen())),
                                  ),
                                  _ProfileRow(
                                    icon: Icons.calendar_month_rounded,
                                    label: S.mySchedule,
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const ScheduleScreen())),
                                  ),
                                  _ProfileRow(
                                    icon: Icons.photo_library_rounded,
                                    label: S.workPortfolio,
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const PortfolioScreen())),
                                  ),
                                ],
                                if (role != 'worker')
                                  _ProfileRow(
                                    icon: Icons.calendar_today_rounded,
                                    label: 'My Bookings',
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                const BookingsScreen())),
                                  ),
                                _ProfileRow(
                                  icon: Icons.message_rounded,
                                  label: 'My Messages',
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const MessagesScreen())),
                                ),
                                _ProfileRow(
                                  icon: Icons.payment_rounded,
                                  label: 'Payment Methods',
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const PaymentMethodsScreen())),
                                ),
                                _ProfileRow(
                                  icon: Icons.star_border_rounded,
                                  label: 'My Reviews',
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const MyReviewsScreen())),
                                ),
                                if (role != 'worker')
                                  _ProfileRow(
                                    icon: Icons.bookmark_border_rounded,
                                    label: 'Saved Workers',
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                const WatchlistScreen())),
                                  ),
                              ]),
                              const SizedBox(height: 14),
                              _rowsPanel([
                                _ProfileRow(
                                  icon: Icons.place_rounded,
                                  label: S.savedPlacesTitle,
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const SavedPlacesScreen())),
                                ),
                                _ProfileRow(
                                  icon: Icons.help_outline_rounded,
                                  label: 'Help & Support',
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const HelpSupportScreen())),
                                ),
                                _ProfileRow(
                                  icon: Icons.settings_rounded,
                                  label: S.settings,
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const SettingsPage())),
                                ),
                              ]),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: _confirmLogout,
                                  icon: const Icon(Icons.logout_rounded,
                                      size: 18, color: AppColors.kmRose),
                                  label: Text(S.logOut,
                                      style: const TextStyle(
                                          color: AppColors.kmRose,
                                          fontWeight: FontWeight.w700)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                        color: AppColors.kmRoseSoft
                                            .withValues(alpha: 0.5)),
                                    backgroundColor:
                                        AppColors.kmPink.withValues(alpha: 0.1),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(25)),
                                  ),
                                ),
                              ),
                            ],
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
}

/// एक समूहका `_ProfileRow` हरूलाई glass panel भित्र, बीचमा पातलो divider
/// सहित राख्ने (मोकअप कै `.row` group) — अन्तिम row मा divider हुँदैन।
Widget _rowsPanel(List<_ProfileRow> rows) {
  return NeonCard(
    radius: 28,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1)
            const Divider(height: 1, color: Color(0x14FFFFFF)),
        ],
      ],
    ),
  );
}

/// Profile group panel भित्रको एउटा row — icon badge + label + chevron।
class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: AppColors.kmOrange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 17, color: AppColors.kmMuted),
          ],
        ),
      ),
    );
  }
}

/// कामदारको KYC / verification स्थिति देखाउने card।
// ── Sahayatri Wallet Card — Profile screen मै सिधै walletBalance/
// isEligibleForJobs (widgets/complete_job_sheet.dart::_confirm() र
// admin_settlement_screen.dart::_markSettled() ले नै गणना/लेख्छन्)
// देखाउने, tap गरे पूरा WalletScreen (screens/wallet_screen.dart) खुल्ने
// — छुट्टै menu खोज्नु नपरोस् भनेर।
class _WalletCard extends StatelessWidget {
  final String uid;
  const _WalletCard({required this.uid});

  void _openWallet(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const WalletScreen()));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final balance = ((data['walletBalance'] as num?) ?? 0).toDouble();
        final isEligible = (data['isEligibleForJobs'] as bool?) ?? true;
        final owed = balance < 0;
        final settled = balance == 0;
        final color = !isEligible
            ? AppColors.kmRose
            : (settled
                ? AppColors.kmTeal
                : (owed ? AppColors.kmAmber : AppColors.kmTeal));
        final statusText = settled
            ? S.fullySettledLabel
            : (owed
                ? S.youOwePlatformLabel((-balance).round())
                : S.payoutPendingLabel(balance.round()));

        return NeonCard(
          radius: AppRadius.lg,
          padding: EdgeInsets.zero,
          fill: color.withValues(alpha: 0.10),
          border: color,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => _openWallet(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded,
                            color: color, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(S.sahayatriWalletTitle,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: color)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: color),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                      child: settled
                          ? Container(
                              key: const ValueKey('settled'),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.kmTeal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: color, size: 15),
                                  const SizedBox(width: 5),
                                  Text('Settled ✓',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: color)),
                                ],
                              ),
                            )
                          : Text(
                              key: const ValueKey('unsettled'),
                              statusText,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: color),
                            ),
                    ),
                    const SizedBox(height: 10),
                    // Current Balance + Platform Dues — दुवै संख्या छुट्टाछुट्टै
                    // स्पष्ट देखियोस् भनेर (माथिको status badge एउटै
                    // semantic वाक्य मात्र हो, यो चाहिं कच्चा आँकडा)।
                    Row(
                      children: [
                        Expanded(
                          child: _WalletStat(
                            label: 'Current Balance',
                            value:
                                '${balance < 0 ? '-' : ''}Rs. ${balance.abs().round()}',
                            color: color,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: AppColors.kmGlassBorder,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        Expanded(
                          child: _WalletStat(
                            label: 'Platform Dues',
                            value: 'Rs. ${owed ? (-balance).round() : 0}',
                            color: owed ? AppColors.kmRose : AppColors.kmMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(S.walletMaintainBalanceSubtitle,
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 11.5)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openWallet(context),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: Text(
                            (owed || !isEligible)
                                ? S.payDuesButton
                                : S.topUpWalletButton),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: AppColors.kmInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// सानो label+value जोडी — Current Balance/Platform Dues स्तम्भ दुवैका
/// लागि एउटै साझा layout।
class _WalletStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _WalletStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _KycCard extends StatelessWidget {
  final String status;
  final bool documentsPending;
  final String reason;
  const _KycCard({
    required this.status,
    required this.documentsPending,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String label;
    switch (status) {
      case 'approved':
        icon = Icons.verified_rounded;
        color = AppColors.kmTeal;
        label = S.kycVerified;
        break;
      case 'rejected':
      case 'declined':
        icon = Icons.cancel_rounded;
        color = AppColors.kmRose;
        label = S.kycRejected;
        break;
      case 'pending':
        icon = Icons.hourglass_top_rounded;
        color = AppColors.kmOrange;
        label = S.kycUnderReview;
        break;
      default:
        icon = Icons.info_outline_rounded;
        color = AppColors.kmMuted;
        label = S.kycNotSubmitted;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(S.documentsKyc,
                  style: const TextStyle(
                      color: AppColors.kmText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const Spacer(),
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ],
          ),
          if (status == 'rejected' && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${S.reasonLabel}: $reason',
                style: const TextStyle(fontSize: 12, color: AppColors.kmMuted)),
          ],
          // Verification पहिल्यै 'approved' भइसकेपछि फेरि कहिल्यै re-upload/
          // resubmit बटन नदेखियोस् — पहिले `documentsPending` झन्डा (जुन
          // status सँग स्वतन्त्र थियो) approved भइसकेपछि पनि true नै रहन
          // सक्थ्यो, जसले गर्दा हरियो "Verified" badge र "Re-upload
          // Documents" बटन एकैचोटि देखिन्थे — पहिलोपटक approve भइसकेपछि
          // फेरि verify गर्नु पर्दैन भन्ने आवश्यकता विपरीत।
          if (status != 'approved' &&
              (documentsPending || status == 'rejected')) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(
                    documentsPending
                        ? Icons.cloud_upload_rounded
                        : Icons.refresh_rounded,
                    size: 16),
                label:
                    Text(documentsPending ? S.reuploadDocuments : S.resubmit),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => documentsPending
                        ? const DocumentResyncPage()
                        : const WorkerRegistrationPage(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Unified Partner Onboarding (Uber/InDrive-style) — एउटै "Earn with Us"
/// entry बाट Driver/Worker/Hotel Owner मध्ये जुनसुकै छान्न सकिने। हरेकले
/// छुट्टै फारम (DriverRegistrationFlow/WorkerRegistrationPage/
/// HotelRegistrationScreen) नै प्रयोग गर्छ — ती सबैले आफैं `role`/`status`
/// लेख्छन् (यहाँ pre-write केही गर्नु पर्दैन)।
/// Worker/Driver दुवै `users/{uid}.role == 'worker'` कै उस्तै data model
/// प्रयोग गर्छन् (category भने `service` field मा) — त्यसैले साझा जाँच।
/// `pending`/`approved` भए मात्र "दोहोरो" मानिने — `rejected` वा अझै
/// दर्ता नभएको भए होइन (रिजेक्ट भएपछि फेरि दर्ता गर्न दिने पुरानै
/// "Change role"/`_startFresh` flow सँग नबाझोस् भनेर)।
Future<String?> _existingWorkerService() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final data = doc.data();
  if (data == null || (data['role'] ?? '') != 'worker') return null;
  final status =
      (data['verificationStatus'] ?? data['workerVerificationStatus'] ?? '')
          .toString();
  if (status != 'pending' && status != 'approved') return null;
  final service = (data['service'] ?? '').toString();
  return service.isEmpty ? null : service;
}

/// Worker/Driver कुनै पनि दर्ता फारम खोल्नुअघि — पहिल्यै दर्ता भइसकेको
/// भए फारम नै नखोली "Already Registered" alert देखाएर आफ्नै (हाल भइरहेको
/// role अनुसार auto-switch हुने) Dashboard मा फर्काउने। true फर्काएमा
/// caller ले अगाडि नबढ्ने।
Future<bool> _blockIfAlreadyWorker(BuildContext context) async {
  final existing = await _existingWorkerService();
  if (existing == null || !context.mounted) return false;
  await showKmDialog<void>(
    context: context,
    title: 'Already Registered',
    message:
        'You are already registered as a $existing. Manage your services from your Partner Dashboard.',
    icon: Icons.info_outline_rounded,
    iconBg:
        const LinearGradient(colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
    actions: [
      KmDialogAction(
        label: 'Go to Dashboard',
        filled: true,
        onPressed: () {
          Navigator.pop(context);
          // root StreamBuilder ले वर्तमान role (worker) अनुसार सही
          // dashboard/tab-layout आफैं देखाउँछ — नयाँ route push गर्नु पर्दैन।
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    ],
  );
  return true;
}

/// Hotel दर्ता फारम खोल्नुअघि — पहिल्यै आफ्नै कुनै होटल भइसकेको भए (स्वीकृत
/// पर्खंदै भए पनि — दर्ता गर्नेबित्तिकै `partnerHotelIds` मा थपिन्छ)
/// फारम नै नखोली Partner Dashboard मा सिधै लैजाने।
Future<bool> _blockIfAlreadyHotelPartner(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final raw = doc.data()?['partnerHotelIds'];
  final ids = raw is List ? List<String>.from(raw) : const <String>[];
  if (ids.isEmpty || !context.mounted) return false;
  await showKmDialog<void>(
    context: context,
    title: 'Already Registered',
    message:
        'You already have ${ids.length > 1 ? 'hotels' : 'a hotel'} registered. Manage ${ids.length > 1 ? 'them' : 'it'} from your Partner Dashboard.',
    icon: Icons.info_outline_rounded,
    iconBg:
        const LinearGradient(colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
    actions: [
      KmDialogAction(
        label: 'Go to Dashboard',
        filled: true,
        onPressed: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HotelPartnerDashboardScreen(hotelIds: ids),
            ),
          );
        },
      ),
    ],
  );
  return true;
}

Future<void> _openBecomePartnerSheet(BuildContext context) async {
  final choice = await showKmSheet<String>(
    context: context,
    title: 'Earn with Us',
    children: [
      KmSheetOption(
        icon: Icons.two_wheeler_rounded,
        label: 'Ride Driver',
        subtitle: 'Bike, Car, Auto — License, Vehicle Reg, Citizenship',
        selected: false,
        onTap: () => Navigator.pop(context, 'driver'),
      ),
      KmSheetOption(
        icon: Icons.handyman_rounded,
        label: 'Service Worker / Handyman',
        subtitle: 'Plumber, Electrician, Mechanic, Painter & more',
        selected: false,
        onTap: () => Navigator.pop(context, 'worker'),
      ),
      KmSheetOption(
        icon: Icons.storefront_rounded,
        label: 'Hotel Owner / Partner',
        subtitle: 'Business Reg/PAN, amenities & photos',
        selected: false,
        onTap: () => Navigator.pop(context, 'hotel'),
      ),
      KmSheetOption(
        icon: Icons.content_cut_rounded,
        label: 'Salon / Beauty Provider',
        subtitle: 'Services, team, working hours & appointments',
        selected: false,
        onTap: () => Navigator.pop(context, 'salon'),
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'driver' || choice == 'worker') {
    if (await _blockIfAlreadyWorker(context)) return;
    if (!context.mounted) return;
  } else if (choice == 'hotel') {
    if (await _blockIfAlreadyHotelPartner(context)) return;
    if (!context.mounted) return;
  }
  if (choice == 'driver') {
    await _openVehicleTypeSheet(context);
    return;
  }
  if (choice == 'salon') {
    // पहिल्यै दर्ता भएको भए सिधै Dashboard, नत्र दर्ता फारम।
    final salons = await mySalons().first;
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => salons.isEmpty
            ? const SalonRegistrationScreen()
            : SalonPartnerDashboardScreen(salonId: salons.first.id),
      ),
    );
    return;
  }
  final page = switch (choice) {
    'worker' => const WorkerRegistrationPage(),
    'hotel' => const HotelRegistrationScreen(),
    _ => null,
  };
  if (page != null) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

/// "Ride Driver" छान्दा Bike/Car/Auto-Rickshaw छुट्टाछुट्टै छान्ने दोस्रो
/// sheet — छानिएको अनुसार सिधै त्यही vehicle को dedicated registration
/// screen मा लैजाने (साझा "Vehicle Category" step भित्र होइन)।
Future<void> _openVehicleTypeSheet(BuildContext context) async {
  final vehicle = await showKmSheet<String>(
    context: context,
    title: 'Choose your vehicle',
    children: [
      KmSheetOption(
        icon: Icons.two_wheeler_rounded,
        label: 'Bike',
        subtitle: 'License, Bluebook Number, Plate No, Photo Uploads',
        selected: false,
        onTap: () => Navigator.pop(context, 'Bike'),
      ),
      KmSheetOption(
        icon: Icons.directions_car_rounded,
        label: 'Car',
        subtitle: 'License, Bluebook Number, Plate No, Seats, AC, Docs',
        selected: false,
        onTap: () => Navigator.pop(context, 'Car'),
      ),
      KmSheetOption(
        icon: Icons.electric_rickshaw_rounded,
        label: 'Auto-Rickshaw',
        subtitle: 'License, Bluebook Number, Plate No, Route Permit, Docs',
        selected: false,
        onTap: () => Navigator.pop(context, 'Auto'),
      ),
    ],
  );
  if (vehicle == null || !context.mounted) return;
  final page = switch (vehicle) {
    'Bike' => const BikeRegistrationScreen(),
    'Car' => const CarRegistrationScreen(),
    'Auto' => const AutoRickshawRegistrationScreen(),
    _ => null,
  };
  if (page != null) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

/// Profile tab कै सबैभन्दा माथिल्लो, सबैलाई देखिने "partner बन्ने" prominent
/// CTA — Driver/Worker/Hotel Owner तीनै यहीँबाट, छुट्टाछुट्टै खोज्नु नपरोस्।
class _BecomePartnerBanner extends StatelessWidget {
  const _BecomePartnerBanner();

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      radius: 22,
      onTap: () => _openBecomePartnerSheet(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.kmCtaGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.volunteer_activism_rounded,
                color: AppColors.kmInk, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earn with Us',
                    style: TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                SizedBox(height: 2),
                Text(
                    'Become a Partner — drive, offer services, or list your hotel',
                    style: TextStyle(color: AppColors.kmMuted, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.kmMuted),
        ],
      ),
    );
  }
}

/// भइसकेको hotel partner लाई सिधै आफ्नो Partner Dashboard मा लैजाने
/// quick-access — managing गरिरहेको hotel भएमा मात्र देखिने। Partner
/// नभएको प्रयोगकर्तालाई यहाँ केही देखिँदैन (पहिले "List Your Property"
/// देखाउँथ्यो, तर त्यो ठ्याक्कै उस्तै `HotelRegistrationScreen` मा
/// पुर्‍याउँथ्यो जुन "Earn with Us" → Hotel Owner बाट पनि पुगिन्छ —
/// दोहोरो registration entry हटाइयो, registration सधैं "Earn with Us"
/// भित्रै रहोस् भनेर)।
class _HotelPartnerBanner extends StatelessWidget {
  const _HotelPartnerBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: myPartnerHotelIds(),
      builder: (context, snap) {
        final ids = snap.data ?? const [];
        final isPartner = ids.isNotEmpty;
        if (!isPartner) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: NeonCard(
            radius: 22,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HotelPartnerDashboardScreen(hotelIds: ids),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.kmCtaGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.dashboard_rounded,
                    color: AppColors.kmInk,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Switch to Partner Dashboard',
                        style: TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800,
                            fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Managing ${ids.length} hotel${ids.length > 1 ? 's' : ''} — bookings, rooms & QR check-in',
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.kmMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// भइसकेको salon provider लाई सिधै आफ्नो Salon Dashboard मा लैजाने
/// quick-access — `salons.ownerId == uid` भएमा मात्र देखिने (hotel partner
/// banner कै उस्तै shape; दर्ता भने "Earn with Us" भित्रै)।
class _SalonPartnerBanner extends StatelessWidget {
  const _SalonPartnerBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: mySalons(),
      builder: (context, snap) {
        final salons = snap.data ?? const [];
        if (salons.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: NeonCard(
            radius: 22,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SalonPartnerDashboardScreen(salonId: salons.first.id),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.kmCtaGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.content_cut_rounded,
                      color: AppColors.kmInk, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Salon Dashboard',
                          style: TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                          '${salons.first.name} — appointments, team & QR check-in',
                          style: const TextStyle(
                              color: AppColors.kmMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.kmMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Verified worker/driver लाई सिधै उनको live Job/Ride Feed (job_feed_screen.dart)
/// मा लैजाने prominent quick-access — role=='worker' र verification
/// approved भएमा मात्र देखिने (profile_screen.dart::_ProfileScreenState.build
/// हेर्नुहोस्)। पहिले यो नै (Job Feed) मुख्य bottom-nav को Home tab थियो —
/// अब सबैलाई उस्तै Super-App Home देखियोस् भनेर त्यहाँबाट हटाइयो, यहीँ मात्र
/// (hotel partner banner कै उस्तै shape/स्थानमा) फेरि प्रस्ट रूपमा पुग्ने
/// बनाइएको।
class _WorkerDashboardBanner extends StatelessWidget {
  final bool isDriver;
  final String service;
  const _WorkerDashboardBanner({required this.isDriver, required this.service});

  @override
  Widget build(BuildContext context) {
    final title = isDriver
        ? S.driverHubTitle
        : '${S.serviceName(service)} ${S.workerRoleWord} ${S.dashboardWord}';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: NeonCard(
        radius: 22,
        // Dashboard-First, Map-On-Demand — पहिले यहाँ सिधै live-map job
        // radar (JobFeedScreen) नै खुल्थ्यो, data-driven dashboard भन्दा
        // पहिले नै full-screen Google Map देखिने। अब `_ProfileRow` (तल,
        // Driver Dashboard/My Earnings) कै उस्तै isDriver-आधारित सही
        // data-driven dashboard सिधै खुल्छ — map भने ती dashboard भित्रैको
        // "Find Nearby Jobs" कार्डबाट मात्र, on-demand।
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => isDriver
                  ? const DriverDashboardScreen()
                  : const EarningsScreen()),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.kmCtaGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isDriver ? Icons.local_taxi_rounded : Icons.handyman_rounded,
                color: AppColors.kmInk,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.workerDashboardSubtitle,
                    style:
                        const TextStyle(color: AppColors.kmMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.kmMuted),
          ],
        ),
      ),
    );
  }
}

/// भूमिका देखाउने आधुनिक gradient चिप। कामदारका लागि दर्ता गरेको सीप/श्रेणी
/// भूमिकासँगै देखाउँछ — जस्तै "Plumber Worker", "Driver Worker"।
class _RoleBadge extends StatelessWidget {
  final bool isWorker;
  final String service;
  const _RoleBadge({required this.isWorker, required this.service});

  @override
  Widget build(BuildContext context) {
    // Rider vs Worker Terminology — Bike/Car सवारी चलाउने worker लाई
    // "{Service} Worker" (जस्तै "Bike Worker") भन्दा "{Service} Rider"
    // ("Bike Rider") बुझ्न सजिलो — साधारण job-service worker (Plumber
    // आदि) मा भने पहिलेकै "Worker" यथावत्।
    final isRide = service == 'Bike' || service == 'Car' || service == 'Auto';
    final roleWord = isRide ? S.riderRoleWord : S.workerRoleWord;
    final label = isWorker
        ? (service.isNotEmpty
            ? '${S.serviceName(service)} $roleWord'
            : roleWord)
        : S.employerRoleWord;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: AppColors.kmCtaGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              isWorker ? Icons.handyman_rounded : Icons.business_center_rounded,
              size: 13,
              color: AppColors.kmInk),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.kmInk,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
