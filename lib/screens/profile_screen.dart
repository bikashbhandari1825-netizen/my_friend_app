// screens/profile_screen.dart
// वास्तविक User Data + Session Photo Upload सहितको Profile स्क्रिन।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_globals.dart';
import '../auth/dev_login.dart';
import '../auth/phone_landing_page.dart';
import '../l10n/strings.dart';
import '../report_page.dart';
import '../saved_places_screen.dart';
import '../settings_page.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_stats.dart';
import '../worker_registration_page.dart';
import 'bookings_screen.dart';
import 'document_resync_page.dart';
import 'driver_dashboard_screen.dart';
import 'earnings_screen.dart';
import 'help_support_screen.dart';
import 'messages_screen.dart';
import 'my_reviews_screen.dart';
import 'payment_methods_screen.dart';
import 'portfolio_screen.dart';
import '../watchlist_screen.dart';
import 'schedule_screen.dart';

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
        SnackBar(content: Text('क्यामेरा खोल्न मिलेन: $e')),
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
        SnackBar(content: Text('फाइल छान्न मिलेन: $e')),
      );
    }
  }

  void _showConfirmDialog() {
    showKmDialog(
      context: context,
      title: 'Profile Photo राख्ने?',
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
              const SnackBar(content: Text('Profile Photo राखियो!')),
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
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PhoneLandingPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topLeft, AppColors.kmOrangeDeep),
        KmOrb(Alignment.bottomRight, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(
                  title: 'My Profile',
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
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.kmTeal));
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
                          final isDriver =
                              service == 'Bike' || service == 'Car';
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
                              GlassPanel(
                                radius: 30,
                                fill: AppColors.kmGlassFillStrong,
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _showPhotoOptions,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 76,
                                            height: 76,
                                            padding: const EdgeInsets.all(3),
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: SweepGradient(colors: [
                                                AppColors.kmOrange,
                                                AppColors.kmPink,
                                                AppColors.kmPurple,
                                                AppColors.kmTeal,
                                                AppColors.kmOrange,
                                              ]),
                                            ),
                                            child: CircleAvatar(
                                              backgroundColor:
                                                  AppColors.kmSurface,
                                              backgroundImage:
                                                  sessionProfilePhoto != null
                                                      ? MemoryImage(
                                                              sessionProfilePhoto!)
                                                          as ImageProvider
                                                      : (selfieUrl.isNotEmpty
                                                          ? NetworkImage(
                                                              selfieUrl)
                                                          : null),
                                              child: sessionProfilePhoto ==
                                                          null &&
                                                      selfieUrl.isEmpty
                                                  ? const Icon(
                                                      Icons.person_rounded,
                                                      size: 32,
                                                      color:
                                                          AppColors.kmLilac)
                                                  : null,
                                            ),
                                          ),
                                          Positioned(
                                            right: -2,
                                            bottom: -2,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient:
                                                    AppColors.kmCtaGradient,
                                                border: Border.all(
                                                    color:
                                                        AppColors.kmSurface,
                                                    width: 2.5),
                                              ),
                                              child: const Icon(
                                                  Icons.camera_alt_rounded,
                                                  size: 13,
                                                  color: AppColors.kmInk),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              fullName.isEmpty
                                                  ? 'नाम राखिएको छैन'
                                                  : fullName,
                                              style: const TextStyle(
                                                  color: AppColors.kmText,
                                                  fontSize: 18,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                          if (email.toString().isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 3),
                                              child: Text(email,
                                                  style: const TextStyle(
                                                      color:
                                                          AppColors.kmMuted,
                                                      fontSize: 12.5)),
                                            ),
                                          if (dobFormatted.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 2),
                                              child: Text(
                                                  'जन्ममिति: $dobFormatted',
                                                  style: const TextStyle(
                                                      color:
                                                          AppColors.kmMuted,
                                                      fontSize: 12.5)),
                                            ),
                                          if (role.toString().isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            _RoleBadge(
                                              isWorker: role == 'worker',
                                              service: service,
                                            ),
                                          ],
                                          if (experience != null &&
                                              experience
                                                  .toString()
                                                  .isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 6),
                                              child: Text('अनुभव: $experience',
                                                  style: const TextStyle(
                                                      color:
                                                          AppColors.kmMuted,
                                                      fontSize: 12.5)),
                                            ),
                                          if (role == 'worker') ...[
                                            const SizedBox(height: 6),
                                            WorkerRatingBadge(
                                                uid: uid, compact: true),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (role == 'worker') ...[
                                const SizedBox(height: 14),
                                _KycCard(
                                  status: (data['verificationStatus'] ??
                                          data['workerVerificationStatus'] ??
                                          '')
                                      .toString(),
                                  documentsPending:
                                      data['documentsPending'] == true,
                                  reason:
                                      (data['rejectionReason'] ?? '')
                                          .toString(),
                                ),
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
                                    icon:
                                        Icons.account_balance_wallet_rounded,
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
                                    backgroundColor: AppColors.kmPink
                                        .withValues(alpha: 0.1),
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
  return GlassPanel(
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
                style:
                    const TextStyle(fontSize: 12, color: AppColors.kmMuted)),
          ],
          if (documentsPending || status == 'rejected') ...[
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

/// भूमिका देखाउने आधुनिक gradient चिप। कामदारका लागि दर्ता गरेको सीप/श्रेणी
/// भूमिकासँगै देखाउँछ — जस्तै "Plumber Worker", "Driver Worker"।
class _RoleBadge extends StatelessWidget {
  final bool isWorker;
  final String service;
  const _RoleBadge({required this.isWorker, required this.service});

  @override
  Widget build(BuildContext context) {
    final label = isWorker
        ? (service.isNotEmpty
            ? '${S.serviceName(service)} ${S.workerRoleWord}'
            : S.workerRoleWord)
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
