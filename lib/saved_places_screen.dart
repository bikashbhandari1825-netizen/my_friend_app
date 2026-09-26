// saved_places_screen.dart
// Home / Work / अन्य स्थान सेभ गर्ने — नक्सा (Google Maps) बाट छानेर।
// Firestore: users/{uid} { homePlace, workPlace, otherPlaces: [ {label,address,lat,lng} ] }
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'location_picker_page.dart';
import 'screens/home_work_route_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return AuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KmScreenHeader(title: S.savedPlacesTitle),
                  const Expanded(
                    child: Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmMuted))),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

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

    void toast(String m, {bool ok = true}) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(m)),
          ]),
          backgroundColor: ok ? AppColors.kmTeal : AppColors.kmRose,
        ));

    /// एउटा merge write — असफल भए कारण देखाउने।
    Future<void> save(Map<String, dynamic> patch) async {
      try {
        await userRef.set(patch, SetOptions(merge: true));
        toast(S.placeSaved);
      } catch (e) {
        toast('${S.errorWord}: $e', ok: false);
      }
    }

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(title: S.savedPlacesTitle),
              ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                  await save({'homePlace': p.toMap()});
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
                  await save({'workPlace': p.toMap()});
                },
              ),
              if ((home?['lat'] as num?) != null &&
                  (work?['lat'] as num?) != null) ...[
                const SizedBox(height: 12),
                _RouteCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HomeWorkRouteScreen(
                        home: home!,
                        work: work!,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _AddTile(
                onTap: () async {
                  final p = await pick(S.addAnotherPlace, null);
                  if (p == null) return;
                  await save({
                    'otherPlaces': FieldValue.arrayUnion([p.toMap()])
                  });
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
                      try {
                        await userRef.set({
                          'otherPlaces': FieldValue.arrayRemove([o])
                        }, SetOptions(merge: true));
                      } catch (e) {
                        toast('${S.errorWord}: $e', ok: false);
                      }
                    },
                    onTap: () async {
                      final p = await pick(
                          (o['label'] ?? S.addAnotherPlace).toString(), o);
                      if (p == null) return;
                      try {
                        await userRef.set({
                          'otherPlaces': FieldValue.arrayRemove([o])
                        }, SetOptions(merge: true));
                        await userRef.set({
                          'otherPlaces': FieldValue.arrayUnion([p.toMap()])
                        }, SetOptions(merge: true));
                        toast(S.placeSaved);
                      } catch (e) {
                        toast('${S.errorWord}: $e', ok: false);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
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
    final address = (place?['address'] ?? '').toString();

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              gradient: AppColors.kmCtaGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.kmInk, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                Text(
                  address.isEmpty ? S.notSetYet : address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.kmMuted),
                ),
              ],
            ),
          ),
          if (onDelete != null && address.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.kmRose),
              onPressed: onDelete,
            )
          else
            const Icon(Icons.chevron_right_rounded, color: AppColors.kmMuted),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RouteCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.kmCtaGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.alt_route_rounded,
                    color: AppColors.kmInk, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.homeToWorkRoute,
                          style: const TextStyle(
                              color: AppColors.kmInk,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(S.viewRoute,
                          style: TextStyle(
                              color: AppColors.kmInk.withValues(alpha: 0.7),
                              fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.kmInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              gradient: AppColors.kmCtaGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded,
                color: AppColors.kmInk, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(S.addAnotherPlace,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.kmMuted),
        ],
      ),
    );
  }
}
