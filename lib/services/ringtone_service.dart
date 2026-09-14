// services/ringtone_service.dart
// कल गर्दा (outgoing ring-back, "ring, ring…") र कल आउँदा (incoming ring)
// बज्ने दुई छुट्टै लुप हुने टोन — widgets/wav_tone.dart कै synth-WAV pattern
// (कुनै asset/license नचाहिने, runtime मा PCM बनाउने) पछ्याएर।
//
// पहिले यी दुवै टोन साधारण एकल-फ्रिक्वेन्सी "पुरानो टेलिफोन" beep थिए। अब
// bell/chime-शैलीको additive synthesis (fundamental + हल्का detuned unison +
// octave overtone, percussive pluck envelope) प्रयोग गरेर Messenger/प्रिमियम
// एपहरूको calling/ringing tone जस्तो सफा, आधुनिक र सुन्नमा रमाइलो बनाइएको छ —
// तर अझै पनि कुनै बाहिरी audio file/license बिना, यही runtime-generated WAV
// नै हो।
//
// एकपटकमा एउटै मात्र बज्छ — नयाँ play() ले अघिल्लो आफै रोक्छ।
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../widgets/wav_tone.dart';

/// एउटा "note" — chime motif भित्रको एउटा पल्स। धेरै note मिलेर एउटा
/// दोहोरिने motif बन्छ (माथि कुल clip length सम्मको silence सहित)।
class _Note {
  final double freqHz;
  final double startSec;
  final double durSec;
  final double amp;
  const _Note(this.freqHz, this.startSec, this.durSec, {this.amp = 1.0});
}

class RingtoneService {
  RingtoneService._();

  static AudioPlayer? _player;
  static Uint8List? _outgoingWav;
  static Uint8List? _incomingWav;
  static String? _playing; // 'out' | 'in' | null

  /// Caller ले पर्खिरहेको बेला बज्ने "ring, ring…" — सफा दुई-टोन chime,
  /// लामो शान्त खाली ठाउँ सहित (harassing नहोस्)। लुप हुँदा दोहोरिन्छ।
  static Future<void> playOutgoing() => _play(
        'out',
        () => _outgoingWav ??= _buildChime(
          const [
            _Note(587.33, 0.00, 0.22), // D5
            _Note(880.00, 0.18, 0.30, amp: 0.9), // A5
          ],
          totalSec: 2.6,
        ),
      );

  /// Callee ले कल आउँदा बज्ने — उज्यालो ३-नोट ascending chime, ध्यान तान्ने
  /// तर कर्कश नभएको (Messenger/प्रिमियम एप जस्तो)।
  static Future<void> playIncoming() => _play(
        'in',
        () => _incomingWav ??= _buildChime(
          const [
            _Note(783.99, 0.00, 0.18), // G5
            _Note(987.77, 0.13, 0.18, amp: 0.95), // B5
            _Note(1174.66, 0.26, 0.34, amp: 1.0), // D6
          ],
          totalSec: 1.65,
        ),
      );

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

  /// [notes] लाई additive-synthesis bell/chime tone मा मिलाएर [totalSec] को
  /// एउटा loop-able WAV बनाउँछ। हरेक note = fundamental + हल्का detuned
  /// unison (warm/chorus feel) + octave overtone (छिटो decay हुने "pluck"
  /// टिप), percussive envelope (छोटो attack, त्यसपछि exponential decay)
  /// सहित — पुरानो टेलिफोन-जस्तो flat sine beep भन्दा धेरै "प्रिमियम" सुनिन्छ।
  static Uint8List _buildChime(List<_Note> notes, {required double totalSec}) {
    const sampleRate = 22050; // टेलिफोन-जस्तो 8kHz भन्दा स्पष्ट/richer
    final total = (sampleRate * totalSec).round();
    final mix = Float64List(total);

    for (final note in notes) {
      final start = (sampleRate * note.startSec).round();
      final n = (sampleRate * note.durSec).round();
      const attackSamples = 220; // ~10ms — click-free पर तुरुन्तै टिप्ने
      for (var i = 0; i < n; i++) {
        final idx = start + i;
        if (idx < 0 || idx >= total) continue;
        final t = i / sampleRate;
        final attackEnv = i < attackSamples ? i / attackSamples : 1.0;
        // Percussive decay — bell/pluck जस्तो, flat sustain होइन।
        final decayEnv = exp(-t * 6.2);
        final env = attackEnv * decayEnv * note.amp;
        if (env <= 0.0008) continue;

        final fundamental = sin(2 * pi * note.freqHz * t);
        final unison = sin(2 * pi * note.freqHz * 1.006 * t) * 0.5;
        final overtone =
            sin(2 * pi * note.freqHz * 2 * t) * 0.22 * exp(-t * 10);
        final sample = (fundamental + unison + overtone) * env * 0.34;
        mix[idx] += sample;
      }
    }

    final out = Int16List(total);
    for (var i = 0; i < total; i++) {
      out[i] = (mix[i] * 32767).round().clamp(-32768, 32767);
    }
    return wrapPcm16Wav(out, sampleRate);
  }
}
