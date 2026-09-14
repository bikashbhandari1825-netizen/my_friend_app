// screens/messages_screen.dart
// Messenger-style कुराकानी सूची — gradient avatar + नाम + पछिल्लो सन्देश + समय।
// tap गर्दा त्यही व्यक्तिसँगको ChatScreen खुल्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_tap.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static const _chatStatuses = {
    'accepted',
    'confirmed',
    'in_progress',
    'completed',
  };

  final _uid = FirebaseAuth.instance.currentUser?.uid;

  // दुवै stream एकपटक मात्र subscribe — tab फर्किंदा वा rebuild मा spinner नआओस्।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? '__none__')
          .snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _reqStream;
  String? _reqField;

  Stream<QuerySnapshot<Map<String, dynamic>>> _requestsStream(String field) {
    if (_reqField != field || _reqStream == null) {
      _reqField = field;
      _reqStream = FirebaseFirestore.instance
          .collection('serviceRequests')
          .where(field, isEqualTo: _uid)
          .snapshots();
    }
    return _reqStream!;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(S.messages,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
          child: uid == null
              ? const Center(
                  child: Text('Login गर्नुहोस्',
                      style: TextStyle(color: Colors.white)))
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _userStream,
                  builder: (context, userSnap) {
                    final role = (userSnap.data?.data()?['role'] ?? 'employer')
                        .toString();
                    final field =
                        role == 'worker' ? 'workerUid' : 'employerUid';

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _requestsStream(field),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white));
                        }
                        final rows = (snap.data?.docs ?? []).where((d) {
                          return _chatStatuses
                              .contains((d.data()['status'] ?? '').toString());
                        }).toList()
                          ..sort((a, b) {
                            final ta = a.data()['lastMessageAt'] ??
                                a.data()['createdAt'];
                            final tb = b.data()['lastMessageAt'] ??
                                b.data()['createdAt'];
                            if (ta is Timestamp && tb is Timestamp) {
                              return tb.compareTo(ta);
                            }
                            return 0;
                          });

                        if (rows.isEmpty) {
                          return _empty();
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final d = rows[i].data();
                            final id = rows[i].id;
                            final name = (role == 'worker'
                                    ? (d['employerName'] ?? 'Customer')
                                    : (d['workerName'] ?? 'Worker'))
                                .toString();
                            final rowStatus = (d['status'] ?? '').toString();
                            final last =
                                (d['lastMessage'] ?? d['service'] ?? '')
                                    .toString();
                            final unread =
                                (d['lastSenderUid'] ?? '').toString() != uid &&
                                    (d['lastMessage'] ?? '')
                                        .toString()
                                        .isNotEmpty;
                            return _ChatRow(
                              name: name,
                              snippet: last,
                              time: _fmt(d['lastMessageAt'] ?? d['createdAt']),
                              unread: unread,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                      requestId: id,
                                      workerName: name,
                                      initialStatus: rowStatus),
                                ),
                              ),
                              onDelete: () => _deleteChat(context, id),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 60, color: Colors.white70),
            const SizedBox(height: 14),
            Text(S.noConversationsYet,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(S.startTheConversation,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  static String _fmt(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    }
    final diff = now.difference(d).inDays;
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d';
    return '${d.day}/${d.month}';
  }

  Future<void> _deleteChat(BuildContext context, String requestId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.deleteChat),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final msgs = await FirebaseFirestore.instance
        .collection('chats')
        .doc(requestId)
        .collection('messages')
        .get();
    for (final m in msgs.docs) {
      await m.reference.delete();
    }
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(requestId)
          .set({
        'lastMessage': FieldValue.delete(),
        'lastMessageAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

class _ChatRow extends StatelessWidget {
  final String name;
  final String snippet;
  final String time;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatRow({
    required this.name,
    required this.snippet,
    required this.time,
    required this.unread,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Dismissible(
      key: Key('chat_$name$snippet$time'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: SpringTap(
        onTap: onTap,
        pressedScale: 0.97,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  shape: BoxShape.circle,
                ),
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.black87)),
                        ),
                        Text(time,
                            style: TextStyle(
                                fontSize: 11,
                                color: unread
                                    ? AppColors.igViolet
                                    : Colors.black45,
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(snippet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color:
                                      unread ? Colors.black87 : Colors.black54,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w400)),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                                gradient: AppColors.buttonGradient,
                                shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
