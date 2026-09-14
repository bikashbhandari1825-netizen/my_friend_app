// screens/chat_screen.dart
// Messenger-style एक-to-एक chat — Instagram gradient bubbles/header/send button,
// theme-aware input (dark mode मा पनि text देखिने)। Text + Photo + Voice।
// पठाउँदा serviceRequests/{requestId} मा lastMessage/lastMessageAt पनि लेखिन्छ
// (Messages list तुरुन्तै अपडेट होस्)।
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/online_badge.dart';
import '../widgets/spring_tap.dart';
import '../widgets/voice_recorder_bar.dart';
import 'call_screen.dart';
import 'image_preview_screen.dart';

class ChatScreen extends StatefulWidget {
  final String requestId;

  /// अर्को व्यक्तिको देखाउने नाम।
  final String workerName;

  /// caller लाई पहिल्यै थाहा भएको request status (दिए) — पहिलो Firestore
  /// snapshot नआएसम्म call बटन/input bar झिम्किएर लुकेर फेरि नदेखियोस्
  /// (flash) भनेर। caller ले नदिए (null) पहिलो snapshot नआएसम्म सुरक्षित
  /// default (locked) मानिन्छ।
  final String? initialStatus;

  const ChatScreen({
    super.key,
    required this.requestId,
    required this.workerName,
    this.initialStatus,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Call/Message दुवै यही set भित्रको status मा मात्र सक्रिय — Pre-Acceptance
/// Security (worker ले Accept नगरेसम्म) र Post-Completion (काम सकिएपछि)
/// दुवै नियम यही एउटा गेटले पूरा गर्छ। `main_container.dart` कै
/// `_activeJobStatuses` सँगै मिल्ने convention।
const _kChatActiveStatuses = {'accepted', 'confirmed', 'in_progress'};

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _recordingVoice = false;
  bool _canSend = false;
  // requestId कै live status — काम अझै accept नभएको (theoretically यहाँसम्म
  // कहिल्यै आइपुग्नु हुँदैन, तर defence-in-depth) वा completed भइसकेको भए
  // call/message दुवै लक हुन्छन्; पहिलो snapshot नआएसम्म पनि (सुरक्षित
  // default) लक्ड नै मानिन्छ।
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  late String? _requestStatus = widget.initialStatus;
  bool get _chatActive => _kChatActiveStatuses.contains(_requestStatus);
  // कल बटन थिचेपछि CallScreen तुरुन्तै (उही frame मा) push हुन्छ — कुनै
  // network round-trip पर्खिनु पर्दैन, त्यसैले छुट्टै "busy" spinner
  // चाहिँदैन। `_inCall` ले मात्र double-tap (दुइटा CallScreen एकैचोटि
  // push हुनबाट) रोक्छ — SpringTap कै press animation ले tactile
  // feedback दिन्छ।
  bool _inCall = false;
  String _myName = '';
  String? _lastMarkedReadDocId;
  String _otherUid = '';

  DocumentReference<Map<String, dynamic>> get _chatDoc =>
      FirebaseFirestore.instance.collection('chats').doc(widget.requestId);

  CollectionReference<Map<String, dynamic>> get _messages =>
      _chatDoc.collection('messages');

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final can = _controller.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    _loadMyName();
    _markRead();
    _otherPartyUid().then((uid) {
      if (mounted && uid != null) setState(() => _otherUid = uid);
    });
    _statusSub = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _requestStatus = (snap.data()?['status'])?.toString());
    });
  }

  /// यो chat अहिले खुलेको छ भनेर आफ्नो "पढेको समय" बचत गर्ने — Messenger
  /// जस्तै अर्को पक्षले पठाएको पछिल्लो सन्देश मुनि "Seen" देखिन यही चाहिन्छ।
  Future<void> _markRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _chatDoc.set({
        'readBy': {uid: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _loadMyName() async {
    final me = FirebaseAuth.instance.currentUser;
    var name = me?.displayName ?? '';
    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(me?.uid)
          .get();
      final n = (u.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) name = n;
    } catch (_) {}
    if (mounted) setState(() => _myName = name.isEmpty ? 'KaamMitra' : name);
  }

  /// अर्को पक्षको uid — `serviceRequests/{requestId}` बाट। Notification
  /// पठाउन (call सुरु हुनेबित्तिकै backgrounded भए पनि थाहा पाओस्) चाहिन्छ;
  /// आउँदो-कल पत्ता लगाउने काम अब यहाँ होइन, MainContainer कै साझा
  /// (tab-independent) watcher ले गर्छ — त्यसैले यो screen खुला नभए पनि
  /// अर्को tab/screen मा भए पनि कल आएको देखिन्छ।
  Future<String?> _otherPartyUid() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get();
      final data = doc.data();
      if (data == null) return null;
      final me = FirebaseAuth.instance.currentUser?.uid;
      final employerUid = (data['employerUid'] ?? '').toString();
      final workerUid = (data['workerUid'] ?? '').toString();
      if (me == employerUid) return workerUid.isEmpty ? null : workerUid;
      if (me == workerUid) return employerUid.isEmpty ? null : employerUid;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Touch हुनेबित्तिकै तुरुन्तै CallScreen खुल्छ — कुनै Firestore
  /// round-trip (stale-signal reset, अर्को पक्षको uid लुकअप) लाई अब यहाँ
  /// await गरिँदैन। पहिले यी दुवै await हुँदा बटन थिचेदेखि screen देखिनेसम्म
  /// नेटवर्क जति ढिलो भयो त्यति नै ढिलो हुन्थ्यो — अब ती background मा सर्छन्:
  /// stale-signal reset अब `CallSession.start()` भित्रै (CallScreen
  /// पहिल्यै push भइसकेपछि) हुन्छ, र notification पठाउने काम fire-and-forget।
  Future<void> _startCall({required bool video}) async {
    if (_inCall) return;
    unawaited(_notifyOtherPartyOfCall(video));
    await _openCall(video: video, isCaller: true);
    _stampLast(video ? '📹 ${S.videoCall}' : '📞 ${S.voiceCall}');
    _messages.add({
      'senderUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      'type': 'call',
      'mode': video ? 'video' : 'audio',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// अर्को पक्ष अहिले app मै नभए/backgrounded भए पनि थाहा पाओस् भनेर —
  /// real-time signaling त `calls/{requestId}` doc ले नै गर्छ, यो त
  /// additional push/in-app alert मात्र हो, कल screen खोल्नुलाई कहिल्यै
  /// block गर्नु हुँदैन।
  Future<void> _notifyOtherPartyOfCall(bool video) async {
    final otherUid = await _otherPartyUid();
    if (otherUid != null) {
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      createNotificationForUser(
        otherUid,
        S.incomingCallTitle,
        '$_myName  ·  ${video ? S.videoCall : S.voiceCall}',
        data: {
          'requestId': widget.requestId,
          'type': 'incoming_call',
          'mode': video ? 'video' : 'audio',
          // Backgrounded/बन्द एपमा push notification ट्याप गर्दा सिधै साँचो
          // full-screen incoming-call UI मा जान (map मा होइन) यी दुवै
          // चाहिन्छ — Cloud Function ले पनि यी forward गर्नुपर्छ (तल
          // functions/index.js हेर्नुहोस्)।
          'callerName': _myName,
          'callerUid': myUid,
        },
      );
    }
  }

  Future<void> _openCall({required bool video, required bool isCaller}) async {
    _inCall = true;
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          requestId: widget.requestId,
          otherName: widget.workerName,
          myName: _myName,
          video: video,
          isCaller: isCaller,
          otherUid: _otherUid,
        ),
      ),
    );
    _inCall = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _statusSub?.cancel();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _stampLast(String preview) async {
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .set({
        'lastMessage': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _messages.add({
      'senderUid': uid,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _stampLast(text);
  }

  Future<void> _sendImage(Uint8List bytes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _messages.add({
      'senderUid': uid,
      'type': 'image',
      'imageBase64': base64Encode(bytes),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _stampLast('📷 ${S.photo}');
  }

  /// Camera/gallery बाट छानेको तस्बिर — सिधै नपठाई पहिले preview देखाउने,
  /// "Send" थिचेपछि मात्र साँच्चै अपलोड हुने।
  Future<void> _previewThenSend(Uint8List bytes) async {
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImagePreviewScreen(bytes: bytes),
      ),
    );
    if (confirmed == true) await _sendImage(bytes);
  }

  Future<void> _pickCamera() async {
    try {
      final XFile? p = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 85);
      if (p != null) await _previewThenSend(await p.readAsBytes());
    } catch (e) {
      _snack('${S.errorWord}: $e');
    }
  }

  Future<void> _pickGallery() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null) await _previewThenSend(await file.readAsBytes());
    } catch (e) {
      _snack('${S.errorWord}: $e');
    }
  }

  /// Voice-note recorder bar (widgets/voice_recorder_bar.dart) ले नै रेकर्ड
  /// + waveform + preview सबै सम्हाल्छ — यहाँ त प्रयोगकर्ताले Send थिचेपछि
  /// आएको bytes मात्र साँच्चै Firestore मा लेख्ने।
  Future<void> _sendVoiceBytes(Uint8List bytes) async {
    setState(() => _recordingVoice = false);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _messages.add({
        'senderUid': uid,
        'type': 'audio',
        'audioBase64': base64Encode(bytes),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _stampLast('🎤 ${S.voiceMessage}');
    } catch (e) {
      _snack('${S.errorWord}: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _time(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = FirebaseAuth.instance.currentUser?.uid;
    final initial = widget.workerName.trim().isEmpty
        ? '?'
        : widget.workerName.trim()[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: Colors.white24, shape: BoxShape.circle),
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.workerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  _otherUid.isEmpty
                      ? Text(S.activeRecently,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11))
                      : OnlineBadge(uid: _otherUid, onDark: true),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Pre-Acceptance/Post-Completion Security — request active
          // (accepted/confirmed/in_progress) नभएसम्म कल बटन नै नदेखिने।
          if (_chatActive) ...[
            _CallBtn(
              key: const ValueKey('audioCallBtn'),
              icon: Icons.call_rounded,
              onTap: () => _startCall(video: false),
            ),
            _CallBtn(
              key: const ValueKey('videoCallBtn'),
              icon: Icons.videocam_rounded,
              onTap: () => _startCall(video: true),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  _messages.orderBy('createdAt', descending: false).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_rounded,
                            size: 54,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(S.startTheConversation,
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  );
                }
                _jumpToBottom();
                // अर्को पक्षले नयाँ सन्देश पठायो र म यो chat हेर्दै नै छु भने
                // तुरुन्तै "पढेको" म्हार्क गर्ने — Messenger जस्तै live "Seen"।
                final lastDoc = docs.last;
                if (lastDoc.id != _lastMarkedReadDocId &&
                    lastDoc.data()['senderUid'] != me) {
                  _lastMarkedReadDocId = lastDoc.id;
                  _markRead();
                }
                // अर्को पक्षको uid — सन्देश इतिहासबाटै (सबभन्दा पछिल्लो
                // "मैले नपठाएको" सन्देशको sender) निकालिन्छ, अलग Firestore
                // पढाइ नचाहिने गरी।
                final otherUid = docs
                    .map((d) => (d.data()['senderUid'] ?? '').toString())
                    .lastWhere((u) => u.isNotEmpty && u != me,
                        orElse: () => '');

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final id = docs[i].id;
                    final isMe = data['senderUid'] == me;
                    final type = (data['type'] ?? 'text').toString();
                    final isLast = i == docs.length - 1;
                    // लगातार एउटै व्यक्तिका सन्देश Messenger-शैलीमा नजिक-नजिक
                    // देखिने — समूहको पछिल्लोमा मात्र समय देखाउने।
                    final isLastOfGroup = isLast ||
                        docs[i + 1].data()['senderUid'] != data['senderUid'];
                    final isFirstOfGroup = i == 0 ||
                        docs[i - 1].data()['senderUid'] != data['senderUid'];

                    return Dismissible(
                      key: Key(id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.danger),
                      ),
                      confirmDismiss: (_) => _confirmDelete(),
                      onDismissed: (_) => _messages.doc(id).delete(),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(id),
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              builder: (context, t, child) => Opacity(
                                opacity: t,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - t) * 8),
                                  child: child,
                                ),
                              ),
                              child: _Bubble(
                                isMe: isMe,
                                showTail: isLastOfGroup,
                                topMargin: isFirstOfGroup ? 8 : 2,
                                time: isLastOfGroup
                                    ? _time(data['createdAt'])
                                    : null,
                                child: _content(type, data, isMe, theme),
                              ),
                            ),
                          ),
                          if (isMe && isLast)
                            _SeenLabel(
                              chatDoc: _chatDoc,
                              otherUid: otherUid,
                              messageTime: data['createdAt'],
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _chatActive ? _inputBar(theme) : _lockedBanner(theme),
        ],
      ),
    );
  }

  /// Request active नरहेको बेला (Accept हुनुअघि, वा काम completed भइसकेपछि)
  /// इनपुट/कल दुवैको सट्टा देखिने read-only सूचना पट्टी।
  Widget _lockedBanner(ThemeData theme) {
    final completed = _requestStatus == 'completed';
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              completed ? S.chatLockedCompleted : S.contactLockedCaption,
              style: TextStyle(
                  fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
      String type, Map<String, dynamic> data, bool isMe, ThemeData theme) {
    if (type == 'call') {
      final video = (data['mode'] ?? 'audio').toString() == 'video';
      final fg = isMe ? Colors.white : theme.colorScheme.onSurface;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(video ? Icons.videocam_rounded : Icons.call_rounded,
              size: 17, color: fg),
          const SizedBox(width: 6),
          Text(video ? S.videoCall : S.voiceCall,
              style: TextStyle(fontSize: 13, color: fg)),
        ],
      );
    }
    if (type == 'image' && data['imageBase64'] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(base64Decode(data['imageBase64']),
            width: 200, fit: BoxFit.cover),
      );
    }
    if (type == 'audio' && data['audioBase64'] != null) {
      return _VoiceBubble(
          audioBytes: base64Decode(data['audioBase64']), isMe: isMe);
    }
    return Text(
      (data['text'] ?? '').toString(),
      style: TextStyle(
        fontSize: 14.5,
        height: 1.3,
        color: isMe ? Colors.white : theme.colorScheme.onSurface,
      ),
    );
  }

  Future<bool?> _confirmDelete() => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(S.delete),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(S.cancel)),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text(S.delete, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _inputBar(ThemeData theme) {
    if (_recordingVoice) {
      return Container(
        padding: EdgeInsets.fromLTRB(
            8, 6, 8, 6 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: VoiceRecorderBar(
          onSend: _sendVoiceBytes,
          onCancel: () => setState(() => _recordingVoice = false),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, 6, 8, 6 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon:
                const Icon(Icons.camera_alt_rounded, color: AppColors.igViolet),
            onPressed: _pickCamera,
          ),
          IconButton(
            icon: const Icon(Icons.image_rounded, color: AppColors.igPink),
            onPressed: _pickGallery,
          ),
          IconButton(
            icon: const Icon(Icons.mic_rounded, color: AppColors.igOrange),
            onPressed: () => setState(() => _recordingVoice = true),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style:
                  TextStyle(color: theme.colorScheme.onSurface, fontSize: 14.5),
              cursorColor: AppColors.igViolet,
              decoration: InputDecoration(
                hintText: S.typeMessage,
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: 6),
          SpringTap(
            onTap: _canSend ? _sendText : null,
            pressedScale: 0.82,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: _canSend ? AppColors.buttonGradient : null,
                color:
                    _canSend ? null : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                boxShadow: _canSend
                    ? [
                        BoxShadow(
                            color: AppColors.igPink.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ]
                    : null,
              ),
              child: Icon(Icons.send_rounded,
                  size: 20,
                  color: _canSend
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// AppBar को गोलो कल बटन — सेतो circle + violet icon (high contrast on
/// gradient)। थिच्नेबित्तिकै CallScreen instant push हुने भएकोले (कुनै
/// network-bound "busy" पर्खाइ छैन) spinner चाहिँदैन — SpringTap कै
/// press-down/bounce ले नै तुरुन्तै tactile feedback दिन्छ।
class _CallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CallBtn({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SpringTap(
        onTap: onTap,
        pressedScale: 0.82,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: AppColors.igViolet),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool isMe;
  // null = यो समूहको अन्तिम सन्देश होइन — Messenger जस्तै लगातार सन्देशमा
  // समय हरेकमा नदेखाई अन्तिममा मात्र देखाउने।
  final String? time;
  // समूहको अन्तिम सन्देशमा मात्र "tail" कुनो (bottom corner) देखिने; बीचका
  // सन्देश दुवैतिर उस्तै गोलो हुन्छन् (Messenger/WhatsApp कै परिचित ढाँचा)।
  final bool showTail;
  final double topMargin;
  final Widget child;
  const _Bubble({
    required this.isMe,
    required this.time,
    required this.child,
    this.showTail = true,
    this.topMargin = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(top: topMargin, bottom: 1),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: BoxDecoration(
        gradient: isMe ? AppColors.buttonGradient : null,
        color: isMe ? null : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe || !showTail ? 18 : 4),
          bottomRight: Radius.circular(!isMe || !showTail ? 18 : 4),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          child,
          if (time != null) ...[
            const SizedBox(height: 3),
            Text(time!,
                style: TextStyle(
                    fontSize: 9.5,
                    color: isMe
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// पठाइएको पछिल्लो सन्देश मुनि "Seen" — अर्को पक्षले त्यो सन्देश आइसकेपछि
/// यो chat खोलेको (उसको `readBy` timestamp त्यो सन्देशको समयभन्दा पछिको)
/// भेटिए मात्र देखिन्छ, ठ्याक्कै Messenger जस्तै।
class _SeenLabel extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> chatDoc;
  final String otherUid;
  final dynamic messageTime;
  const _SeenLabel({
    required this.chatDoc,
    required this.otherUid,
    required this.messageTime,
  });

  @override
  Widget build(BuildContext context) {
    if (otherUid.isEmpty || messageTime is! Timestamp) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chatDoc.snapshots(),
      builder: (context, snap) {
        final readBy = snap.data?.data()?['readBy'] as Map<String, dynamic>?;
        final readAt = readBy?[otherUid];
        final seen = readAt is Timestamp &&
            !readAt.toDate().isBefore((messageTime as Timestamp).toDate());
        if (!seen) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 4, top: 2),
          child: Text(S.seenWord,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
      },
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  final Uint8List audioBytes;
  final bool isMe;
  const _VoiceBubble({required this.audioBytes, required this.isMe});

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(widget.audioBytes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg =
        widget.isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Icon(
              _playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: fg,
              size: 30),
        ),
        const SizedBox(width: 8),
        Icon(Icons.graphic_eq_rounded, color: fg.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Text(S.voiceMessage, style: TextStyle(fontSize: 12.5, color: fg)),
      ],
    );
  }
}
