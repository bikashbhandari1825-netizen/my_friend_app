// widgets/active_job_bar.dart
// एउटै साझा, role-aware "सक्रिय काम" bar — bottom nav माथि हरेक tab मा टाँसिने
// (worker/employer दुवैले उही widget प्रयोग गर्छन्, छुट्टाछुट्टै दुई होइन)।
//
// यसले serviceRequests/{requestId} लाई सिधै आफैं सुन्छ — parent ले कुनै तथ्याङ्क
// पास गर्नु पर्दैन, कुनै tap पनि चाहिँदैन। accepted/confirmed/in_progress भएको
// बित्तिकै (cold start मा समेत) आफैं देखिन्छ, र completed/cancelled/declined
// हुनेबित्तिकै आफैं हराउँछ। दूरी/ETA worker को लाइभ GPS (workerLat/workerLng,
// job_route_screen.dart र main_container.dart दुवैले लेख्छन्) बाट प्रत्येक
// Firestore अपडेटमा पुनः गणना हुन्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../screens/chat_screen.dart';
import '../screens/job_actions.dart'
    show deleteCancelledBooking, isCommunicationUnlocked;
import '../screens/nearby_common.dart' show haversineKm, serviceIconFor;
import 'status_badge.dart';

class ActiveJobBar extends StatelessWidget {
  final String requestId;
  final bool isWorker;
  final VoidCallback onOpenMap;

  const ActiveJobBar({
    super.key,
    required this.requestId,
    required this.isWorker,
    required this.onOpenMap,
  });

  static const _liveStatuses = {'accepted', 'confirmed', 'in_progress'};

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('serviceRequests').doc(requestId);

  // सडक-मार्ग (Directions API) यहाँ बारम्बार नतान्ने — हरेक tab मा हरेक
  // सेकेन्ड देखिने bar ले API cost नबढाओस् भनेर सीधा-रेखा दूरी + अनुमानित
  // समय (home_work_route_screen.dart कै उस्तै ~22km/h अनुमान, एपभरि consistent)।
  int _estMinutes(double km) => (km / 22 * 60).round().clamp(1, 600);

  Future<void> _call(BuildContext context, String phone) async {
    if (phone.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.noPhoneOnFile)));
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
    } catch (_) {}
  }

  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _confirmCancel(
      BuildContext context, Map<String, dynamic> data) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.activeJobBarCancelTitle),
        content: Text(S.activeJobBarCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.keepJob),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.cancelRequest,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      // Cancelled Bookings Cleanup — status मात्र बदल्ने होइन, पूरै मेट्ने
      // (कुनै अवशेष history नरहोस्)।
      await deleteCancelledBooking(
        requestId,
        workerUid: (data['workerUid'] ?? '').toString(),
        // worker आफैंले cancel गर्‍यो भने मात्र penalty — employer लाई
        // कहिल्यै penalty छैन (job_actions.dart::deleteCancelledBooking हेर्नुहोस्)।
        cancelledByWorker: isWorker,
      );
    }
  }

  void _showExpandedSheet(
      BuildContext context, Map<String, dynamic> data, String status) {
    final empLat = (data['employerLat'] as num?)?.toDouble();
    final empLng = (data['employerLng'] as num?)?.toDouble();
    final address = (data['address'] ?? '').toString();
    final service = (data['service'] ?? '').toString();
    final desc = (data['details'] ?? '').toString();
    final price = data['finalPrice'] ??
        data['employerCounterPrice'] ??
        data['workerCounterPrice'] ??
        data['proposedPrice'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(S.jobDetailsTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  StatusBadge(status: status, large: true),
                ],
              ),
              const SizedBox(height: 14),
              if (service.isNotEmpty)
                _sheetRow(
                    sheetContext, Icons.build_rounded, S.serviceName(service)),
              if (desc.isNotEmpty)
                _sheetRow(sheetContext, Icons.notes_rounded, desc),
              if (address.isNotEmpty)
                _sheetRow(sheetContext, Icons.place_rounded, address),
              if (price != null)
                _sheetRow(sheetContext, Icons.payments_rounded, 'Rs. $price'),
              const SizedBox(height: 18),
              if (empLat != null && empLng != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openInGoogleMaps(empLat, empLng),
                    icon: const Icon(Icons.map_rounded),
                    label: Text(S.openInGoogleMaps),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                  ),
                ),
              if (_liveStatuses.contains(status)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _confirmCancel(context, data);
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: Text(S.cancelRequest),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) return const SizedBox.shrink();
        final status = (data['status'] ?? '').toString();
        if (!_liveStatuses.contains(status)) return const SizedBox.shrink();

        final otherName = (isWorker ? data['employerName'] : data['workerName'])
                ?.toString() ??
            (isWorker ? S.customerWord : S.workerRoleWord);
        final otherPhone =
            (isWorker ? data['employerPhone'] : data['workerPhone'])
                    ?.toString() ??
                '';
        final service = (data['service'] ?? '').toString();
        final price = data['finalPrice'] ??
            data['employerCounterPrice'] ??
            data['workerCounterPrice'] ??
            data['proposedPrice'];

        final empLat = (data['employerLat'] as num?)?.toDouble();
        final empLng = (data['employerLng'] as num?)?.toDouble();
        final wLat = (data['workerLat'] as num?)?.toDouble();
        final wLng = (data['workerLng'] as num?)?.toDouble();
        String? distanceLine;
        if (empLat != null && empLng != null && wLat != null && wLng != null) {
          final km = haversineKm(wLat, wLng, empLat, empLng);
          final minutes = _estMinutes(km);
          distanceLine = '${km.toStringAsFixed(1)} km · ${S.etaAway(minutes)}';
        }

        final meta = jobStatusMeta(status);
        final theme = Theme.of(context);

        return GestureDetector(
          onTap: onOpenMap,
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -150) {
              _showExpandedSheet(context, data, status);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.dividerColor)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, -3)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0x22833AB4),
                        child: Icon(serviceIconFor(service),
                            color: AppColors.igViolet),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(otherName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5)),
                                ),
                                const SizedBox(width: 6),
                                Icon(meta.icon, size: 13, color: meta.color),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                S.serviceName(service),
                                if (price != null) 'Rs. $price',
                                distanceLine ?? meta.label,
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      // Arrival-Gated Communication — worker साँच्चै
                      // आइपुगेर status `in_progress` नभएसम्म Call/Message
                      // यहाँ देखिँदैनन्, स्वीकृति भइसकेको भए पनि।
                      if (isCommunicationUnlocked(status)) ...[
                        IconButton(
                          onPressed: () => _call(context, otherPhone),
                          icon: const Icon(Icons.call_rounded),
                          color: AppColors.igViolet,
                          tooltip: S.callWord,
                        ),
                        IconButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                requestId: requestId,
                                workerName: otherName,
                                initialStatus: status,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_rounded),
                          color: AppColors.igViolet,
                          tooltip: S.messageWord,
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.lock_outline_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
