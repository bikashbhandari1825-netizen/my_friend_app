// widgets/app_ui.dart
//
// inDrive-style साझा widget हरू। हरेक screen मा दोहोर्‍याएर लेख्नु नपरोस् भनेर।
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';

/// छोटो Instagram-gradient action pill — icon + bold white text + glow shadow।
/// थिच्दा elevation घट्छ + हल्का scale-down bounce + ripple + haptic।
class GradientActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool expand;

  const GradientActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.expand = false,
  });

  @override
  State<GradientActionButton> createState() => _GradientActionButtonState();
}

class _GradientActionButtonState extends State<GradientActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final btn = AnimatedScale(
      scale: _pressed ? 0.95 : 1,
      duration: Duration(milliseconds: _pressed ? 90 : 320),
      curve: _pressed ? Curves.easeOut : Curves.elasticOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.buttonGradient,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.igPink.withValues(alpha: _pressed ? 0.22 : 0.42),
              blurRadius: _pressed ? 8 : 16,
              offset: Offset(0, _pressed ? 2 : 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: widget.onPressed,
            onHighlightChanged: (v) {
              setState(() => _pressed = v);
              if (v) HapticFeedback.selectionClick();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize:
                    widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 17, color: Colors.white),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Full-width pill बटन — Instagram-style gradient। `loading` दिँदा spinner।
/// थिच्दा हल्का scale-down (tactile feel) + InkWell ripple।
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final onPressed = widget.onPressed;
    final icon = widget.icon;
    final loading = widget.loading;
    final expand = widget.expand;
    final disabled = loading || onPressed == null;
    final child = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          );

    final button = Opacity(
      opacity: disabled ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.buttonGradient,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: AppColors.igPink.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: disabled ? null : onPressed,
            onHighlightChanged:
                disabled ? null : (v) => setState(() => _pressed = v),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: child,
            ),
          ),
        ),
      ),
    );

    final scaled = AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: Duration(milliseconds: _pressed ? 90 : 340),
      curve: _pressed ? Curves.easeOut : Curves.elasticOut,
      child: button,
    );

    return expand ? SizedBox(width: double.infinity, child: scaled) : scaled;
  }
}

/// Instagram gradient AppBar — form screen हरूको header मा।
AppBar gradientAppBar(String title, {List<Widget>? actions, Widget? leading}) =>
    AppBar(
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800)),
      iconTheme: const IconThemeData(color: Colors.white),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: leading,
      actions: actions,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.buttonGradient),
      ),
    );

/// Instagram gradient background — auth/onboarding screen हरूमा `child` वरिपरि।
class AppGradientBackground extends StatelessWidget {
  final Widget child;
  final bool glows;
  const AppGradientBackground(
      {super.key, required this.child, this.glows = true});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.instaGradient),
          child: SizedBox.expand(),
        ),
        if (glows) ...[
          _blob(const Alignment(-1.1, -0.9), const Color(0xFFFF4FD8), 320),
          _blob(const Alignment(1.2, -0.3), const Color(0xFF7C4DFF), 300),
          _blob(const Alignment(0.9, 1.15), const Color(0xFFFFB300), 340),
        ],
        child,
      ],
    );
  }

  Widget _blob(Alignment a, Color c, double size) => IgnorePointer(
        child: Align(
          alignment: a,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                c.withValues(alpha: 0.5),
                c.withValues(alpha: 0.0),
              ]),
            ),
          ),
        ),
      );
}

/// Outline pill बटन (secondary action)। थिच्दा हल्का scale-down।
class SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final Color? color;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.color,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final onPressed = widget.onPressed;
    final icon = widget.icon;
    final expand = widget.expand;
    final color = widget.color;
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(
            color: color ?? Theme.of(context).dividerColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

    final scaled = Listener(
      onPointerDown:
          onPressed == null ? null : (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 340),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: button,
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: scaled) : scaled;
  }
}

/// Rounded surface card, वैकल्पिक tap सहित।
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color ?? theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: theme.dividerColor),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Section को शीर्षक + वैकल्पिक "See all" जस्तो trailing action।
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!,
                style: const TextStyle(
                    color: AppColors.lime,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
      ],
    );
  }
}

/// सानो status/tag pill।
class Pill extends StatelessWidget {
  final String text;
  final Color? bg;
  final Color? fg;
  final IconData? icon;

  const Pill(this.text, {super.key, this.bg, this.fg, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = bg ?? theme.colorScheme.surfaceContainerHighest;
    final foreground = fg ?? theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  color: foreground,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// GPS स्थान लिने field — capture भएको lat/lng `onChanged` बाट फर्काउँछ।
class LocationField extends StatefulWidget {
  final void Function(double? lat, double? lng) onChanged;
  const LocationField({super.key, required this.onChanged});

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  double? _lat;
  double? _lng;
  bool _loading = false;
  String? _msg;

  Future<void> _capture() async {
    setState(() {
      _loading = true;
      _msg = null;
    });
    final r = await getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _lat = r.lat;
        _lng = r.lng;
        _msg = null;
      } else {
        _msg = S.locationDeniedShort;
      }
    });
    widget.onChanged(_lat, _lng);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = _lat != null && _lng != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: has ? AppColors.lime : theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            has ? Icons.check_circle_rounded : Icons.my_location_rounded,
            color: has ? AppColors.lime : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _loading
                  ? S.gettingLocation
                  : has
                      ? '${S.locationCaptured}  (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})'
                      : _msg ?? S.locationSection,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: _loading ? null : _capture,
            child: Text(has ? S.retry : S.useMyLocation),
          ),
        ],
      ),
    );
  }
}

/// गोलाकार lime-tinted icon container — list को leading मा प्रयोग हुन्छ।
class LimeIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool solid;

  const LimeIconBadge(this.icon,
      {super.key, this.size = 44, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? AppColors.lime : AppColors.lime.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon,
          color: solid ? AppColors.onLime : AppColors.lime, size: size * 0.5),
    );
  }
}
