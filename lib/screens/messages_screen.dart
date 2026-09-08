// screens/messages_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';

// 10. Messages List Screen (Firestore बाट वास्तविक Conversation List)
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Messages'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1),
      body: uid == null
          ? const Center(child: Text('Login गर्नुहोस्'))
          : FutureBuilder<DocumentSnapshot>(
              future:
                  FirebaseFirestore.instance.collection('users').doc(uid).get(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final userData =
                    userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final role = userData['role'] ?? 'employer';
                final fieldName =
                    role == 'worker' ? 'workerUid' : 'employerUid';

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('serviceRequests')
                      .where(fieldName, isEqualTo: uid)
                      .where('status', isEqualTo: 'confirmed')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('अहिलेसम्म कुनै Conversation छैन।',
                            style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final requestId = docs[index].id;
                        final otherPersonName = role == 'worker'
                            ? (data['employerName'] ?? 'Employer')
                            : (data['workerName'] ?? 'Worker');
                        return Dismissible(
                          key: Key(requestId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child:
                                const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Conversation'),
                                content: const Text(
                                    'के तपाईं यो पूरा Chat Delete गर्न चाहनुहुन्छ?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red),
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (direction) async {
                            // Chat भित्रका सबै Message पहिले हटाउने
                            final messagesSnap = await FirebaseFirestore
                                .instance
                                .collection('chats')
                                .doc(requestId)
                                .collection('messages')
                                .get();
                            for (final doc in messagesSnap.docs) {
                              await doc.reference.delete();
                            }
                          },
                          child: ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(otherPersonName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(data['service'] ?? ''),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    requestId: requestId,
                                    workerName: otherPersonName,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
