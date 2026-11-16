// onboarding/mascot_intro_screen.dart
//
// एप पहिलोपटक खोल्दा सबैभन्दा पहिलो देखिने २-स्लाइड mascot illustration
// carousel — language-selection भन्दा पनि अघि (हेर्नुहोस् onboarding_gate.dart
// को क्रम: यो स्क्रिन → LanguageSelectionScreen → OnboardingScreen (3-slide
// feature carousel) → PhoneLandingPage)। onboarding_screen.dart कै उस्तै
// दृश्य ढाँचा (AuroraBackground, PageView, dot indicator, Skip + Next/Get
// Started बटन) — फरक यत्ति: यहाँ साना circular icon होइन, पूरै-composed
// mascot poster illustration (assets/images/mascot_female.png/mascot_male.png)
// ठूलो आकारमा देखिन्छ। कुनै auth/business logic छैन, केवल visual intro।
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class _MascotSlide {
  final String imageAsset;
  final String title;
  final String subtitle;
  // यो illustration भित्रै baked (source PNG pixel) "३ dots" decorative
  // element छ/छैन — भए मात्र `_MascotSlideView` ले त्यही सानो क्षेत्रमाथि
  // background-matching patch थप्छ (हेर्नुहोस् तल `_dotsPatchRect`)।
  final bool hasBakedInDots;
  // फोनको screen भित्रको generic mountain icon माथि official Sahayatri
  // "SY" logo (assets/icon/app_icon_foreground.png) overlay गर्ने हो भने
  // (image fraction coords, pixel-measured — हेर्नुहोस् `_MascotSlideView`)।
  final Rect? logoOverlayRect;
  // फोन चित्रमा झुकेको छ — logo लाई पनि सोही कोणमा घुमाउने (डिग्री,
  // negative = anticlockwise)।
  final double logoOverlayAngleDeg;
  const _MascotSlide({
    required this.imageAsset,
    required this.title,
    required this.subtitle,
    this.hasBakedInDots = false,
    this.logoOverlayRect,
    this.logoOverlayAngleDeg = 0,
  });
}

class MascotIntroScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const MascotIntroScreen({super.key, required this.onFinish});

  @override
  State<MascotIntroScreen> createState() => _MascotIntroScreenState();
}

