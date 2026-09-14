// services/call_service.dart
// पूर्ण in-app WebRTC कल — media flutter_webrtc ले, signaling (offer/answer/ICE)
// Firebase Firestore ले सम्हाल्छ। कुनै external browser / Jitsi छैन।
//
// Firestore:
//   calls/{requestId}            { offer, answer, mode, callerUid, callerName,
//                                  calleeUid, status: ringing|connected|ended }
//   calls/{requestId}/offerCandidates/*   (caller ले लेख्ने)
//   calls/{requestId}/answerCandidates/*  (callee ले लेख्ने)
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// थ्रो हुने custom exception — UI ले यसलाई पक्डेर "अनुमति चाहियो" जस्तो
/// स्पष्ट सन्देश देखाउन सकोस्, कालो/अड्किएको स्क्रिनको सट्टा।
class CallPermissionDenied implements Exception {
  final bool video;
  const CallPermissionDenied(this.video);
  @override
  String toString() => video
      ? 'Camera/microphone permission is required for video calls.'
      : 'Microphone permission is required for calls.';
}

const _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ],
};

enum CallStatus { idle, ringing, connecting, connected, ended }

/// एउटा live कल — CallScreen ले बनाउँछ र नियन्त्रण गर्छ।
class CallSession {
  final String requestId;
  final bool video;

  /// true = यो user ले कल गर्‍यो; false = अर्को पक्षको कल स्वीकार गर्दै।
  final bool isCaller;
  final String myName;

  CallSession({
    required this.requestId,
    required this.video,
    required this.isCaller,
    required this.myName,
  });

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  final status = ValueNotifier<CallStatus>(CallStatus.idle);
  final micOn = ValueNotifier<bool>(true);
  final camOn = ValueNotifier<bool>(true);
  final remoteJoined = ValueNotifier<bool>(false);
  // Video कलमा default speaker-on (Messenger जस्तै — screen हेर्दै हुँदा
  // कान नजिक लैजानु अस्वाभाविक हुन्छ); voice कलमा default earpiece।
  // `start()` भित्र वास्तविक routing सेट हुन्छ।
  final speakerOn = ValueNotifier<bool>(false);
  // Local PiP mirror गर्ने कि नगर्ने — front camera मा mirror सही देखिन्छ,
  // back camera मा मिरर गरे उल्टो/गलत देखिन्छ (यो अघिल्लो एउटा वास्तविक बग थियो)।
  final isFrontCamera = ValueNotifier<bool>(true);

  RTCPeerConnection? _pc;
  MediaStream? _local;
  final _subs = <StreamSubscription>[];
  bool _closed = false;

  // ── ICE candidate race-condition fix ──────────────────────────────────
  // अर्को पक्षको ICE candidate, हाम्रो remote description सेट हुनुअघि नै
  // आइपुग्न सक्छ (Firestore का दुई छुट्टाछुट्टै listener — parent doc को
  // 'answer'/'offer' field र candidates subcollection — कुन पहिले फायर
  // हुन्छ भन्ने कुनै ग्यारेन्टी छैन)। remote description नभई `addCandidate`
  // कल गर्दा silently असफल/exception हुन्छ र त्यो candidate सधैंलाई हराउँछ —
  // ठ्याक्कै यही थियो "कल कहिलेकाहीं नजोडिने/बीचैमा कट्ने" bug को साँचो जड।
  // यहाँ त्यस्ता candidate लाई पर्खाएर राख्ने (buffer), remote description
  // सेट भएपछि मात्र एकैचोटि थप्ने।
  bool _remoteDescSet = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  Future<void> _addRemoteCandidate(RTCIceCandidate c) async {
    if (!_remoteDescSet) {
      _pendingRemoteCandidates.add(c);
      return;
    }
    try {
      await _pc!.addCandidate(c);
    } catch (_) {
      // कहिलेकाहीं ढिलो/duplicate candidate आउँछ — कल तोड्नु भन्दा बेवास्ता गर्ने।
    }
  }

