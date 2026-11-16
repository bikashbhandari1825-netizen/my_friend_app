// onboarding/onboarding_gate.dart
//
// एप पहिलोपटक खोल्दा मात्र देखिने ४-चरण gate — [MascotIntroScreen] (२-स्लाइड
// mascot illustration carousel) → भाषा छनोट → [OnboardingScreen] (3-slide
// feature carousel) → अन्त्यमा [PhoneLandingPage]। तीनै चरण आ-आफ्नै
// SharedPreferences flag मा save हुन्छन्, अर्को पटकदेखि सिधै
// [PhoneLandingPage] (फोन नम्बर/OTP login) मै लैजान्छ। कुनै auth/OTP logic
// यहाँ छैन।
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/phone_landing_page.dart';
import 'language_selection_screen.dart';
import 'mascot_intro_screen.dart';
import 'onboarding_screen.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  static const _kMascotSeen = 'onboarding.mascotSeen';
  static const _kLanguageChosen = 'onboarding.languageChosen';
  static const _kSeenOnboarding = 'onboarding.seen';

  bool? _mascotSeen;
  bool? _languageChosen;
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final mascotSeen = p.getBool(_kMascotSeen) ?? false;
      final languageChosen = p.getBool(_kLanguageChosen) ?? false;
      final seen = p.getBool(_kSeenOnboarding) ?? false;
      if (mounted) {
        setState(() {
          _mascotSeen = mascotSeen;
          _languageChosen = languageChosen;
          _seen = seen;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _mascotSeen = true;
          _languageChosen = true;
          _seen = true;
        });
      }
    }
  }

  Future<void> _finishMascotIntro() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kMascotSeen, true);
    } catch (_) {}
    if (mounted) setState(() => _mascotSeen = true);
  }

  Future<void> _chooseLanguage() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kLanguageChosen, true);
    } catch (_) {}
    if (mounted) setState(() => _languageChosen = true);
  }

  Future<void> _finish() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kSeenOnboarding, true);
    } catch (_) {}
    if (mounted) setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_mascotSeen == null || _languageChosen == null || _seen == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF07060D),
        body: SizedBox.shrink(),
      );
    }
    if (_mascotSeen == false) {
      return MascotIntroScreen(onFinish: _finishMascotIntro);
    }
    if (_languageChosen == false) {
      return LanguageSelectionScreen(onNext: _chooseLanguage);
    }
    if (_seen == false) {
      return OnboardingScreen(onFinish: _finish);
    }
    return const PhoneLandingPage();
  }
}
