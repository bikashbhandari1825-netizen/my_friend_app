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
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/app_theme.dart';
import 'chat_waveform.dart';
import 'spring_tap.dart';

enum _RecPhase { recording, preview }

class VoiceRecorderBar extends StatefulWidget {
  /// प्रयोगकर्ताले Send थिचेपछि मात्र call हुने — रेकर्ड गरिएको audio bytes।
  final ValueChanged<Uint8List> onSend;

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
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
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
      final bytes = await File(path).readAsBytes();
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
    try {
      if (_path != null) await File(_path!).delete();
    } catch (_) {}
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
    widget.onSend(_bytes!);
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
