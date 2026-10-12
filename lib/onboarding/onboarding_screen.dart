// onboarding/onboarding_screen.dart
//
// एप पहिलोपटक खोल्दा देखिने ३-स्लाइड स्वाइप गर्न मिल्ने इन्ट्रो/onboarding
// carousel — dark glassmorphic aurora थिम (My Profile जस्तै)। यहाँ कुनै पनि
// auth/business logic छैन — केवल visual intro हो; "सुरु गर्नुहोस्" थिचेपछि
// वा सबै स्लाइड स्वाइप गरेपछि [onFinish] कल हुन्छ, जसले caller लाई (OnboardingGate)
// अघि बढ्न (phone-OTP landing page देखाउन) संकेत गर्छ।
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class _OnboardSlide {
  final IconData icon;
  final Gradient iconBg;
  // Glow ring/particle को रङ — `iconBg` कै मुख्य टोनसँग मिल्ने, छुट्टै दिइएको
  // (gradient बाट runtime मै रङ निकाल्नु भन्दा सजिलो/सुरक्षित)।
  final Color accentColor;
  // सानो "badge" icon — मुख्य icon कै तल्लो-दायाँ कुनामा छुट्टै गोलो
  // ब्याजको रूपमा देखिने (जस्तै handshake + price-tag, phone + verified
  // checkmark) — एउटै सादा icon भन्दा बढी "composed illustration" जस्तो
  // देखियोस् भनेर।
  final IconData badgeIcon;
  final Color badgeColor;
  final String title;
  final String subtitle;
  const _OnboardSlide({
    required this.icon,
    required this.iconBg,
    required this.accentColor,
    required this.badgeIcon,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
  });
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
          icon: Icons.directions_car_filled_rounded,
          iconBg: const LinearGradient(
              colors: [AppColors.kmPurple, AppColors.kmPink]),
          accentColor: AppColors.kmPurple,
          badgeIcon: Icons.handyman_rounded,
          badgeColor: AppColors.kmOrange,
          title: S.isNepali ? 'एकै ठाउँमा सबै सेवा' : 'All-in-one services',
          subtitle: S.isNepali
              ? 'राइड बुक गर्नुहोस् वा भरपर्दो स्थानीय कामदार भाडामा लिनुहोस् — सबै एउटै एपबाट।'
              : 'Book a ride or hire a trusted local worker — all from one app.',
        ),
        _OnboardSlide(
          icon: Icons.handshake_rounded,
          iconBg: const LinearGradient(
              colors: [AppColors.kmOrange, AppColors.kmOrangeDeep]),
          accentColor: AppColors.kmOrange,
          badgeIcon: Icons.sell_rounded,
          badgeColor: AppColors.kmTealBlue,
          title: S.isNepali ? 'आफ्नै मूल्यमा प्रस्ताव राख्नुहोस्' : 'Offer your own price',
          subtitle: S.isNepali
              ? 'स्थानीय कामदारसँग सिधै मूल्य कुराकानी गर्नुहोस् — बीचमा कुनै कमिसन दलाल छैन।'
              : 'Negotiate directly with local workers — no middleman commission.',
        ),
        _OnboardSlide(
          icon: Icons.phone_iphone_rounded,
          iconBg: const LinearGradient(colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
          accentColor: AppColors.kmTealBlue,
          badgeIcon: Icons.verified_rounded,
          badgeColor: AppColors.kmTeal,
          title: S.isNepali ? 'फोन नम्बरबाट छिटो लगइन' : 'Fast login by phone number',
          subtitle: S.isNepali
              ? 'कुनै पासवर्ड झन्झट छैन — फोन नम्बर हालेर सजिलै खाता बनाउनुहोस् वा लगइन गर्नुहोस्।'
              : 'No password hassle — just your phone number to sign up or log in.',
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
    // पहिले यहाँ सिधै (scroll बिनाको) `Column(mainAxisAlignment: center)`
    // मात्र थियो — सानो/कम उचाइको फोन (landscape, वा ठूलो font-scale जस्तै
    // घटेको उचाइ) मा `_GlowIcon` (156px, नयाँ glow ring सहित, पहिलेको
    // सादा 96px भन्दा ठूलो) + title + subtitle जोड्दा उपलब्ध उचाइभन्दा
    // बढी भई RenderFlex overflow (पहेँलो/कालो धर्का) आउँथ्यो। पहिलो try
    // (`LayoutBuilder` + `ConstrainedBox(minHeight)`) ले औंल्याइएको ठाउँमा
    // नै title/subtitle पूर्ण रूपमा (कुनै error/overflow warning बिनै)
    // बेपत्ता भइदियो — त्यो जटिल pattern भरपर्दो सावित भएन। अब सिधा,
    // जोखिम-रहित bulletproof तरिका: `SingleChildScrollView` + Column
    // (`mainAxisSize: min`, content-अनुसार मात्र अग्लो) — ठाउँ पुगे सुरुतिर
    // (top-anchored) देखिन्छ (ठूलो स्क्रिनमा बीचमा नहुन सक्छ, तर त्यो
    // कमजोरी सजावटी मात्र हो), नपुगे scroll हुन्छ — content कहिल्यै
    // बेपत्ता/काटिने वा overflow-धर्का देखिने छैन।
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowIcon(slide: slide),
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

/// Onboarding icon — "neon glow orb" शैली (reference डिजाइन फोटो जस्तै):
/// घुमिरहने बहु-रङी (cyan→purple→pink→orange) neon ring, gradient-रंगिएको
/// icon glyph (एउटै ठोस रङ होइन), बाहिरी नरम ambient glow, अनि वरिपरि
/// तैरिरहेका सानो accent particle dot — दुवै icon-slide (price-offer र
/// phone-login) मा उही एउटै आधुनिक/एडभान्स ring treatment (पहिले यहाँ
/// खाली एउटा सादा भरिएको circle + पातलो सेतो-मात्र ring थियो)। सेतो
/// पृष्ठभूमि/box कतै थपिएको छैन — गाढा theme सँगै मिलिरहन्छ।
class _GlowIcon extends StatefulWidget {
  final _OnboardSlide slide;
  const _GlowIcon({required this.slide});

  @override
  State<_GlowIcon> createState() => _GlowIconState();
}

class _GlowIconState extends State<_GlowIcon>
    with SingleTickerProviderStateMixin {
  // Ring बिस्तारै घुमिरहोस् — value मात्र ०..१ बीच loop हुने, कुनै
  // jank/setState-heavy काम छैन (CustomPainter ले सिधै repaint गर्छ)।
  late final AnimationController _ringCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  // एपभरिकै brand accent — दुवै icon-slide मा उही एउटा neon sweep, ताकि
  // "यही फोटो जस्तै डिजाइन दुवैतिर" भन्ने माग अनुसार एउटै signature ring।
  static const _ringColors = [
    AppColors.kmTealBlue,
    AppColors.kmPurple,
    AppColors.kmPink,
    AppColors.kmOrange,
    AppColors.kmTealBlue,
  ];

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  Widget _dot(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = widget.slide.accentColor;
    return RepaintBoundary(
      child: SizedBox(
        width: 156,
        height: 156,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // बाहिरी नरम ambient glow — बीचबाट बाहिर हराउँदै।
            Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent.withValues(alpha: 0.30), Colors.transparent],
                ),
              ),
            ),
            // घुमिरहने बहु-रङी neon ring (glow + crisp दुवै तह)।
            AnimatedBuilder(
              animation: _ringCtrl,
              builder: (context, _) => CustomPaint(
                size: const Size(132, 132),
                painter: _NeonRingPainter(
                  turns: _ringCtrl.value,
                  colors: _ringColors,
                ),
              ),
            ),
            // मुख्य gradient circle + gradient-रंगिएको icon glyph।
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: widget.slide.iconBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.kmInk, Colors.white70],
                ).createShader(bounds),
                child: Icon(widget.slide.icon, size: 42),
              ),
            ),
            // तैरिरहेका सजावटी particle dot।
            Positioned(top: 6, right: 14, child: _dot(AppColors.kmTeal, 10)),
            Positioned(bottom: 20, left: 2, child: _dot(AppColors.kmPink, 8)),
            Positioned(top: 44, left: -6, child: _dot(accent, 7)),
            // सानो "badge" circle — मुख्य icon लाई एउटा सादा glyph नभई दुई
            // अवधारणा (जस्तै handshake + price-tag) जोडिएको composed
            // illustration जस्तो देखाउनको लागि, मुख्य circle कै तल्लो-दायाँ
            // किनारमा अलिक ओभरल्याप गरेर।
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.slide.badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.kmSurface.withValues(alpha: 0.9),
                      width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: widget.slide.badgeColor.withValues(alpha: 0.6),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(widget.slide.badgeIcon,
                    size: 19, color: AppColors.kmInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Neon sweep-gradient ring — built-in `Border`/`BoxDecoration` ले circular
/// stroke मा gradient दिन नमिल्ने भएकोले CustomPainter चाहियो। [turns]
/// (०..१, लुप हुने) ले पूरै ring बिस्तारै घुमाउँछ; बाहिरी blurred तह (नरम
/// glow) + भित्री crisp पातलो line दुवै उही SweepGradient बाट, ताकि
/// जोर्नी (सुरु/अन्त्य) कहीं टुटेको नदेखियोस्।
class _NeonRingPainter extends CustomPainter {
  final double turns;
  final List<Color> colors;
  const _NeonRingPainter({required this.turns, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      colors: colors,
      transform: GradientRotation(turns * 2 * math.pi),
    );
    final shader = gradient.createShader(rect);

    final glow = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius, glow);

    final line = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawCircle(center, radius, line);
  }

  @override
  bool shouldRepaint(covariant _NeonRingPainter oldDelegate) =>
      oldDelegate.turns != turns;
}
