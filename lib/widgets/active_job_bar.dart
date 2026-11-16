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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../screens/chat_screen.dart';
import '../screens/job_actions.dart'
    show
        deleteCancelledBooking,
        isCommunicationUnlocked,
        offerErrorSnackBar,
        pickCancellationReason;
import '../screens/nearby_common.dart' show haversineKm, ServiceIconBadge;
import 'glass_ui.dart';
import 'status_badge.dart';
import 'worker_avatar.dart';

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
    final service = (data['service'] ?? '').toString();
    final isRide =
        service == 'Bike' || service == 'Car' || service == 'Auto';
    final ok = await showKmDialog<bool>(
      context: context,
      title: S.activeJobBarCancelTitleFor(isRide),
      message: S.activeJobBarCancelBodyFor(isRide),
      icon: Icons.close_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.keepJobFor(isRide),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        KmDialogAction(
          label: S.cancelRequest,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (ok != true || !context.mounted) return;
    // "पक्का हो?" पछि मात्र किन cancel गर्दै भन्ने छोटो कारण — sheet बन्द
    // गरे (null) भने cancel नै नगर्ने।
    final reason = await pickCancellationReason(context);
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Cancelled Bookings Cleanup — status मात्र बदल्ने होइन, पूरै मेट्ने
      // (कुनै अवशेष history नरहोस्)।
      await deleteCancelledBooking(
        requestId,
        workerUid: (data['workerUid'] ?? '').toString(),
        // worker आफैंले cancel गर्‍यो भने मात्र penalty — employer लाई
        // कहिल्यै penalty छैन (job_actions.dart::deleteCancelledBooking हेर्नुहोस्)।
        cancelledByWorker: isWorker,
        reason: reason,
      );
      // Silent-Success Fix — यहाँ सफल भएपछि पहिले कुनै संकेत नै थिएन; यो
      // बार आफैं (stream-driven) केही क्षणमा बिस्तारै हराउने भएकोले, छिटो
      // टेस्ट गर्दा "थिचेर पनि केही भएन" जस्तै देखिन्थ्यो (data कै हिसाबले
      // cancel साँच्चै भइसकेको भए पनि)। अब तुरुन्तै स्पष्ट संकेत।
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(S.requestCancelled)));
      }
    } catch (e) {
      // पहिले यहाँ असफल भए पनि कुनै संकेत नै नदेखिने थियो — "Cancel बटन
      // थिचेर पनि केही नहुने" गुनासोको सम्भाव्य जड। अब स्पष्ट त्रुटि।
      if (!context.mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  /// Emergency SOS — पक्का हो भनेर एकपटक सोधेपछि: (१) हालको लाइभ स्थान +
  /// राइड सन्दर्भसहित `sosAlerts` मा एउटा log (admin/support ले पछि हेर्ने,
  /// best-effort — यसले फोन कल रोक्दैन), (२) फोनको dialer मा साँचो
  /// आपतकालीन नम्बर (नेपाल प्रहरी: १००) सिधै खोल्ने। कुनै नक्कली "help is
  /// on the way" जस्तो दाबी गरिँदैन — केवल साँच्चै हुने दुई कुरा मात्र।
  Future<void> _triggerSos(
      BuildContext context, Map<String, dynamic> data) async {
    final ok = await showKmDialog<bool>(
      context: context,
      title: S.sosConfirmTitle,
      message: S.sosConfirmBody,
      icon: Icons.emergency_rounded,
      iconBg:
          const LinearGradient(colors: [AppColors.danger, AppColors.kmRose]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        KmDialogAction(
          label: S.sosCallEmergency,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (ok != true) return;
    unawaited(_logSosAlert(data));
    try {
      await launchUrl(Uri(scheme: 'tel', path: '100'));
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.sosAlertSent)));
    }
  }

  Future<void> _logSosAlert(Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final base = {
      'requestId': requestId,
      'uid': uid,
      'service': (data['service'] ?? '').toString(),
      'employerUid': (data['employerUid'] ?? '').toString(),
      'workerUid': (data['workerUid'] ?? '').toString(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 6));
      await FirebaseFirestore.instance.collection('sosAlerts').add({
        ...base,
        'lat': p.latitude,
        'lng': p.longitude,
      });
    } catch (_) {
      // स्थान लिन असफल भए पनि — बिना coordinate भए पनि alert log हुनुपर्छ,
      // पूर्ण रूपमा हराउनु भन्दा राम्रो।
      try {
        await FirebaseFirestore.instance.collection('sosAlerts').add(base);
      } catch (_) {}
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
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          child: glassBackdrop(sigma: 26, child: Container(
              decoration: BoxDecoration(
                color: AppColors.kmSurface.withValues(alpha: 0.94),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg)),
                border: Border(
                    top: BorderSide(color: AppColors.kmGlassBorder),
                    left: BorderSide(color: AppColors.kmGlassBorder),
                    right: BorderSide(color: AppColors.kmGlassBorder)),
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
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            S.jobDetailsTitleFor(service == 'Bike' ||
                                service == 'Car' ||
                                service == 'Auto'),
                            style: const TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                      ),
                      StatusBadge(status: status, large: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (service.isNotEmpty)
                    _sheetRow(Icons.build_rounded, S.serviceName(service)),
                  if (desc.isNotEmpty) _sheetRow(Icons.notes_rounded, desc),
                  if (address.isNotEmpty)
                    _sheetRow(Icons.place_rounded, address),
                  if (price != null)
                    _sheetRow(Icons.payments_rounded, 'Rs. $price'),
                  const SizedBox(height: 18),
                  if (empLat != null && empLng != null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openInGoogleMaps(empLat, empLng),
                        icon: const Icon(Icons.map_rounded,
                            color: AppColors.kmText),
                        label: Text(S.openInGoogleMaps,
                            style:
                                const TextStyle(color: AppColors.kmText)),
                        style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.kmGlassBorder),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13)),
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
                          foregroundColor: AppColors.kmRose,
                          side: const BorderSide(color: AppColors.kmRose),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.kmMuted),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: AppColors.kmText, fontSize: 13.5))),
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
        // Compact ETA/Distance Badge — पहिले यो लामो वाक्य (`S.etaAway`:
        // "about N min away") बाकी meta टेक्स्टसँगै एउटै लाइनमा जोडिन्थ्यो
        // — compact capsule मा ठाउँ धेरै ओगट्थ्यो। अब छोटो, badge-अनुकूल
        // ढाँचा ("N min • 0.1 km") छुट्टै सानो pill मा (तल हेर्नुहोस्)।
        String? distanceLine;
        if (empLat != null && empLng != null && wLat != null && wLng != null) {
          final km = haversineKm(wLat, wLng, empLat, empLng);
          final minutes = _estMinutes(km);
          distanceLine = '$minutes min  •  ${km.toStringAsFixed(1)} km';
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
          // Floating Glass Capsule — पहिले यहाँ edge-to-edge solid
          // (`theme.colorScheme.surface`) strip थियो, बटम-nav माथि पूरै
          // चौडाइ ढाक्ने। अब 16dp साइड-मार्जिन सहितको छुट्टै तैरिरहेको
          // (rounded, frosted) capsule — `GlassIconButton`/`_GlassActionCluster`
          // कै उस्तै blur-once ढाँचा, नक्सा/अरू सामग्री बाहिरका किनाराबाट
          // अझै देखिने।
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: glassBackdrop(sigma: 20, child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.kmGlass2Fill,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.kmGlass2Border),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 20,
                              offset: const Offset(0, 8)),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
                      child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // यो सानो drag-handle लाई अब सिधै tappable पनि बनाइयो —
                  // पहिले "job details" sheet (जसभित्र Cancel बटन छ) माथि
                  // (swipe-up gesture) बाट मात्र पुगिन्थ्यो, कुनै देखिने संकेत
                  // (icon/chevron/लेबल) बिना — प्रयोगकर्ताले त्यो gesture
                  // कहिल्यै भेट्टाउँदैनथे, र बारकै सिधा tap ले सिधै नक्सा
                  // खोल्थ्यो (Cancel भेट्टाउने कुनै स्पष्ट बाटो नै थिएन)।
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showExpandedSheet(context, data, status),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
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
                    ),
                  ),
                  Row(
                    children: [
                      // employer ले driver हेर्दा साँचो selfie photo देख्छन्;
                      // worker ले employer हेर्दा भने (employer को कुनै
                      // registration selfie नहुने भएकाले) service icon नै।
                      if (!isWorker)
                        WorkerAvatar(
                          uid: (data['workerUid'] ?? '').toString(),
                          size: 38,
                          iconColor: AppColors.igViolet,
                          backgroundColor: const Color(0x22833AB4),
                        )
                      else
                        ServiceIconBadge(
                          service: service,
                          size: 38,
                          iconColor: AppColors.igViolet,
                          backgroundColor: const Color(0x22833AB4),
                        ),
                      const SizedBox(width: 8),
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
                                          fontSize: 13.5)),
                                ),
                                const SizedBox(width: 5),
                                Icon(meta.icon, size: 12, color: meta.color),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    [
                                      S.serviceName(service),
                                      if (price != null) 'Rs. $price',
                                      if (distanceLine == null) meta.label,
                                    ].join('  ·  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                                // Compact ETA/Distance Pill — माथिकै
                                // "Compact ETA/Distance Badge" कमेन्ट
                                // हेर्नुहोस्। हल्का teal-tinted pill, एउटै
                                // लाइनमा नै (थप line नचाहिने)।
                                if (distanceLine != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.kmTeal
                                          .withValues(alpha: 0.16),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      border: Border.all(
                                          color: AppColors.kmTeal
                                              .withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      distanceLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.kmTeal),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 2026 Glassmorphism Action Cluster — पहिले यी चारवटा
                      // (SOS/Cancel/Call/Message) बाँकी bare Material
                      // `IconButton` थिए, bar कै solid background माथि सीधै।
                      // अब एउटै frosted-glass pill cluster (`_GlassActionCluster`)
                      // भित्र — blur एकपटक मात्र (प्रत्येक गोलाकार बटनले
                      // आफ्नै छुट्टै BackdropFilter नदोहोर्‍याओस्, महँगो/धमिलो
                      // दुवै नहोस्) — र SOS/Cancel जस्ता urgent/destructive
                      // कार्यमा छुट्टै रङ-tinted "glow" (outer shadow) ले
                      // बाँकी (Call/Message) भन्दा दृश्यात्मक रूपमा अलग देखिने।
                      _GlassActionCluster(
                        children: [
                          // Emergency SOS — सधैँ देखिने (Call/Message जस्तो
                          // arrival-gate छैन; आपतकालीन बटन कहिल्यै लुक्न हुँदैन)।
                          _GlassActionButton(
                            icon: Icons.emergency_rounded,
                            color: AppColors.danger,
                            glow: true,
                            tooltip: S.sosButtonLabel,
                            onTap: () => _triggerSos(context, data),
                          ),
                          // सिधै देखिने Cancel — पहिले यो पूरै "job details"
                          // sheet (swipe-up/handle-tap मार्फत मात्र पुगिने)
                          // भित्रै मात्र थियो, कतै स्पष्ट/सिधै देखिने थिएन।
                          // SOS कै छेउमा, handle कै साथसाथै अझै भरपर्दो/छिटो
                          // सिधै तरिका।
                          if (_liveStatuses.contains(status))
                            _CancelIconButton(
                              onTap: () => _confirmCancel(context, data),
                            ),
                          // Arrival-Gated Communication — worker साँच्चै
                          // आइपुगेर status `in_progress` नभएसम्म Call/Message
                          // यहाँ देखिँदैनन्, स्वीकृति भइसकेको भए पनि।
                          if (isCommunicationUnlocked(status)) ...[
                            _GlassActionButton(
                              icon: Icons.call_rounded,
                              color: AppColors.igViolet,
                              tooltip: S.callWord,
                              onTap: () => _call(context, otherPhone),
                            ),
                            _GlassActionButton(
                              icon: Icons.chat_bubble_rounded,
                              color: AppColors.igViolet,
                              tooltip: S.messageWord,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    requestId: requestId,
                                    workerName: otherName,
                                    initialStatus: status,
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.lock_outline_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Optimistic UI — Cancel थिचेपछि Firestore बाट जवाफ नआउँदै (पहिले सम्भवतः
// 20-60s सम्म पर्खिनुपर्ने) बटन तुरुन्तै spinner मा बदलिन्छ, ताकि "बटन
// थिचेर पनि केही नहुने" जस्तो नदेखिओस्। [onTap] (जो पूरै confirm+reason
// dialog chain चलाउँछ) सकिएपछि मात्र फेरि साधारण बटनमा फिर्ता।
class _CancelIconButton extends StatefulWidget {
  final Future<void> Function() onTap;
  const _CancelIconButton({required this.onTap});

  @override
  State<_CancelIconButton> createState() => _CancelIconButtonState();
}

class _CancelIconButtonState extends State<_CancelIconButton> {
  bool _busy = false;

  Future<void> _handle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassActionButton(
      icon: Icons.close_rounded,
      color: AppColors.kmRose,
      glow: true,
      busy: _busy,
      tooltip: S.cancelRequest,
      onTap: _busy ? null : _handle,
    );
  }
}

/// 2026 Glassmorphism Action Cluster — SOS/Cancel/Call/Message लाई एउटै
/// frosted-glass pill भित्र बेर्ने साझा container। Blur एकपटक मात्र यहीं
/// (भित्रका बटनहरूले आफ्नै छुट्टै `BackdropFilter` नदोहोर्‍याउने) —
/// `GlassIconButton` (`widgets/glass_ui.dart`) कै उस्तै perf-सचेत ढाँचा।
class _GlassActionCluster extends StatelessWidget {
  final List<Widget> children;
  const _GlassActionCluster({required this.children});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: glassBackdrop(sigma: 14, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.kmGlass2Fill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.kmGlass2Border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2026 Glassmorphism Action Button — `_GlassActionCluster` भित्र प्रयोग
/// हुने गोलाकार pill बटन। आफ्नै blur छैन (cluster ले एकपटक मात्र दिइसकेको) —
/// केवल रङ-tinted fill/border + (urgent कार्यका लागि) बाहिरी "glow" shadow
/// + हल्का press-scale micro-interaction।
class _GlassActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool glow;
  final bool busy;

  const _GlassActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
    this.glow = false,
    this.busy = false,
  });

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    final btn = AnimatedScale(
      scale: _pressed ? 0.88 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.busy ? null : widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.color
                  .withValues(alpha: widget.glow ? 0.20 : 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color
                    .withValues(alpha: widget.glow ? 0.65 : 0.35),
                width: widget.glow ? 1.2 : 1,
              ),
              boxShadow: widget.glow
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: widget.busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: widget.color),
                  )
                : Icon(widget.icon, color: widget.color, size: 19),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}
