// screens/notification_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'job_actions.dart';

// 8. Notifications Screen (Firestore सँग जोडिएको)
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  String _formatTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topRight, AppColors.kmOrangeDeep),
        KmOrb(Alignment.bottomLeft, AppColors.kmPurple),
      ],
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
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.kmTeal));
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
                                const SizedBox(height: 4),
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

/// एउटा notification row — timeline glow ring node + title/body + समय,
/// साइड-रेखा (मोकअप कै "nd"/timeline) सहित।
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
    final ringColor = unread ? AppColors.kmPurple : AppColors.kmTeal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: first ? 23 : 0,
                      bottom: last ? 23 : 0,
                      child: Container(width: 2, color: Colors.white12),
                    ),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.kmSurface,
                        border: Border.all(
                            color: ringColor.withValues(alpha: 0.55)),
                        boxShadow: [
                          BoxShadow(
                              color: ringColor.withValues(alpha: 0.3),
                              blurRadius: 16),
                        ],
                      ),
                      child: Icon(
                        unread
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        size: 18,
                        color: ringColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(
                                    color: AppColors.kmText,
                                    fontSize: 16,
                                    fontWeight: unread
                                        ? FontWeight.w800
                                        : FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(body,
                                style: const TextStyle(
                                    color: AppColors.kmMuted, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(time,
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
