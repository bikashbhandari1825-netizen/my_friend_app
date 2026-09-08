// screens/my_reviews_screen.dart
// रेटिङ breakdown + feedback cards + sorting सहितको My Reviews।
// Firestore: reviews { targetUid, authorName, rating(1-5), comment, service, createdAt }
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../report_page.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

enum _Sort { recent, highest, lowest }

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  _Sort _sort = _Sort.recent;

  String _sortLabel(_Sort s) => switch (s) {
        _Sort.recent => S.sortRecent,
        _Sort.highest => S.sortHighest,
        _Sort.lowest => S.sortLowest,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.reviewsTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'report') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReportOptionsPage()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report a Problem')),
            ],
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Login गर्नुहोस्'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('reviews')
                  .where('targetUid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _empty(theme);
                }

                final reviews = docs.map((d) => d.data()).toList();
                final total = reviews.length;
                final avg = reviews.fold<num>(
                        0, (a, r) => a + ((r['rating'] ?? 0) as num)) /
                    total;

                // star breakdown 5..1
                final counts = <int, int>{for (var i = 1; i <= 5; i++) i: 0};
                for (final r in reviews) {
                  final s = ((r['rating'] ?? 0) as num).round().clamp(1, 5);
                  counts[s] = (counts[s] ?? 0) + 1;
                }

                final sorted = [...reviews];
                sorted.sort((a, b) {
                  switch (_sort) {
                    case _Sort.highest:
                      return ((b['rating'] ?? 0) as num)
                          .compareTo((a['rating'] ?? 0) as num);
                    case _Sort.lowest:
                      return ((a['rating'] ?? 0) as num)
                          .compareTo((b['rating'] ?? 0) as num);
                    case _Sort.recent:
                      final ta = a['createdAt'];
                      final tb = b['createdAt'];
                      if (ta is Timestamp && tb is Timestamp) {
                        return tb.compareTo(ta);
                      }
                      return 0;
                  }
                });

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _SummaryCard(
                        avg: avg, total: total, counts: counts),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(S.sortBy,
                            style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                        DropdownButton<_Sort>(
                          value: _sort,
                          underline: const SizedBox(),
                          items: _Sort.values
                              .map((s) => DropdownMenuItem(
                                  value: s, child: Text(_sortLabel(s))))
                              .toList(),
                          onChanged: (s) =>
                              setState(() => _sort = s ?? _Sort.recent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final r in sorted) ...[
                      _ReviewCard(r),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.reviews_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(S.noReviewsYet, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  final num avg;
  final int total;
  final Map<int, int> counts;
  const _SummaryCard(
      {required this.avg, required this.total, required this.counts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(avg.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w800)),
              _Stars(avg.toDouble(), size: 15),
              const SizedBox(height: 4),
              Text('$total ${S.basedOnReviews}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                for (var s = 5; s >= 1; s--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text('$s',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: total == 0
                                  ? 0
                                  : (counts[s] ?? 0) / total,
                              minHeight: 7,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.lime),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 20,
                          child: Text('${counts[s] ?? 0}',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> r;
  const _ReviewCard(this.r);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (r['authorName'] ?? 'User').toString();
    final rating = ((r['rating'] ?? 0) as num).toDouble();
    final comment = (r['comment'] ?? '').toString();
    final service = (r['service'] ?? '').toString();
    final ts = r['createdAt'];
    String date = '';
    if (ts is Timestamp) {
      final d = ts.toDate();
      date = '${d.day}/${d.month}/${d.year}';
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LimeIconBadge(Icons.person, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                    if (service.isNotEmpty)
                      Text(service, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              _Stars(rating, size: 14),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          ],
          if (date.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(date, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final double value;
  final double size;
  const _Stars(this.value, {this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: AppColors.lime,
        );
      }),
    );
  }
}
