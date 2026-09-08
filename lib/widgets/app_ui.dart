// widgets/app_ui.dart
//
// inDrive-style साझा widget हरू। हरेक screen मा दोहोर्‍याएर लेख्नु नपरोस् भनेर।
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';

/// Full-width pill बटन (lime)। `loading` दिँदा spinner देखाउँछ।
class PrimaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.onLime),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ],
          );

    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outline pill बटन (secondary action)।
class SecondaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: color ?? Theme.of(context).dividerColor, width: 1.5),
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
    return expand ? SizedBox(width: double.infinity, child: button) : button;
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
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
        border: Border.all(
            color: has ? AppColors.lime : theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            has ? Icons.check_circle_rounded : Icons.my_location_rounded,
            color:
                has ? AppColors.lime : theme.colorScheme.onSurfaceVariant,
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

  const LimeIconBadge(this.icon, {super.key, this.size = 44, this.solid = false});

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
