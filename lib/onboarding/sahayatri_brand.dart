// onboarding/sahayatri_brand.dart
//
// "Sahayatri" brand-mark widgets — गोलाकार gradient "S" लोगो + "सह"+"yatri"
// wordmark। Onboarding र Welcome (phone landing) स्क्रिनमा साझा प्रयोगको लागि।
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// गोलाकार गाढा ब्याजमा gradient "S" चिन्ह + छेउको सानो टिप्पी बिन्दु।
class SahayatriLogoMark extends StatelessWidget {
  final double size;
  const SahayatriLogoMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.kmSurface.withValues(alpha: 0.6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.kmPurple.withValues(alpha: 0.35),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const SweepGradient(
              startAngle: 0,
              endAngle: 6.28319,
              colors: [
                AppColors.kmTealBlue,
                AppColors.kmPurple,
                AppColors.kmPink,
                AppColors.kmOrange,
                AppColors.kmTealBlue,
              ],
            ).createShader(bounds),
            child: Text(
              'S',
              style: TextStyle(
                fontSize: size * 0.56,
                fontWeight: FontWeight.w900,
                height: 1,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: size * 0.2,
            bottom: size * 0.2,
            child: Container(
              width: size * 0.1,
              height: size * 0.1,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.kmTeal, AppColors.kmTealBlue],
                ),
              ),
            ),
          ),
        ],
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
