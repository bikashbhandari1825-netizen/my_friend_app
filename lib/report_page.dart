// report_page.dart
import 'main.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'theme/app_theme.dart';

// मुख्य Report Options पेज (Bullying, Scam, 18+ Content छान्ने ठाउँ)
class ReportOptionsPage extends StatelessWidget {
  const ReportOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report a Problem'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.red),
            title: const Text('Bullying, Harassment or Abuse'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const BullyingReportPage()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.report_problem, color: Colors.orange),
            title: const Text('Scam Fraud'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ScamReportPage()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.purple),
            title: const Text(
                'Problem involving sexually explicit or 18+ content'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ContentReportPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

// साझा फंक्सन: Firestore मा report पठाउने
Future<void> _submitReport({
  required BuildContext context,
  required String category,
  required String details,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('reports').add({
      'uid': user?.uid,
      'email': user?.email,
      'category': category,
      'details': details,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await createNotification(
      'Report Submitted',
      '$category सम्बन्धी रिपोर्ट Admin लाई पठाइयो।',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('तपाईंको रिपोर्ट Admin लाई पठाइयो।')),
    );
    Navigator.popUntil(context, (route) => route.isFirst);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('त्रुटि: $e')),
    );
  }
}

// १. Bullying, Harassment or Abuse Report पेज
class BullyingReportPage extends StatelessWidget {
  const BullyingReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppColors.igViolet,
        foregroundColor: Colors.white,
        title: const Text('Back'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Person being harassed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _submitReport(
                  context: context,
                  category: 'Bullying, Harassment or Abuse',
                  details: 'Me',
                ),
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                label: const Text('Me', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.igViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _submitReport(
                  context: context,
                  category: 'Bullying, Harassment or Abuse',
                  details: 'A friend',
                ),
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                label: const Text('A friend',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.igViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// २. Scam Fraud Report पेज
class ScamReportPage extends StatefulWidget {
  const ScamReportPage({super.key});

  @override
  State<ScamReportPage> createState() => _ScamReportPageState();
}

class _ScamReportPageState extends State<ScamReportPage> {
  String? _selectedIssue;
  final List<String> _issues = [
    'Fake payment request',
    'Worker asked for money before job',
    'Fake profile or documents',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.igViolet,
        foregroundColor: Colors.white,
        title: const Text('Scam Fraud'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'समस्या छान्नुहोस्',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._issues.map((issue) => RadioListTile<String>(
                  title: Text(issue),
                  value: issue,
                  groupValue: _selectedIssue,
                  activeColor: AppColors.igViolet,
                  onChanged: (val) => setState(() => _selectedIssue = val),
                )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedIssue == null
                    ? null
                    : () => _submitReport(
                          context: context,
                          category: 'Scam Fraud',
                          details: '${_selectedIssue!} - Me',
                        ),
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                label: const Text('Me', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.igViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedIssue == null
                    ? null
                    : () => _submitReport(
                          context: context,
                          category: 'Scam Fraud',
                          details: '${_selectedIssue!} - A friend',
                        ),
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                label: const Text('A friend',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.igViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ३. 18+ Content Report पेज
class ContentReportPage extends StatelessWidget {
  const ContentReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.igViolet,
        foregroundColor: Colors.white,
        title: const Text('Report Content'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sexually explicit or 18+ content',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'यदि तपाईंले यस्तो सामग्री भेट्टाउनुभयो भने, कृपया Report गर्नुहोस्। यो सिधै Admin लाई पठाइनेछ।',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _submitReport(
                  context: context,
                  category: '18+ Content',
                  details: 'Reported via app',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.igViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Submit',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
