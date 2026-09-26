// admin_notifications_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

class AdminNotificationsPage extends StatelessWidget {
  const AdminNotificationsPage({super.key});

  String _formatTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: 'Admin Notifications'),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('adminNotifications')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.kmOrange));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_none_rounded,
                                size: 56, color: AppColors.kmMuted),
                            const SizedBox(height: 12),
                            Text('अहिलेसम्म कुनै Notification छैन।',
                                style: const TextStyle(
                                    color: AppColors.kmMuted)),
                          ],
                        ),
                      );
                    }
                    final docs = snapshot.data!.docs;
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final data =
                            docs[index].data() as Map<String, dynamic>;
                        final isRead = data['read'] ?? false;
                        final timestamp = data['createdAt'] as Timestamp?;
                        final timeStr = timestamp != null
                            ? _formatTime(timestamp.toDate())
                            : '';
                        return GlassPanel(
                          radius: 18,
                          padding: const EdgeInsets.all(14),
                          fill: isRead
                              ? null
                              : AppColors.kmOrange.withValues(alpha: 0.08),
                          border: isRead
                              ? null
                              : AppColors.kmOrange.withValues(alpha: 0.4),
                          onTap: () =>
                              docs[index].reference.update({'read': true}),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: isRead
                                      ? null
                                      : AppColors.kmCtaGradient,
                                  color: isRead
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : null,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.notifications_rounded,
                                    size: 19,
                                    color: isRead
                                        ? AppColors.kmMuted
                                        : AppColors.kmInk),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(data['title'] ?? '',
                                        style: TextStyle(
                                            color: AppColors.kmText,
                                            fontWeight: isRead
                                                ? FontWeight.w500
                                                : FontWeight.w700,
                                            fontSize: 14.5)),
                                    const SizedBox(height: 3),
                                    Text(data['body'] ?? '',
                                        style: const TextStyle(
                                            color: AppColors.kmMuted,
                                            fontSize: 12.5)),
                                    const SizedBox(height: 6),
                                    Text(timeStr,
                                        style: const TextStyle(
                                            color: AppColors.kmMuted,
                                            fontSize: 10.5)),
                                  ],
                                ),
                              ),
                            ],
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
