// widgets/success_feedback.dart
// सफलता feedback — haptic + छोटो celebratory chime (asset बिना, runtime मा WAV बन्छ)।
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'wav_tone.dart';
import 'futuristic_ui.dart';

AudioPlayer? _player;
Uint8List? _cachedChime;

/// एकपटक बजाउने — haptic + rising arpeggio (C–E–G–C)।
Future<void> playSuccessFeedback() async {
  try {
    HapticFeedback.heavyImpact();
    Future.delayed(
        const Duration(milliseconds: 130), HapticFeedback.mediumImpact);
    Future.delayed(
        const Duration(milliseconds: 260), HapticFeedback.lightImpact);
  } catch (_) {}

  try {
    _player ??= AudioPlayer();
    _cachedChime ??= _buildChimeWav();
    await _player!.stop();
    await _player!.play(BytesSource(_cachedChime!), volume: 0.8);
  } catch (_) {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }
}

/// भुक्तानी सफलता कार्ड — payment confirm भएपछि दुवैतिर (passenger कै
/// `complete_job_sheet.dart` र rider कै `job_route_screen.dart`) एउटै
/// हेर्दो देखियोस् भनेर साझा widget। haptic+chime सँगै बजाउँछ, झन्डै २
/// सेकेन्ड देखिएर आफैं बन्द हुन्छ (`Future` त्यही बेला पूरा हुन्छ) — caller
/// ले यसलाई `await` गरेर त्यसपछि मात्र home-तिर navigate गर्न सक्छ।
/// `barrierDismissible: false` — tap गरेर हतारमा बन्द गर्न नमिल्ने, ताकि
/// भुक्तानी साँच्चै सफल भएको प्रस्ट रूपमा देखियोस्।
Future<void> showPaymentSuccessCard(
  BuildContext context, {
  required bool isRide,
}) {
  unawaited(playSuccessFeedback());
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.85 + 0.15 * curved.value.clamp(0.0, 1.5),
          child: _PaymentSuccessCard(isRide: isRide),
        ),
      );
    },
  );
}

class _PaymentSuccessCard extends StatefulWidget {
  final bool isRide;
  const _PaymentSuccessCard({required this.isRide});

  @override
  State<_PaymentSuccessCard> createState() => _PaymentSuccessCardState();
}

class _PaymentSuccessCardState extends State<_PaymentSuccessCard> {
  @override
  void initState() {
    super.initState();
    // झन्डै २ सेकेन्ड देखिएपछि आफैं बन्द — प्रयोगकर्ताले केही नथिची पनि।
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1F18), Color(0xFF05080F)],
            ),
            border: Border.all(
                color: const Color(0xFF00E676).withValues(alpha: 0.7),
                width: 1.4),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 36,
                  spreadRadius: 2),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              children: [
                const Positioned.fill(
                    child: NeonGridBackground(color: Color(0xFF00E676))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PulsingCheck(size: 76),
                      const SizedBox(height: 4),
                      Text(S.paymentSuccessTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              letterSpacing: 0.3,
                              decoration: TextDecoration.none)),
                      const SizedBox(height: 8),
                      Text(
                          widget.isRide
                              ? S.paymentSuccessRideBody
                              : S.paymentSuccessJobBody,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                              decoration: TextDecoration.none)),
                    ],
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

Uint8List _buildChimeWav() {
  const sampleRate = 22050;
  const notes = <double>[523.25, 659.25, 783.99, 1046.50]; // C5 E5 G5 C6
  const noteDur = 0.12; // s per note
  const totalDur = 0.62;
  final n = (sampleRate * totalDur).round();
  final samples = Int16List(n);

  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var idx = (t / noteDur).floor();
    if (idx > notes.length - 1) idx = notes.length - 1;
    final localT = t - idx * noteDur;
    // छिटो attack, exponential decay
    final env = (1 - exp(-localT * 60)) * exp(-localT * 7);
    final tail = (1 - (t / totalDur)).clamp(0.0, 1.0);
    var s = sin(2 * pi * notes[idx] * t);
    // हल्का overtone — richer tick
    s += 0.3 * sin(2 * pi * notes[idx] * 2 * t);
    final v = s * env * tail * 0.32;
    samples[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  return wrapPcm16Wav(samples, sampleRate);
}
