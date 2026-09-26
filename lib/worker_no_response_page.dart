// worker_no_response_page.dart
import 'main.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

class WorkerNoResponsePage extends StatefulWidget {
  const WorkerNoResponsePage({super.key});

  @override
  State<WorkerNoResponsePage> createState() => _WorkerNoResponsePageState();
}

class _WorkerNoResponsePageState extends State<WorkerNoResponsePage> {
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _isSending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('supportMessages').add({
        'uid': user?.uid,
        'email': user?.email,
        'topic': 'Worker Don\'t Response',
        'message': _messageController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await createNotification(
        'Support Message Sent',
        'तपाईंको सन्देश Admin लाई पठाइयो।',
      );

      if (!mounted) return;
      _messageController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('तपाईंको सन्देश पठाइयो। Admin ले चाँडै जवाफ दिनेछ।')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटि: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KmScreenHeader(title: "Worker Don't Response"),
                const SizedBox(height: 24),
                const Text(
                  'यदि तपाईंले बुक गर्नुभएको कामदारले जवाफ दिइरहनुभएको छैन भने, यहाँबाट सिधै Admin लाई सन्देश पठाउनुहोस्।',
                  style: TextStyle(fontSize: 15, color: AppColors.kmMuted),
                ),
                const SizedBox(height: 24),
                GlassPanel(
                  radius: 16,
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          gradient: AppColors.kmCtaGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.message_rounded,
                            color: AppColors.kmInk, size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Write a support',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.kmText),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageController,
                  maxLines: 5,
                  style: const TextStyle(color: AppColors.kmText),
                  decoration: kmInputDecoration('', hint: 'Enter your message'),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: KmCtaButton(
                    label: 'Send',
                    icon: Icons.send_rounded,
                    loading: _isSending,
                    expand: false,
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
