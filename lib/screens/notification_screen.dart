// screens/notification_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
                      color: isRead ? Colors.white : Colors.green.shade50,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? Colors.grey.shade300
                              : Colors.green.shade100,
                          child: Icon(Icons.notifications,
                              color: isRead ? Colors.grey : Colors.green),
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
                        onTap: () {
                          docs[index].reference.update({'read': true});
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
