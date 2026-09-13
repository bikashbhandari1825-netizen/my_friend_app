// screens/notification_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
    return Scaffold(
      appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1),
      body: uid == null
          ? const Center(child: Text('Login गर्नुहोस्'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('uid', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('अहिलेसम्म कुनै Notification छैन।',
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final bool isRead = data['read'] ?? false;
                    final timestamp = data['createdAt'] as Timestamp?;
                    final timeStr = timestamp != null
                        ? _formatTime(timestamp.toDate())
                        : '';

                    return Card(
                      // notification तुरुन्तै (real-time) आउने/read-state
                      // बदलिने भएकोले list पुनः-क्रमबद्ध/पुनः-निर्माण हुँदा
                      // Flutter ले सही element सँग सही data जोड्न doc id कै
                      // key चाहिन्छ।
                      key: ValueKey(docs[index].id),
                      color: isRead
                          ? Colors.white
                          : AppColors.igViolet.withValues(alpha: 0.06),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? Colors.grey.shade300
                              : AppColors.igViolet.withValues(alpha: 0.15),
                          child: Icon(Icons.notifications,
                              color: isRead ? Colors.grey : AppColors.igViolet),
                        ),
                        title: Text(data['title'] ?? '',
                            style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold)),
                        subtitle: Text(data['body'] ?? ''),
                        trailing: Text(timeStr,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        onTap: () async {
                          docs[index].reference.update({'read': true});
                          // requestId भएको notification (जस्तै "offer
                          // accepted") थिच्दा सिधै त्यही काम खोल्ने —
                          // push tap गर्दा जस्तै deep-link।
                          final requestId = data['requestId'] as String?;
                          if (requestId == null || requestId.isEmpty) return;
                          final doc = await FirebaseFirestore.instance
                              .collection('serviceRequests')
                              .doc(requestId)
                              .get();
                          final jobData = doc.data();
                          if (jobData == null || !context.mounted) return;
                          openJobRoute(context, requestId, jobData);
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
