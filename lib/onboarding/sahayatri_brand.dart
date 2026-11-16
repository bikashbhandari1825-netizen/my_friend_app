// onboarding/sahayatri_brand.dart
//
// "Sahayatri" brand-mark widgets — गोलाकार glow ब्याजमा साँचो logo glyph +
// "सह"+"yatri" wordmark। Onboarding र Welcome (phone landing) स्क्रिनमा
// साझा प्रयोगको लागि।
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// गोलाकार गाढा glass ब्याज (हल्का purple radial gradient + neon purple
/// border + बाहिरी glow) भित्र साँचो brand logo ("SY" road+traveler mark,
/// `assets/icon/app_icon_foreground.png` — launcher icon कै उही transparent
/// source, हेर्नुहोस् `pubspec.yaml`'s `flutter_launcher_icons`)। सेतो ठोस
/// ब्याज (अघिल्लो version) landing page कै गाढा neon theme सँग नमिलेर अति
/// उज्यालो/flat देखिन्थ्यो — अब गाढा glass background ले नै glyph (जुन
/// आफैं उज्यालो/saturated purple-pink-orange gradient हो) लाई पर्याप्त
/// luminance contrast दिन्छ, कुनै सेतो/flat panel बिनै।
class SahayatriLogoMark extends StatelessWidget {
  final double size;
  const SahayatriLogoMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.kmPurple.withValues(alpha: 0.24),
            AppColors.kmSurface.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(
          color: AppColors.kmPurple.withValues(alpha: 0.55),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.kmPurple.withValues(alpha: 0.5),
            blurRadius: 38,
            spreadRadius: 3,
          ),
          BoxShadow(
            color: AppColors.kmOrange.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Padding(
        // `app_icon_foreground.png` भित्र आफैं थप transparent margin
        // (launcher adaptive-icon safe-zone) बाँकी नै छ, त्यसैले यहाँ ठूलो
        // थप padding चाहिँदैन (glyph सानो देखिने गुनासो दोहोरिने)।
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          'assets/icon/app_icon_foreground.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// "सह" (सेतो) + "yatri" (orange→pink gradient) wordmark, तल गाढा gradient
/// underline swoosh सहित।
class SahayatriWordmark extends StatelessWidget {
  final double fontSize;
  final bool showUnderline;
  const SahayatriWordmark({
    super.key,
    this.fontSize = 32,
    this.showUnderline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
            children: [
              const TextSpan(
                text: 'सह',
                style: TextStyle(color: AppColors.kmText),
              ),
              TextSpan(
                text: 'yatri',
                style: TextStyle(
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [AppColors.kmOrange, AppColors.kmPink],
                    ).createShader(
                        Rect.fromLTWH(0, 0, fontSize * 3.2, fontSize * 1.4)),
                ),
              ),
            ],
          ),
        ),
        if (showUnderline) ...[
          const SizedBox(height: 8),
          Container(
            width: fontSize * 2.4,
            height: 4,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.kmTealBlue, AppColors.kmPurple, AppColors.kmPink, AppColors.kmOrange],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ],
    );
  }
}
