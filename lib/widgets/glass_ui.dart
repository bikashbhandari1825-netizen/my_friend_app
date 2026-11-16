// widgets/glass_ui.dart
//
// "KaamMitra 2050" — dark glassmorphic aurora redesign कै साझा widget हरू।
// यी widget हरूले केवल VISUAL/UI मात्र दिन्छन् — कुनै पनि Firestore/business
// logic यहाँ छैन, प्रयोग गर्ने screen ले आफ्नो सबै state/logic उस्तै राख्छ।
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// true हुँदा blur छोडिन्छ (केवल translucent fill) — चलिरहेको नक्सा माथि
/// प्रत्येक frame BackdropFilter blur गर्न कमजोर GPU मा धेरै महँगो हुन्छ।
/// Android मा blur पूर्वनिर्धारित बन्द — 90/120Hz मा हरेक frame blur गर्दा
/// (विशेष गरी नक्सा माथि) frame-drop/lag आउँछ; translucent fill ले उस्तै देखिन्छ।
final bool glassBlurDefaultDisabled =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool glassBlurDisabled = glassBlurDefaultDisabled;

Widget glassBackdrop({required double sigma, required Widget child}) =>
    glassBlurDisabled
        ? child
        : BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: child);

/// एउटा पृष्ठभूमि "orb" (radial-gradient glow) को स्पेक — कुन कुनामा,
/// कति ठूलो, कुन रङ।
class KmOrb {
  final Alignment corner; // topLeft / topRight / bottomLeft / bottomRight
  final Color color;
  final double size;
  const KmOrb(this.corner, this.color, {this.size = 460});
}

/// गहिरो near-black पृष्ठभूमि + कुनाबाट पोखिएका glow "orb" हरू + हल्का
/// grid-line texture — नयाँ डिजाइनका सबै screen को साझा base।
class AuroraBackground extends StatelessWidget {
  final Widget child;
  final List<KmOrb> orbs;
  final bool grid;

