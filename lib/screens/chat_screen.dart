// screens/chat_screen.dart
// Text + Photo + Voice सहितको एक-to-एक Chat स्क्रिन।
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

// 11. Chat Screen (Text + Photo + Voice सहित)
class ChatScreen extends StatefulWidget {
  final String requestId;
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
  final TextEditingController _controller = TextEditingController();
  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();

  void _sendTextMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    _controller.clear();

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.requestId)
        .collection('messages')
        .add({
      'senderUid': user?.uid ?? '',
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _sendImageMessage(Uint8List bytes) async {
    final user = FirebaseAuth.instance.currentUser;
    final base64Image = base64Encode(bytes);

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.requestId)
        .collection('messages')
        .add({
      'senderUid': user?.uid ?? '',
      'type': 'image',
      'imageBase64': base64Image,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        await _sendImageMessage(bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('क्यामेरा खोल्न मिलेन: $e')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        await _sendImageMessage(result.files.single.bytes!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('फाइल छान्न मिलेन: $e')),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      if (path != null) {
        await _sendVoiceMessage(path);
      }
    } else {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone अनुमति चाहिन्छ')),
        );
        return;
      }

      await _audioRecorder.start(
        const RecordConfig(),
        path: 'voice_message',
      );
      setState(() => _isRecording = true);
    }
  }

  Future<void> _sendVoiceMessage(String blobUrl) async {
    try {
      final response = await http.get(Uri.parse(blobUrl));
      final base64Audio = base64Encode(response.bodyBytes);
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.requestId)
          .collection('messages')
          .add({
        'senderUid': user?.uid ?? '',
        'type': 'audio',
        'audioBase64': base64Audio,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice Message पठाउन मिलेन: $e')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workerName),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.requestId)
                  .collection('messages')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'सन्देश पठाएर कुराकानी सुरु गर्नुहोस्',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final messageId = docs[index].id;
                    final isMe = data['senderUid'] == currentUid;
                    final type = data['type'] ?? 'text';

                    Widget content;
                    if (type == 'image' && data['imageBase64'] != null) {
                      content = ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          base64Decode(data['imageBase64']),
                          width: 180,
                          fit: BoxFit.cover,
                        ),
                      );
                    } else if (type == 'audio' && data['audioBase64'] != null) {
                      content = _VoiceMessageBubble(
                        audioBytes: base64Decode(data['audioBase64']),
                        isMe: isMe,
                      );
                    } else {
                      content = Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.green.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          data['text'] ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }

                    return Dismissible(
                      key: Key(messageId),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Message'),
                            content: const Text(
                              'के तपाईं यो Message Delete गर्न चाहनुहुन्छ?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) {
                        FirebaseFirestore.instance
                            .collection('chats')
                            .doc(widget.requestId)
                            .collection('messages')
                            .doc(messageId)
                            .delete();
                      },
                      child: Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: content,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined,
                      color: Colors.green),
                  onPressed: _pickFromCamera,
                ),
                IconButton(
                  icon: const Icon(Icons.image_outlined, color: Colors.blue),
                  onPressed: _pickFromGallery,
                ),
                IconButton(
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic_none,
                    color: _isRecording ? Colors.red : Colors.orange,
                  ),
                  onPressed: _toggleRecording,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'मेसेज लेख्नुहोस्...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.green.shade700),
                  onPressed: _sendTextMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceMessageBubble extends StatefulWidget {
  final Uint8List audioBytes;
  final bool isMe;
  const _VoiceMessageBubble({required this.audioBytes, required this.isMe});

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _player.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(widget.audioBytes));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isMe ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle_fill,
                color: Colors.green.shade700, size: 32),
            onPressed: _togglePlay,
          ),
          const Icon(Icons.graphic_eq, color: Colors.grey, size: 20),
          const SizedBox(width: 6),
          const Text('Voice message', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
