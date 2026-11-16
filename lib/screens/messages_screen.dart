// screens/messages_screen.dart
// Messenger-style कुराकानी सूची — gradient avatar + नाम + पछिल्लो सन्देश + समय।
// tap गर्दा त्यही व्यक्तिसँगको ChatScreen खुल्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/spring_tap.dart';
import 'chat_screen.dart';
import '../widgets/skeleton.dart';

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

    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: S.messages),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmText)))
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _userStream,
                        builder: (context, userSnap) {
                          final role =
                              (userSnap.data?.data()?['role'] ?? 'employer')
                                  .toString();
                          final field =
                              role == 'worker' ? 'workerUid' : 'employerUid';

                          return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: _requestsStream(field),
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return const SkeletonList();
                              }
                              final rows = (snap.data?.docs ?? []).where((d) {
                                return _chatStatuses.contains(
                                    (d.data()['status'] ?? '').toString());
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
                                padding: const EdgeInsets.fromLTRB(
                                    16, 14, 16, 24),
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final d = rows[i].data();
                                  final id = rows[i].id;
                                  final name = (role == 'worker'
                                          ? (d['employerName'] ?? 'Customer')
                                          : (d['workerName'] ?? 'Worker'))
                                      .toString();
                                  final rowStatus =
                                      (d['status'] ?? '').toString();
                                  final last = (d['lastMessage'] ??
                                          d['service'] ??
                                          '')
                                      .toString();
                                  final unread =
                                      (d['lastSenderUid'] ?? '').toString() !=
                                              uid &&
                                          (d['lastMessage'] ?? '')
                                              .toString()
                                              .isNotEmpty;
                                  return _ChatRow(
                                    name: name,
                                    snippet: last,
                                    time: _fmt(
                                        d['lastMessageAt'] ?? d['createdAt']),
                                    unread: unread,
                                    bg: KmListTile.gradients[
                                        i % KmListTile.gradients.length],
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
            ],
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
                size: 60, color: AppColors.kmMuted),
            const SizedBox(height: 14),
            Text(S.noConversationsYet,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(S.startTheConversation,
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 12)),
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
    final ok = await showKmDialog<bool>(
      context: context,
      title: S.deleteChat,
      icon: Icons.delete_outline_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: S.delete,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
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
  final Gradient bg;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatRow({
    required this.name,
    required this.snippet,
    required this.time,
    required this.unread,
    required this.bg,
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
          color: AppColors.kmPink.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(26),
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
        child: NeonCard(
          accent: unread ? kNeonTeal : kNeonViolet,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                      colors: [kNeonTeal, kNeonViolet, kNeonPink, kNeonTeal]),
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0xFF05070A)),
                  child: Text(initial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 20)),
                ),
              ),
              const SizedBox(width: 13),
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
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.white)),
                        ),
                        Text(time,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    unread ? kNeonTeal : AppColors.kmMuted,
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(snippet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: unread
                                      ? AppColors.kmText
                                      : AppColors.kmMuted,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                                color: kNeonTeal,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: kNeonTeal.withValues(alpha: 0.7),
                                      blurRadius: 8),
                                ]),
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
