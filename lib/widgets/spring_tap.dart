// widgets/spring_tap.dart
// कुनै पनि child लाई touch गर्दा छिटो scale-down + spring-back bounce दिने wrapper।
// nav tab, button, icon — जहाँ पनि "tactile" feel चाहिँदा प्रयोग गर्ने।
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpringTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// थिच्दा घट्ने scale (०.९२ = ८% सानो)।
  final double pressedScale;

  /// tap मा हल्का haptic।
  final bool haptic;

  const SpringTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.92,
    this.haptic = true,
  });

  @override
  State<SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<SpringTap>
    with SingleTickerProviderStateMixin {
  // 1 = rest, 0 = fully pressed। release मा elasticOut ले bounce गर्छ।
  late final AnimationController _c =
      AnimationController(vsync: this, value: 1, duration: Duration.zero);
  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _press() {
    _down = true;
    _c.animateTo(0,
        duration: const Duration(milliseconds: 110), curve: Curves.easeOut);
  }

  void _release({required bool fire}) {
    if (!_down) return;
    _down = false;
    _c.animateTo(1,
        duration: const Duration(milliseconds: 440), curve: Curves.elasticOut);
    if (fire) {
      if (widget.haptic) HapticFeedback.selectionClick();
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null && widget.onLongPress == null
          ? null
          : (_) => _press(),
      onTapUp: (_) => _release(fire: true),
      onTapCancel: () => _release(fire: false),
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(
          scale: lerpDouble(widget.pressedScale, 1.0, _c.value)!,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
