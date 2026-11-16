// widgets/splash_intro.dart
//
// एप खोल्दा देखिने भव्य "Disney-शैली" opening animation:
//   १. गाढा रातो-नीलो रातको आकाश, ताराहरू झिलमिल हुँदै देखिन्छन्
//   २. सुनौलो जादुई तारा (comet) ठूलो चाप बनाएर उडेर आउँछ, पछाडि चम्किलो पुच्छर
//   ३. बीचमा पुग्दा प्रकाशको विस्फोट — चक्र (ring) र किरणहरू फैलिन्छन्
//   ४. सहयात्री logo चम्किलो पाटीमा ठूलो हुँदै प्रकट हुन्छ, चमक (shimmer) सर्छ
//   ५. वरिपरि ताराहरू घुम्छन्, अनि सहज fade-out भएर एप देखिन्छ
// ~४.६ सेकेन्ड; स्क्रिन थिचे skip। एप खुल्दा प्रक्रियामा एकपटक मात्र।
import 'dart:math' as math;

import 'package:flutter/material.dart';

const _gold = Color(0xFFFFD98A);
const _violet = Color(0xFF9B6BFF);
const _orange = Color(0xFFF8873F);

class SplashIntro extends StatefulWidget {
  final Widget child;
  const SplashIntro({super.key, required this.child});

