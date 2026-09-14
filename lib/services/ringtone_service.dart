// services/ringtone_service.dart
// कल गर्दा (outgoing ring-back) र कल आउँदा (incoming ring) बज्ने दुई छुट्टै
// लुप हुने tone — widgets/wav_tone.dart कै synth-WAV pattern (asset बिना runtime
// मा PCM बनाउने) पछ्याएर, job_alert_sound.dart सँग सुसंगत। एकपटकमा एउटै मात्र
// बज्छ — नयाँ play() ले अघिल्लो आफै रोक्छ।
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../widgets/wav_tone.dart';

class _Seg {
  final double freqHz; // 0 = चुप (silence)
  final double durationSec;
  const _Seg(this.freqHz, this.durationSec);
}

class RingtoneService {
  RingtoneService._();

  static AudioPlayer? _player;
  static Uint8List? _outgoingWav;
  static Uint8List? _incomingWav;
  static String? _playing; // 'out' | 'in' | null

  /// Caller ले पर्खिरहेको बेला बज्ने — साँचो टेलिफोन ring-back जस्तै
  /// (१ सेकेन्ड tone, ३ सेकेन्ड चुप), लुप हुँदा दोहोरिन्छ।
  static Future<void> playOutgoing() => _play('out', () => _outgoingWav ??= _buildWav(
        const [_Seg(425, 1.0), _Seg(0, 3.0)],
      ));

  /// Callee ले कल आउँदा बज्ने — छिटो double-beep, अलि चर्को।
  static Future<void> playIncoming() => _play('in', () => _incomingWav ??= _buildWav(
        const [
          _Seg(950, 0.35),
          _Seg(0, 0.15),
          _Seg(950, 0.35),
          _Seg(0, 1.2),
        ],
      ));

  static Future<void> _play(String kind, Uint8List Function() build) async {
    if (_playing == kind) return; // पहिल्यै यही बजिरहेको छ
    try {
      final wav = build();
      _player ??= AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.stop();
      _playing = kind;
      await _player!.play(BytesSource(wav), volume: kind == 'in' ? 1.0 : 0.65);
    } catch (_) {
      // Ringtone मात्र UX polish हो — बज्न सकेन भने पनि कल आफैं चलिरहन्छ।
    }
  }

  static Future<void> stop() async {
    if (_playing == null) return;
    _playing = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  static Uint8List _buildWav(List<_Seg> segments) {
    const sampleRate = 8000;
    final total =
        segments.fold<int>(0, (a, s) => a + (sampleRate * s.durationSec).round());
    final out = Int16List(total);
    var idx = 0;
    for (final seg in segments) {
      final n = (sampleRate * seg.durationSec).round();
      final fadeSamples = (sampleRate * 0.01).round(); // १०ms fade — click/pop हटाउन
      for (var i = 0; i < n; i++) {
        if (seg.freqHz <= 0) {
          out[idx] = 0;
        } else {
          final t = i / sampleRate;
          final env = fadeSamples == 0
              ? 1.0
              : min(1.0, min(i / fadeSamples, (n - i) / fadeSamples));
          final v = sin(2 * pi * seg.freqHz * t) * 0.35 * env;
          out[idx] = (v * 32767).round().clamp(-32768, 32767);
        }
        idx++;
      }
    }
    return wrapPcm16Wav(out, sampleRate);
  }
}
