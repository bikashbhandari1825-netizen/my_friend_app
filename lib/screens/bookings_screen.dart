// screens/bookings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';

// 9. Bookings Screen (Firestore सँग जोडिएको, Counter-offer Accept/Decline सहित)
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  Future<void> _acceptCounterOffer(
      BuildContext context, String docId, num counterPrice) async {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'confirmed',
      'finalPrice': counterPrice,
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking Confirmed भयो!')),
    );
  }

  Future<void> _declineRequest(BuildContext context, String docId) async {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({'status': 'declined'});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Request अस्वीकृत गरियो।'),
          backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings & Requests'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          bottom: const TabBar(
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.green,
            tabs: [Tab(text: 'Active/Pending'), Tab(text: 'Completed')],
          ),
        ),
        body: uid == null
            ? const Center(child: Text('Login गर्नुहोस्'))
            : TabBarView(
                children: [
                  // Tab 1: Active/Pending
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('serviceRequests')
                        .where('employerUid', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final allDocs = snapshot.data?.docs ?? [];
                      final docs = allDocs.where((d) {
                        final status =
                            (d.data() as Map<String, dynamic>)['status'];
                        return status != 'declined';
                      }).toList();

                      if (docs.isEmpty) {
                        return const Center(
                            child: Text('No active bookings yet',
                                style: TextStyle(color: Colors.grey)));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          final docId = docs[index].id;
                          final status = data['status'] ?? 'pending_worker';
                          final proposedPrice = data['proposedPrice'] ?? 0;
                          final counterPrice = data['workerCounterPrice'];

                          Color statusColor;
                          String statusLabel;
                          switch (status) {
                            case 'confirmed':
                              statusColor = Colors.green;
                              statusLabel = 'Confirmed';
                              break;
                            case 'pending_employer_approval':
                              statusColor = Colors.orange;
                              statusLabel = 'नयाँ मूल्य आयो!';
                              break;
                            default:
                              statusColor = Colors.blue;
                              statusLabel = 'Worker को जवाफको पर्खाइमा';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${data['workerName'] ?? 'Worker'} (${data['service'] ?? ''})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          statusLabel,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                          ),
                                        ),
                                        backgroundColor: statusColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('विवरण: ${data['details'] ?? ''}'),
                                  Text('सुरुको मूल्य: Rs. $proposedPrice'),
                                  if (status == 'pending_employer_approval' &&
                                      counterPrice != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Worker को प्रस्तावित मूल्य: Rs. $counterPrice',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (status == 'confirmed')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'अन्तिम मूल्य: Rs. ${data['finalPrice'] ?? proposedPrice}',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (status ==
                                      'pending_employer_approval') ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton(
                                          onPressed: () =>
                                              _declineRequest(context, docId),
                                          child: const Text(
                                            'Decline',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                          ),
                                          onPressed: () => _acceptCounterOffer(
                                            context,
                                            docId,
                                            counterPrice ?? 0,
                                          ),
                                          child: const Text(
                                            'Accept',
                                            style:
                                                TextStyle(color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (status == 'confirmed')
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ChatScreen(
                                                requestId: docId,
                                                workerName:
                                                    data['workerName'] ??
                                                        'Worker',
                                              ),
                                            ),
                                          );
                                        },
                                        icon:
                                            const Icon(Icons.message, size: 18),
                                        label: const Text('Message'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),

                  // Tab 2: Completed
                  const Center(
                    child: Text(
                      'No completed bookings yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
