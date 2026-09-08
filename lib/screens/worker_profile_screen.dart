// screens/worker_profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// 14. Worker Profile Detail Screen
class WorkerProfileScreen extends StatelessWidget {
  final Map<String, String> worker;
  const WorkerProfileScreen({super.key, required this.worker});

  Future<void> _sendServiceRequest(BuildContext context) async {
    final TextEditingController detailsController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request Service to ${worker['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Service: ${worker['service']}'),
            const SizedBox(height: 10),
            TextField(
              controller: detailsController,
              decoration: const InputDecoration(
                labelText: 'Describe your problem / task',
                border: OutlineInputBorder(),
                hintText: 'e.g., Kitchen pipe leaking',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              if (detailsController.text.trim().isEmpty) return;

              final priceStr = (worker['price'] ?? 'Rs. 500')
                  .replaceAll(RegExp(r'[^0-9]'), '');
              final price = num.tryParse(priceStr) ?? 500;

              final currentUser = FirebaseAuth.instance.currentUser;

              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .add({
                'workerUid': worker['uid'] ?? '',
                'employerUid': currentUser?.uid ?? '',
                'employerName': currentUser?.email ?? 'Employer',
                'workerName': worker['name'] ?? '',
                'service': worker['service'] ?? '',
                'details': detailsController.text.trim(),
                'proposedPrice': price,
                'status': 'pending_worker',
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (!context.mounted) return;
              Navigator.pop(context);

              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Request Sent!'),
                  content: const Text(
                      'Your service request has been sent successfully. The worker will accept it soon!'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Send Request',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(worker['name'] ?? 'Worker Profile'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 60)),
            const SizedBox(height: 15),
            Text(worker['name'] ?? '',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(worker['service'] ?? '',
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      leading:
                          const Icon(Icons.location_on, color: Colors.green),
                      title: const Text('Location'),
                      subtitle: Text(worker['location'] ?? 'N/A'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.work, color: Colors.green),
                      title: const Text('Experience'),
                      subtitle: Text(worker['experience'] ?? 'N/A'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file,
                          color: Colors.blue),
                      title: const Text('Verified Document'),
                      subtitle: Text(worker['document'] ?? 'Available'),
                    ),
                    const Divider(),
                    ListTile(
                      leading:
                          const Icon(Icons.attach_money, color: Colors.green),
                      title: const Text('Starting Price'),
                      subtitle: Text(worker['price'] ?? 'N/A'),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                label: const Text('Request Service',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _sendServiceRequest(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