class _MascotIntroScreenState extends State<MascotIntroScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _MascotSlide(
      imageAsset: 'assets/images/mascot_female.png',
      title: 'Ride-Sharing & Fare Bargaining',
      subtitle:
          'Namaste! Book rides, bargain fares directly with drivers, & enjoy zero middleman fees!',
    ),
    _MascotSlide(
      imageAsset: 'assets/images/mascot_male.png',
      title: 'Hotels, Handyman & All-in-One Services',
      subtitle:
          'Welcome! Find verified hotels, local handymen, & trusted home services at your own price!',
      hasBakedInDots: true,
      // mascot_male.png अब नयाँ asset हो — phone screen भित्रको mountain
      // icon source PNG बाटै पूर्ण रूपमा erase गरिसकिएको (कुनै mask/patch
      // अब चाहिँदैन)। logo-rect ले अब त्यो खाली सेतो ठाउँमा logo राख्ने
      // स्थान तोक्छ — "A Brighter Tomorrow Together" text को ठ्याक्कै
      // पिक्सेल-नापिएको horizontal center (x≈184, screen भित्र फोन
      // झुकेकोले bezel-center भन्दा अलि दायाँ) मा केन्द्रित, notch र
      // text बीचको खाली ठाउँमा।
      //
      // Centered + Tilt-Aware — पहिले logo सीधा र सानो थियो, र text को
      // x-केन्द्रमा (फोन झुकेकोले screen को साँचो केन्द्र भन्दा दायाँ)
      // राखिएको थियो। अब screen को दुवै bezel बीचको साँचो केन्द्र-रेखामा
      // (notch र text बीचको खाली ठाउँको ठ्याक्कै बीच), फोनकै कोण (~9.5°)
      // मा घुमाइएको। मान 1254×1254 source PNG कै अनुपातमा (center
      // x=.1360, y=.3991, साइज .093 — वर्गाकार icon canvas)।
      logoOverlayRect: Rect.fromLTWH(0.0895, 0.3526, 0.093, 0.093),
      logoOverlayAngleDeg: -9.5,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    final last = _slides.length - 1;
    if (_page >= last) {
      widget.onFinish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
                  child: TextButton(
                    onPressed: widget.onFinish,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.kmMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _MascotSlideView(slide: _slides[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: active ? AppColors.kmCtaGradient : null,
                      color: active ? null : Colors.white.withValues(alpha: 0.18),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: KmCtaButton(
                  label: isLast ? 'Get started' : 'Next',
                  icon: isLast ? Icons.arrow_forward_rounded : null,
                  onPressed: _next,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _MascotSlideView extends StatelessWidget {
  final _MascotSlide slide;
  const _MascotSlideView({required this.slide});

  // Baked-In Dots Patch — पिक्सेल-नापिएको (System.Drawing bitmap crop +
  // gridline जाँचबाट प्रत्यक्ष verify गरिएको, अड्कलले होइन) ३ सानो dot
  // cluster को ठ्याक्कै bounding box, 1254×1254 source PNG मा। "Let's
  // build a kinder, brighter Nepal!" ह्यान्डराइटेन (tilted) क्याप्सनबाट
  // टाढै छ, त्यसैले क्याप्सन कहिल्यै ढाकिँदैन।
  static const _dotsPatchRect =
      Rect.fromLTRB(0.7137, 0.8335, 0.8094, 0.8613);

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView + Column (`mainAxisSize: min`) — onboarding_screen.dart
    // कै उस्तै ढाँचा — ठाउँ पुगे top-anchored, नपुगे (सानो फोन) scroll हुन्छ,
    // content कहिल्यै overflow नहोस् भनेर। Illustration अब स्क्रिनको उचाइ
    // अनुसार नै ठूलो (screen height कै ५२%, न्यूनतम ३८०) — पहिले स्थिर
    // ३४० मात्र हुँदा सानो/अधुरो देखिन्थ्यो भन्ने गुनासो थियो।
    //
    // CRITICAL: imageSize screenHeight कै आधारमा मात्र गणना गर्दा साँघुरो
    // फोनमा (यो padding पछिको उपलब्ध चौडाइभन्दा ठूलो हुँदा) SizedBox को
    // चौडाइ parent ले क्लम्प गरिदिन्छ तर उचाइ उस्तै ठूलो रहन्छ — वर्गाकार
    // नभई अग्लो आयताकार बन्छ, अनि BoxFit.contain ले square source image
    // लाई center-letterbox गर्छ (माथि/तल खाली ठाउँ छोडेर)। यसले गर्दा
    // फोन/dots overlay-हरूको fraction-based स्थिति (जुन 1254×1254 source
    // image कै सापेक्षमा नापिएको हो) गलत ठाउँमा देखिन्थ्यो। अब उपलब्ध
    // चौडाइ (screen width घटाउँदा horizontal padding 40) लाई पनि ध्यानमा
    // राखेर दुबैको सानो मान लिइन्छ — SizedBox सधैं साँचो वर्गाकार रहोस्
    // भनेर, त्यसपछि मात्र BoxFit.contain ले image लाई ठ्याक्कै edge-to-edge
    // भर्छ, कुनै letterbox-gap बिना।
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxAvailableWidth = screenWidth - 40;
    final imageSize = math.min(
      maxAvailableWidth,
      (screenHeight * 0.52).clamp(380.0, 520.0),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // कुनै ClipRRect/corner-round नराखिएको — त्यसले illustration को
            // कुनाको पिक्सेल अलिकति भए पनि क्रप गरेको आभास दिन सक्थ्यो।
            // अब पूरै वर्गाकार PNG जस्ताको-त्यस्तै, कुनै कटौती बिना।
            SizedBox(
              width: imageSize,
              height: imageSize,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      slide.imageAsset,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (slide.hasBakedInDots)
                    Positioned(
                      left: imageSize * _dotsPatchRect.left,
                      top: imageSize * _dotsPatchRect.top,
                      width: imageSize * _dotsPatchRect.width,
                      height: imageSize * _dotsPatchRect.height,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  // Phone-screen logo overlay — mascot_male.png असेट
                  // आफैं अब mountain-icon-रहित (source PNG बाटै erase
                  // गरिसकिएको) भएकाले कुनै mask/erase-patch आवश्यक छैन,
                  // सिधै साँचो Sahayatri "SY" brand glyph (transparent
                  // PNG, त्यही asset जुन launcher icon + SahayatriLogoMark
                  // मा पनि प्रयोग हुन्छ) खाली ठाउँमा राख्छ।
                  if (slide.logoOverlayRect != null)
                    Positioned(
                      left: imageSize * slide.logoOverlayRect!.left,
                      top: imageSize * slide.logoOverlayRect!.top,
                      width: imageSize * slide.logoOverlayRect!.width,
                      height: imageSize * slide.logoOverlayRect!.height,
                      child: Transform.rotate(
                        angle: slide.logoOverlayAngleDeg * math.pi / 180,
                        child: Image.asset(
                          'assets/icon/app_icon_foreground.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.kmText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              slide.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
