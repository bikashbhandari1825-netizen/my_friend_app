// onboarding/language_selection_screen.dart
//
// एप पहिलोपटक खोल्दा सबैभन्दा पहिलो देखिने भाषा-छनोट screen — यसपछि मात्र
// onboarding_screen.dart (3-slide carousel), अनि अन्त्यमा phone-OTP landing
// page (हेर्नुहोस् onboarding_gate.dart को क्रम)। छानेको भाषा सिधै
// `localeNotifier` (app_globals.dart) मा लेख्छ — prefs.dart कै existing
// listener ले नै भविष्यका सबै launch को लागि आफैं बचत गर्छ, यहाँ छुट्टै
// persist गर्नु पर्दैन।
//
// हाल `supportedLocales` (app.dart) मा केवल English/नेपाली छ — बंगाली
// (Bangla) को लागि कुनै अनुवादित string/l10n डाटा एपमा छैन, त्यसैले यहाँ
// नराखिएको (नराम्रो/अधुरो "भाषा" देखाउनुभन्दा नदेखाउनु बेस)।
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'sahayatri_brand.dart';

class LanguageSelectionScreen extends StatefulWidget {
  final VoidCallback onNext;
  const LanguageSelectionScreen({super.key, required this.onNext});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageOption {
  final String code;
  final String nativeName;
  const _LanguageOption(this.code, this.nativeName);
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  static const _languages = [
    _LanguageOption('en', 'English'),
    _LanguageOption('ne', 'नेपाली'),
  ];

  late String _selected = localeNotifier.value.languageCode;

  void _next() {
    localeNotifier.value = Locale(_selected);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const Center(child: SahayatriLogoMark(size: 92)),
                const SizedBox(height: 20),
                const Center(child: SahayatriWordmark(fontSize: 28)),
                const SizedBox(height: 10),
                const Text(
                  'Choose your language\nभाषा छान्नुहोस्',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.kmMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const Spacer(flex: 1),
                ..._languages.map((lang) {
                  final selected = _selected == lang.code;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = lang.code),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.kmOrange.withValues(alpha: 0.14)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? AppColors.kmOrange
                                : Colors.white.withValues(alpha: 0.14),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                lang.nativeName,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.kmOrange
                                      : AppColors.kmText,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected
                                  ? AppColors.kmOrange
                                  : AppColors.kmMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(flex: 2),
                KmCtaButton(
                  label: _selected == 'ne' ? 'अर्को' : 'Next',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
