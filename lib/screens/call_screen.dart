// screens/call_screen.dart
// एपभित्रैको full-screen WebRTC कल UI — remote video full-bleed, local PiP,
// mic / camera / flip / hang-up नियन्त्रण। कुनै browser redirect छैन।
//
// Incoming कल पनि यही एउटै स्क्रिनको भाग हो (`needsAcceptance: true`) — छुट्टै
// सानो `AlertDialog` (पहिले जस्तो, map/chat माथि टाँसिएर "messy overlay"
// देखिने र Accept थिचेपछि दोस्रोपटक फेरि Navigator.push गर्दा कहिलेकाहीं
// map मा बाउन्स-ब्याक हुने) होइन। एउटै full-screen route भित्रै "Accept
// नगरेसम्म" (ringing UI + ठूला Accept/Decline बटन) देखाउँछ, Accept थिचेपछि
// त्यही स्क्रिनमै (कुनै दोस्रो push/pop नगरी) साँचो कल सुरु हुन्छ — यसैले
// "pop back / crash on accept" जस्तो navigation race सम्भवै छैन।
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../services/ringtone_service.dart';
import '../theme/app_theme.dart';
import '../widgets/online_badge.dart';
import '../widgets/spring_tap.dart';
import 'nearby_common.dart' show PulseRings;

class CallScreen extends StatefulWidget {
  final String requestId;
  final String otherName;
  final String myName;
  final bool video;

  /// true = यो user ले कल गर्‍यो; false = incoming कल स्वीकार गर्दै।
  final bool isCaller;

  /// अर्को पक्षको uid — थाहा भएमा (दुवै caller/callee sideबाट सजिलै भेटिने
  /// भएकोले उपलब्ध गराइएको) "Online" presence badge देखाउन प्रयोग हुन्छ।
  /// नभए (खाली) badge नै नदेखिने — कल आफैं यसबिना पनि सामान्य चल्छ।
  final String otherUid;

  /// true = यो screen आउँदो कलको हो र callee ले अझै Accept/Decline गर्नुपर्छ
  /// — त्यसबेलासम्म WebRTC session (`_s.start()`) सुरुै हुँदैन, केवल पूर्ण
  /// पर्दाको ringing UI देखिन्छ। isCaller (आफैं कल गर्दा) मा यो सधैं false।
  final bool needsAcceptance;

