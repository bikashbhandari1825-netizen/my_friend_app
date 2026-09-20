// widgets/counter_offer_card.dart
//
// ग्राहकले कामदारको मूल्य काउन्टर गर्दा (उदाहरण: Rs 600 → Rs 300) कामदारको
// "कामका अनुरोध" स्क्रिनमा तुरुन्तै देखिने high-impact, animated alert card।
//   • slide + fade + scale एन्ट्रान्स एनिमेसन
//   • नयाँ मूल्यमा लगातार pulse/glow
//   • Instagram gradient (violet → pink → orange) + frosted-glass भित्री प्यानल
//   • पुरानो मूल्य काटिएको + नयाँ मूल्य ठूलो/हाइलाइट
//   • दुई ठूला बटन: Accept  |  Decline / Counter back
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class CounterOfferCard extends StatefulWidget {
  /// माथि देखिने सानो शीर्षक — सामान्यतया "ग्राहक · सेवा"।
  final String heading;

  /// कामदारले अघि प्रस्ताव गरेको (वा टेबलमा रहेको) मूल्य — काटिएर देखिन्छ।
  final num previousPrice;

  /// ग्राहकले अहिले पठाएको नयाँ काउन्टर मूल्य — हाइलाइट भएर देखिन्छ।
  final num newPrice;

  /// नयाँ मूल्यमै स्वीकार्ने।
  final Future<void> Function() onAccept;

  /// अस्वीकार गर्ने वा आफ्नो नयाँ मूल्य फिर्ता पठाउने (parent ले dialog देखाउँछ)।
  final Future<void> Function() onCounterBack;

  /// शीर्षक line — नदिए worker-side default ("ग्राहकले नयाँ मूल्य पठाउनुभयो")।
  final String? title;

  /// सहायक line — नदिए worker-side default।
  final String? body;

  /// Accept बटनको text — नदिए "Accept"।
  final String? acceptLabel;

  /// Decline/Counter बटनको text — नदिए "Decline / Counter back"।
  final String? counterLabel;

  const CounterOfferCard({
    super.key,
    required this.heading,
    required this.previousPrice,
    required this.newPrice,
    required this.onAccept,
    required this.onCounterBack,
    this.title,
    this.body,
    this.acceptLabel,
    this.counterLabel,
  });

  @override
  State<CounterOfferCard> createState() => _CounterOfferCardState();
}

class _CounterOfferCardState extends State<CounterOfferCard>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);

  late final Animation<double> _fade =
      CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.16),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutBack));
  late final Animation<double> _scaleIn = Tween<double>(begin: 0.94, end: 1)
      .animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutBack));

  bool _busyAccept = false;
  bool _busyCounter = false;

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String _money(num v) =>
      'Rs ${v % 1 == 0 ? v.toInt().toString() : v.toString()}';

  Future<void> _run(bool accept) async {
    if (_busyAccept || _busyCounter) return;
    setState(() => accept ? _busyAccept = true : _busyCounter = true);
    try {
      await (accept ? widget.onAccept() : widget.onCounterBack());
    } finally {
      if (mounted) {
        setState(() => accept ? _busyAccept = false : _busyCounter = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scaleIn,
          child: _cardBody(),
        ),
      ),
    );
  }

  Widget _cardBody() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_pulse.value); // 0..1
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF9B3FC4), // soft violet
                Color(0xFFE84C88), // soft pink
                Color(0xFFF8873F), // soft orange
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.igPink.withValues(alpha: 0.30 + 0.22 * t),
                blurRadius: 26 + 12 * t,
                spreadRadius: 1,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(t),
                    const SizedBox(height: 14),
                    _priceRow(t),
                    const SizedBox(height: 18),
                    _actions(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(double t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18 + 0.12 * t),
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title ?? S.customerCounteredTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.body ?? S.customerCounteredBody,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _priceRow(double t) {
    return Row(
      children: [
        // पुरानो मूल्य — काटिएको
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.previousPriceLabel,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _money(widget.previousPrice),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.lineThrough,
                decorationColor: Colors.white.withValues(alpha: 0.72),
                decorationThickness: 2,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Icon(Icons.arrow_forward_rounded,
            color: Colors.white.withValues(alpha: 0.9), size: 22),
        const SizedBox(width: 12),
        // नयाँ मूल्य — pulsing glow pill मा हाइलाइट
        Expanded(
          child: Transform.scale(
            scale: 1 + 0.035 * t,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16 + 0.10 * t),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55 + 0.25 * t),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.18 * t),
                    blurRadius: 18 * t,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    S.theirOfferLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _money(widget.newPrice),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: _GlassButton(
            label: widget.acceptLabel ?? S.accept,
            icon: Icons.check_rounded,
            filled: true,
            busy: _busyAccept,
            onTap: () => _run(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _GlassButton(
            label: widget.counterLabel ?? S.declineOrCounter,
            icon: Icons.reply_rounded,
            filled: false,
            busy: _busyCounter,
            onTap: () => _run(false),
          ),
        ),
      ],
    );
  }
}

/// Alert भित्रको pill बटन — `filled` भए सेतो पृष्ठभूमि (primary Accept),
/// नत्र frosted outline (secondary)।
class _GlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  const _GlassButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.igPink : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: busy ? null : onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: filled
                  ? null
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.7), width: 1.5),
            ),
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: fg),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
