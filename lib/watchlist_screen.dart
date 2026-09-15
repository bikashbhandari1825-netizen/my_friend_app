// watchlist_screen.dart
// सबै दर्ता भएका सेवाप्रदायकहरूको सूची — Instagram gradient background।
// यी worker profile हरू अब home page मा होइन, यहाँ मात्र देखिन्छन्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';
import 'widgets/worker_avatar.dart';
import 'screens/worker_profile_screen.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: gradientAppBar(S.watchlistTitle),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.igGradient),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('registeredWorkers')
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_search_rounded,
                          size: 56, color: Colors.white70),
                      const SizedBox(height: 12),
                      Text(S.noWorkersNearby,
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final name = (d['name'] ?? '—').toString();
                  final service = (d['service'] ?? '').toString();
                  final experience = (d['experience'] ?? '').toString();
                  final location =
                      (d['location'] ?? d['district'] ?? '—').toString();
                  final price = (d['price'] ?? 'Rs. 500').toString();
                  final rating = (d['rating'] ?? '5.0').toString();

                  return _WorkerCard(
                    uid: (d['uid'] ?? '').toString(),
                    name: name,
                    service: service,
                    experience: experience,
                    location: location,
                    price: price,
                    rating: rating,
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
                        }),
                      ),
                    ),
                  );
                },
              );
            },
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
  final VoidCallback onTap;

  const _WorkerCard({
    required this.uid,
    required this.name,
    required this.service,
    required this.experience,
    required this.location,
    required this.price,
    required this.rating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WorkerAvatar(
                    uid: uid,
                    size: 44,
                    backgroundColor: const Color(0x22833AB4),
                    iconColor: AppColors.igViolet,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                color: Colors.black87)),
                        const SizedBox(height: 2),
                        Text(
                          experience.isEmpty
                              ? S.serviceName(service)
                              : '${S.serviceName(service)} · $experience',
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: AppColors.igYellow),
                      const SizedBox(width: 2),
                      Text(rating,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ),
                  Text(S.fromPrice(price),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.igRed)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
