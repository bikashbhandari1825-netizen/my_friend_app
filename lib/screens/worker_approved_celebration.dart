// screens/worker_approved_celebration.dart
// कामदार स्वीकृत हुँदाको full-screen celebration — pulse rings + elastic ✓ +
// radial confetti + haptic/chime। ~2.4s पछि आफै dashboard (gate) मा जान्छ।
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/success_feedback.dart';
import 'main_container.dart';

class WorkerApprovedCelebration extends StatefulWidget {
  const WorkerApprovedCelebration({super.key});

  @override
  State<WorkerApprovedCelebration> createState() =>
      _WorkerApprovedCelebrationState();
}

class _WorkerApprovedCelebrationState extends State<WorkerApprovedCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  final _rnd = Random(7);
  bool _navigated = false;

  late final Animation<double> _circle = CurvedAnimation(
      parent: _c, curve: const Interval(0.10, 0.55, curve: Curves.elasticOut));
  late final Animation<double> _check = CurvedAnimation(
      parent: _c, curve: const Interval(0.34, 0.70, curve: Curves.easeOutBack));
  late final Animation<double> _text = CurvedAnimation(
      parent: _c, curve: const Interval(0.55, 0.9, curve: Curves.easeOut));
  late final Animation<double> _burst = CurvedAnimation(
      parent: _c, curve: const Interval(0.30, 1.0, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    playSuccessFeedback();
    _c.forward();
    Future.delayed(const Duration(milliseconds: 2400), _goDashboard);
  }

  void _goDashboard() {
    if (_navigated || !mounted) return;
    _navigated = true;
    // नोट: यो screen app.dart को gate ले सिधै root content को रूपमा नै
    // देखाउँछ (कुनै push बाट होइन) र यहाँको transition कुनै Firestore/auth
    // stream event ले होइन, बरु यही timer (Future.delayed) ले चलाउँछ —
    // त्यसैले `popUntil` ले काम गर्दैन (pop गर्ने केही छैन)। तर नयाँ
    // `KaamMitraApp()` (नयाँ MaterialApp) पनि कहिल्यै नबनाउने — त्यसले root
    // कै `rootNavigatorKey` सँग टकराएर element-lifecycle assertion (red/
    // black screen crash) ल्याउँथ्यो। `MainContainer` भने सादा widget हो
    // (आफ्नै MaterialApp/navigatorKey छैन), त्यसैले सुरक्षित।
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainContainer()),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confetti = List.generate(14, (i) {
      final ang = (i / 14) * 2 * pi + _rnd.nextDouble();
      final dist = 90 + _rnd.nextDouble() * 90;
      final color = [
        AppColors.igYellow,
        AppColors.success,
        Colors.white,
        AppColors.igPink,
      ][i % 4];
      return (ang, dist, color, 4.0 + _rnd.nextDouble() * 5);
    });

    return Scaffold(
      body: GestureDetector(
        onTap: _goDashboard, // टेप गरे तुरुन्तै अगाडि
        child: Container(
          decoration: const BoxDecoration(gradient: AppColors.igGradient),
          child: SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // pulse rings
                            for (final d in const [0.0, 0.22, 0.44]) _ring(d),
                            // radial confetti
                            for (final (ang, dist, color, sz) in confetti)
                              Transform.translate(
                                offset: Offset(cos(ang) * dist * _burst.value,
                                    sin(ang) * dist * _burst.value),
                                child: Opacity(
                                  opacity: (1 - _burst.value).clamp(0.0, 1.0),
                                  child: Container(
                                    width: sz,
                                    height: sz,
                                    decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2)),
                                  ),
                                ),
                              ),
                            // white circle
                            Transform.scale(
                              scale: _circle.value.clamp(0.0, 1.2),
                              child: Container(
                                width: 128,
                                height: 128,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            Colors.white.withValues(alpha: 0.5),
                                        blurRadius: 40,
                                        spreadRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                            // checkmark
                            Transform.scale(
                              scale: _check.value.clamp(0.0, 1.0),
                              child: const Icon(Icons.check_rounded,
                                  size: 84, color: AppColors.success),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Opacity(
                        opacity: _text.value.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - _text.value)),
                          child: Column(
                            children: [
                              Text(S.approvedCelebrateTitle,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black38,
                                            blurRadius: 12)
                                      ])),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 40),
                                child: Text(S.approvedCelebrateBody,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        fontSize: 13.5,
                                        height: 1.4)),
                              ),
                              const SizedBox(height: 18),
                              Text(S.openingDashboard,
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double delay) {
    final p = ((_burst.value - delay) / (1 - delay)).clamp(0.0, 1.0);
    return Opacity(
      opacity: (1 - p) * 0.6,
      child: Container(
        width: 100 + p * 150,
        height: 100 + p * 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
        ),
      ),
    );
  }
}
