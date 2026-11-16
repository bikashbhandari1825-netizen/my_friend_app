// widgets/futuristic_ui.dart
//
// सलोन सम्पर्क बटन, chat, र कल/ringing स्क्रिनका लागि साझा "futuristic" (OLED
// कालो + नियोन चमक) widget। भारी blur (BackdropFilter) प्रयोग गरिएको छैन —
// पारदर्शी gradient + सीमा + स्थिर glow मात्र, ताकि ९०Hz मा पनि smooth रहोस्।
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'spring_tap.dart';

const Color kNeonTeal = Color(0xFF3CF5D2);
const Color kNeonViolet = Color(0xFF9B6BFF);
const Color kNeonPink = Color(0xFFFF4FA3);
const Color kNeonBlue = Color(0xFF38B6FF);
const Color kNeonRose = Color(0xFFFF4D6D);

/// गहिरो OLED कालो पृष्ठभूमि — दुई धिमा नियोन "aurora" चमक सहित (स्थिर, blur बिना)।
class OledBackdrop extends StatelessWidget {
  final Widget child;
  final Color glowA;
  final Color glowB;
  const OledBackdrop({
    super.key,
    required this.child,
    this.glowA = kNeonViolet,
    this.glowB = kNeonTeal,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Positioned(
          top: -140,
          left: -120,
          child: _glow(glowA, 380),
        ),
        Positioned(
          bottom: -160,
          right: -140,
          child: _glow(glowB, 420),
        ),
        child,
      ],
    );
  }

  Widget _glow(Color c, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [c.withValues(alpha: 0.16), Colors.transparent],
            ),
          ),
        ),
      );
}

/// नियोन ग्लास बटन — पारदर्शी gradient भरिएको, नियोन सीमा, बाहिरी चमक,
/// गोलो आइकन-तकिया, र थिच्दा haptic + spring-scale।
class NeonGlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const NeonGlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SpringTap(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      pressedScale: 0.93,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.32),
                blurRadius: 16,
                spreadRadius: -2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.12)]),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4)),
          ],
        ),
      ),
    );
  }
}

/// तैरिरहेको "ग्लास क्याप्सुल" — chat को तलको बार (क्यामेरा/ग्यालरी/माइक/सन्देश
/// बक्स) राख्ने। पारदर्शी gradient + पातलो नियोन-सीमा + नरम तल-चमक।
class GlassCapsule extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GlassCapsule(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.fromLTRB(8, 6, 8, 6)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.11),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: kNeonTeal.withValues(alpha: 0.32), width: 1),
        boxShadow: [
          BoxShadow(
              color: kNeonViolet.withValues(alpha: 0.22),
              blurRadius: 26,
              spreadRadius: -6,
              offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

/// क्याप्सुल भित्रको सानो गोलो नियोन आइकन बटन।
class CapsuleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const CapsuleIcon(
      {super.key, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SpringTap(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      pressedScale: 0.82,
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
    );
  }
}

/// Ringing/कलका लागि बहु-तह धड्किने नियोन घेरा — दुई रङका तह, फरक चरणमा।
class NeonPulseRings extends StatelessWidget {
  final Animation<double> t;
  final double size;
  const NeonPulseRings({super.key, required this.t, this.size = 280});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: t,
          builder: (_, __) => CustomPaint(painter: _NeonRingsPainter(t.value)),
        ),
      ),
    );
  }
}

class _NeonRingsPainter extends CustomPainter {
  final double t;
  _NeonRingsPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var layer = 0; layer < 2; layer++) {
      final color = layer == 0 ? kNeonTeal : kNeonViolet;
      for (var i = 0; i < 3; i++) {
        final p = ((t + i / 3 + layer * 0.17) % 1.0);
        final r = maxR * (0.42 + 0.58 * p);
        final alpha = (1 - p) * (layer == 0 ? 0.55 : 0.38);
        paint
          ..strokeWidth = 2.4 - 1.4 * p
          ..color = color.withValues(alpha: alpha);
        canvas.drawCircle(c, r, paint);
      }
    }
    // घुम्ने "radar sweep" चाप — sci-fi अनुभूति
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(t * math.pi * 2),
        colors: [
          Colors.transparent,
          kNeonBlue.withValues(alpha: 0.9),
          Colors.transparent,
        ],
        stops: const [0.0, 0.18, 0.36],
      ).createShader(Rect.fromCircle(center: c, radius: maxR * 0.5));
    canvas.drawArc(Rect.fromCircle(center: c, radius: maxR * 0.47), 0,
        math.pi * 2, false, arc);
    // बीचको नरम चमक
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        kNeonViolet.withValues(alpha: 0.28 + 0.1 * math.sin(t * math.pi * 2)),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: c, radius: maxR * 0.5));
    canvas.drawCircle(c, maxR * 0.5, glow);
  }

  @override
  bool shouldRepaint(_NeonRingsPainter old) => old.t != t;
}