  Future<void> _markRemoteDescSet() async {
    _remoteDescSet = true;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final c in pending) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('calls').doc(requestId);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> start() async {
    // getUserMedia अघि नै स्पष्ट रूपमा अनुमति माग्ने — नत्र अनुमति अस्वीकृत
    // भएमा getUserMedia चुपचाप असफल हुन्छ र UI ले remote/local video कतै
    // नआएको कालो/खाली स्क्रिन मात्र देखाउँछ, प्रयोगकर्तालाई किन थाहै हुँदैन।
    final mic = await Permission.microphone.request();
    final cam =
        video ? await Permission.camera.request() : PermissionStatus.granted;
    if (!mic.isGranted || !cam.isGranted) {
      throw CallPermissionDenied(video);
    }

    await localRenderer.initialize();
    await remoteRenderer.initialize();
    status.value = isCaller ? CallStatus.ringing : CallStatus.connecting;

    // Caller मात्र — अघिल्लो कल (उही requestId) बाट बाँकी रहन सक्ने stale
    // signaling doc/candidates नयाँ offer लेख्नुअघि हटाउने (नत्र पुराना
    // candidate हरू नयाँ listener मा "added" भनेर फेरि आउन सक्छन्)। यो
    // पहिले chat_screen.dart बाट CallScreen नै push गर्नुअघि await हुन्थ्यो
    // — नेटवर्क round-trip सकिउन्जेल call बटन थिचेको केही सेकेन्ड
    // प्रतिक्रियाविहीन देखिन्थ्यो। अहिले CallScreen पहिल्यै (instant)
    // push भइसकेपछि, यहाँ background मै चलेको यो await ले UI लाई छुँदैन।
    if (isCaller) {
      await CallService.resetSignal(requestId);
    }

    _pc = await createPeerConnection(_iceServers);

    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video':
          video ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    });
    // `renderer.srcObject = stream` (synchronous setter) ले native side
    // confirm गर्नुअघि नै फर्किन्छ — त्यही race ले कहिलेकाहीं local/remote
    // preview कालो/खाली नै रहिरहने बग दिन्थ्यो। `setSrcObject()` (awaited)
    // ले टेक्स्चर साँच्चै bind नभएसम्म पर्खन्छ, र trackId पनि स्पष्ट पठाउँछ।
    await localRenderer.setSrcObject(stream: _local);
    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }

    // कल-प्रकार अनुसार सुरुवाती audio routing — video कलमा speaker (screen
    // हेर्दै कान नजिक लैजानु अस्वाभाविक), voice कलमा earpiece। कहिलेकाहीं
    // device/OEM defaults नमिल्न सक्ने भएकोले स्पष्ट रूपमा सेट गर्ने।
    speakerOn.value = video;
    try {
      await Helper.setSpeakerphoneOn(video);
    } catch (_) {}

    _pc!.onTrack = (RTCTrackEvent e) async {
      if (e.streams.isNotEmpty) {
        await remoteRenderer.setSrcObject(stream: e.streams.first);
        remoteJoined.value = true;
        status.value = CallStatus.connected;
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_closed) hangUp(remote: false);
      }
    };

    if (isCaller) {
      await _createOffer();
    } else {
      await _answerOffer();
    }

    // दुवै पक्षले कल end भयो कि सुन्ने
    _subs.add(_doc.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null || data['status'] == 'ended') {
        if (!_closed) hangUp(remote: true);
      }
    }));
  }

  Future<void> _createOffer() async {
    final me = _uid;
    _pc!.onIceCandidate = (c) {
      _doc.collection('offerCandidates').add(c.toMap());
    };

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await _doc.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'mode': video ? 'video' : 'audio',
      'callerUid': me,
      'callerName': myName,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // answer आउने बित्तिकै set गर्ने
    _subs.add(_doc.snapshots().listen((snap) async {
      if (_remoteDescSet) return;
      final data = snap.data();
      final ans = data?['answer'];
      if (ans == null) return;
      try {
        await _pc!.setRemoteDescription(
            RTCSessionDescription(ans['sdp'], ans['type']));
        status.value = CallStatus.connecting;
        await _markRemoteDescSet();
      } catch (_) {}
    }));

    // callee का ICE candidate सुन्ने — remote description नआएसम्म buffer मै।
    _subs.add(_doc.collection('answerCandidates').snapshots().listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final m = ch.doc.data()!;
          _addRemoteCandidate(
              RTCIceCandidate(m['candidate'], m['sdpMid'], m['sdpMLineIndex']));
        }
      }
    }));
  }

  Future<void> _answerOffer() async {
    final me = _uid;
    _pc!.onIceCandidate = (c) {
      _doc.collection('answerCandidates').add(c.toMap());
    };

    final snap = await _doc.get();
    final offer = snap.data()?['offer'];
    if (offer == null) {
      await hangUp(remote: false);
      return;
    }
    await _pc!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']));
    // offer subcollection सुन्नुअघि नै remote description सेट भइसकेको
    // ग्यारेन्टी गर्ने — यहाँबाट पछि आउने candidate सबै तुरुन्तै थपिन्छन्,
    // तर subcollection ले पहिल्यै भएका पुराना doc पनि "added" भनेर फर्काउने
    // भएकोले buffering (caller-side कै उस्तै) यहाँ पनि सुरक्षाको लागि राखिएको।
    await _markRemoteDescSet();

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await _doc.set({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'calleeUid': me,
      // "connected" भन्नु साँचो होइन — signaling मात्र पूरा भएको हो, ICE
      // अझै जोडिँदै छ। साँचो जोडिएको त माथि नै `onTrack`/`onConnectionState`
      // ले `status` (local ValueNotifier) मार्फत managed छ। Firestore कै यो
      // doc-level status चाहिं अरूले (incoming-call watcher) "अब ringing
      // होइन" भनेर छुट्याउन प्रयोग गर्छन् — त्यसैले 'connecting' नै सही।
      'status': 'connecting',
    }, SetOptions(merge: true));

    // caller का ICE candidate सुन्ने
    _subs.add(_doc.collection('offerCandidates').snapshots().listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final m = ch.doc.data()!;
          _addRemoteCandidate(
              RTCIceCandidate(m['candidate'], m['sdpMid'], m['sdpMLineIndex']));
        }
      }
    }));
  }

  void toggleMic() {
    micOn.value = !micOn.value;
    for (final t in _local?.getAudioTracks() ?? []) {
      t.enabled = micOn.value;
    }
  }

  void toggleCam() {
    camOn.value = !camOn.value;
    for (final t in _local?.getVideoTracks() ?? []) {
      t.enabled = camOn.value;
    }
  }

  Future<void> switchCamera() async {
    try {
      final t = _local?.getVideoTracks();
      if (t != null && t.isNotEmpty) {
        await Helper.switchCamera(t.first);
        isFrontCamera.value = !isFrontCamera.value;
      }
    } catch (_) {}
  }

  /// Speaker (loudspeaker/hands-free) ⇄ earpiece — flutter_webrtc कै native
  /// audio-routing (कुनै अतिरिक्त package नचाहिने), त्यसैले तुरुन्तै र भरपर्दो।
  Future<void> toggleSpeaker() async {
    speakerOn.value = !speakerOn.value;
    try {
      await Helper.setSpeakerphoneOn(speakerOn.value);
    } catch (_) {}
  }

  /// कल समाप्त। [remote] = अर्को पक्षले काटेको (त्यसो भए हामी signal नलेख्ने)।
  Future<void> hangUp({bool remote = false}) async {
    if (_closed) return;
    _closed = true;
    status.value = CallStatus.ended;

    for (final s in _subs) {
      await s.cancel();
    }
    try {
      for (final t in _local?.getTracks() ?? []) {
        await t.stop();
      }
      await _local?.dispose();
      await _pc?.close();
    } catch (_) {}

    if (!remote) {
      // यो पूरै UI pop भइसकेपछि (background मा, CallScreen.dispose() बाट
      // fire-and-forget) चल्छ — त्यसैले ढिलो भए पनि केही touch नगर्ने। तैपनि
      // छिटो र हल्का राख्न सबै candidate delete एउटै batched write मा
      // (parallel read + एक commit), पहिले जस्तो हरेक doc लाई छुट्टाछुट्टै
      // await गर्दै (candidate जति धेरै, त्यति धेरै sequential round-trip —
      // ठ्याक्कै यही थियो "hang-up पछि केही सेकेन्ड
      // अड्किने"/ढिलो हुनुको साँचो जड)।
      try {
        final results = await Future.wait([
          _doc.collection('offerCandidates').get(),
          _doc.collection('answerCandidates').get(),
        ]);
        final batch = FirebaseFirestore.instance.batch();
        batch.set(
            _doc,
            {'status': 'ended', 'endedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
        for (final q in results) {
          for (final d in q.docs) {
            batch.delete(d.reference);
          }
        }
        await batch.commit();
      } catch (_) {}
    }

    try {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}

/// Chat header बाट कल सुरु गर्दा signal doc reset गर्ने helper।
class CallService {
  CallService._();

  static Future<void> resetSignal(String requestId) async {
    final doc = FirebaseFirestore.instance.collection('calls').doc(requestId);
    try {
      // दुई subcollection parallel मा पढ्ने, अनि सबै delete एउटै batch मा
      // commit गर्ने — candidate जति भए पनि नेटवर्क round-trip एउटै (धेरै
      // sequential awaited delete भन्दा धेरै छिटो)।
      final results = await Future.wait([
        doc.collection('offerCandidates').get(),
        doc.collection('answerCandidates').get(),
      ]);
      final batch = FirebaseFirestore.instance.batch();
      for (final q in results) {
        for (final d in q.docs) {
          batch.delete(d.reference);
        }
      }
      batch.delete(doc);
      await batch.commit();
    } catch (_) {}
  }

  /// यो request मा अहिले ringing/connected कल छ? (callee लाई देखाउन)
  static Stream<Map<String, dynamic>?> watch(String requestId) =>
      FirebaseFirestore.instance
          .collection('calls')
          .doc(requestId)
          .snapshots()
          .map((s) => s.data());
}
