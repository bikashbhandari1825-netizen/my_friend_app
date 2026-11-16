// screens/salon_inbox_screen.dart
//
// Salon मालिकको सन्देश-सूची — ग्राहकहरूले पठाएका chat (`salon_chats`)।
// ट्याप गर्दा साझा `ChatScreen` (message + call + video call) खुल्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/salon_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_common.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/skeleton.dart';

class SalonInboxScreen extends StatelessWidget {
  final String salonId;
  const SalonInboxScreen({super.key, required this.salonId});

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: KmScreenHeader(title: 'Customer messages'),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('salon_chats')
                      .where('salonId', isEqualTo: salonId)
                      .limit(100)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Center(
                          child: Text('Could not load messages.',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }
                    if (!snap.hasData) {
                      return const SkeletonList();
                    }
                    final docs = [...snap.data!.docs]..sort((a, b) {
                        Timestamp? t(QueryDocumentSnapshot<Map<String, dynamic>> d) {
                          final x = d.data()['lastMessageAt'] ??
                              d.data()['createdAt'];
                          return x is Timestamp ? x : null;
                        }

                        final ta = t(a);
                        final tb = t(b);
                        if (ta == null && tb == null) return 0;
                        if (ta == null) return 1;
                        if (tb == null) return -1;
                        return tb.compareTo(ta);
                      });
                    if (docs.isEmpty) {
                      return const Center(
                          child: Text('No customer messages yet.',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final data = d.data();
                        final name =
                            (data['customerName'] ?? 'Customer').toString();
                        final last = (data['lastMessage'] ?? '').toString();
                        return salonCard(
                          child: InkWell(
                            onTap: () =>
                                openSalonChatAsOwner(context, d.id, data),
                            child: Row(
                              children: [
                                const Icon(Icons.chat_bubble_rounded,
                                    color: AppColors.kmTeal),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(
                                              color: AppColors.kmText,
                                              fontWeight: FontWeight.w800)),
                                      if (last.isNotEmpty)
                                        Text(last,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: AppColors.kmMuted,
                                                fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    color: AppColors.kmMuted),
                              ],
                            ),
                          ),
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
