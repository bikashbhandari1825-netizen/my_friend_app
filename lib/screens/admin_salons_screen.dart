// screens/admin_salons_screen.dart
//
// Admin → Salon approvals। नयाँ दर्ता भएका salon (`status: pending`) यहाँ
// देखिन्छन्; admin ले Approve (→ 'active', ग्राहकलाई browse/बुकिङमा देखिने)
// वा Reject (कारण सहित) गर्छ। अनुमति firestore.rules ले लागू गर्छ — salon को
// status admin मात्रले pending/rejected बाट बदल्न सक्छ।
import 'package:flutter/material.dart';

import '../models/salon_models.dart';
import '../services/salon_partner_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_common.dart';
import '../widgets/skeleton.dart';

enum _Filter { pending, active, paused, rejected, all }

extension on _Filter {
  String get label => switch (this) {
        _Filter.pending => 'Pending',
        _Filter.active => 'Active',
        _Filter.paused => 'Paused',
        _Filter.rejected => 'Rejected',
        _Filter.all => 'All',
      };

  bool matches(Salon s) => switch (this) {
        _Filter.pending => s.isPending,
        _Filter.active => s.isActive,
        _Filter.paused => s.status == SalonStatus.paused,
        _Filter.rejected => s.isRejected,
        _Filter.all => true,
      };
}

class AdminSalonsScreen extends StatefulWidget {
  const AdminSalonsScreen({super.key});

  @override
  State<AdminSalonsScreen> createState() => _AdminSalonsScreenState();
}

class _AdminSalonsScreenState extends State<AdminSalonsScreen>
    with AutomaticKeepAliveClientMixin {
  late final _stream = allSalonsForAdmin();
  _Filter _filter = _Filter.pending;
  final _busyIds = <String>{};

  @override
  bool get wantKeepAlive => true;

  Future<void> _approve(Salon s) async {
    setState(() => _busyIds.add(s.id));
    try {
      await setSalonApproval(s.id, approved: true);
      if (mounted) salonSnack(context, '${s.name} approved.');
    } catch (e) {
      if (mounted) salonSnack(context, 'Could not approve: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(s.id));
    }
  }

  Future<void> _reject(Salon s) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.kmSurface,
        title: Text('Reject ${s.name}?',
            style: const TextStyle(color: AppColors.kmText)),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          style: const TextStyle(color: AppColors.kmText),
          decoration: kmInputDecoration('Reason (shown to the owner)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: TextButton.styleFrom(foregroundColor: AppColors.kmRose),
              child: const Text('Reject')),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || !mounted) return;
    setState(() => _busyIds.add(s.id));
    try {
      await setSalonApproval(s.id, approved: false, reason: reason);
      if (mounted) salonSnack(context, '${s.name} rejected.');
    } catch (e) {
      if (mounted) salonSnack(context, 'Could not reject: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(s.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: StreamBuilder<List<Salon>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load salons: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.kmRose)),
                  ),
                );
              }
              if (!snap.hasData) {
                return const SkeletonList();
              }
              final all = snap.data!;
              final rows = all.where(_filter.matches).toList();
              return Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      itemCount: _Filter.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final f = _Filter.values[i];
                        final sel = f == _filter;
                        final n = all.where(f.matches).length;
                        return ChoiceChip(
                          selected: sel,
                          showCheckmark: false,
                          label: Text('${f.label} · $n'),
                          labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: sel ? Colors.white : AppColors.kmMuted),
                          selectedColor: AppColors.kmPurple,
                          backgroundColor:
                              AppColors.kmSurface.withValues(alpha: 0.6),
                          onSelected: (_) => setState(() => _filter = f),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(
                            child: Text('No ${_filter.label.toLowerCase()} salons',
                                style:
                                    const TextStyle(color: AppColors.kmMuted)))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [for (final s in rows) _card(s)],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _card(Salon s) {
    final busy = _busyIds.contains(s.id);
    return salonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SalonAvatar(
                  url: s.logoUrl.isNotEmpty ? s.logoUrl : s.coverUrl,
                  icon: salonCategoryIcon(s.category),
                  size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        s.address.isEmpty
                            ? s.category
                            : '${s.category} · ${s.address}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.kmMuted, fontSize: 12)),
                  ],
                ),
              ),
              KmTag(
                  s.status,
                  color: s.isPending
                      ? AppColors.kmAmber
                      : s.isRejected
                          ? AppColors.kmRose
                          : s.isActive
                              ? AppColors.kmTeal
                              : AppColors.kmMuted),
            ],
          ),
          const SizedBox(height: 8),
          if (s.phone.isNotEmpty)
            Text('Phone: ${s.phone}',
                style: const TextStyle(color: AppColors.kmText, fontSize: 12.5)),
          Text('Owner UID: ${s.ownerId}',
              style: const TextStyle(color: AppColors.kmMuted, fontSize: 11)),
          if (s.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(s.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.kmMuted, fontSize: 12, height: 1.35)),
          ],
          if (s.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: s.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => SalonAvatar(
                    url: s.photos[i],
                    icon: Icons.image_rounded,
                    size: 56,
                    radius: 10),
              ),
            ),
          ],
          if (s.isRejected && s.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Rejected: ${s.rejectionReason}',
                style: const TextStyle(color: AppColors.kmRose, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          if (busy)
            const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            Row(
              children: [
                if (!s.isActive)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _approve(s),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.kmTeal,
                          foregroundColor: AppColors.kmInk),
                    ),
                  ),
                if (!s.isActive && !s.isRejected) const SizedBox(width: 8),
                if (!s.isRejected)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reject(s),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(s.isActive ? 'Unlist' : 'Reject'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.kmRose,
                          side: BorderSide(
                              color: AppColors.kmRose.withValues(alpha: 0.5))),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
