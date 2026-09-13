// auth/phone_landing_page.dart
// inDrive-style landing — logo + welcome + "Confirm" (primary lime) र
// "Create account / Change account" (secondary)।
import 'package:flutter/material.dart';

import '../auth_page.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'email_auth_page.dart';
import 'phone_input_page.dart';

class PhoneLandingPage extends StatelessWidget {
  const PhoneLandingPage({super.key});

  void _go(BuildContext context, Widget page) {
    // यहाँ पहिले currentUser भए signOut() गर्ने कोड थियो — तर यो landing page
    // मा आइपुग्ने बेला user पहिल्यै signed-out हुनुपर्ने हो (logout/delete-account
    // जस्ता ठाउँले सधैँ आफैं signOutClean() अघि नै गर्छन्, settings_page.dart र
    // profile_screen.dart हेर्नुहोस्)। यो अनावश्यक signOut() ले भर्खरै सफल भएको
    // login लाई पनि (popUntil बाट यही page मा फर्किंदाको transition-बीचको
    // duplicate/stray tap ले _go फेरि call भएमा) तुरुन्तै sign out गरिदिन्थ्यो —
    // Android मा "login पछि welcome screen मा फर्कने" bug यसैले गर्दा थियो।
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 132,
                  height: 132,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.igPink.withValues(alpha: 0.45),
                          blurRadius: 40,
                          spreadRadius: -4),
                      const BoxShadow(
                          color: Colors.black38,
                          blurRadius: 24,
                          offset: Offset(0, 12)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.handyman_rounded,
                          size: 56,
                          color: AppColors.igViolet),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(S.welcomeTo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 12)
                        ])),
                const SizedBox(height: 10),
                Text(S.welcomeTagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const Spacer(flex: 3),
                PrimaryButton(
                  label: S.continueWithPhone,
                  icon: Icons.phone_iphone_rounded,
                  onPressed: () => _go(context, const PhoneInputPage()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _go(context, const EmailAuthPage()),
                    icon: const Icon(Icons.mail_outline_rounded,
                        color: Colors.white),
                    label: Text(S.continueWithEmail,
                        style: const TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthPage()),
                  ),
                  child: Text(
                    S.isNepali ? 'एडमिन लगइन' : 'Admin login',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
