// auth/phone_landing_page.dart
// Sahayatri welcome/landing page — dark glassmorphic aurora थिम, logo +
// welcome + "Continue with phone" (gradient CTA) मात्र। कुनै छुट्टै "Admin
// login" लिङ्क/बटन जानाजान यहाँ छैन — Admin पहुँच पूर्ण रूपमा गुप्त छ
// (हेर्नुहोस् auth/admin_gate_page.dart र phone_input_page.dart::_continue())।
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../onboarding/sahayatri_brand.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
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
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const SahayatriLogoMark(size: 116),
                const SizedBox(height: 24),
                const SahayatriWordmark(fontSize: 30),
                const SizedBox(height: 18),
                Text(S.welcomeTo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(S.welcomeTagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const Spacer(flex: 3),
                // फोन नम्बर (OTP) मात्र — साधारण user को खाता बनाउने/लगइन
                // गर्ने एकमात्र बाटो। बटन थिचेपछि साँचो Firebase Phone Auth
                // (SMS + reCAPTCHA) चल्छ — phone_input_page.dart हेर्नुहोस्।
                KmCtaButton(
                  label: S.continueWithPhone,
                  icon: Icons.phone_iphone_rounded,
                  onPressed: () => _go(context, const PhoneInputPage()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
