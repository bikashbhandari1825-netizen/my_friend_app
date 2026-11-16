// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// widgets/skeleton.dart
// Spinner को सट्टा skeleton loading — लोड हुँदै गरेको पृष्ठको आकार (avatar +
// रेखा + कार्ड) मधुरो ढाँचामा देखिन्छ, र एउटा चम्किलो पाटी बायाँबाट दायाँ
// सर्छ (shimmer reads left to right)। कुनै बाहिरी package चाहिँदैन।
import 'package:flutter/material.dart';

const Color _kBase = Color(0xFF121821);
const Color _kHighlight = Color(0xFF2B3A47);

class _SlideGradient extends GradientTransform {
  final double percent;
  const _SlideGradient(this.percent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * percent, 0, 0);
}

/// [child] भित्र जति सेतो (opaque) आकृति छन्, तिनमाथि मात्र shimmer चल्छ।
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
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
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          colors: const [_kBase, _kHighlight, _kBase],
          stops: const [0.25, 0.5, 0.75],
          transform: _SlideGradient(-1 + 2 * _c.value),
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

/// एउटा सेतो आकृति (Shimmer भित्र मात्र प्रयोग गर्ने)।
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// पूरा-स्क्रिन सूची loading — हरेक row: गोलो avatar + दुई रेखा (+ ऐच्छिक ठूलो
/// ब्लक)। `StreamBuilder` को waiting अवस्थामा `CircularProgressIndicator` कै
/// ठाउँमा राख्ने।
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final bool block;
  final EdgeInsetsGeometry padding;
  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.block = false,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 24),
  });

  Widget _row() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        color: Colors.white.withValues(alpha: 0.02),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox(height: 52, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 150, height: 14),
                    SizedBox(height: 9),
                    SkeletonBox(width: 90, height: 10),
                  ],
                ),
              ),
            ],
          ),
          if (block) ...[
            const SizedBox(height: 14),
            const SkeletonBox(height: 90, radius: 14),
            const SizedBox(height: 12),
            const SkeletonBox(height: 10),
            const SizedBox(height: 8),
            const SkeletonBox(width: 200, height: 10),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: padding,
        // उचाइ सीमित नभएको अभिभावक (Column/Padding) भित्र पनि सुरक्षित।
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => _row(),
      ),
    );
  }
}
