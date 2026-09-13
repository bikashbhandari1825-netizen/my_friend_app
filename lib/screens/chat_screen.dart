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
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_tap.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String requestId;

  /// अर्को व्यक्तिको देखाउने नाम।
  final String workerName;

  const ChatScreen({
    super.key,
    required this.requestId,
    required this.workerName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _canSend = false;
  bool _callBusy = false;
  bool _inCall = false;
  String _myName = '';
  StreamSubscription<Map<String, dynamic>?>? _callWatch;

  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.requestId)
          .collection('messages');

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final can = _controller.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    _loadMyName();
    _watchForIncomingCall();
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

  void _watchForIncomingCall() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    _callWatch = CallService.watch(widget.requestId).listen((c) {
      if (!mounted || _inCall || c == null) return;
      final status = (c['status'] ?? '').toString();
      final callerUid = (c['callerUid'] ?? '').toString();
      // कसैले कल गर्‍यो, त्यो म होइन, अझै जोडिएको छैन → incoming दिखाउने
      if (status == 'ringing' && callerUid.isNotEmpty && callerUid != me) {
        _showIncoming(
          video: (c['mode'] ?? 'audio').toString() == 'video',
          callerName: (c['callerName'] ?? widget.workerName).toString(),
        );
      }
    });
  }

  Future<void> _showIncoming(
      {required bool video, required String callerName}) async {
    _inCall = true;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(video ? Icons.videocam_rounded : Icons.call_rounded,
              color: AppColors.igViolet),
          const SizedBox(width: 8),
          Text(S.incomingCallTitle),
        ]),
        content: Text('$callerName  ·  ${video ? S.videoCall : S.voiceCall}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.decline,
                style: const TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(S.accept),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accept == true) {
      await _openCall(video: video, isCaller: false);
    } else {
      await CallService.resetSignal(widget.requestId);
      _inCall = false;
    }
  }

  Future<void> _startCall({required bool video}) async {
    if (_callBusy || _inCall) return;
    setState(() => _callBusy = true);
    await CallService.resetSignal(widget.requestId);
    setState(() => _callBusy = false);
    await _openCall(video: video, isCaller: true);
    _stampLast(video ? '📹 ${S.videoCall}' : '📞 ${S.voiceCall}');
    _messages.add({
      'senderUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      'type': 'call',
      'mode': video ? 'video' : 'audio',
      'createdAt': FieldValue.serverTimestamp(),
    });
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
        ),
      ),
    );
    _inCall = false;
  }

  @override
  void dispose() {
    _callWatch?.cancel();
    _controller.dispose();
    _scroll.dispose();
    _audioRecorder.dispose();
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

  Future<void> _pickCamera() async {
    try {
      final XFile? p = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 70);
      if (p != null) await _sendImage(await p.readAsBytes());
    } catch (e) {
      _snack('${S.errorWord}: $e');
    }
  }

  Future<void> _pickGallery() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null) await _sendImage(await file.readAsBytes());
    } catch (e) {
      _snack('${S.errorWord}: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) await _sendVoice(path);
    } else {
      if (!await _audioRecorder.hasPermission()) {
        _snack('Microphone अनुमति चाहिन्छ');
        return;
      }
      await _audioRecorder.start(const RecordConfig(), path: 'voice_message');
      setState(() => _isRecording = true);
    }
  }

  Future<void> _sendVoice(String blobUrl) async {
    try {
      final res = await http.get(Uri.parse(blobUrl));
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _messages.add({
        'senderUid': uid,
        'type': 'audio',
        'audioBase64': base64Encode(res.bodyBytes),
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
                  Text(S.activeRecently,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _CallBtn(
            icon: Icons.call_rounded,
            busy: _callBusy,
            onTap: () => _startCall(video: false),
          ),
          _CallBtn(
            icon: Icons.videocam_rounded,
            busy: _callBusy,
            onTap: () => _startCall(video: true),
          ),
          const SizedBox(width: 6),
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
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final id = docs[i].id;
                    final isMe = data['senderUid'] == me;
                    final type = (data['type'] ?? 'text').toString();

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
                      child: Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: _Bubble(
                          isMe: isMe,
                          time: _time(data['createdAt']),
                          child: _content(type, data, isMe, theme),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _inputBar(theme),
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
            icon: Icon(
                _isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                color: _isRecording ? AppColors.danger : AppColors.igOrange),
            onPressed: _toggleRecording,
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

/// AppBar को गोलो कल बटन — सेतो circle + violet icon (high contrast on gradient)।
class _CallBtn extends StatelessWidget {
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;
  const _CallBtn({required this.icon, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SpringTap(
        onTap: busy ? null : onTap,
        pressedScale: 0.82,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.igViolet))
              : Icon(icon, size: 20, color: AppColors.igViolet),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool isMe;
  final String time;
  final Widget child;
  const _Bubble({required this.isMe, required this.time, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: BoxDecoration(
        gradient: isMe ? AppColors.buttonGradient : null,
        color: isMe ? null : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 3),
          Text(time,
              style: TextStyle(
                  fontSize: 9.5,
                  color: isMe
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant)),
        ],
      ),
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