/// नियोन-सीमा भएको अवतार (नाम को पहिलो अक्षर) — कलको बीचको आकृति।
class NeonAvatar extends StatelessWidget {
  final String initial;
  final double size;
  const NeonAvatar({super.key, required this.initial, this.size = 130});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const SweepGradient(
            colors: [kNeonTeal, kNeonViolet, kNeonPink, kNeonTeal]),
        boxShadow: [
          BoxShadow(
              color: kNeonViolet.withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 2),
        ],
      ),
      child: Container(
        width: size - 8,
        height: size - 8,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF05050A)),
        child: Text(initial,
            style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900)),
      ),
    );
  }
}

/// आकृति-नियन्त्रण र बटनहरूमा प्रयोग हुने सानो "neon chip" (VIDEO CALL / VOICE CALL)।
class NeonChip extends StatelessWidget {
  final String label;
  final Color color;
  const NeonChip({super.key, required this.label, this.color = kNeonTeal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 14),
        ],
      ),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 2)),
    );
  }
}

/// ठूला Accept/Decline कल बटन — नियोन घेरा, चमक, haptic।
class NeonCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const NeonCallButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpringTap(
          onTap: () {
            HapticFeedback.heavyImpact();
            onTap();
          },
          pressedScale: 0.88,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withValues(alpha: 0.9),
                color.withValues(alpha: 0.55),
              ]),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.65),
                    blurRadius: 26,
                    spreadRadius: 2),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 1.6)),
      ],
    );
  }
}

/// ठूलो ग्लोइङ ग्रेडियन्ट एक्सन बटन (Accept / Decline / Offer Price) —
/// [filled] true: नियोन ग्रेडियन्ट भरिएको; false: गाढा ग्लास + नियोन सीमा।
/// थिच्दा haptic + spring। [onTap] null भए मधुरो (disabled)।
class NeonActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color? color2;
  final VoidCallback? onTap;
  final bool filled;
  final bool loading;
  final double height;
  final IconData? icon;
  const NeonActionButton({
    super.key,
    required this.label,
    required this.color,
    this.color2,
    this.onTap,
    this.filled = false,
    this.loading = false,
    this.height = 50,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    final fg = filled ? Colors.black : color;
    final content = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.4)),
                ),
              ),
            ],
          );
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: SpringTap(
        onTap: enabled
            ? () {
                HapticFeedback.mediumImpact();
                onTap!();
              }
            : null,
        pressedScale: 0.93,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: filled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color2 ?? color.withValues(alpha: 0.7)])
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0.03),
                    ]),
            color: filled ? null : const Color(0xCC0A0A12),
            border: Border.all(
                color: filled
                    ? Colors.white.withValues(alpha: 0.45)
                    : color.withValues(alpha: 0.8),
                width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: filled ? 0.5 : 0.24),
                  blurRadius: filled ? 20 : 12,
                  spreadRadius: filled ? 1 : -1),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}

/// राइडको बेला Call / Video / Message — तैरिरहेको ग्लास क्याप्सुलभित्र तीन
/// नियोन बटन। callbacks बाहिरबाट आउँछन् (logic यहाँ छैन)।
class NeonCommBar extends StatelessWidget {
  final String callLabel;
  final String videoLabel;
  final String messageLabel;
  final VoidCallback onCall;
  final VoidCallback onVideo;
  final VoidCallback onMessage;
  const NeonCommBar({
    super.key,
    required this.callLabel,
    required this.videoLabel,
    required this.messageLabel,
    required this.onCall,
    required this.onVideo,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCapsule(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
              child: NeonGlassButton(
                  icon: Icons.call_rounded,
                  label: callLabel,
                  color: kNeonBlue,
                  onTap: onCall)),
          const SizedBox(width: 8),
          Expanded(
              child: NeonGlassButton(
                  icon: Icons.videocam_rounded,
                  label: videoLabel,
                  color: kNeonPink,
                  onTap: onVideo)),
          const SizedBox(width: 8),
          Expanded(
              child: NeonGlassButton(
                  icon: Icons.chat_bubble_rounded,
                  label: messageLabel,
                  color: kNeonTeal,
                  onTap: onMessage)),
        ],
      ),
    );
  }
}

