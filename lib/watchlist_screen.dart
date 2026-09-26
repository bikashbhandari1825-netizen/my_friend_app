// watchlist_screen.dart
// सबै दर्ता भएका सेवाप्रदायकहरूको सूची — "KaamMitra 2050" dark glass design।
// यी worker profile हरू अब home page मा होइन, यहाँ मात्र देखिन्छन्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';
import 'widgets/worker_avatar.dart';
import 'screens/worker_profile_screen.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topLeft, AppColors.kmPink),
        KmOrb(Alignment.bottomRight, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: S.watchlistTitle),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('registeredWorkers')
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.kmTeal));
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_search_rounded,
                                size: 56, color: AppColors.kmMuted),
                            const SizedBox(height: 12),
                            Text(S.noWorkersNearby,
                                style: const TextStyle(
                                    color: AppColors.kmText)),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final d = docs[i].data();
                        final name = (d['name'] ?? '—').toString();
                        final service = (d['service'] ?? '').toString();
                        final experience =
                            (d['experience'] ?? '').toString();
                        final location =
                            (d['location'] ?? d['district'] ?? '—')
                                .toString();
                        final price = (d['price'] ?? 'Rs. 500').toString();
                        // '5.0' default हटाइयो — नयाँ worker सुरुमा साँच्चै
                        // ०/कुनै review नभएको देखिनुपर्छ।
                        final rating = (d['rating'] ?? '0.0').toString();

                        return _WorkerCard(
                          uid: (d['uid'] ?? '').toString(),
                          name: name,
                          service: service,
                          experience: experience,
                          location: location,
                          price: price,
                          rating: rating,
                          bg: KmListTile.gradients[i % KmListTile.gradients.length],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkerProfileScreen(worker: {
                                'uid': (d['uid'] ?? '').toString(),
                                'name': name,
                                'service': service,
                                'experience': experience,
                                'location': location,
                                'price': price,
                                'document': (d['document'] ?? '').toString(),
                                'phone': (d['phone'] ?? '').toString(),
                                'vehicleDetails':
                                    (d['vehicleDetails'] ?? '').toString(),
                              }),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final String uid;
  final String name;
  final String service;
  final String experience;
  final String location;
  final String price;
  final String rating;
  final Gradient bg;
  final VoidCallback onTap;

  const _WorkerCard({
    required this.uid,
    required this.name,
    required this.service,
    required this.experience,
    required this.location,
    required this.price,
    required this.rating,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 26,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: WorkerAvatar(
              uid: uid,
              size: 60,
              backgroundColor: Colors.transparent,
              iconColor: AppColors.kmInk,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.kmText)),
                const SizedBox(height: 3),
                Text(
                  experience.isEmpty
                      ? S.serviceName(service)
                      : '${S.serviceName(service)} · $experience',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.kmMuted),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.place_rounded,
                        size: 14, color: AppColors.kmMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.kmMuted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 15, color: AppColors.kmOrange),
                  const SizedBox(width: 4),
                  Text(rating,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.kmOrange)),
                ],
              ),
              Text(S.fromPrice(price),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.kmOrange)),
            ],
          ),
        ],
      ),
    );
  }
}
