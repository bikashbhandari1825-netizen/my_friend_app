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
  /// true: चम्किलो नियोन-हरियो बिन्दु (chat header)।
  final bool neon;
  const OnlineBadge(
      {super.key, required this.uid, this.onDark = false, this.neon = false});

  @override
  State<OnlineBadge> createState() => _OnlineBadgeState();
}

class _OnlineBadgeState extends State<OnlineBadge> {
  Timer? _ticker;

  // Firestore Internal Assertion Failed Fix — यो widget एपभरि (job feed,
  // bookings, call screen, आदि) एकैचोटि धेरै copy मा प्रयोग हुन्छ, र
  // हरेक copy ले आफ्नै "freshness" पुनः-गणना गर्न हरेक १०s मा आफैं
  // `setState` तान्छ (तल)। पहिले `stream:` सिधै `build()` भित्रै
  // (`FirebaseFirestore...snapshots()`) बन्थ्यो — त्यसैले त्यो हरेक १०s
  // ticker ले पनि (केवल हल्का "कति बेर भयो" पुनः-गणना गर्नुको सट्टा) हरेक
  // पटक नयाँ Firestore listener बनाई पुरानो unlisten गराउँथ्यो — स्क्रिनमा
  // एकैचोटि धेरै badge भए ती सबैको churn लगभग एकैचोटि (सबैको ticker उस्तै
  // समयमा सुरु भएकोले) दोहोरिने। Firestore Web SDK मा बारम्बार धेरै
  // listener एकैचोटि churn हुँदा "INTERNAL ASSERTION FAILED: Unexpected
  // state" आउने गुनासोको यो एउटा ठूलो (शायद मुख्य) contributor थियो —
  // request_tracking_screen.dart कै उस्तै जड, तर यहाँ हरेक १०s मा
  // दोहोरिने भएकोले बारम्बार आउने ढाँचासँग बढी मिल्छ। अब stream एकपटक
  // मात्र बन्छ — ticker ले केवल हल्का repaint गराउँछ, listener कहिल्यै
  // पुनः-सुरु हुँदैन।
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _subscribe();
    // हरेक १०s मा रिबिल्ड — नयाँ Firestore snapshot नआए पनि "कति बेर भयो"
    // ताजै गणना होस्।
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant OnlineBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _subscribe();
  }

  void _subscribe() {
    _stream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots();
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
      stream: _stream,
      builder: (context, snap) {
        final ts = snap.data?.data()?['lastActive'];
        final online = ts is Timestamp &&
            DateTime.now().difference(ts.toDate()) < kOnlineFreshWindow;
        if (!online) return const SizedBox.shrink();
        final fg = widget.onDark ? Colors.white : AppColors.igViolet;
        if (widget.neon) {
          const green = Color(0xFF3CF5D2);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: green,
                  boxShadow: [
                    BoxShadow(
                        color: green.withValues(alpha: 0.9),
                        blurRadius: 8,
                        spreadRadius: 1),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(S.onlineNow,
                  style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      letterSpacing: 0.4)),
            ],
          );
        }
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
