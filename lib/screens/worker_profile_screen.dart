// screens/worker_profile_screen.dart
// ग्राहकले कामदारको विवरण हेर्ने स्क्रिन — Instagram-style gradient background,
// भित्रको सेतो card पढ्न सजिलो।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/worker_stats.dart';
import 'portfolio_screen.dart';

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
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.igViolet,
                foregroundColor: Colors.white),
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
      backgroundColor: Colors.transparent,
      appBar: gradientAppBar(worker['name'] ?? 'Worker Profile'),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded,
                      size: 58, color: AppColors.igViolet),
                ),
                const SizedBox(height: 14),
                Text(worker['name'] ?? '',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                Text(worker['service'] ?? '',
                    style:
                        const TextStyle(fontSize: 15, color: Colors.white70)),
                const SizedBox(height: 8),
                WorkerRatingBadge(uid: worker['uid'] ?? '', onDark: true),
                const SizedBox(height: 20),
                Card(
                  color: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        _row(Icons.location_on_rounded, 'Location',
                            worker['location'] ?? 'N/A'),
                        const Divider(height: 1),
                        _row(Icons.work_rounded, 'Experience',
                            worker['experience'] ?? 'N/A'),
                        const Divider(height: 1),
                        _row(Icons.verified_user_rounded, 'Verified document',
                            'Available'),
                        const Divider(height: 1),
                        _row(Icons.payments_rounded, 'Starting price',
                            worker['price'] ?? 'N/A'),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.photo_library_rounded,
                              color: AppColors.igViolet),
                          title: Text(S.workPortfolio),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PortfolioScreen(
                                  workerUid: worker['uid'] ?? ''),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  label: 'Request Service',
                  icon: Icons.send_rounded,
                  onPressed: () => _sendServiceRequest(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, String subtitle) => ListTile(
        leading: Icon(icon, color: AppColors.igViolet),
        title: Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: Text(subtitle),
      );
}
