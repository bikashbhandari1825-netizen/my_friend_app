// screens/notification_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import 'job_actions.dart';
import '../widgets/skeleton.dart';

// 8. Notifications Screen (Firestore सँग जोडिएको)
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  String _formatTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: S.isNepali ? 'सूचनाहरू' : 'Notifications'),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmText)))
                    : StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('notifications')
                            .where('uid', isEqualTo: uid)
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SkeletonList();
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text('अहिलेसम्म कुनै Notification छैन।',
                                  style: TextStyle(color: AppColors.kmMuted)),
                            );
                          }

                          final docs = snapshot.data!.docs;

                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final data = docs[index].data()
                                  as Map<String, dynamic>;
                              final bool isRead = data['read'] ?? false;
                              final timestamp =
                                  data['createdAt'] as Timestamp?;
                              final timeStr = timestamp != null
                                  ? _formatTime(timestamp.toDate())
                                  : '';

                              return _NotifRow(
                                // notification तुरुन्तै (real-time) आउने/
                                // read-state बदलिने भएकोले list पुनः-
                                // क्रमबद्ध/पुनः-निर्माण हुँदा Flutter ले
                                // सही element सँग सही data जोड्न doc id
                                // कै key चाहिन्छ।
                                key: ValueKey(docs[index].id),
                                title: (data['title'] ?? '').toString(),
                                body: (data['body'] ?? '').toString(),
                                time: timeStr,
                                unread: !isRead,
                                first: index == 0,
                                last: index == docs.length - 1,
                                onTap: () async {
                                  docs[index].reference.update({'read': true});
                                  // requestId भएको notification (जस्तै
                                  // "offer accepted") थिच्दा सिधै त्यही काम
                                  // खोल्ने — push tap गर्दा जस्तै deep-link।
                                  final requestId =
                                      data['requestId'] as String?;
                                  if (requestId == null ||
                                      requestId.isEmpty) {
                                    return;
                                  }
                                  final doc = await FirebaseFirestore.instance
                                      .collection('serviceRequests')
                                      .doc(requestId)
                                      .get();
                                  final jobData = doc.data();
                                  if (jobData == null || !context.mounted) {
                                    return;
                                  }
                                  openJobRoute(context, requestId, jobData);
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
}

/// एउटा notification row — neon-glass card; unread मा teal चमक र बिन्दु।
class _NotifRow extends StatelessWidget {
  final String title;
  final String body;
  final String time;
  final bool unread;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  const _NotifRow({
    super.key,
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
    required this.first,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ring = unread ? kNeonTeal : kNeonViolet;
    return NeonCard(
      accent: ring,
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ring.withValues(alpha: 0.10),
              border: Border.all(color: ring.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                    color: ring.withValues(alpha: unread ? 0.4 : 0.15),
                    blurRadius: 14),
              ],
            ),
            child: Icon(
              unread
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 20,
              color: ring,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w600)),
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
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 13, height: 1.3)),
                if (time.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(time,
                      style: TextStyle(
                          color: ring.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