  static bool _shown = false;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  );
  bool _done = SplashIntro._shown;

  /// एपको मुख्य भाग सुरुमै mount हुन्छ — यसको पहिलो build ~१s लाग्ने रहेछ।
  /// मैले यो animation को बीचमा सार्दा (नापेर) १.२s को झट्का देखियो, त्यसैले
  /// यो भार animation सुरु हुनुअघिको (native splash) समयमै लुकाइन्छ।
  final bool _childMounted = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // logo को decode animation सुरु हुनुअघि नै — प्रकट हुँदा झट्का नलागोस्।
    if (!_done) {
      for (final a in const [
        'assets/images/app_logo_gold.png',
        'assets/images/app_logo_white.png',
        'assets/images/app_logo_glow.png',
      ]) {
        precacheImage(AssetImage(a), context);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (_done) return;
    SplashIntro._shown = true;
    // एपको पहिलो भारी build (पछाडि) सकिएपछि मात्र animation चलाउने — नत्र
    // त्यो build बीचमै animation लाई झट्का दिन्छ। त्यतिञ्जेल गाढा आकाश स्थिर।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        _c.forward().whenComplete(() {
          if (mounted) setState(() => _done = true);
        });
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_done) return;
    _c.animateTo(1, duration: const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    // Stack की संरचना सधैँ उस्तै — splash सकिँदा `widget.child` (Navigator)
    // फेरि mount भएर route/state नगुमाओस् र अतिरिक्त झट्का नआओस्।
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        _childMounted ? widget.child : const SizedBox.shrink(),
        if (!_done)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _skip,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _frame(context, _c.value),
              ),
            ),
          ),
      ],
    );
  }

  Widget _frame(BuildContext context, double t) {
    final size = MediaQuery.of(context).size;
    final out = Curves.easeIn.transform(((t - 0.90) / 0.10).clamp(0.0, 1.0));
    // logo पाटी: विस्फोटपछि (≈.५०) बाट प्रकट
    final lt = ((t - 0.50) / 0.26).clamp(0.0, 1.0);
    final lScale = 0.35 + 0.65 * Curves.easeOutBack.transform(lt);
    final lOpacity = Curves.easeOut.transform(((t - 0.50) / 0.12).clamp(0.0, 1.0));
    final shine = Curves.easeInOut.transform(((t - 0.68) / 0.20).clamp(0.0, 1.0));
    final glowPulse = 0.5 + 0.5 * math.sin(t * math.pi * 6);

    return Opacity(
      opacity: 1 - out,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070418), Color(0xFF160A36), Color(0xFF3B1457)],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _SkyPainter(t: t)),
              ),
            ),
            Opacity(
              opacity: lOpacity,
              child: Transform.scale(
                scale: lScale * (1 + 0.04 * out),
                child: _GlowLogo(
                  width: math.min(size.width * 0.88, 480.0),
                  shine: shine,
                  pulse: glowPulse,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// रातको आकाश: तारा, उड्ने जादुई तारा (comet), विस्फोट (ring + किरण), र logo
/// वरिपरि घुम्ने ताराहरू — सबै एउटै painter मा, समय `t` (०–१) बाट।
class _SkyPainter extends CustomPainter {
  final double t;
  _SkyPainter({required this.t});

  static final _rnd = math.Random(11);
  // (x, y, आकार, phase) — स्क्रिनको अनुपातमा
  static final _stars = List.generate(
      55,
      (_) => (_rnd.nextDouble(), _rnd.nextDouble(), 0.4 + _rnd.nextDouble(),
          _rnd.nextDouble() * math.pi * 2));
  static final _orbit = List.generate(
      18,
      (i) => (i / 18 * math.pi * 2, 0.34 + _rnd.nextDouble() * 0.16,
          0.5 + _rnd.nextDouble() * 0.8, _rnd.nextDouble()));

  Offset _comet(Size s, double p) {
    // quadratic Bézier: तल-बायाँ बाहिरबाट, माथि घुमेर, केन्द्रमा
    final p0 = Offset(-0.10 * s.width, 0.92 * s.height);
    final p1 = Offset(0.18 * s.width, 0.04 * s.height);
    final p2 = Offset(0.5 * s.width, 0.5 * s.height);
    final u = 1 - p;
    return p0 * (u * u) + p1 * (2 * u * p) + p2 * (p * p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();

    // ── ताराहरू (सुरुमै फिक्का हुँदै देखिने, झिलमिल) ──
    final starIn = (t / 0.18).clamp(0.0, 1.0);
    for (final (x, y, sz, ph) in _stars) {
      final tw = 0.55 + 0.45 * math.sin(t * math.pi * 9 + ph);
      paint.color = Colors.white.withValues(alpha: 0.85 * starIn * tw);
      canvas.drawCircle(Offset(x * size.width, y * size.height), 0.8 * sz + 0.4,
          paint);
    }

    // ── जादुई तारा (comet) ──
    final cp = ((t - 0.10) / 0.40).clamp(0.0, 1.0);
    if (cp > 0 && cp < 1) {
      final ease = Curves.easeInOut.transform(cp);
      for (var k = 28; k >= 0; k--) {
        final pk = (ease - k * 0.014).clamp(0.0, 1.0);
        final pos = _comet(size, pk);
        final f = 1 - k / 28;
        paint.color = Color.lerp(_violet, _gold, f)!.withValues(alpha: 0.55 * f);
        canvas.drawCircle(pos, 2 + 7 * f, paint);
      }
      final head = _comet(size, ease);
      _glow(canvas, head, 34, _gold, 0.9);
      _star4(canvas, head, 15, Colors.white);
    }

    // ── विस्फोट: चक्र + किरण + उज्यालो ──
    final bt = ((t - 0.50) / 0.34).clamp(0.0, 1.0);
    if (bt > 0 && bt < 1) {
      final e = Curves.easeOutCubic.transform(bt);
      final fade = 1 - bt;
      final maxR = size.shortestSide * 0.95;
      // उज्यालो चमक — gradient shader (हरेक frame नयाँ बन्ने, ठूलो क्षेत्र) को
      // सट्टा सादा पारदर्शी घेरा: उस्तै देखिन्छ, तर GPU/CPU भार निकै कम।
      canvas.drawCircle(
          center,
          maxR * 0.55 * e + 40,
          Paint()..color = Colors.white.withValues(alpha: 0.14 * fade * fade));
      // चक्र
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * fade + 1
        ..color = _gold.withValues(alpha: 0.9 * fade);
      canvas.drawCircle(center, maxR * e, paint);
      paint
        ..strokeWidth = 3 * fade + 0.5
        ..color = _violet.withValues(alpha: 0.7 * fade);
      canvas.drawCircle(center, maxR * 0.7 * e, paint);
      paint.style = PaintingStyle.fill;
      // किरणहरू — सबै एउटै Path मा, एकै draw call (२८ अलग-अलग होइन)।
      const rays = 24;
      final rayPath = Path();
      for (var i = 0; i < rays; i++) {
        final a = i / rays * math.pi * 2 + t * 0.6;
        final len = maxR * (0.35 + 0.65 * ((i % 3) / 2)) * e;
        final dir = Offset(math.cos(a), math.sin(a));
        final from = center + dir * (len * 0.25);
        final to = center + dir * len;
        rayPath
          ..moveTo(from.dx, from.dy)
          ..lineTo(to.dx, to.dy);
      }
      paint
        ..color = _gold.withValues(alpha: 0.45 * fade)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(rayPath, paint);
      paint.style = PaintingStyle.fill;
    }

    // ── logo वरिपरि घुम्ने ताराहरू (विस्फोटपछि) ──
    final ot = ((t - 0.58) / 0.30).clamp(0.0, 1.0);
    if (ot > 0) {
      final fadeIn = math.sin(ot * math.pi).clamp(0.0, 1.0);
      for (final (a0, r, sc, ph) in _orbit) {
        final a = a0 + t * 2.2 * (ph > 0.5 ? 1 : -1) * 0.5;
        final pos = center +
            Offset(math.cos(a) * size.width * r,
                math.sin(a) * size.width * r * 0.45);
        final tw = 0.5 + 0.5 * math.sin(t * math.pi * 14 + ph * 6);
        _star4(canvas, pos, (5 + 9 * sc) * tw,
            Color.lerp(_gold, Colors.white, ph)!.withValues(alpha: fadeIn));
      }
    }
  }

  void _glow(Canvas canvas, Offset c, double r, Color color, double a) {
    final shader = RadialGradient(colors: [
      color.withValues(alpha: a),
      color.withValues(alpha: 0),
    ]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, Paint()..shader = shader);
  }

  void _star4(Canvas canvas, Offset p, double len, Color color) {
    if (len <= 0) return;
    final path = Path()
      ..moveTo(p.dx, p.dy - len)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + len, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + len)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - len, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - len)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t;
}


/// पाटी बिनाको logo — सबै चित्र पहिल्यै तयार (gold/white/glow PNG), त्यसैले
/// animation मा कुनै blur/ShaderMask/saveLayer चल्दैन (नापेर फ्रेम-रोकाइ
/// देखिएको थियो)। चमक = सेतो logo को एउटा साँघुरो पट्टी मात्र clip गरेर सार्ने।
class _GlowLogo extends StatelessWidget {
  final double width;
  final double shine;
  final double pulse;
  const _GlowLogo(
      {required this.width, required this.shine, required this.pulse});

  static const _gold = 'assets/images/app_logo_gold.png';
  static const _white = 'assets/images/app_logo_white.png';
  static const _glow = 'assets/images/app_logo_glow.png';

  @override
  Widget build(BuildContext context) {
    final h = width * 199 / 672;
    // glow चित्रमा ७०px (मूल चौडाइको 70/672) सबैतिर padding
    final padPx = width * 70 / 672;
    return SizedBox(
      width: width * 1.3,
      height: width * 0.62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // नरम बैजनी-सुन्तला halo
          Container(
            width: width * 1.3,
            height: width * 0.62,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                _violet.withValues(alpha: 0.38 + 0.12 * pulse),
                _orange.withValues(alpha: 0.12),
                Colors.transparent,
              ], stops: const [0.0, 0.55, 1.0]),
            ),
          ),
          // पहिल्यै धमिलो पारिएको glow
          Opacity(
            opacity: 0.55 + 0.25 * pulse,
            child: Image.asset(_glow,
                width: width + 2 * padPx, fit: BoxFit.contain),
          ),
          // मुख्य logo
          Image.asset(_gold,
              width: width,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high),
          // चमकको पट्टी — सेतो logo को सार्ने भाग
          ClipRect(
            clipper: _BandClipper(center: -0.15 + 1.3 * shine, half: 0.07),
            child: Image.asset(_white,
                width: width,
                height: h,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high),
          ),
        ],
      ),
    );
  }
}

/// चौडाइको अनुपातमा `center ± half` को ठाडो पट्टी मात्र देखाउने clipper।
class _BandClipper extends CustomClipper<Rect> {
  final double center;
  final double half;
  _BandClipper({required this.center, required this.half});

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
      size.width * (center - half), 0, size.width * (center + half), size.height);

  @override
  bool shouldReclip(_BandClipper old) => old.center != center;
}
