// screens/call_screen.dart
// एपभित्रैको full-screen WebRTC कल UI — remote video full-bleed, local PiP,
// mic / camera / flip / hang-up नियन्त्रण। कुनै browser redirect छैन।
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../services/ringtone_service.dart';
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
  bool _permissionDenied = false;
  // दुवैतिरबाट कल एकपटक मात्र बन्द हुनुपर्छ — button थिचेर (local) र अर्को
  // पक्षले काटेर (remote, _s.status ले 'ended' सूचित गर्छ) दुवै बाटोले यही
  // guard प्रयोग गर्छन्, ताकि Navigator.pop() दुइपटक नचलोस्।
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _s.status.addListener(_onStatusChanged);
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _s.start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is CallPermissionDenied ? null : '$e';
        _permissionDenied = e is CallPermissionDenied;
      });
    }
  }

  /// Ring-back tone (caller मात्र, जबसम्म callee ले उठाउँदैन) + अर्को
  /// पक्षले कल काट्दा (remote hang-up) यो स्क्रिन आफैं बन्द हुने — पहिले यो
  /// नभएकोले callee ले काटेपछि पनि caller को स्क्रिन कालो/अड्किएको देखिन्थ्यो,
  /// जुन "दुवैतिर तुरुन्तै बन्द हुनुपर्छ" भन्ने आवश्यकता तोड्थ्यो।
  ///
  /// यहाँ कुनै artificial delay छैन — status `ended` भएको bित्तिकै (अर्को
  /// पक्षले काटेको भए पनि) तुरुन्तै pop हुन्छ। Network/WebRTC cleanup
  /// (hangUp भित्रको track stop/PC close/Firestore delete) यो pop लाई
  /// कहिल्यै block गर्दैन — ती background मा आफ्नै गतिमा पूरा हुन्छन्।
  void _onStatusChanged() {
    final st = _s.status.value;
    if (widget.isCaller && st == CallStatus.ringing) {
      RingtoneService.playOutgoing();
    } else {
      RingtoneService.stop();
    }
    if (st == CallStatus.ended && !_closing) {
      _closing = true;
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _s.status.removeListener(_onStatusChanged);
    RingtoneService.stop();
    // fire-and-forget — dispose() आफैं async हुन सक्दैन, र यसलाई await
    // गर्नु पनि गलत हुन्थ्यो: screen पहिल्यै हटिसकेको छ, track stop/PC
    // close/Firestore cleanup ले UI लाई कुनै हालतमा block नगरोस्।
    unawaited(_s.hangUp());
    super.dispose();
  }

  /// Hang-up बटन/back-gesture — touch हुनेबित्तिकै तुरुन्तै pop हुन्छ।
  /// `_s.hangUp()` (network + WebRTC teardown) लाई कहिल्यै await गर्दैन:
  /// त्यो background मा चलिरहन्छ, pop यो function भित्रकै पहिलो र एकमात्र
  /// synchronous काम हो — त्यसैले touch-to-dismiss उही frame मा हुन्छ।
  void _end() {
    if (_closing) return;
    _closing = true;
    RingtoneService.stop();
    unawaited(_s.hangUp());
    Navigator.of(context).pop();
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
        // अनुमति अस्वीकृत भएमा साधारण कालो/अड्किएको स्क्रिन देखाउनुको सट्टा
        // स्पष्ट कारण + "Settings खोल्नुहोस्" बटन — प्रयोगकर्तालाई थाहा
        // होस् किन कल जोडिएन।
        body: _permissionDenied
            ? _permissionDeniedView()
            : Stack(
                children: [
                  // remote video / placeholder
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _s.remoteJoined,
                      builder: (_, joined, __) {
                        if (joined && widget.video) {
                          return RTCVideoView(_s.remoteRenderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover);
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
                            border:
                                Border.all(color: Colors.white24, width: 1.5),
                            color: Colors.black,
                          ),
                          child: camOn
                              ? ValueListenableBuilder<bool>(
                                  valueListenable: _s.isFrontCamera,
                                  builder: (_, front, __) => RTCVideoView(
                                      _s.localRenderer,
                                      // Front camera मात्र mirror गर्ने — back
                                      // camera मा mirror गरे feed उल्टो/गलत
                                      // देखिन्थ्यो (यो अघिल्लो वास्तविक बग)।
                                      mirror: front,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover))
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
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
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
                          const SizedBox(width: 18),
                        ],
                        // Speaker ⇄ earpiece — दुवै audio र video कलमा
                        // उपलब्ध (पहिले video कलमा यो बटन नै हराएको थियो,
                        // र voice कलमा भए पनि onTap खाली/no-op थियो)।
                        ValueListenableBuilder<bool>(
                          valueListenable: _s.speakerOn,
                          builder: (_, on, __) => _ctl(
                            on
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            active: on,
                            onTap: _s.toggleSpeaker,
                          ),
                        ),
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

  Widget _permissionDeniedView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                widget.video
                    ? Icons.videocam_off_rounded
                    : Icons.mic_off_rounded,
                color: Colors.white70,
                size: 56),
            const SizedBox(height: 18),
            Text(
              S.cameraMicNeeded,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_rounded),
              label: Text(S.openSettings),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.igViolet,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _end,
              child:
                  Text(S.cancel, style: const TextStyle(color: Colors.white70)),
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
