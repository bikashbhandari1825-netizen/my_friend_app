// widgets/wav_tone.dart
// छोटो in-app chime हरू (success feedback, नयाँ काम अलर्ट, आदि) ले साझा
// गर्ने PCM16 → WAV wrapper — asset बिना runtime मा tone बनाउन।
import 'dart:typed_data';

Uint8List wrapPcm16Wav(Int16List samples, int sampleRate) {
  final pcm = samples.buffer.asUint8List();
  final b = BytesBuilder();
  void str(String x) => b.add(x.codeUnits);
  void u32(int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);

  str('RIFF');
  u32(36 + pcm.length);
  str('WAVE');
  str('fmt ');
  u32(16); // PCM header size
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate (16-bit mono)
  u16(2); // block align
  u16(16); // bits per sample
  str('data');
  u32(pcm.length);
  b.add(pcm);
  return b.toBytes();
}
