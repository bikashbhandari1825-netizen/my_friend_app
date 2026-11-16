// auth/account_confirmation_page.dart
// Smart Account Recognition — OTP verify भइसकेपछि (Firebase ले phone नम्बर
// अनुसार uid पहिल्यै निश्चित गरिसकेको हुन्छ), यो नम्बरमा पहिल्यैदेखि नाम
// भएको profile (फिर्ता आउने प्रयोगकर्ता) भेटिए मात्र यो देखिन्छ — "यो तपाईं
// नै हो?" भनेर एकपटक देखाइदिने friendly trust-step, inDrive/Uber-शैलीको
// super-app हरूमा जस्तै। "Change account" ले signOut गरेर फोन-इनपुटमै फर्काउँछ।
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_ui.dart' show SecondaryButton;
import '../widgets/glass_ui.dart';
import 'dev_login.dart' show signOutClean;

class AccountConfirmationPage extends StatefulWidget {
  final String name;

  const AccountConfirmationPage({super.key, required this.name});

  @override
  State<AccountConfirmationPage> createState() =>
      _AccountConfirmationPageState();
}

class _AccountConfirmationPageState extends State<AccountConfirmationPage> {
  bool _switching = false;

  Future<void> _changeAccount() async {
    setState(() => _switching = true);
    await signOutClean();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topRight, AppColors.kmPurple),
        KmOrb(Alignment.bottomLeft, AppColors.kmTeal),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Illustration placeholder — भविष्यमा साँचो illustration
                // asset यहीं राख्ने (हाल glow-circle + icon प्लेसहोल्डर)।
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                    border:
                        Border.all(color: AppColors.kmGlass2Border, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.kmTeal.withValues(alpha: 0.28),
                          blurRadius: 36,
                          spreadRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.verified_user_rounded,
                      size: 72, color: AppColors.kmTeal),
                ),
                const SizedBox(height: 32),
                Text('${widget.name}, please confirm it is you',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.3)),
                const SizedBox(height: 10),
                const Text(
                  'We found an account linked to this phone number.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 13.5),
                ),
                const SizedBox(height: 36),
                KmCtaButton(
                  label: 'Confirm',
                  icon: Icons.check_rounded,
                  loading: false,
                  onPressed: _switching
                      ? () {}
                      : () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Change account',
                  color: AppColors.kmMuted,
                  onPressed: _switching ? null : _changeAccount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
