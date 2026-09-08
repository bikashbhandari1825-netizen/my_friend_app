// screens/nearby_common.dart
// Nearby list र Nearby map दुवैले प्रयोग गर्ने साझा: geo helper + offer/bidding sheet।
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

// काठमाडौँ केन्द्र — location नपाउँदा fallback।
const double fallbackLat = 27.7172;
const double fallbackLng = 85.3240;

const List<Map<String, dynamic>> serviceFilters = [
  {'name': 'Mechanic', 'icon': Icons.car_repair},
  {'name': 'Plumber', 'icon': Icons.plumbing},
  {'name': 'Electrician', 'icon': Icons.electric_bolt},
  {'name': 'Carpenter', 'icon': Icons.carpenter},
  {'name': 'Painter', 'icon': Icons.format_paint},
  {'name': 'Cleaner', 'icon': Icons.cleaning_services},
  {'name': 'Driver', 'icon': Icons.drive_eta},
  {'name': 'Tutor', 'icon': Icons.school},
];

double _deg2rad(double d) => d * pi / 180.0;

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) *
          cos(_deg2rad(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return earthKm * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Worker को coordinate — Firestore मा `lat`/`lng` छ भने त्यही, नत्र docId बाट
/// deterministic रूपमा origin वरिपरि 0.4–6 किमी भित्र (placeholder)।
({double lat, double lng}) workerPos(
    Map<String, dynamic> data, String id, double originLat, double originLng) {
  final lat = (data['lat'] as num?)?.toDouble();
  final lng = (data['lng'] as num?)?.toDouble();
  if (lat != null && lng != null) return (lat: lat, lng: lng);

  final h = id.hashCode;
  final bearing = (h % 360) * pi / 180.0;
  final distKm = 0.4 + (h.abs() % 560) / 100.0;
  final dLat = (distKm / 111.0) * cos(bearing);
  final dLng =
      (distKm / (111.0 * cos(_deg2rad(originLat)))) * sin(bearing);
  return (lat: originLat + dLat, lng: originLng + dLng);
}

/// inDrive-style offer/bidding sheet देखाउने।
Future<void> showOfferSheet(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String workerId,
  required double distanceKm,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OfferSheet(
      data: data,
      workerId: workerId,
      distanceKm: distanceKm,
    ),
  );
}

class OfferSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String workerId;
  final double distanceKm;

  const OfferSheet({
    super.key,
    required this.data,
    required this.workerId,
    required this.distanceKm,
  });

  @override
  State<OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<OfferSheet> {
  final _detailsCtrl = TextEditingController();
  late int _asking;
  late int _amount;
  bool _sending = false;

  static const int _step = 50;

  @override
  void initState() {
    super.initState();
    final digits = (widget.data['price'] ?? 'Rs. 500')
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    _asking = int.tryParse(digits) ?? 500;
    if (_asking < _step) _asking = 500;
    _amount = _asking;
  }

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  void _setAmount(int v) => setState(() => _amount = v.clamp(_step, 1000000));

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('serviceRequests').add({
        'workerUid': widget.data['uid'] ?? widget.workerId,
        'employerUid': user?.uid ?? '',
        'employerName': user?.email ?? 'Employer',
        'workerName': widget.data['name'] ?? '',
        'service': widget.data['service'] ?? '',
        'details': _detailsCtrl.text.trim(),
        'proposedPrice': _amount,
        'status': 'pending_worker',
        'createdAt': FieldValue.serverTimestamp(),
        'distanceKm': double.parse(widget.distanceKm.toStringAsFixed(2)),
      });
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(S.offerSentTitle),
          content: Text(S.offerSentBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text(S.ok)),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.errorWord}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (widget.data['name'] ?? '').toString();
    final service = (widget.data['service'] ?? '').toString();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget quickChip(String label, int value) => GestureDetector(
          onTap: () => _setAmount(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const LimeIconBadge(Icons.person, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? '—' : name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                          '${S.serviceName(service)}  ·  ${S.distanceLabel(widget.distanceKm)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('${S.askingPrice}: Rs. $_asking',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(S.yourOffer,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundStepBtn(
                    icon: Icons.remove_rounded,
                    onTap: () => _setAmount(_amount - _step)),
                const SizedBox(width: 18),
                Column(
                  children: [
                    const Text('Rs.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('$_amount',
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(width: 18),
                _RoundStepBtn(
                    icon: Icons.add_rounded,
                    onTap: () => _setAmount(_amount + _step)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                quickChip('−20%', (_asking * 0.8).round()),
                const SizedBox(width: 8),
                quickChip(S.askingPrice, _asking),
                const SizedBox(width: 8),
                quickChip('+10%', (_asking * 1.1).round()),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _detailsCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: S.describeTask,
                hintText: S.describeTaskHint,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: S.sendOffer,
              icon: Icons.send_rounded,
              loading: _sending,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundStepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundStepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: theme.dividerColor),
        ),
        child: Icon(icon, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
