// widgets/online_badge.dart
// "Online" pill — services/presence_service.dart कै heartbeat (users/{uid}.
// lastActive) हेरेर। Firestore doc आफैं नयाँ नलेखिए पनि (अर्को पक्षले एप
// बन्द गरेपछि) समय बित्दै जाँदा "Online" बाट हराउनुपर्छ — त्यसैले Firestore
// snapshot मात्र सुन्दा पुग्दैन (त्यो बेला कुनै नयाँ event नै आउँदैन)। यहाँ
// एउटा हल्का local ticker पनि थपिएको छ जसले पछिल्लो थाहा भएको timestamp
// विरुद्ध "freshness" लाई हरेक केही सेकेन्डमा पुनः-गणना गर्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/presence_service.dart';
import '../theme/app_theme.dart';

class OnlineBadge extends StatefulWidget {
  final String uid;
  final bool onDark;
  const OnlineBadge({super.key, required this.uid, this.onDark = false});

  @override
  State<OnlineBadge> createState() => _OnlineBadgeState();
}

class _OnlineBadgeState extends State<OnlineBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // हरेक १०s मा रिबिल्ड — नयाँ Firestore snapshot नआए पनि "कति बेर भयो"
    // ताजै गणना होस्।
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .snapshots(),
      builder: (context, snap) {
        final ts = snap.data?.data()?['lastActive'];
        final online = ts is Timestamp &&
            DateTime.now().difference(ts.toDate()) < kOnlineFreshWindow;
        if (!online) return const SizedBox.shrink();
        final fg = widget.onDark ? Colors.white : AppColors.igViolet;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.buttonGradient,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.igPink.withValues(alpha: 0.6),
                      blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text(S.onlineNow,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        );
      },
    );
  }
}
