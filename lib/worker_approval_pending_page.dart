// worker_approval_pending_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';
import 'document_verification_page.dart';

class WorkerApprovalPendingPage extends StatefulWidget {
  const WorkerApprovalPendingPage({super.key});

  @override
  State<WorkerApprovalPendingPage> createState() =>
      _WorkerApprovalPendingPageState();
}

class _WorkerApprovalPendingPageState extends State<WorkerApprovalPendingPage> {
  bool _navigating = false;

  void _goToHomeAfterDelay() {
    if (_navigating) return;
    _navigating = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const KaamMitraApp()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Login गर्नुहोस्')));
    }

    return Scaffold(
      backgroundColor: Colors.green.shade700,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: Colors.white));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final status = data['workerVerificationStatus'] ?? 'pending';

            if (status == 'approved') {
              _goToHomeAfterDelay();
              return _buildApprovedAnimation();
            }

            if (status == 'declined') {
              return _buildDeclinedView(context);
            }

            return _buildPendingView();
          },
        ),
      ),
    );
  }

  Widget _buildPendingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              child: Icon(Icons.hourglass_top, size: 50, color: Colors.orange),
            ),
            const SizedBox(height: 30),
            const Text(
              'तपाईंको Request पेश गरिएको छ',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Admin ले हेरेर स्वीकृत गरेपछि, तपाईं एपमा काम गर्न सुरु गर्न सक्नुहुन्छ। कृपया पर्खनुहोस्।',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildDeclinedView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              child: Icon(Icons.cancel, size: 50, color: Colors.red),
            ),
            const SizedBox(height: 30),
            const Text(
              'तपाईंको Request अस्वीकृत गरियो',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'कृपया सही विवरण र सर्टिफिकेटसहित फेरि Submit गर्नुहोस्।',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const DocumentVerificationPage()),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              child: const Text('फेरि Submit गर्नुहोस्',
                  style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovedAnimation() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  size: 100, color: Colors.green),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your request has been accepted!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'तपाईं अब KaamMitra मा काम गर्न सक्नुहुन्छ',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
