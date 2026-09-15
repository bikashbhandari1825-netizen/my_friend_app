// screens/job_map_screen.dart
// कामदारको "कामको सूची" (dashboard) को Live Map layer — inDrive/Pathao-शैली:
// पृष्ठभूमिमा पूरा-स्क्रिन Google Map, आफ्नो हालको स्थान (pulsing dot) +
// नजिकका broadcasting job हरू सेवा-अनुसार रङ्गीन pin मार्फत। Pin थिच्दा त्यही
// काम स्वीकार्ने/अस्वीकार्ने/मूल्य प्रस्ताव गर्ने sheet खुल्छ।
//
// JobFeedScreen ले यसलाई पूरा-स्क्रिन पृष्ठभूमि तहको रूपमा embed गर्छ (आफ्नै
// Scaffold/AppBar छैन) — स्थान/दूरी/सीप filter सबै parent बाट आउँछ ताकि map
// र माथिको draggable list सधैँ उस्तै काम देखाउँछन्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'job_actions.dart';
import 'nearby_common.dart';

class JobsMapLayer extends StatefulWidget {
  final double lat;
  final double lng;
  final int? radiusKm;
  final String trade; // '__mine__' | '__all__' | service name
  final String myService;
  /// Map को तल्लो किनारमा कति ठाउँ छोप्ने (draggable sheet ले) — recentre
  /// FAB त्यसमाथि राख्न, र camera padding मिलाउन।
  final double bottomInset;

  const JobsMapLayer({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.trade,
    required this.myService,
    this.bottomInset = 0,
  });

  @override
  State<JobsMapLayer> createState() => _JobsMapLayerState();
}

class _JobsMapLayerState extends State<JobsMapLayer> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  GoogleMapController? _map;
  bool _centeredOnce = false;
  BitmapDescriptor? _meIcon;

  final Stream<QuerySnapshot<Map<String, dynamic>>> _jobsStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('status', isEqualTo: 'broadcasting')
          .snapshots();

  @override
  void initState() {
    super.initState();
    pulseDotMarker(AppColors.igViolet).then((bd) {
      if (mounted) setState(() => _meIcon = bd);
    });
  }

  @override
  void didUpdateWidget(covariant JobsMapLayer old) {
    super.didUpdateWidget(old);
    // सटीक GPS fix आउनेबित्तिकै (fallback बाट real location मा सर्दा) एकपटक
    // camera लाई त्यहाँ centre गर्ने — हरेक सानो movement मा भने होइन (नत्र
    // कामदार आफैं हिँड्दा नक्सा पटक-पटक jerk हुन्छ)।
    if (!_centeredOnce &&
        (old.lat != widget.lat || old.lng != widget.lng) &&
        _map != null) {
      _recentre();
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _recentre() async {
    if (_map == null) return;
    await _map!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(widget.lat, widget.lng), 13.5),
    );
    _centeredOnce = true;
  }

  bool _passesFilters(Map<String, dynamic> data) {
    final rejected = (data['rejectedBy'] as List?) ?? const [];
    if (rejected.contains(_uid)) return false;
    final svc = (data['service'] ?? '').toString();
    final wantTrade = widget.trade == '__mine__'
        ? widget.myService
        : (widget.trade == '__all__' ? '' : widget.trade);
    if (wantTrade.isNotEmpty && svc.toLowerCase() != wantTrade.toLowerCase()) {
      return false;
    }
    return true;
  }

  Future<Set<Marker>> _buildMarkers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('__me__'),
        position: LatLng(widget.lat, widget.lng),
        icon: _meIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
        consumeTapEvents: true,
      ),
    };

    for (final d in docs) {
      final data = d.data();
      if (!_passesFilters(data)) continue;
      final jLat = (data['employerLat'] as num?)?.toDouble();
      final jLng = (data['employerLng'] as num?)?.toDouble();
      if (jLat == null || jLng == null) continue;
      final km = haversineKm(widget.lat, widget.lng, jLat, jLng);
      if (widget.radiusKm != null && km > widget.radiusKm!) continue;

      final svc = (data['service'] ?? '').toString();
      final icon = await categoryPinMarker(svc);
      markers.add(
        Marker(
          markerId: MarkerId(d.id),
          position: LatLng(jLat, jLng),
          icon: icon,
          infoWindow: InfoWindow(
            title: S.serviceName(svc),
            snippet: S.distanceLabel(km),
          ),
          onTap: () => _openJobSheet(d.id, data, km),
        ),
      );
    }
    return markers;
  }

  void _openJobSheet(String docId, Map<String, dynamic> data, double km) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JobMapSheet(
        docId: docId,
        data: data,
        distanceKm: km,
        myService: widget.myService,
        // sheet बन्द भएपछि पनि ScaffoldMessenger/Navigator चाहिने काम
        // (accept/counter) यही stable, कहिल्यै deactivate नहुने context
        // मार्फत गर्ने — sheet आफ्नै context pop भएलगत्तै अमान्य हुन्छ।
        outerContext: context,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _jobsStream,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return FutureBuilder<Set<Marker>>(
              future: _buildMarkers(docs),
              builder: (context, markerSnap) {
                return GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(widget.lat, widget.lng),
                    zoom: 13.5,
                  ),
                  onMapCreated: (c) {
                    _map = c;
                    if (!_centeredOnce) _recentre();
                  },
                  padding: EdgeInsets.only(bottom: widget.bottomInset),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर "उल्टो"
                  // देखिने बग नआओस्।
                  rotateGesturesEnabled: false,
                  markers: markerSnap.data ?? const {},
                );
              },
            );
          },
        ),
        Positioned(
          right: 12,
          bottom: widget.bottomInset + 12,
          child: FloatingActionButton.small(
            heroTag: 'jobsMapRecentre',
            onPressed: _recentre,
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }
}

class _JobMapSheet extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final double distanceKm;
  final String myService;
  final BuildContext outerContext;

  const _JobMapSheet({
    required this.docId,
    required this.data,
    required this.distanceKm,
    required this.myService,
    required this.outerContext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = (data['service'] ?? '').toString();
    final desc = (data['details'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final budget = data['proposedPrice'];
    final skillMismatch =
        myService.isNotEmpty && myService.toLowerCase() != service.toLowerCase();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0x11833AB4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    serviceImageFor(service),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                        serviceIconFor(service),
                        color: AppColors.igViolet),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.serviceName(service),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15.5)),
                      Text(S.distanceLabel(distanceKm),
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black45)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.igRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('${S.customerBudget}: Rs. $budget',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.igRed)),
                ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(desc,
                  style:
                      const TextStyle(fontSize: 13.5, color: Colors.black87)),
            ],
            if (address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined,
                      size: 16, color: Colors.black45),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(address,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.black54)),
                  ),
                ],
              ),
            ],
            if (skillMismatch) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(S.notAuthorizedForJobCategory,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      declineBroadcastJob(docId);
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: Text(S.decline),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: skillMismatch
                        ? null
                        : () {
                            Navigator.pop(context);
                            counterBroadcastJob(outerContext, docId, data,
                                myService: myService);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.igViolet,
                      side: const BorderSide(color: AppColors.igViolet),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: Text(S.offerPrice, textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: skillMismatch
                        ? null
                        : () {
                            Navigator.pop(context);
                            acceptBroadcastJob(outerContext, docId, data,
                                myService: myService);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.igViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: Text(S.accept,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
