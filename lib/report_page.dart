// report_page.dart
import 'main.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

// मुख्य Report Options पेज (Bullying, Scam, 18+ Content छान्ने ठाउँ)
class ReportOptionsPage extends StatelessWidget {
  const ReportOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KmScreenHeader(title: 'Report a Problem'),
                const SizedBox(height: 20),
                KmListTile(
                  icon: Icons.warning_amber_rounded,
                  iconBg: const LinearGradient(
                      colors: [AppColors.kmRose, AppColors.kmPink]),
                  title: 'Bullying, Harassment or Abuse',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const BullyingReportPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                KmListTile(
                  icon: Icons.report_problem_rounded,
                  iconBg: const LinearGradient(
                      colors: [AppColors.kmOrange, AppColors.kmOrangeDeep]),
                  title: 'Scam Fraud',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ScamReportPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                KmListTile(
                  icon: Icons.block_rounded,
                  iconBg: const LinearGradient(
                      colors: [AppColors.kmPurple, AppColors.kmPurpleDeep]),
                  title: 'Sexually explicit or 18+ content',
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
          ),
        ),
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
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KmScreenHeader(title: 'Person being harassed'),
                const SizedBox(height: 30),
                KmCtaButton(
                  label: 'Me',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _submitReport(
                    context: context,
                    category: 'Bullying, Harassment or Abuse',
                    details: 'Me',
                  ),
                ),
                const SizedBox(height: 16),
                KmCtaButton(
                  label: 'A friend',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _submitReport(
                    context: context,
                    category: 'Bullying, Harassment or Abuse',
                    details: 'A friend',
                  ),
                ),
              ],
            ),
          ),
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
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KmScreenHeader(title: 'Scam Fraud'),
                const SizedBox(height: 20),
                const Text('समस्या छान्नुहोस्',
                    style: TextStyle(
                        color: AppColors.kmText,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GlassPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: _issues
                        .map((issue) => RadioListTile<String>(
                              title: Text(issue,
                                  style: const TextStyle(
                                      color: AppColors.kmText)),
                              value: issue,
                              groupValue: _selectedIssue,
                              activeColor: AppColors.kmOrange,
                              onChanged: (val) =>
                                  setState(() => _selectedIssue = val),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),
                KmCtaButton(
                  label: 'Me',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _selectedIssue == null
                      ? null
                      : () => _submitReport(
                            context: context,
                            category: 'Scam Fraud',
                            details: '${_selectedIssue!} - Me',
                          ),
                ),
                const SizedBox(height: 16),
                KmCtaButton(
                  label: 'A friend',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _selectedIssue == null
                      ? null
                      : () => _submitReport(
                            context: context,
                            category: 'Scam Fraud',
                            details: '${_selectedIssue!} - A friend',
                          ),
                ),
              ],
            ),
          ),
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
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const KmScreenHeader(title: 'Report Content'),
                const SizedBox(height: 20),
                const Text(
                  'Sexually explicit or 18+ content',
                  style: TextStyle(
                      color: AppColors.kmText,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'यदि तपाईंले यस्तो सामग्री भेट्टाउनुभयो भने, कृपया Report गर्नुहोस्। यो सिधै Admin लाई पठाइनेछ।',
                  style: TextStyle(fontSize: 14, color: AppColors.kmMuted),
                ),
                const SizedBox(height: 30),
                KmCtaButton(
                  label: 'Submit',
                  onPressed: () => _submitReport(
                    context: context,
                    category: '18+ Content',
                    details: 'Reported via app',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
