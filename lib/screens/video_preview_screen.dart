// screens/video_preview_screen.dart
// क्यामेरा/gallery बाट भिडियो छानेपछि (Send/Discard) र chat मा आइसकेको
// भिडियो म्यासेज play गर्दा (हेर्ने मात्र) — दुवैका लागि एउटै screen।
// नियन्त्रण (play/pause, progress bar) पूर्ण रूपमा आफ्नै — कुनै तेस्रो-
// पक्षको player UI/watermark/logo (जस्तै chewie कै default controls)
// प्रयोग गरिएको छैन, `video_player` ले दिने raw texture माथि KaamMitra
// कै gradient/theme मिल्ने बटन/progress bar मात्र।
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_tap.dart';

class VideoPreviewScreen extends StatefulWidget {
  /// Pre-send preview मा (local, disk/memory बाट) — दिइएमा Send/Discard
  /// बटन देखिन्छ, "true" फर्काएपछि मात्र caller ले साँच्चै अपलोड गर्छ।
  final Uint8List? bytes;

  /// पहिल्यै पठाइसकेको भिडियो म्यासेज play गर्दा — दिइएमा play-only UI
  /// (Send/Discard छैन)।
  final String? url;

  const VideoPreviewScreen({super.key, this.bytes, this.url})
      : assert(bytes != null || url != null,
            'either bytes (preview) or url (playback) required');

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _error = false;
  bool _showControls = true;
  Timer? _hideTimer;

  bool get _isPreview => widget.bytes != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Local (pre-send) bytes र remote URL दुवैलाई एउटै `networkUrl`
      // constructor बाट play गर्न मिल्छ — local bytes लाई `data:` URI मा
      // बदलेर (सबै platform मा, web सहित, काम गर्ने एकमात्र cross-platform
      // तरिका — `VideoPlayerController.file`/`contentUri` Android/iOS-मात्र हुन्छन्)।
      final uri = widget.bytes != null
          ? Uri.dataFromBytes(widget.bytes!, mimeType: 'video/mp4')
          : Uri.parse(widget.url!);
      final c = VideoPlayerController.networkUrl(uri);
      await c.initialize();
      c.setLooping(false);
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _ready = true;
      });
      c.addListener(_onTick);
      await c.play();
      _scheduleHideControls();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
      _scheduleHideControls();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleTap,
                child: Center(
                  child: _error
                      ? const Icon(Icons.error_outline_rounded,
                          color: Colors.white54, size: 48)
                      : (_ready && c != null)
                          ? AspectRatio(
                              aspectRatio: c.value.aspectRatio == 0
                                  ? 16 / 9
                                  : c.value.aspectRatio,
                              child: VideoPlayer(c),
                            )
                          : const CircularProgressIndicator(
                              color: Colors.white),
                ),
              ),
            ),
            if (_ready && c != null && _showControls)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          c.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_ready && c != null)
              GestureDetector(
                onTap: _togglePlay,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            Positioned(
              left: 8,
              top: 8,
              child: SpringTap(
                onTap: () => Navigator.of(context).pop(false),
                pressedScale: 0.85,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
            if (_ready && c != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: _isPreview ? 96 : 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(_fmt(c.value.position),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11.5)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape:
                                const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: AppColors.igPink,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            min: 0,
                            max: c.value.duration.inMilliseconds
                                .toDouble()
                                .clamp(1, double.infinity),
                            value: c.value.position.inMilliseconds
                                .toDouble()
                                .clamp(0,
                                    c.value.duration.inMilliseconds.toDouble()),
                            onChanged: (v) =>
                                c.seekTo(Duration(milliseconds: v.round())),
                          ),
                        ),
                      ),
                      Text(_fmt(c.value.duration),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11.5)),
                    ],
                  ),
                ),
              ),
            if (_isPreview)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white),
                          label: Text(S.cancel,
                              style: const TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.white38),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: SpringTap(
                          onTap: () => Navigator.of(context).pop(true),
                          pressedScale: 0.95,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: AppColors.buttonGradient,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.igPink
                                        .withValues(alpha: 0.4),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send_rounded,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(S.send,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