/// रद्द गर्ने बटन — रातो नियोन पिल (राइडको बार मुनि)।
class NeonCancelPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const NeonCancelPill({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const rose = Color(0xFFFF4D6D);
    return Center(
      child: SpringTap(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        pressedScale: 0.94,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: rose.withValues(alpha: 0.08),
            border: Border.all(color: rose.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(color: rose.withValues(alpha: 0.2), blurRadius: 12),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.close_rounded, size: 16, color: rose),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: rose,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      letterSpacing: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// ग्रिड पृष्ठभूमि — फ्युचरिस्टिक कार्ड/पेमेन्ट बक्समा (पातलो रेखा + कुना चमक)।
class NeonGridBackground extends StatelessWidget {
  final Color color;
  const NeonGridBackground({super.key, this.color = kNeonTeal});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GridPainter(color)));
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    const step = 22.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        color.withValues(alpha: 0.22),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width, 0), radius: size.width * 0.6));
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

/// धड्किने सफलता चिन्ह — बाहिर फैलिने घेरा सहित ✔ गोला।
class PulsingCheck extends StatefulWidget {
  final double size;
  final Color color;
  const PulsingCheck(
      {super.key, this.size = 84, this.color = const Color(0xFF00E676)});

  @override
  State<PulsingCheck> createState() => _PulsingCheckState();
}

class _PulsingCheckState extends State<PulsingCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.9,
      height: s * 1.9,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _CheckRingsPainter(_c.value, widget.color),
          child: Center(
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  widget.color,
                  widget.color.withValues(alpha: 0.65),
                ]),
                boxShadow: [
                  BoxShadow(
                      color: widget.color.withValues(alpha: 0.6),
                      blurRadius: 26,
                      spreadRadius: 2),
                ],
              ),
              child: Icon(Icons.check_rounded,
                  color: Colors.black, size: s * 0.58),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckRingsPainter extends CustomPainter {
  final double t;
  final Color color;
  _CheckRingsPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      paint
        ..strokeWidth = 2.2 * (1 - p) + 0.4
        ..color = color.withValues(alpha: (1 - p) * 0.6);
      canvas.drawCircle(c, size.width * (0.27 + 0.23 * p) + size.width * 0.0, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckRingsPainter old) => old.t != t;
}

/// स्थिर import-रक्षा: `AppColors` प्रयोग नभए पनि यहाँ राखिएको (theme मा निर्भरता)।
// ignore: unused_element
Color _themeTouch() => AppColors.kmInk;

/// Dark glass card with a thin neon gradient border + soft glow — list rows
/// (workers, bookings, messages, notifications) share this look.
class NeonCard extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  // GlassPanel-compatible: `border` tints the glow; `fill` is ignored
  // (the card is always the dark neon-glass fill).
  final Color? fill;
  final Color? border;
  const NeonCard({
    super.key,
    required this.child,
    this.accent = kNeonViolet,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = 20,
    this.fill,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final accent = border ?? this.accent;
    final card = Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.8),
            kNeonBlue.withValues(alpha: 0.16),
            kNeonPink.withValues(alpha: 0.5),
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 16,
              spreadRadius: -3),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius - 1),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C1118), Color(0xFF070A0F)],
          ),
        ),
        child: child,
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: card,
    );
  }
}

/// Plain-Container version of the neon card look (dark gradient fill, neon
/// outline + glow) for cards that need to clip children (image headers).
BoxDecoration neonDecoration(
    {Color accent = kNeonViolet, double radius = 20}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0C1118), Color(0xFF070A0F)],
    ),
    border: Border.all(color: accent.withValues(alpha: 0.55)),
    boxShadow: [
      BoxShadow(
          color: accent.withValues(alpha: 0.18), blurRadius: 16, spreadRadius: -3),
    ],
  );
}
