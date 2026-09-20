// widgets/worker_avatar.dart
// कामदारको प्रोफाइल फोटो — registration बेला खिचेको selfie (`providers/{uid}.
// selfieUrl`) लाई uid बाट live हेरेर देखाउने। पहिले यो कतै पनि प्रयोग
// नभएकोले जताततै (profile view, map bottom sheet, search result) placeholder
// icon मात्र देखिन्थ्यो, वास्तविक selfie कहिल्यै मैप हुँदैनथ्यो। `providers`
// collection नै source of truth (worker_registration_page.dart ले त्यहीं
// लेख्छ); `registeredWorkers` (search/list snapshot) मा यो field नहुन सक्छ,
// त्यसैले हरेक card ले आफैं live lookup गर्छ — `WorkerRatingBadge` कै उस्तै
// established per-card pattern।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WorkerAvatar extends StatelessWidget {
  final String uid;
  final double size;
  final Color? iconColor;
  final Color? backgroundColor;

  const WorkerAvatar({
    super.key,
    required this.uid,
    this.size = 44,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return _fallback();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('providers')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final url = (snap.data?.data()?['selfieUrl'] ?? '').toString();
        if (url.isEmpty) return _fallback();
        return ClipOval(
          child: Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        );
      },
    );
  }

  Widget _fallback() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.lime.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person_rounded,
            color: iconColor ?? AppColors.lime, size: size * 0.5),
      );
}
