// screens/call_screen.dart
// एपभित्रैको full-screen WebRTC कल UI — remote video full-bleed, local PiP,
// mic / camera / flip / hang-up नियन्त्रण। कुनै browser redirect छैन।
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_tap.dart';

class CallScreen extends StatefulWidget {
  final String requestId;
  final String otherName;
  final String myName;
  final bool video;

  /// true = यो user ले कल गर्‍यो; false = incoming कल स्वीकार गर्दै।
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.requestId,
    required this.otherName,
    required this.myName,
    required this.video,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallSession _s = CallSession(
    requestId: widget.requestId,
    video: widget.video,
    isCaller: widget.isCaller,
    myName: widget.myName,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _s.start();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _s.hangUp();
    super.dispose();
  }

  Future<void> _end() async {
    await _s.hangUp();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10061E),
        body: Stack(
          children: [
            // remote video / placeholder
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _s.remoteJoined,
                builder: (_, joined, __) {
                  if (joined && widget.video) {
                    return RTCVideoView(_s.remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
                  }
                  return _placeholder();
                },
              ),
            ),

            // local PiP (video calls only)
            if (widget.video)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).padding.top + 12,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _s.camOn,
                  builder: (_, camOn, __) => Container(
                    width: 108,
                    height: 150,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24, width: 1.5),
                      color: Colors.black,
                    ),
                    child: camOn
                        ? RTCVideoView(_s.localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover)
                        : const Icon(Icons.videocam_off_rounded,
                            color: Colors.white38),
                  ),
                ),
              ),

            // top: name + status
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).padding.top + 16,
              child: Column(
                children: [
                  Text(widget.otherName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 12)
                          ])),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<CallStatus>(
                    valueListenable: _s.status,
                    builder: (_, st, __) => Text(
                      _error != null
                          ? '${S.errorWord}: $_error'
                          : switch (st) {
                              CallStatus.ringing => S.callingWord,
                              CallStatus.connecting => S.callConnecting,
                              CallStatus.connected => S.onlineNow,
                              CallStatus.ended => S.callEnded,
                              _ => '',
                            },
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            // bottom controls
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _s.micOn,
                    builder: (_, on, __) => _ctl(
                      on ? Icons.mic_rounded : Icons.mic_off_rounded,
                      active: !on,
                      onTap: _s.toggleMic,
                    ),
                  ),
                  const SizedBox(width: 18),
                  _ctl(Icons.call_end_rounded,
                      bg: AppColors.danger, big: true, onTap: _end),
                  const SizedBox(width: 18),
                  if (widget.video) ...[
                    ValueListenableBuilder<bool>(
                      valueListenable: _s.camOn,
                      builder: (_, on, __) => _ctl(
                        on
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        active: !on,
                        onTap: _s.toggleCam,
                      ),
                    ),
                  ] else
                    _ctl(Icons.volume_up_rounded, onTap: () {}),
                ],
              ),
            ),

            // flip camera (video only, top-left)
            if (widget.video)
              Positioned(
                left: 12,
                top: MediaQuery.of(context).padding.top + 8,
                child: _ctl(Icons.flip_camera_ios_rounded,
                    small: true, onTap: _s.switchCamera),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    final initial = widget.otherName.trim().isEmpty
        ? '?'
        : widget.otherName.trim()[0].toUpperCase();
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.instaGradient),
      alignment: Alignment.center,
      child: Container(
        width: 120,
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _ctl(IconData icon,
      {required VoidCallback onTap,
      Color? bg,
      bool active = false,
      bool big = false,
      bool small = false}) {
    final size = big ? 66.0 : (small ? 40.0 : 56.0);
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.85,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg ??
              (active ? Colors.white : Colors.white.withValues(alpha: 0.18)),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: bg != null || !active ? Colors.white : Colors.black87,
            size: big ? 30 : (small ? 20 : 24)),
      ),
    );
  }
}