  const AuroraBackground({
    super.key,
    required this.child,
    this.orbs = const [
      KmOrb(Alignment.topRight, AppColors.kmPurple),
      KmOrb(Alignment.bottomLeft, AppColors.kmOrangeDeep),
    ],
    this.grid = true,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.kmVoid),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final o in orbs) _orb(o),
          if (grid)
            const Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _GridPainter())),
            ),
          child,
        ],
      ),
    );
  }

  Widget _orb(KmOrb o) {
    final inset = -o.size * 0.37;
    return Positioned(
      left: o.corner.x <= 0 ? inset : null,
      right: o.corner.x > 0 ? inset : null,
      top: o.corner.y <= 0 ? inset : null,
      bottom: o.corner.y > 0 ? inset : null,
      child: IgnorePointer(
        child: Container(
          width: o.size,
          height: o.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [o.color.withValues(alpha: 0.4), o.color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 30.0;
    final fadeH = size.height * 0.62;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, fadeH), paint);
    }
    for (double y = 0; y < fadeH; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// पातलो frosted-glass panel (.gl) — card/list background मा।
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? fill;
  final Color? border;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
    this.fill,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: glassBackdrop(
        sigma: 20,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill ?? AppColors.kmGlassFill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border ?? AppColors.kmGlassBorder),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// गाढा frosted-glass पट्टी (.g2) — floating bottom-nav/bottom-sheet हरूमा।
class GlassPanel2 extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassPanel2({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 26,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: glassBackdrop(
        sigma: 26,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.kmGlass2Fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.kmGlass2Border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// साना वर्गाकार-गोलो frosted icon बटन (.bk) — Back/Menu/Notification जस्ता
/// app-bar action हरूमा। पहिले यहाँ सेतो-tint (`Colors.white` @ 7% मात्र)
/// भएकोले नक्सा/उज्यालो पृष्ठभूमिमाथि झन्डै अदृश्य देखिन्थ्यो — अब
/// `kmGlass2Fill` (गाढा, बढी opaque डिस्क) प्रयोग गरिन्छ ताकि icon
/// जुनसुकै पृष्ठभूमि (नक्सा, सेतो card, वा गाढा screen) माथि पनि सधैँ
/// प्रस्ट देखियोस्।
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? iconColor;
  final Widget? badge;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.iconColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Stack(
      clipBehavior: Clip.none,
      children: [
        // `BackdropFilter` (blur) महँगो हो — यो बटन प्रायः नक्सा/animation
        // माथि tair-रहेको हुन्छ, `RepaintBoundary` ले यसको blur/paint लाई
        // छेउछाउका अरू ऐनिमेसन (pin-lift, sheet-drag, camera-pan) कै
        // कारणले हरेक frame फेरि दोहोर्‍याउनबाट जोगाउँछ।
        RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: glassBackdrop(
        sigma: 16,
        child: Material(
                color: AppColors.kmGlass2Fill,
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.kmGlass2Border),
                    ),
                    child: Icon(icon,
                        size: size * 0.5,
                        color: iconColor ?? AppColors.kmText),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (badge != null) Positioned(right: -6, top: -6, child: badge!),
      ],
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Full-width gradient CTA pill (.cta/.no) — नयाँ डिजाइनको primary बटन।
class KmCtaButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final double height;

  const KmCtaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  });

  @override
  State<KmCtaButton> createState() => _KmCtaButtonState();
}

class _KmCtaButtonState extends State<KmCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onPressed == null;
    final child = widget.loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.kmInk),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 19, color: AppColors.kmInk),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.kmInk)),
              ),
            ],
          );

    final button = Opacity(
      opacity: disabled ? 0.55 : 1,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 260),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.kmCtaGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: disabled ? null : widget.onPressed,
              onHighlightChanged: disabled
                  ? null
                  : (v) => setState(() => _pressed = v),
              child: Container(
                height: widget.height,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Section को सानो uppercase-ish muted शीर्षक (.sec)।
class KmSectionLabel extends StatelessWidget {
  final String text;
  const KmSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.kmLilac,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Settings/Profile/Help जस्ता स्क्रिनको एउटा glass row — gradient icon badge
/// + title (+ subtitle) + chevron। (.st)
class KmListTile extends StatelessWidget {
  final IconData icon;
  final Gradient iconBg;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? titleColor;
  final Color? borderColor;
  final Color? fillColor;

  const KmListTile({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.titleColor,
    this.borderColor,
    this.fillColor,
  });

  static const List<Gradient> gradients = [
    LinearGradient(colors: [AppColors.kmLilac, AppColors.kmPurple]),
    LinearGradient(colors: [AppColors.kmRose, AppColors.kmPink]),
    LinearGradient(colors: [AppColors.kmOrange, AppColors.kmOrangeDeep]),
    LinearGradient(colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
    LinearGradient(colors: [AppColors.kmAmber, AppColors.kmOrange]),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: glassBackdrop(
        sigma: 18,
        child: Material(
          color: fillColor ?? Colors.white.withValues(alpha: 0.07),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: subtitle == null ? 64 : 68,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: borderColor ?? AppColors.kmGlassBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: iconBg,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(icon, color: AppColors.kmInk, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: titleColor ?? AppColors.kmText)),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.kmMuted)),
                          ),
                      ],
                    ),
                  ),
                  trailing ??
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.kmMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// साना status/tag pill — glass tint background + coloured border/text।
class KmTag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const KmTag(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// फारम/input field हरूको साझा dark-glass style — नयाँ डिजाइनका सबै
/// TextField/TextFormField ले यही प्रयोग गर्छन् (registration/edit forms)।
InputDecoration kmInputDecoration(String label, {String? hint, Widget? suffixIcon}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
    labelStyle: const TextStyle(color: AppColors.kmMuted),
    hintStyle: const TextStyle(color: AppColors.kmMuted),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: Colors.white, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.kmRose),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.kmRose, width: 1.4),
    ),
  );
}

