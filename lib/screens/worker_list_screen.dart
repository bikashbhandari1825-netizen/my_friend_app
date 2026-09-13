// screens/worker_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'worker_profile_screen.dart';

// 13. Worker List Screen (Firestore बाट वास्तविक Approved Workers)
class WorkerListScreen extends StatelessWidget {
  final String serviceName;
  const WorkerListScreen({super.key, required this.serviceName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        title: Text('$serviceName near you',
            style: const TextStyle(color: Colors.black, fontSize: 18)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('registeredWorkers')
            .where('service', isEqualTo: serviceName)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No approved workers available in this category yet.',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading:
                      const CircleAvatar(radius: 25, child: Icon(Icons.person)),
                  title: Text(data['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${data['service']} • ${data['experience']} exp'),
                      Text('Location: ${data['location'] ?? 'N/A'}',
                          style: const TextStyle(
                              color: AppColors.igViolet,
                              fontWeight: FontWeight.w500)),
                      Text('Price: ${data['price'] ?? 'N/A'}'),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      final workerMap = <String, String>{
                        'uid': data['uid'] ?? '',
                        'name': data['name'] ?? '',
                        'service': data['service'] ?? '',
                        'experience': data['experience'] ?? '',
                        'location': data['location'] ?? '',
                        'price': data['price'] ?? '',
                        'document': data['document'] ?? '',
                      };
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              WorkerProfileScreen(worker: workerMap),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.igViolet),
                    child: const Text('View Profile',
                        style: TextStyle(color: Colors.white)),
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
