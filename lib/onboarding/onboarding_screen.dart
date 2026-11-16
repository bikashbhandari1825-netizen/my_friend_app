// onboarding/onboarding_screen.dart
//
// एप पहिलोपटक खोल्दा देखिने ३-स्लाइड स्वाइप गर्न मिल्ने इन्ट्रो/onboarding
// carousel — dark glassmorphic aurora थिम (My Profile जस्तै)। यहाँ कुनै पनि
// auth/business logic छैन — केवल visual intro हो; "सुरु गर्नुहोस्" थिचेपछि
// वा सबै स्लाइड स्वाइप गरेपछि [onFinish] कल हुन्छ, जसले caller लाई (OnboardingGate)
// अघि बढ्न (phone-OTP landing page देखाउन) संकेत गर्छ।
//
// हरेक स्लाइडको illustration `assets/images/slide{1,2,3}.png` (साँचो
// 3D-render PNG, `pubspec.yaml`'s `assets/images/` बाट) — `_IllustrationRing`
// ले घुमिरहेको cyan-नियन rim-light ring (`_GlowRingPainter`) भित्र circle
// मा crop गरेर देखाउँछ। कुनै image नदिई CustomPainter vector fallback पनि
// अझै सम्भव छ (`_OnboardSlide.paint`) — हाल कुनै स्लाइडले प्रयोग गर्दैन।
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class _OnboardSlide {
  final String title;
  final String subtitle;
  // दुईमध्ये एउटा मात्र दिइन्छ — `imageAsset` (साँचो PNG, `Image.asset`)
  // भए त्यही देखाउने, नभए `paint` (CustomPainter vector illustration)
  // fallback को रूपमा।
  final String? imageAsset;
  final CustomPainter Function(double t)? paint;
  const _OnboardSlide({
    required this.title,
    required this.subtitle,
    this.imageAsset,
    this.paint,
  }) : assert(imageAsset != null || paint != null);
}

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  List<_OnboardSlide> get _slides => [
        _OnboardSlide(
          title: S.isNepali ? 'एकै ठाउँमा सबै सेवा' : 'All-in-one services',
          subtitle: S.isNepali
              ? 'राइड बुक गर्नुहोस् वा भरपर्दो स्थानीय कामदार भाडामा लिनुहोस् — सबै एउटै एपबाट।'
              : 'Book a ride or hire a trusted local worker — all from one app.',
          imageAsset: 'assets/images/slide1.png',
        ),
        _OnboardSlide(
          title: S.isNepali ? 'आफ्नै मूल्यमा प्रस्ताव राख्नुहोस्' : 'Offer your own price',
          subtitle: S.isNepali
              ? 'स्थानीय कामदारसँग सिधै मूल्य कुराकानी गर्नुहोस् — बीचमा कुनै कमिसन दलाल छैन।'
              : 'Negotiate directly with local workers — no middleman commission.',
          imageAsset: 'assets/images/slide2.png',
        ),
        _OnboardSlide(
          title: S.isNepali ? 'फोन नम्बरबाट छिटो लगइन' : 'Fast login by phone number',
          subtitle: S.isNepali
              ? 'कुनै पासवर्ड झन्झट छैन — फोन नम्बर हालेर सजिलै खाता बनाउनुहोस् वा लगइन गर्नुहोस्।'
              : 'No password hassle — just your phone number to sign up or log in.',
          imageAsset: 'assets/images/slide3.png',
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
    final slides = _slides;
    final isLast = _page == slides.length - 1;
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
                    child: Text(
                      S.isNepali ? 'छोड्नुहोस्' : 'Skip',
                      style: const TextStyle(
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
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _SlideView(slide: slides[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slides.length, (i) {
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
                  label: isLast
                      ? (S.isNepali ? 'सुरु गर्नुहोस्' : 'Get started')
                      : (S.isNepali ? 'अर्को' : 'Next'),
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

class _SlideView extends StatelessWidget {
  final _OnboardSlide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView + Column (`mainAxisSize: min`) — ठाउँ पुगे
    // सुरुतिर (top-anchored) देखिन्छ, नपुगे (सानो/कम उचाइको फोन) scroll
    // हुन्छ — content कहिल्यै बेपत्ता/काटिने वा overflow-धर्का देखिने छैन।
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IllustrationRing(slide: slide),
            const SizedBox(height: 34),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.kmText,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              slide.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.kmMuted,
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// नियन rim-light accent — यो फाइलभरि प्रयोग हुने दुई cyan/blue टोन (settings_page.dart
/// जस्ता अन्य screen मा पहिल्यै प्रयोग भइसकेको उही signature accent)।
class _Neon {
  static const a = Color(0xFF5CFFD1);
  static const b = Color(0xFF22B8FF);
}

/// घुम्ने radar-style neon ring + भित्र slide-विशेष illustration — दुवैलाई
/// एउटै घुम्ने `t` (0..1 loop) ले animate गर्छ।
class _IllustrationRing extends StatefulWidget {
  final _OnboardSlide slide;
  const _IllustrationRing({required this.slide});

  @override
  State<_IllustrationRing> createState() => _IllustrationRingState();
}

class _IllustrationRingState extends State<_IllustrationRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageAsset = widget.slide.imageAsset;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ringController,
        builder: (context, _) {
          final t = _ringController.value;
          return SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _GlowRingPainter(t),
              child: Padding(
                padding: EdgeInsets.all(imageAsset != null ? 14 : 32),
                child: imageAsset != null
                    ? ClipOval(
                        child: Image.asset(imageAsset, fit: BoxFit.cover),
                      )
                    : CustomPaint(
                        painter: widget.slide.paint!(t),
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// घुम्ने radar-style neon ring — icon वरिपरि rim-light।
class _GlowRingPainter extends CustomPainter {
  final double t;
  _GlowRingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;

    final halo = Paint()
      ..shader = RadialGradient(colors: [
        _Neon.b.withValues(alpha: 0.32),
        _Neon.b.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: c, radius: r + 28));
    canvas.drawCircle(c, r + 28, halo);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(colors: [
        Color(0x005CFFD1),
        _Neon.a,
        _Neon.b,
        Color(0x0022B8FF),
      ]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 2 * math.pi);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), 0, math.pi * 0.6, false, sweep);
    canvas.restore();

    canvas.drawCircle(c, r - 16, Paint()..color = Colors.white.withValues(alpha: 0.065));
    canvas.drawCircle(
      c,
      r - 16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter old) => old.t != t;
}
