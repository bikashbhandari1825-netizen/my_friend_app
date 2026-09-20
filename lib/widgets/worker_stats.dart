// widgets/worker_stats.dart
// कामदारको औसत रेटिङ + समीक्षा संख्या + "Top Worker" badge — `reviews`
// collection (targetUid) बाट live।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class WorkerRatingBadge extends StatelessWidget {
  final String uid;

  /// true भए एउटै लाइनमा सानो (card हरूमा); false भए ठूलो (profile header)।
  final bool compact;

  /// dark background मा राख्दा text सेतो।
  final bool onDark;

  const WorkerRatingBadge({
    super.key,
    required this.uid,
    this.compact = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();
    final textColor = onDark ? Colors.white : Colors.black87;
    final subColor = onDark ? Colors.white70 : Colors.black54;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('targetUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final count = docs.length;
        final avg = count == 0
            ? 0.0
            : docs.fold<num>(
                    0, (a, d) => a + ((d.data()['rating'] ?? 0) as num)) /
                count;
        final isTop =
            avg >= kTopWorkerMinRating && count >= kTopWorkerMinReviews;

        if (count == 0) {
          return Text(S.noRatingsYet,
              style: TextStyle(color: subColor, fontSize: compact ? 11 : 13));
        }

        final star = Icon(Icons.star_rounded,
            color: AppColors.igYellow, size: compact ? 15 : 20);
        final ratingText = Text(
          avg.toStringAsFixed(1),
          style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 12.5 : 18),
        );
        final countText = Text(
          '  ·  ${S.ratingCount(count)}',
          style: TextStyle(color: subColor, fontSize: compact ? 11 : 13),
        );

        if (compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              star,
              const SizedBox(width: 2),
              ratingText,
              if (isTop) ...[
                const SizedBox(width: 6),
                const _TopPill(small: true),
              ],
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            star,
            const SizedBox(width: 4),
            ratingText,
            countText,
            if (isTop) ...[
              const SizedBox(width: 10),
              const _TopPill(small: false),
            ],
          ],
        );
      },
    );
  }
}

class _TopPill extends StatelessWidget {
  final bool small;
  const _TopPill({required this.small});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 7 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        gradient: AppColors.buttonGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: small ? 12 : 15),
          const SizedBox(width: 3),
          Text(S.topWorker,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: small ? 9.5 : 11.5)),
        ],
      ),
    );
  }
}