/// Dark-glass modal dialog — पुरानो default (सेतो/कालो ठोस) `AlertDialog` को
/// सट्टा एपभरि यही प्रयोग हुन्छ (Legal Documents, Logout confirm, Delete
/// account, वा कुनै पनि "छान्नुहोस्/पुष्टि गर्नुहोस्" पपअप)। `actions` मा
/// [KmDialogAction] प्रयोग गर्नुहोस्।
Future<T?> showKmDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const [],
  IconData? icon,
  Gradient? iconBg,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: glassBackdrop(
        sigma: 26,
        child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
            decoration: BoxDecoration(
              color: AppColors.kmSurface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.kmGlassBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 30,
                    offset: const Offset(0, 14)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: iconBg ?? AppColors.kmCtaGradient,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(icon, color: AppColors.kmInk, size: 22),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                if (message != null) ...[
                  const SizedBox(height: 10),
                  Text(message,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 14, height: 1.4)),
                ],
                if (content != null) ...[
                  const SizedBox(height: 12),
                  content,
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Strict Document Cross-Matching — KYC मा टाइप गरेको नाम/जन्ममिति/कागजात-
/// नम्बर अपलोड गरेको ID फोटोसँग (OCR-तुलना, `OcrMatchService`) मेल नखाँदा
/// देखाउने साझा alert — पहिले driver_registration_flow.dart भित्रैको निजी
/// `_showMismatchAlert` (license-category/date जाँचका लागि) थियो, अब worker/
/// hotel flow ले पनि उही एउटा ठाउँबाट प्रयोग गर्न यहाँ साझा गरिएको।
Future<void> showMismatchAlert(BuildContext context, String message) {
  return showKmDialog<void>(
    context: context,
    title: 'कागजात मेल खाएन',
    message: message,
    icon: Icons.error_outline_rounded,
    iconBg:
        const LinearGradient(colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
    actions: [
      KmDialogAction(
        label: 'ठीक छ',
        filled: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}

/// [showKmDialog] भित्रको action बटन — Cancel (मुटेड टेक्स्ट) वा
/// Confirm/Delete (रंगीन, वैकल्पिक gradient/solid fill)।
class KmDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool filled;
  const KmDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!filled) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: destructive ? AppColors.kmRose : AppColors.kmMuted,
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: destructive
            ? const LinearGradient(
                colors: [AppColors.kmRose, AppColors.kmPinkDeep])
            : AppColors.kmCtaGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.kmInk, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Dark-glass bottom sheet — पुरानो default (सेतो) `showModalBottomSheet`
/// को सट्टा एपभरि यही प्रयोग हुन्छ (Appearance/Language/Vehicle-type जस्ता
/// छान्ने पपअप)। भित्र [KmSheetOption] row हरू राख्नुहोस्।
Future<T?> showKmSheet<T>({
  required BuildContext context,
  required List<Widget> children,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: glassBackdrop(
        sigma: 26,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.kmSurface.withValues(alpha: 0.94),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
                top: BorderSide(color: AppColors.kmGlassBorder),
                left: BorderSide(color: AppColors.kmGlassBorder),
                right: BorderSide(color: AppColors.kmGlassBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  if (title != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
                      child: Text(title,
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// [showKmSheet] भित्रको एउटा छान्ने row — icon + label (+ subtitle) +
/// छानिएकोमा tick।
class KmSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;
  const KmSheetOption({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 21,
                  color: selected
                      ? AppColors.kmText
                      : (iconColor ?? AppColors.kmMuted)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: selected
                                ? AppColors.kmText
                                : AppColors.kmText.withValues(alpha: 0.85),
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            style: const TextStyle(
                                color: AppColors.kmMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded,
                    color: AppColors.kmTeal, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen header row — GlassIconButton(back) + title, नयाँ डिजाइनका सबै
/// sub-screen मा उस्तै ढाँचामा।
class KmScreenHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  // बटम-नेभिगेसन tab root screen हरू (जस्तै Profile) कुनै Navigator route
  // push नगरी सिधै `IndexedStack` मा बस्छन् — त्यहाँ back arrow ले गर्ने
  // default `Navigator.maybePop()` ले सबैभन्दा नजिकको ancestor Navigator
  // (app-व्यापी root) लाई नै pop गरिदिन सक्छ, जसले login flow मा फर्काउन
  // सक्छ। त्यस्ता root tab screen हरूमा `showBack: false` पास गर्नुहोस्।
  final bool showBack;

  const KmScreenHeader({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack) ...[
          GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontSize: 21,
                  fontWeight: FontWeight.w700)),
        ),
        if (actions != null) ...actions!,
      ],
    );
  }
}
