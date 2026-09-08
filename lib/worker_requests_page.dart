// worker_requests_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

class WorkerRequestsPage extends StatelessWidget {
  const WorkerRequestsPage({super.key});

  Future<void> _acceptAtListedPrice(
      BuildContext context, String docId, num price) async {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'confirmed',
      'finalPrice': price,
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request Confirmed भयो!')),
    );
  }

  Future<void> _showCounterOfferDialog(
      BuildContext parentContext, String docId, num currentPrice) async {
    final controller = TextEditingController(text: currentPrice.toString());

    await showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('नयाँ मूल्य प्रस्ताव गर्नुहोस्'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'तपाईंको मूल्य (Rs.)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              final newPrice = num.tryParse(controller.text.trim());
              if (newPrice == null) return;

              Navigator.of(dialogContext).pop();

              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'status': 'pending_employer_approval',
                'workerCounterPrice': newPrice,
              });

              if (!parentContext.mounted) return;
              ScaffoldMessenger.of(parentContext).showSnackBar(
                const SnackBar(
                    content: Text('नयाँ मूल्य Employer लाई पठाइयो।')),
              );
            },
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: uid == null
          ? const Center(child: Text('Login गर्नुहोस्'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .where('workerUid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('अहिलेसम्म कुनै Request आएको छैन।',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final docId = docs[index].id;
                    final status = data['status'] ?? 'pending_worker';
                    final price = data['proposedPrice'] ?? 0;

                    Color statusColor;
                    String statusLabel;
                    switch (status) {
                      case 'confirmed':
                        statusColor = Colors.green;
                        statusLabel = 'Confirmed';
                        break;
                      case 'pending_employer_approval':
                        statusColor = Colors.orange;
                        statusLabel = 'Employer को जवाफको पर्खाइमा';
                        break;
                      case 'declined':
                        statusColor = Colors.red;
                        statusLabel = 'Declined';
                        break;
                      default:
                        statusColor = Colors.blue;
                        statusLabel = 'नयाँ Request';
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
                                      data['employerName'] ?? 'Employer',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                                Chip(
                                  label: Text(statusLabel,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11)),
                                  backgroundColor: statusColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Service: ${data['service'] ?? ''}'),
                            Text('विवरण: ${data['details'] ?? ''}'),
                            Text('प्रस्तावित मूल्य: Rs. $price',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (status == 'pending_worker') ...[
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
                                            workerName: data['employerName'] ??
                                                'Employer',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.message, size: 18),
                                    label: const Text('Message'),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _showCounterOfferDialog(
                                        context, docId, price),
                                    child: const Text('मूल्य बदल्ने'),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green),
                                    onPressed: () => _acceptAtListedPrice(
                                        context, docId, price),
                                    child: const Text('यही मूल्यमा Accept',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
