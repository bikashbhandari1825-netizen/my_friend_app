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
import '../widgets/worker_stats.dart';
import '../worker_registration_page.dart';
import 'bookings_screen.dart';
import 'document_resync_page.dart';
import 'earnings_screen.dart';
import 'help_support_screen.dart';
import 'messages_screen.dart';
import 'my_reviews_screen.dart';
import 'payment_methods_screen.dart';
import 'portfolio_screen.dart';
import 'saved_workers_screen.dart';
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
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: AppColors.igViolet),
                title: const Text('क्यामेराबाट फोटो खिच्ने'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: Colors.blue),
                title: const Text('फाइलबाट छान्ने'),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile Photo राख्ने?'),
        content: SizedBox(
          width: 150,
          height: 150,
          child: ClipOval(
            child: Image.memory(_pendingPhoto!, fit: BoxFit.cover),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pendingPhoto = null);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.igViolet),
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
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.logoutConfirmTitle),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.logOut, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          title: const Text('My Profile',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.buttonGradient),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ReportOptionsPage()),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report a Problem'),
                ),
              ],
            ),
          ]),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: uid == null
            ? const Center(child: Text('Login गर्नुहोस्'))
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
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
                  final service = (data['service'] ?? '').toString().trim();
                  final experience = data['experience'];
                  final selfieUrl = (data['selfieUrl'] ?? '').toString();

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
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _showPhotoOptions,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 35,
                                  backgroundImage: sessionProfilePhoto != null
                                      ? MemoryImage(sessionProfilePhoto!)
                                          as ImageProvider
                                      : (selfieUrl.isNotEmpty
                                          ? NetworkImage(selfieUrl)
                                          : null),
                                  child: sessionProfilePhoto == null &&
                                          selfieUrl.isEmpty
                                      ? const Icon(Icons.person, size: 40)
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.igPink,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    fullName.isEmpty
                                        ? 'नाम राखिएको छैन'
                                        : fullName,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                if (email.toString().isNotEmpty)
                                  Text(email,
                                      style:
                                          const TextStyle(color: Colors.grey)),
                                if (dobFormatted.isNotEmpty)
                                  Text('जन्ममिति: $dobFormatted',
                                      style:
                                          const TextStyle(color: Colors.grey)),
                                if (role.toString().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  _RoleBadge(
                                    isWorker: role == 'worker',
                                    service: service,
                                  ),
                                ],
                                if (experience != null &&
                                    experience.toString().isNotEmpty)
                                  Text('अनुभव: $experience',
                                      style:
                                          const TextStyle(color: Colors.grey)),
                                if (role == 'worker') ...[
                                  const SizedBox(height: 6),
                                  WorkerRatingBadge(uid: uid, compact: true),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (role == 'worker') ...[
                        const SizedBox(height: 16),
                        _KycCard(
                          status: (data['verificationStatus'] ??
                                  data['workerVerificationStatus'] ??
                                  '')
                              .toString(),
                          documentsPending: data['documentsPending'] == true,
                          reason: (data['rejectionReason'] ?? '').toString(),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Divider(),
                      if (role == 'worker') ...[
                        ListTile(
                            leading: const Icon(
                                Icons.account_balance_wallet_rounded),
                            title: Text(S.myEarnings),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const EarningsScreen()))),
                        ListTile(
                            leading: const Icon(Icons.calendar_month_rounded),
                            title: Text(S.mySchedule),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ScheduleScreen()))),
                        ListTile(
                            leading: const Icon(Icons.photo_library_rounded),
                            title: Text(S.workPortfolio),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const PortfolioScreen()))),
                      ],
                      if (role != 'worker')
                        ListTile(
                            leading: const Icon(Icons.calendar_today),
                            title: const Text('My Bookings'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const BookingsScreen()))),
                      ListTile(
                          leading: const Icon(Icons.message),
                          title: const Text('My Messages'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const MessagesScreen()))),
                      ListTile(
                          leading: const Icon(Icons.payment),
                          title: const Text('Payment Methods'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const PaymentMethodsScreen()))),
                      ListTile(
                          leading: const Icon(Icons.star_border),
                          title: const Text('My Reviews'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const MyReviewsScreen()))),
                      if (role != 'worker')
                        ListTile(
                            leading: const Icon(Icons.bookmark_border),
                            title: const Text('Saved Workers'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const SavedWorkersScreen()))),
                      ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(S.savedPlacesTitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const SavedPlacesScreen()))),
                      ListTile(
                          leading: const Icon(Icons.help_outline),
                          title: const Text('Help & Support'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const HelpSupportScreen()))),
                      ListTile(
                          leading: const Icon(Icons.settings_rounded),
                          title: Text(S.settings),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const SettingsPage()))),
                      ListTile(
                          leading: const Icon(Icons.logout_rounded,
                              color: Colors.orange),
                          title: Text(S.logOut),
                          onTap: _confirmLogout),
                    ],
                  );
                },
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
        color = AppColors.success;
        label = S.kycVerified;
        break;
      case 'rejected':
      case 'declined':
        icon = Icons.cancel_rounded;
        color = AppColors.danger;
        label = S.kycRejected;
        break;
      case 'pending':
        icon = Icons.hourglass_top_rounded;
        color = AppColors.warning;
        label = S.kycUnderReview;
        break;
      default:
        icon = Icons.info_outline_rounded;
        color = Colors.grey;
        label = S.kycNotSubmitted;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
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
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ],
          ),
          if (status == 'rejected' && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${S.reasonLabel}: $reason',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
        gradient: AppColors.buttonGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.igPink.withValues(alpha: 0.35),
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
              color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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
