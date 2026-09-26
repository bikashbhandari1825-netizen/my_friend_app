// widgets/voice_recorder_bar.dart
// Chat input bar भित्र embed हुने voice-note recorder — Messenger/WhatsApp
// जस्तै दुई चरण:
//   1. recording  — live waveform + timer + discard (trash)। मुख्य mic बटन
//      फेरि थिच्दा recording रोकिन्छ र preview मा जान्छ — auto-send हुँदैन।
//   2. preview    — रेकर्ड भएको clip play/pause + discard + Send। Send
//      button ले मात्र `onSend` call हुन्छ — recording रोकिनेबित्तिकै होइन।
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/app_theme.dart';
import 'chat_waveform.dart';
import 'spring_tap.dart';

// ── Web voice-recording ──────────────────────────────────────────────────
// यो recorder मोबाइलमा (`path_provider` को real temp file + `dart:io` को
// `File.readAsBytes()`) राम्रोसँग चल्थ्यो, तर Flutter Web मा दुई ठाउँमा
// पूर्ण रूपमा भाँचिन्थ्यो — त्यसैले "laptop मा voice message नै पठाउन
// मिल्दैन" गुनासो सधैँ १००% दोहोरिने (कहिलेकाहीं होइन, हरेकपटक) थियो:
//   (१) `AudioEncoder.aacLc` — Chrome/Edge (Chromium) को `MediaRecorder`
//       ले AAC/MP4 audio recording नै समर्थन गर्दैन (Safari मात्र गर्छ)।
//       `record_web` त्यसैले कुनै पनि समर्थित mime-type नभेटेर सिधै
//       `'aacLc not supported.'` throw गर्थ्यो — recording सुरुै हुनुअघि नै।
//   (२) भेटिए पनि — `record_web` को `stop()` ले real filesystem path कहिल्यै
//       फर्काउँदैन, ब्राउजरको `URL.createObjectURL()` बाट बनेको `blob:...`
//       URL मात्र फर्काउँछ। त्यो `dart:io` को `File(path)` लाई दिँदा (जो
//       web मा वास्तविक फाइलसिस्टम नै छैन) असफल हुन्थ्यो।
// समाधान: web मा फरक (व्यापक-समर्थित) encoder — `AudioEncoder.opus`
// (`audio/webm;codecs=opus`, Chrome/Firefox/Edge सबैले समर्थन गर्छन्) —
// र bytes `dart:io File` को सट्टा त्यही blob URL लाई सिधै `http.get()` गरेर
// (ब्राउजरको आफ्नै page-scoped blob, कुनै network/CORS round-trip चाहिँदैन)
// प्राप्त गर्ने। Mobile/desktop (native) तिर अघिकै (aacLc + real file)
// व्यवहार ज्यूँकात्यूँ।
AudioEncoder get _voiceEncoder =>
    kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
String get _voiceExt => kIsWeb ? 'webm' : 'm4a';

enum _RecPhase { recording, preview }

class VoiceRecorderBar extends StatefulWidget {
  /// प्रयोगकर्ताले Send थिचेपछि मात्र call हुने — रेकर्ड गरिएको audio bytes +
  /// त्यसको साँचो extension (मोबाइलमा 'm4a', web मा 'webm' — दुई फरक
  /// container format हुन् भन्ने caller (chat_screen.dart) लाई थाहा हुनुपर्छ,
  /// नत्र गलत content-type/extension सहित अपलोड हुन्छ र playback असफल हुन्छ)।
  /// अन्तिम पेरामिटर — यहीं रेकर्डिङ बेला नै नाप्ता (सेकेन्डमा) लम्बाइ,
  /// caller ले chat bubble मा तुरुन्तै देखाउन (पछि audio फाइल नै लोड गरेर
  /// नाप्नु पर्दैन — त्यसले playback सुरु नहुन्जेल संख्या नै नदेखिने/flicker
  /// हुने समस्या दिन्थ्यो)।
  final void Function(Uint8List bytes, String ext, int durationSeconds) onSend;

  /// Discard/cancel भयो (recording बेला वा preview बेला) — केही पठाइँदैन।
  final VoidCallback onCancel;

