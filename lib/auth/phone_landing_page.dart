// auth/phone_landing_page.dart
// inDrive-style landing — logo + welcome + "Confirm" (primary lime) र
// "Create account / Change account" (secondary)।
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_page.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'phone_input_page.dart';

class PhoneLandingPage extends StatelessWidget {
  const PhoneLandingPage({super.key});

  void _goToPhone(BuildContext context, {bool changeAccount = false}) async {
    if (changeAccount && FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PhoneInputPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 128,
                height: 128,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.handyman_rounded,
                      size: 56,
                      color: AppColors.onLime),
                ),
              ),
              const SizedBox(height: 28),
              Text(S.welcomeTo,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 10),
              Text(S.welcomeTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(flex: 3),
              PrimaryButton(
                label: S.confirm,
                icon: Icons.arrow_forward_rounded,
                onPressed: () => _goToPhone(context),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: S.createOrChangeAccount,
                onPressed: () => _goToPhone(context, changeAccount: true),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthPage()),
                ),
                child: Text(S.isNepali ? 'एडमिन लगइन' : 'Admin login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
