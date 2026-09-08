// saved_places_screen.dart
// Home / Work / अन्य स्थान सेभ गर्ने — नक्सा (Google Maps) बाट छानेर।
// Firestore: users/{uid} { homePlace, workPlace, otherPlaces: [ {label,address,lat,lng} ] }
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'location_picker_page.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';

class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(S.savedPlacesTitle)),
        body: const Center(child: Text('Login गर्नुहोस्')),
      );
    }

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(uid);

    Future<PickedPlace?> pick(String label, Map<String, dynamic>? existing) {
      return Navigator.push<PickedPlace>(
        context,
        MaterialPageRoute(
          builder: (_) => LocationPickerPage(
            initialLabel: label,
            initialLat: (existing?['lat'] as num?)?.toDouble() ?? 27.7172,
            initialLng: (existing?['lng'] as num?)?.toDouble() ?? 85.3240,
          ),
        ),
      );
    }

    void toast(String m) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));

    return Scaffold(
      appBar: AppBar(title: Text(S.savedPlacesTitle)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          final home = (data['homePlace'] as Map?)?.cast<String, dynamic>();
          final work = (data['workPlace'] as Map?)?.cast<String, dynamic>();
          final others = ((data['otherPlaces'] as List?) ?? [])
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _PlaceTile(
                icon: Icons.home_rounded,
                title: S.saveAsHome,
                place: home,
                onTap: () async {
                  final p = await pick(S.saveAsHome, home);
                  if (p == null) return;
                  await userRef.set({
                    'homePlace': {
                      'label': p.label,
                      'address': p.address,
                      'lat': p.lat,
                      'lng': p.lng,
                    }
                  }, SetOptions(merge: true));
                  toast(S.placeSaved);
                },
              ),
              const SizedBox(height: 12),
              _PlaceTile(
                icon: Icons.work_rounded,
                title: S.saveAsWork,
                place: work,
                onTap: () async {
                  final p = await pick(S.saveAsWork, work);
                  if (p == null) return;
                  await userRef.set({
                    'workPlace': {
                      'label': p.label,
                      'address': p.address,
                      'lat': p.lat,
                      'lng': p.lng,
                    }
                  }, SetOptions(merge: true));
                  toast(S.placeSaved);
                },
              ),
              const SizedBox(height: 12),
              _AddTile(
                onTap: () async {
                  final p = await pick(S.addAnotherPlace, null);
                  if (p == null) return;
                  await userRef.set({
                    'otherPlaces': FieldValue.arrayUnion([
                      {
                        'label': p.label,
                        'address': p.address,
                        'lat': p.lat,
                        'lng': p.lng,
                      }
                    ])
                  }, SetOptions(merge: true));
                  toast(S.placeSaved);
                },
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (final o in others) ...[
                  _PlaceTile(
                    icon: Icons.location_on_rounded,
                    title: (o['label'] ?? '').toString().isEmpty
                        ? S.addAnotherPlace
                        : o['label'].toString(),
                    place: o,
                    onDelete: () async {
                      await userRef.set({
                        'otherPlaces': FieldValue.arrayRemove([o])
                      }, SetOptions(merge: true));
                    },
                    onTap: () async {
                      final p = await pick(
                          (o['label'] ?? S.addAnotherPlace).toString(), o);
                      if (p == null) return;
                      await userRef.set({
                        'otherPlaces': FieldValue.arrayRemove([o])
                      }, SetOptions(merge: true));
                      await userRef.set({
                        'otherPlaces': FieldValue.arrayUnion([
                          {
                            'label': p.label,
                            'address': p.address,
                            'lat': p.lat,
                            'lng': p.lng,
                          }
                        ])
                      }, SetOptions(merge: true));
                      toast(S.placeSaved);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Map<String, dynamic>? place;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PlaceTile({
    required this.icon,
    required this.title,
    required this.place,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = (place?['address'] ?? '').toString();

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          LimeIconBadge(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  address.isEmpty ? S.notSetYet : address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onDelete != null && address.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.danger),
              onPressed: onDelete,
            )
          else
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          const LimeIconBadge(Icons.add_rounded, solid: true),
          const SizedBox(width: 14),
          Expanded(
            child: Text(S.addAnotherPlace,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Icon(Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
