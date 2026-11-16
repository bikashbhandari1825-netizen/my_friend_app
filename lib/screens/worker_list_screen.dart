// screens/worker_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/worker_avatar.dart';
import 'worker_profile_screen.dart';
import '../widgets/skeleton.dart';

// 13. Worker List Screen (Firestore बाट वास्तविक Approved Workers)
class WorkerListScreen extends StatelessWidget {
  final String serviceName;
  const WorkerListScreen({super.key, required this.serviceName});

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: Border(
              bottom: BorderSide(color: kNeonTeal.withValues(alpha: 0.5))),
          title: Text('$serviceName near you',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('registeredWorkers')
              .where('service', isEqualTo: serviceName)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList();
            }
            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_off, size: 60, color: AppColors.kmMuted),
                    SizedBox(height: 10),
                    Text('No approved workers available in this category yet.',
                        style:
                            TextStyle(color: AppColors.kmMuted, fontSize: 15),
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
                void open() {
                  final workerMap = <String, String>{
                    'uid': data['uid'] ?? '',
                    'name': data['name'] ?? '',
                    'service': data['service'] ?? '',
                    'experience': data['experience'] ?? '',
                    'location': data['location'] ?? '',
                    'price': data['price'] ?? '',
                    'document': data['document'] ?? '',
                    'phone': data['phone'] ?? '',
                    'vehicleDetails': data['vehicleDetails'] ?? '',
                  };
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          WorkerProfileScreen(worker: workerMap),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NeonCard(
                    accent: index == 0 ? kNeonTeal : kNeonViolet,
                    onTap: open,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: SweepGradient(colors: [
                                  kNeonTeal,
                                  kNeonViolet,
                                  kNeonPink,
                                  kNeonTeal
                                ]),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF05070A)),
                                child: WorkerAvatar(
                                    uid: (data['uid'] ?? '').toString(),
                                    size: 50),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((data['name'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    NeonChip(
                                        label:
                                            (data['service'] ?? '').toString(),
                                        color: kNeonBlue),
                                    if ((data['experience'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      NeonChip(
                                          label: '${data['experience']} exp',
                                          color: kNeonPink),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.place_rounded,
                                size: 15, color: kNeonBlue),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text('${data['location'] ?? 'N/A'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.kmMuted,
                                      fontSize: 12.5)),
                            ),
                            Text('${data['price'] ?? 'N/A'}',
                                style: const TextStyle(
                                    color: kNeonTeal,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        NeonActionButton(
                          label: 'View Profile',
                          icon: Icons.person_rounded,
                          color: kNeonTeal,
                          color2: kNeonViolet,
                          filled: true,
                          height: 44,
                          onTap: open,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