  const CallScreen({
    super.key,
    required this.requestId,
    required this.otherName,
    required this.myName,
    required this.video,
    required this.isCaller,
    this.otherUid = '',
    this.needsAcceptance = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
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

  // Accept नगरेसम्म true — त्यतिञ्जेल ठूलो ringing UI (Accept/Decline बटन
  // सहित) देखिन्छ, WebRTC session सुरुै हुँदैन। needsAcceptance नभएको
  // (outgoing कल) मा सुरुदेखि नै false।
  late bool _awaitingAccept = widget.needsAcceptance;
  // `_s.start()` साँच्चै एकपटक भए मात्र true — dispose() मा `_s.hangUp()`
  // (track/PC/renderer cleanup) यही भए मात्र चलाउने। Accept नगरी Decline
  // गरे session कहिल्यै सुरुै नभएकोले त्यो cleanup चलाउनु आवश्यक पर्दैन, र
  // चलाए पनि (`hangUp()` भित्रैको batch-write) `resetSignal()` ले भर्खरै
  // मेटेको call doc लाई फेरि `{status:'ended'}` सहित पुनः-सिर्जना गर्ने
  // race हुन्थ्यो।
  bool _sessionStarted = false;

  // Accept नगरेसम्म — caller आफैंले कल काटिदिए (मन फेरे/गल्तिले थिचे) यो
  // स्क्रिन आफैं बन्द होस् र फेरि नबजोस् भनेर call doc हेर्ने हल्का watcher।
  // Accept गरेपछि यो चाहिँदैन (त्यसपछि `CallSession.start()` भित्रकै
  // आफ्नै doc-listener ले यही काम गर्छ)।
  StreamSubscription<Map<String, dynamic>?>? _preAcceptSub;

  // "Ring, ring…" indicator — जोडिनअघि (ringing/connecting/awaiting-accept)
  // placeholder avatar वरिपरि radar-जस्तो pulse (नक्सा/searching screen मै
  // प्रयोग हुने उही `PulseRings` — एपभरि एउटै भाषा)।
  late final AnimationController _ringPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void initState() {
    super.initState();
    activeCallRequestId = widget.requestId;
    _s.status.addListener(_onStatusChanged);
    if (_awaitingAccept) {
      RingtoneService.playIncoming();
      _preAcceptSub = CallService.watch(widget.requestId).listen((c) {
        final status = (c?['status'] ?? '').toString();
        if ((c == null || status == 'ended') && _awaitingAccept && mounted) {
          RingtoneService.stop();
          Navigator.of(context).pop();
        }
      });
    } else {
      _boot();
    }
  }

  Future<void> _boot() async {
    _sessionStarted = true;
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

  /// Accept बटन — ringing UI तुरुन्तै हट्छ (उही स्क्रिनमै), अनि साँचो WebRTC
  /// session सुरु हुन्छ। कुनै दोस्रो Navigator.push/pop छैन।
  Future<void> _acceptIncoming() async {
    if (!_awaitingAccept) return;
    await _preAcceptSub?.cancel();
    RingtoneService.stop();
    setState(() => _awaitingAccept = false);
    await _boot();
  }

  /// Decline बटन — session कहिल्यै सुरु नगरिकनै call doc मेटेर सिधै pop।
  Future<void> _declineIncoming() async {
    if (!_awaitingAccept || _closing) return;
    _closing = true;
    RingtoneService.stop();
    await _preAcceptSub?.cancel();
    unawaited(CallService.resetSignal(widget.requestId));
    if (mounted) Navigator.of(context).pop();
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
    if (activeCallRequestId == widget.requestId) activeCallRequestId = null;
    _s.status.removeListener(_onStatusChanged);
    _preAcceptSub?.cancel();
    _ringPulse.dispose();
    RingtoneService.stop();
    // fire-and-forget — dispose() आफैं async हुन सक्दैन, र यसलाई await
    // गर्नु पनि गलत हुन्थ्यो: screen पहिल्यै हटिसकेको छ, track stop/PC
    // close/Firestore cleanup ले UI लाई कुनै हालतमा block नगरोस्। session
    // साँच्चै सुरु भएकोमा मात्र — Accept नगरी बन्द भए यो चाहिँदैन (माथि
    // `_sessionStarted` को doc हेर्नुहोस्)।
    if (_sessionStarted) unawaited(_s.hangUp());
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
        if (didPop) return;
        if (_awaitingAccept) {
          _declineIncoming();
        } else {
          _end();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10061E),
        // अनुमति अस्वीकृत भएमा साधारण कालो/अड्किएको स्क्रिन देखाउनुको सट्टा
        // स्पष्ट कारण + "Settings खोल्नुहोस्" बटन — प्रयोगकर्तालाई थाहा
        // होस् किन कल जोडिएन।
        body: _awaitingAccept
            ? _incomingCallView()
            : _permissionDenied
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
                        if (widget.otherUid.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ValueListenableBuilder<CallStatus>(
                            valueListenable: _s.status,
                            builder: (_, st, __) =>
                                (st == CallStatus.ringing ||
                                        st == CallStatus.connecting)
                                    ? OnlineBadge(
                                        uid: widget.otherUid, onDark: true)
                                    : const SizedBox.shrink(),
                          ),
                        ],
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

  /// Accept नगरेसम्मको full-screen incoming-call UI — Instagram/Messenger
  /// जस्तै: पूरा-पर्दा gradient, धड्किने avatar, ठूलो नाम, र तल ठूला
  /// Accept/Decline बटन। कुनै सानो dialog/overlay होइन — यो आफैं स्वतन्त्र
  /// full route हो, त्यसैले map/chat माथि "टाँसिएर" कहिल्यै overlap हुँदैन।
  Widget _incomingCallView() {
    final initial = widget.otherName.trim().isEmpty
        ? '?'
        : widget.otherName.trim()[0].toUpperCase();
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.instaGradient),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(S.incomingCallTitle,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
            const Spacer(),
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PulseRings(t: _ringPulse, color: Colors.white),
                  Container(
                    width: 150,
                    height: 150,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 58,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(widget.otherName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(color: Colors.black38, blurRadius: 10),
                    ])),
            const SizedBox(height: 6),
            Text(widget.video ? S.videoCall : S.voiceCall,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            if (widget.otherUid.isNotEmpty) ...[
              const SizedBox(height: 12),
              OnlineBadge(uid: widget.otherUid, onDark: true),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _bigCallBtn(
                    icon: Icons.call_end_rounded,
                    label: S.decline,
                    color: AppColors.danger,
                    onTap: _declineIncoming,
                  ),
                  _bigCallBtn(
                    icon: widget.video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    label: S.accept,
                    gradient: AppColors.buttonGradient,
                    onTap: _acceptIncoming,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigCallBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    Gradient? gradient,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpringTap(
          onTap: onTap,
          pressedScale: 0.88,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: color,
              gradient: gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: (color ?? AppColors.igPink).withValues(alpha: 0.5),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
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
      child: ValueListenableBuilder<CallStatus>(
        valueListenable: _s.status,
        builder: (_, st, __) {
          // जोडिनअघि (ringing/connecting) मात्र — "Ring, ring…" जस्तो radar
          // pulse; जोडिएपछि (connected) शान्त, स्थिर avatar।
          final ringing =
              st == CallStatus.ringing || st == CallStatus.connecting;
          return SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (ringing) PulseRings(t: _ringPulse, color: Colors.white),
                Container(
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
              ],
            ),
          );
        },
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
