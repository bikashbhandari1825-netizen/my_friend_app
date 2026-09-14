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

    _pc = await createPeerConnection(_iceServers);

    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video':
          video ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    });
    localRenderer.srcObject = _local;
    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }

    _pc!.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams.first;
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
      }
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
      try {
        await _doc.set(
            {'status': 'ended', 'endedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
        // cleanup candidates (best-effort)
        for (final c in ['offerCandidates', 'answerCandidates']) {
          final q = await _doc.collection(c).get();
          for (final d in q.docs) {
            await d.reference.delete();
          }
        }
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
      for (final c in ['offerCandidates', 'answerCandidates']) {
        final q = await doc.collection(c).get();
        for (final d in q.docs) {
          await d.reference.delete();
        }
      }
      await doc.delete();
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
