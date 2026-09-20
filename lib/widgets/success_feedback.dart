// widgets/success_feedback.dart
// सफलता feedback — haptic + छोटो celebratory chime (asset बिना, runtime मा WAV बन्छ)।
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'wav_tone.dart';

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
