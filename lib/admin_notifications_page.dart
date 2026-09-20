// admin_notifications_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminNotificationsPage extends StatelessWidget {
  const AdminNotificationsPage({super.key});

  String _formatTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Notifications'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('adminNotifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text('अहिलेसम्म कुनै Notification छैन।',
                    style: TextStyle(color: Colors.grey)));
          }
          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final isRead = data['read'] ?? false;
              final timestamp = data['createdAt'] as Timestamp?;
              final timeStr =
                  timestamp != null ? _formatTime(timestamp.toDate()) : '';
              return Card(
                color: isRead ? Colors.white : Colors.orange.shade50,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.notifications,
                      color: isRead ? Colors.grey : Colors.deepOrange),
                  title: Text(data['title'] ?? '',
                      style: TextStyle(
                          fontWeight:
                              isRead ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text(data['body'] ?? ''),
                  trailing: Text(timeStr, style: const TextStyle(fontSize: 11)),
                  onTap: () => docs[index].reference.update({'read': true}),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
