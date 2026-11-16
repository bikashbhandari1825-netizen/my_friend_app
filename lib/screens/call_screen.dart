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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../services/ringtone_service.dart';
import '../theme/app_theme.dart';
import '../widgets/online_badge.dart';
import '../widgets/spring_tap.dart';
import '../widgets/futuristic_ui.dart';

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
  // Absolute Connect Timeout फायर भएपछि (CallSession.connectTimedOut) —
  // "Connecting…" अनन्त-कालसम्म देखिनुको सट्टा प्रयोगकर्तालाई प्रस्ट
  // "जोडिन सकिएन, नेटवर्क जाँच्नुहोस्" देखाउने, स्वतः pop नगरी (permission-
  // denied view कै जस्तै) — उनी आफैं "Hang Up" थिचेर मात्र बाहिरिन्छन्।
  bool _connectFailed = false;
  // दुवैतिरबाट कल एकपटक मात्र बन्द हुनुपर्छ — button थिचेर (local) र अर्को
  // पक्षले काटेर (remote, _s.status ले 'ended' सूचित गर्छ) दुवै बाटोले यही
  // guard प्रयोग गर्छन्, ताकि Navigator.pop() दुइपटक नचलोस्।
  bool _closing = false;
  // Accept बटन दुइपटक (double-tap/race) नचलोस् भनेर — `_closing` कै जस्तै
  // synchronous, पहिलो `await` भन्दा अघि नै सेट हुने guard।
  bool _accepting = false;

  // ── Global multi-call prevention ──────────────────────────────────────
  // माथिकै `activeCallRequestId` पहिले उही requestId को दोहोरो-नेभिगेसन
  // (उदाहरण: notification tap ले उही आउँदो कल फेरि push नगर्नोस्) रोक्नमात्र
  // प्रयोग हुन्थ्यो — तर app भरि धेरै ठाउँ (chat header, job/route screen,
  // profile, bookings, notification) बाट यो एउटै `CallScreen` push हुन्छ,
  // र ती कुनैले पनि "अहिल्यै अर्को (फरक requestId को) कल active छ कि छैन"
  // जाँच्दैनथे। नतिजा: दुई फरक ठाउँबाट झट्ट-झट्टै (वा दुई ट्याप) कल सुरु
  // गरे दुई छुट्टाछुट्टै `CallSession` (दुई अलग peer connection + दुई
  // क्यामेरा स्ट्रिम) एकैचोटि खुल्न सक्थे — ठ्याक्कै "physically impossible
  // to spawn multiple concurrent... call sessions" भन्ने आवश्यकता तोड्ने।
  // अब यहीं, एउटै साझा widget भित्रैबाट, केन्द्रीकृत रूपमा रोकिन्छ — हरेक
  // छुट्टाछुट्टै "कल गर्नुहोस्" बटन भएको फाइल छुट्टाछुट्टै नछोई।
  bool _blockedDuplicateCall = false;

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
    if (activeCallRequestId != null &&
        activeCallRequestId != widget.requestId) {
      // अर्को (फरक requestId को) कल पहिल्यै active — यो नयाँ स्क्रिनले
      // `_s` (CallSession) कहिल्यै नछोई, WebRTC/permission/renderer कुनै
      // पनि सुरु नगरी, अर्को frame मै आफैं बन्द हुन्छ।
      _blockedDuplicateCall = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.alreadyOnACall)),
        );
        Navigator.of(context).pop();
      });
      return;
    }
    activeCallRequestId = widget.requestId;
    _s.status.addListener(_onStatusChanged);
    _s.connectTimedOut.addListener(_onConnectTimeout);
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
    // `_declineIncoming()` कै जस्तो synchronous re-entrancy guard (पहिलो
    // `await` भन्दा अघि नै) — नत्र छिटो double-tap (वा ठ्याक्कै त्यही
    // क्षण Decline/back) ले यो function दुइपटक "in-flight" बनाएर `_boot()`
    // (→ `CallSession.start()`) उही session मा दुइपटक चलाउन सक्थ्यो — दुई
    // छुट्टाछुट्टै peer connection/camera stream एकैचोटि खोलिने, त्यही
    // race ले crash/leak दिने जोखिम।
    if (!_awaitingAccept || _accepting) return;
    _accepting = true;
    await _preAcceptSub?.cancel();
    RingtoneService.stop();
    if (!mounted) return;
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
      if (mounted) Navigator.of(context).pop(_s.callDuration.value.inSeconds);
    }
  }

  /// Absolute Connect Timeout फायर भएपछि — स्वतः pop नगरी (कल भर्खरै साँच्चै
  /// जोडिन सफल भइहाल्यो भने यो notifier फेरि कहिल्यै true हुँदैन, त्यसैले
  /// race छैन) प्रस्ट "जोडिन सकिएन" view देखाउने, प्रयोगकर्ता आफैं "Hang
  /// Up" थिचेर मात्र बाहिरिने।
  void _onConnectTimeout() {
    if (_s.connectTimedOut.value && mounted && !_connectFailed) {
      setState(() => _connectFailed = true);
    }
  }

  @override
  void dispose() {
    if (_blockedDuplicateCall) {
      // माथि (initState) मा `_s`/`_ringPulse` कहिल्यै छोइएको छैन — तिनको
      // lazy (`late final`) initializer यहाँ (केवल dispose गर्ने प्रयासले)
      // व्यर्थै ट्रिगर नहोस् भनेर सिधै फर्कने।
      super.dispose();
      return;
    }
    if (activeCallRequestId == widget.requestId) activeCallRequestId = null;
    _s.status.removeListener(_onStatusChanged);
    _s.connectTimedOut.removeListener(_onConnectTimeout);
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
    // `hangUp()` ले (माथिकै फाइल हेर्नुहोस्) `callDuration` लाई कुनै पनि
    // `await` भन्दा अघि नै अन्तिम/ताजा मानमा सेट गर्छ, त्यसैले
    // `unawaited(...)` भइकन पनि यहाँ synchronously त्यही ताजा मान पाइन्छ।
    Navigator.of(context).pop(_s.callDuration.value.inSeconds);
  }

  @override
  Widget build(BuildContext context) {
    if (_blockedDuplicateCall) {
      // यो फ्रेम पछि नै (माथि initState मा) आफैं pop हुन्छ — बीचमा
      // `_s`/WebRTC UI कहिल्यै नबनाई हल्का खाली पर्दा मात्र।
      return const Scaffold(backgroundColor: Color(0xFF10061E));
    }
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
                : _connectFailed
                    ? _connectFailedView()
                    : Stack(
                        children: [
                          // remote video / placeholder
                          Positioned.fill(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _s.remoteJoined,
                              builder: (_, joined, __) {
                                if (!joined || !widget.video) {
                                  return _placeholder();
                                }
                                // Track event (`onTrack`) आइपुग्नु र साँच्चै
                                // पहिलो डिकोड भएको फ्रेम आउनु एउटै क्षण होइन।
                                // `RTCVideoRenderer.renderVideo` (getter)
                                // `srcObject` सेट हुनेबित्तिकै true हुन्छ —
                                // frame नआईकनै — त्यसैले त्यो भरपर्दो होइन
                                // (यहीचाहिं Web मा `onFirstFrameRendered`
                                // कहिल्यै trigger नहुने भएकोले पहिले यो
                                // placeholder अनन्त-कालसम्म अड्किने गुनासोको
                                // जड थियो)। Renderer आफैं (`ValueNotifier
                                // <RTCVideoValue>`) चाहिं दुवै platform मा
                                // भरपर्दो रूपमा अपडेट हुन्छ — native मा
                                // `didTextureChangeVideoSize`, web मा video
                                // element कै `onCanPlay`/`onResize` बाट —
                                // त्यसैले साँचो "फ्रेम आयो" भनेर `width/height
                                // > 0` मात्र हेर्ने, राw कालो texture होइन।
                                return ValueListenableBuilder<RTCVideoValue>(
                                  valueListenable: _s.remoteRenderer,
                                  builder: (_, v, __) =>
                                      (v.width > 0 && v.height > 0)
                                          ? RTCVideoView(_s.remoteRenderer,
                                              objectFit: RTCVideoViewObjectFit
                                                  .RTCVideoViewObjectFitCover)
                                          : _placeholder(),
                                );
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
                                    border: Border.all(
                                        color: Colors.white24, width: 1.5),
                                    color: Colors.black,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  // Advanced PiP — camera off / starting / live तीनै
                                  // अवस्थाबीच सहज cross-fade (AnimatedSwitcher)।
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 320),
                                    switchInCurve: Curves.easeOut,
                                    child: !camOn
                                        ? const _PipOff(key: ValueKey('off'))
                                        // camOn भए पनि साँच्चै पहिलो local फ्रेम
                                        // अझै नआएसम्म (width/height>0 जाँच, दुवै
                                        // platform मा भरपर्दो) raw कालो texture
                                        // होइन — shimmer + "Starting camera…"।
                                        : ValueListenableBuilder<RTCVideoValue>(
                                            key: const ValueKey('cam'),
                                            valueListenable: _s.localRenderer,
                                            builder: (_, v, __) =>
                                                (v.width > 0 && v.height > 0)
                                                    ? ValueListenableBuilder<
                                                        bool>(
                                                        valueListenable:
                                                            _s.isFrontCamera,
                                                        builder: (_, front,
                                                                __) =>
                                                            // Front camera मात्र
                                                            // mirror — back
                                                            // camera मा mirror
                                                            // गरे feed उल्टो
                                                            // देखिन्थ्यो।
                                                            RTCVideoView(
                                                                _s.localRenderer,
                                                                mirror: front,
                                                                objectFit:
                                                                    RTCVideoViewObjectFit
                                                                        .RTCVideoViewObjectFitCover),
                                                      )
                                                    : const _PipLoading(),
                                          ),
                                  ),
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
                                          Shadow(
                                              color: Colors.black54,
                                              blurRadius: 12)
                                        ])),
                                const SizedBox(height: 4),
                                ValueListenableBuilder<CallStatus>(
                                  valueListenable: _s.status,
                                  builder: (_, st, __) {
                                    if (_error != null) {
                                      return Text('${S.errorWord}: $_error',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13));
                                    }
                                    // जोडिएपछि — static "Online now" को सट्टा live
                                    // "00:00" timer, हरेक सेकेन्ड बढ्दै। यो भित्री
                                    // ValueListenableBuilder ले मात्र (न कि पूरै
                                    // status/name/avatar tree ले) हरेक सेकेन्ड
                                    // rebuild हुने भएकोले कुनै flicker/lag छैन।
                                    if (st == CallStatus.connected) {
                                      return ValueListenableBuilder<Duration>(
                                        valueListenable: _s.callDuration,
                                        builder: (_, d, __) => Text(
                                          formatDuration(d.inSeconds),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                              fontFeatures: [
                                                FontFeature.tabularFigures()
                                              ]),
                                        ),
                                      );
                                    }
                                    return Text(
                                      switch (st) {
                                        CallStatus.ringing => S.callingWord,
                                        CallStatus.connecting =>
                                          S.callConnecting,
                                        CallStatus.ended => S.callEnded,
                                        _ => '',
                                      },
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                    );
                                  },
                                ),
                                if (widget.otherUid.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  ValueListenableBuilder<CallStatus>(
                                    valueListenable: _s.status,
                                    builder: (_, st, __) =>
                                        (st == CallStatus.ringing ||
                                                st == CallStatus.connecting)
                                            ? OnlineBadge(
                                                uid: widget.otherUid,
                                                onDark: true)
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
                            child: Center(
                             child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: GlassCapsule(
                               padding: const EdgeInsets.symmetric(
                                   horizontal: 16, vertical: 12),
                               child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: _s.micOn,
                                  builder: (_, on, __) => _ctl(
                                    on
                                        ? Icons.mic_rounded
                                        : Icons.mic_off_rounded,
                                    active: !on,
                                    onTap: _s.toggleMic,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                _ctl(Icons.call_end_rounded,
                                    bg: AppColors.kmRose,
                                    big: true,
                                    onTap: _end),
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
                             ),
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
    return OledBackdrop(
      glowA: kNeonViolet,
      glowB: widget.video ? kNeonPink : kNeonTeal,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(S.incomingCallTitle.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3)),
            const Spacer(),
            SizedBox(
              width: 300,
              height: 300,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  NeonPulseRings(t: _ringPulse, size: 300),
                  NeonAvatar(initial: initial, size: 150),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.otherName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(color: kNeonViolet, blurRadius: 18),
                    ])),
            const SizedBox(height: 10),
            NeonChip(
                label: widget.video ? S.videoCall : S.voiceCall,
                color: widget.video ? kNeonPink : kNeonTeal),
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
                    color: AppColors.kmRose,
                    onTap: _declineIncoming,
                  ),
                  _bigCallBtn(
                    icon: widget.video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    label: S.accept,
                    gradient: const LinearGradient(
                        colors: [kNeonTeal, kNeonViolet],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
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
                    color: (color ?? kNeonTeal).withValues(alpha: 0.6),
                    blurRadius: 26,
                    spreadRadius: 2),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
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
                foregroundColor: AppColors.kmPurple,
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

  /// Absolute Connect Timeout पछि — "Connecting…" अनन्त-कालसम्म देखिनुको
  /// सट्टा प्रस्ट कारण + Hang Up बटन, `_permissionDeniedView()` कै उही
  /// ढाँचामा। कुनै साँचो media/ICE कनेक्शन जोडिन नसकेको (कमजोर नेटवर्क वा
  /// TURN relay पुगेन) प्रस्ट देखियोस्, कालो/स्थिर स्क्रिन होइन।
  Widget _connectFailedView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 56),
            const SizedBox(height: 18),
            Text(
              S.callConnectFailedTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              S.callConnectFailedBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _end,
              icon: const Icon(Icons.call_end_rounded),
              label: Text(S.hangUp),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.kmRose,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
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
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: Center(
        child: ValueListenableBuilder<CallStatus>(
          valueListenable: _s.status,
          builder: (_, st, __) {
            // जोडिनअघि (ringing/connecting) मात्र — "Ring, ring…" जस्तो radar
            // pulse; जोडिएपछि (connected) शान्त, स्थिर avatar।
            final ringing =
                st == CallStatus.ringing || st == CallStatus.connecting;
            return SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (ringing) NeonPulseRings(t: _ringPulse, size: 280),
                  NeonAvatar(initial: initial, size: 120),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _ctl(IconData icon,
      {required VoidCallback onTap,
      Color? bg,
      bool active = false,
      bool big = false,
      bool small = false}) {
    // गाढा ग्लास गोला + नियोन सीमा/चमक (blur बिना — हल्का)। end-call रातो चमक;
    // active (mute/cam off) हुँदा नियोन भरिएको।
    final size = big ? 78.0 : (small ? 44.0 : 64.0);
    final neon = bg ?? kNeonTeal;
    final filled = bg != null || active;
    return SpringTap(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      pressedScale: 0.84,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled
              ? RadialGradient(colors: [
                  neon.withValues(alpha: 0.95),
                  neon.withValues(alpha: 0.6),
                ])
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.14),
                    Colors.white.withValues(alpha: 0.04),
                  ],
                ),
          color: filled ? null : const Color(0xCC0A0A12),
          border: Border.all(
              color: filled
                  ? Colors.white.withValues(alpha: 0.5)
                  : neon.withValues(alpha: 0.55),
              width: 1.2),
          boxShadow: [
            BoxShadow(
                color: neon.withValues(alpha: filled ? 0.6 : 0.22),
                blurRadius: filled ? 24 : 14,
                spreadRadius: filled ? 2 : -1),
          ],
        ),
        child: Icon(icon,
            color: filled && bg == null ? Colors.black : Colors.white,
            size: big ? 34 : (small ? 21 : 27)),
      ),
    );
  }
}


