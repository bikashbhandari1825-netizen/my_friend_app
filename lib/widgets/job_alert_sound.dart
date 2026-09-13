// widgets/job_alert_sound.dart
// नयाँ काम/अफर आउनेबित्तिकै बज्ने छोटो "ting-ting" अलर्ट — asset बिना, runtime मा
// PCM WAV बनाइन्छ (success_feedback.dart कै चिम synth pattern, फरक note/ताल)।
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'wav_tone.dart';

AudioPlayer? _alertPlayer;
Uint8List? _cachedTing;

/// नयाँ broadcasting job देखिनेबित्तिकै बजाउने — haptic + दुई उच्च-pitch "ting"।
Future<void> playNewJobAlert() async {
  try {
    HapticFeedback.mediumImpact();
  } catch (_) {}

  try {
    _alertPlayer ??= AudioPlayer();
    _cachedTing ??= _buildTingWav();
    await _alertPlayer!.stop();
    await _alertPlayer!.play(BytesSource(_cachedTing!), volume: 0.9);
  } catch (_) {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }
}

/// नयाँ काम-अफर र counter-offer (मूल्य प्रस्ताव) दुवैका लागि उही "ting-ting"
/// अलर्ट — negotiation कहिले पनि रोकिँदैन भन्ने संकेत दिन employer/worker
/// दुवैतिर हरेक counter-offer round मा यही बज्छ (MainContainer बाट प्रयोग)।
Future<void> playCounterOfferAlert() => playNewJobAlert();

Uint8List _buildTingWav() {
  const sampleRate = 22050;
  const note = 1567.98; // G6
  const noteDur = 0.15;
  const gap = 0.09;
  const totalDur = noteDur * 2 + gap;
  final n = (sampleRate * totalDur).round();
  final samples = Int16List(n);
  final starts = [0.0, noteDur + gap];

  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var v = 0.0;
    for (final start in starts) {
      final localT = t - start;
      if (localT >= 0 && localT < noteDur) {
        final env = (1 - exp(-localT * 90)) * exp(-localT * 14);
        var s = sin(2 * pi * note * localT);
        s += 0.25 * sin(2 * pi * note * 2 * localT);
        v += s * env * 0.4;
      }
    }
    samples[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  return wrapPcm16Wav(samples, sampleRate);
}