  const VoiceRecorderBar({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  _RecPhase _phase = _RecPhase.recording;
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<PlayerState>? _playerSub;
  Timer? _timer;
  final List<double> _levels = [];
  Duration _elapsed = Duration.zero;
  String? _path;
  Uint8List? _bytes;
  bool _playing = false;
  bool _starting = true;
  bool _busy = false; // stop/discard बीच double-tap रोक्न

  @override
  void initState() {
    super.initState();
    _playerSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        widget.onCancel();
        return;
      }
      // web मा `path_provider` को कुनै platform implementation नै छैन
      // (`getTemporaryDirectory()` सिधै throw हुन्छ) — र `record_web` ले
      // यसलाई वास्तविक फाइलसिस्टम path को रूपमा प्रयोगै गर्दैन, त्यसैले
      // web मा खाली string नै पठाउने।
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}'
            '.$_voiceExt';
      }
      await _recorder.start(
        RecordConfig(encoder: _voiceEncoder),
        path: path,
      );
      _path = path;
      if (!mounted) return;
      setState(() => _starting = false);
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) {
          setState(() => _elapsed += const Duration(milliseconds: 100));
        }
      });
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        // dB scale (सामान्यतया -50..0 वरपर) — 0..1 मा सामान्यीकृत।
        final norm = ((amp.current + 50) / 50).clamp(0.0, 1.0);
        if (mounted) {
          setState(() {
            _levels.add(norm);
          });
        }
      });
    } catch (_) {
      widget.onCancel();
    }
  }

  Future<void> _stopToPreview() async {
    if (_busy || _phase != _RecPhase.recording) return;
    setState(() => _busy = true);
    _timer?.cancel();
    await _ampSub?.cancel();
    try {
      final path = await _recorder.stop();
      if (path == null) {
        widget.onCancel();
        return;
      }
      // web मा `path` वास्तविक फाइल होइन, ब्राउजरको आफ्नै `blob:...` URL हो
      // (page-scoped, same-origin) — `dart:io` को `File()` ले यसलाई कहिल्यै
      // पढ्न सक्दैन (web मा साँचो filesystem नै छैन); `http.get()` ले भने
      // यो blob लाई कुनै network round-trip बिनै सिधै fetch गर्छ।
      final bytes = kIsWeb
          ? (await http.get(Uri.parse(path))).bodyBytes
          : await File(path).readAsBytes();
      if (bytes.lengthInBytes < 500) {
        // धेरै छोटो (गल्तिले tap मात्र) — पठाउनलायक केही छैन।
        widget.onCancel();
        return;
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _phase = _RecPhase.preview;
        _busy = false;
      });
    } catch (_) {
      widget.onCancel();
    }
  }

  Future<void> _discard() async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    await _ampSub?.cancel();
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        if (_path != null && _path!.isNotEmpty) await File(_path!).delete();
      } catch (_) {}
    }
    widget.onCancel();
  }

  Future<void> _togglePlay() async {
    if (_bytes == null) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(_bytes!));
    }
  }

  void _send() {
    if (_bytes == null || _busy) return;
    widget.onSend(_bytes!, _voiceExt, _elapsed.inSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _playerSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  String get _timeLabel {
    final s = _elapsed.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recording = _phase == _RecPhase.recording;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          SpringTap(
            onTap: recording ? _discard : widget.onCancel,
            pressedScale: 0.85,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger, size: 22),
            ),
          ),
          const SizedBox(width: 4),
          if (recording) ...[
            _PulsingDot(active: !_starting),
            const SizedBox(width: 8),
            Text(_timeLabel,
                style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 10),
            Expanded(
              child: ChatWaveform(
                levels: _levels,
                color: AppColors.igViolet,
                live: true,
              ),
            ),
          ] else ...[
            SpringTap(
              onTap: _togglePlay,
              pressedScale: 0.85,
              // Padding ले tap target कम्तीमा ~44dp बनाउँछ — ठ्याक्कै 30dp
              // icon मात्रैमा भर पर्दा साँघुरो/miss-tap हुने ठाउँ थियो।
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: AppColors.igViolet,
                    size: 30),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ChatWaveform(
                levels: _levels,
                color: AppColors.igViolet,
                live: false,
              ),
            ),
            const SizedBox(width: 8),
            Text(_timeLabel,
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
          const SizedBox(width: 8),
          SpringTap(
            onTap: recording ? _stopToPreview : _send,
            pressedScale: 0.82,
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                gradient: AppColors.buttonGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  recording ? Icons.stop_rounded : Icons.send_rounded,
                  color: Colors.white,
                  size: 19),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recording हुँदा बज्ने रातो थोप्लो — blink गर्दै "record भइरहेको छ" संकेत।
class _PulsingDot extends StatefulWidget {
  final bool active;
  const _PulsingDot({required this.active});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_ctrl),
      child: const Icon(Icons.fiber_manual_record_rounded,
          color: AppColors.danger, size: 12),
    );
  }
}