/// Self-view (PiP) — camera बन्द (user ले off गरेको)।
class _PipOff extends StatelessWidget {
  const _PipOff({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 26),
            SizedBox(height: 6),
            Text('Camera off',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Self-view (PiP) — camera सुरु हुँदै (पहिलो frame नआएसम्म)। सानो सादा
/// spinner को सट्टा: चल्ने gradient shimmer + धड्किने camera आइकन + लेखाइ।
/// ८ सेकेन्डसम्म frame नआए "Check camera permission" संकेत।
class _PipLoading extends StatefulWidget {
  const _PipLoading();

  @override
  State<_PipLoading> createState() => _PipLoadingState();
}

class _PipLoadingState extends State<_PipLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        // आइकन हल्का धड्कन (scale 0.92<->1.08) — sine।
        final pulse = 1.0 + 0.08 * math.sin(t * 2 * math.pi);
        return Stack(
          fit: StackFit.expand,
          children: [
            // दायाँतिर सर्ने shimmer band।
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.6 + 3.2 * t, -1),
                  end: Alignment(-0.6 + 3.2 * t, 1),
                  colors: const [
                    Color(0xFF1B1030),
                    Color(0xFF3A2766),
                    Color(0xFF1B1030),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: pulse,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28)),
                      ),
                      child: const Icon(Icons.videocam_rounded,
                          color: Colors.white70, size: 22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      _slow ? 'Check camera permission' : 'Starting camera…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _slow ? const Color(0xFFFFD66B) : Colors.white60,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
