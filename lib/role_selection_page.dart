// role_selection_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'employer_registration_page.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';
import 'worker_registration_page.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  bool _isSaving = false;

  Future<void> createAdminNotification(String title, String message) async {
    await FirebaseFirestore.instance.collection('adminNotifications').add({
      'title': title,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  Future<void> _selectRole(String role) async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'role': role,
        'email': user.email,
        'phone': user.phoneNumber ?? '',
        'accountStatus': 'active',
        // customer/employer लाई verify चाहिँदैन; provider/worker ले फारम भर्दा 'pending' हुन्छ
        'verificationStatus': 'none',
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await createAdminNotification(
        'नयाँ User दर्ता',
        '${FirebaseAuth.instance.currentUser!.email} ले $role को रूपमा दर्ता गर्नुभयो।',
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => role == 'worker'
              ? const WorkerRegistrationPage()
              : const EmployerRegistrationPage(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("त्रुटि: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.igPink.withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: -4),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset('assets/images/app_logo.png',
                        width: 88,
                        height: 88,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.handyman_rounded,
                            size: 50,
                            color: AppColors.igViolet)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('KaamMitra',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 12)
                        ])),
                const SizedBox(height: 36),
                const Text(
                  'Are you looking to work?\nLooking to hire?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 36),
                if (_isSaving)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  _RoleCard(
                    icon: Icons.handyman_rounded,
                    title: 'Worker',
                    subtitle: 'काम गर्ने',
                    onTap: () => _selectRole('worker'),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.work_rounded,
                    title: 'Employer',
                    subtitle: 'काम गराउने',
                    onTap: () => _selectRole('employer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.igViolet,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.igPink),
            ],
          ),
        ),
      ),
    );
  }
}
