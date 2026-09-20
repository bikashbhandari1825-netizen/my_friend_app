// screens/request_tracking_screen.dart
// अनुरोध पठाएपछि ग्राहकले यहाँ स्थिति हेर्छ।
//  • status broadcasting/pending_worker → "नजिकका प्रदायक खोज्दै…" (radar animation)
//  • status accepted/confirmed        → साझा RouteMapView (झन्डा = स्थिर सेवा-
//                                        ठेगाना, दिशा-सूचक marker + कालो
//                                        polyline = कामदारको लाइभ स्थान/बाटो)
//                                        + Call/Message (Arrival-Gated)
//  • status declined/cancelled        → समाप्त सन्देश
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/counter_offer_card.dart';
import '../widgets/status_badge.dart';
import 'chat_screen.dart';
import 'job_actions.dart';
import 'nearby_common.dart';
import 'route_map_view.dart';

class RequestTrackingScreen extends StatefulWidget {
  final String requestId;
  const RequestTrackingScreen({super.key, required this.requestId});

  @override
  State<RequestTrackingScreen> createState() => _RequestTrackingScreenState();
}

class _RequestTrackingScreenState extends State<RequestTrackingScreen> {
  @override
  void initState() {
    super.initState();
    visibleRouteScreenRequestId = widget.requestId;
  }

  @override
  void dispose() {
    if (visibleRouteScreenRequestId == widget.requestId) {
      visibleRouteScreenRequestId = null;
    }
    super.dispose();
  }

  // ── worker accept गरेपछिको लाइभ ट्र्याकिङ — साझा RouteMapView (flag = स्थिर
  // job site, pulsing dot = कामदारको हालको स्थान, कालो polyline = बीचको
  // बाटो) प्रयोग गर्छ, यसले route मात्र थ्रोटल गरेर तान्छ ──
  RoadRoute? _liveRoute;
  LatLng? _lastRoutedWorkerPos;
  DateTime? _lastRouteFetch;

  // worker ले अझै लाइभ स्थान नलेखेको केसमा (उदाहरण: पुरानो data, वा accept
  // भइसकेको तर JobRouteScreen नखोलिएको) प्रोफाइलमा बचत भएको अन्तिम थाहा
  // भएको स्थान fallback — एकपटक मात्र fetch गर्न workerUid cache गरिएको।
  LatLng? _fallbackWorkerPos;
  String? _fallbackFetchedForUid;

  Future<void> _maybeLoadFallbackWorkerPos(String workerUid) async {
    if (workerUid.isEmpty || _fallbackFetchedForUid == workerUid) return;
    _fallbackFetchedForUid = workerUid;
    final last = await lastKnownProfileLocation(workerUid);
    if (last != null && mounted) {
      setState(() => _fallbackWorkerPos = LatLng(last.lat, last.lng));
    }
  }

  DocumentReference<Map<String, dynamic>> get _ref => FirebaseFirestore.instance
      .collection('serviceRequests')
      .doc(widget.requestId);

  /// worker ले JobRouteScreen मा छानेको यातायात मोड — यहीं उही route
  /// (सोही मोडको) देखियोस् भनेर हरेक fetch मा साथै पठाइन्छ।
  TravelMode _travelMode = TravelMode.driving;

  /// कामदार अलिकति चलेको वा केही सेकेन्ड भइसकेको भए मात्र OSRM route
  /// पुनः तान्ने — हरेक GPS अपडेटमा नहित्याउन।
  void _maybeFetchLiveRoute(LatLng worker, LatLng site, TravelMode mode) {
    final now = DateTime.now();
    final last = _lastRoutedWorkerPos;
    final modeChanged = mode != _travelMode;
    final moved = last == null ||
        haversineKm(last.latitude, last.longitude, worker.latitude,
                worker.longitude) >
            0.03;
    final due = _lastRouteFetch == null ||
        now.difference(_lastRouteFetch!) > const Duration(seconds: 15);
    if (!moved && !due && !modeChanged) return;
    _lastRoutedWorkerPos = worker;
    _lastRouteFetch = now;
    _travelMode = mode;
    fetchRoadRoute(worker, site, mode: mode).then((r) {
      if (mounted) setState(() => _liveRoute = r);
    });
  }

  Future<void> _cancel() async {
    // Cancelled Bookings Cleanup — status मात्र बदल्ने होइन, पूरै मेट्ने
    // (कुनै अवशेष history नरहोस्)। यो चरणमा (broadcasting/pending_worker)
    // अझै कुनै worker assign नभएकोले workerUid दिनु पर्दैन।
    await deleteCancelledBooking(widget.requestId);
    if (mounted) Navigator.pop(context);
  }

  // ── कामदारको counter-offer मा ग्राहकको जवाफ ────────────────────────────────
  // post-acceptance flow (transaction + agreedAmount/acceptedAt + worker लाई
  // in-app/push notification) `job_actions.dart` को साझा function मार्फत —
  // `price` param अब चाहिँदैन, transaction ले नै अहिलेकै मूल्य पढ्छ।
  Future<void> _acceptWorkerCounter() => acceptWorkerCounterOffer(
        context,
        widget.requestId,
      );

  Future<void> _declineWorkerCounter() async {
    await _ref.update({'status': 'declined'});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.decline), backgroundColor: AppColors.danger),
    );
    Navigator.pop(context);
  }

  /// "Decline / Counter back" — ग्राहकले आफ्नो नयाँ मूल्य कामदारलाई फिर्ता
  /// पठाउँछ, वा अनुरोध अस्वीकार गर्छ।
  Future<void> _counterBackToWorker(num current) async {
    final controller = TextEditingController(text: current.toString());
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.counterBack),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.yourPriceRs,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _declineWorkerCounter();
            },
            child: Text(S.declineJob,
                style: const TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.igViolet),
            onPressed: () async {
              final newPrice = num.tryParse(controller.text.trim());
              if (newPrice == null) return;
              Navigator.of(dialogContext).pop();
              await _ref.update({
                'status': 'pending_worker_counter',
                'employerCounterPrice': newPrice,
                'counterFrom': 'employer',
                'employerCounteredAt': FieldValue.serverTimestamp(),
              });
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(S.counterSentToWorker)),
              );
            },
            child: Text(S.sendNewPrice,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // नक्सा भएको जुनसुकै state (यो पहिलो loading spinner होस्, वा
      // पछि आउने साँचो नक्सा) एउटै हल्का रङमा — dark theme को झन्डै-कालो
      // default background मा होइन। "Track on map" थिचेपछि native
      // Google Map view attach हुन एक क्षण लाग्छ; Scaffold नै सुरुदेखि यो
      // रङमा भए त्यो क्षणभरको खाली ठाउँ नक्सासँगै मिल्छ — कालो/खैरो
      // flash कहिल्यै देखिँदैन।
      backgroundColor: AppColors.mapPlaceholderBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
        title: Text(S.trackOnMap,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data?.data();
          if (data == null) {
            return _Ended(
              icon: Icons.info_outline_rounded,
              title: S.requestCancelled,
              onBack: () => Navigator.pop(context),
            );
          }

          final status = (data['status'] ?? 'broadcasting').toString();

          if (status == 'declined' ||
              status == 'cancelled' ||
              status == 'no_provider') {
            return _Ended(
              icon: Icons.cancel_outlined,
              title: status == 'declined'
                  ? S.noProviderAccepted
                  : S.requestCancelled,
              onBack: () => Navigator.pop(context),
            );
          }

          if (status == 'broadcasting' || status == 'pending_worker') {
            final myLat = (data['employerLat'] as num?)?.toDouble() ??
                (data['lat'] as num?)?.toDouble() ??
                fallbackLat;
            final myLng = (data['employerLng'] as num?)?.toDouble() ??
                (data['lng'] as num?)?.toDouble() ??
                fallbackLng;
            return _Searching(
              service: (data['service'] ?? '').toString(),
              center: LatLng(myLat, myLng),
              onCancel: _cancel,
            );
          }

          // कामदारले मूल्य काउन्टर गर्‍यो → live high-impact alert card।
          // "previous" = ग्राहकको आफ्नै पछिल्लो प्रस्ताव — पहिलो round मा
          // proposedPrice (मूल budget), दोस्रो/तेस्रो/...round मा भने
          // employerCounterPrice (आफैले पछिल्लो पटक counter गरेको मूल्य)।
          // सधैँ proposedPrice मात्र देख्दा दोस्रो round पछि negotiation
          // "अड्किएको"/भ्रमपूर्ण देखिन्थ्यो — असीमित round चल्दा पनि सही
          // history देखियोस् भनेर unlimited counter-offer fix कै भाग।
          if (status == 'pending_employer_approval') {
            final prev = (data['employerCounterPrice'] as num?) ??
                (data['proposedPrice'] as num?) ??
                0;
            final counter = (data['workerCounterPrice'] as num?) ?? prev;
            return Container(
              decoration: const BoxDecoration(gradient: AppColors.igGradient),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: CounterOfferCard(
                      heading:
                          '${data['workerName'] ?? S.customerWord}  ·  ${S.serviceName((data['service'] ?? '').toString())}',
                      title: S.workerCounteredTitle,
                      body: S.workerCounteredBody,
                      previousPrice: prev,
                      newPrice: counter,
                      acceptLabel: S.acceptCounterOffer,
                      onAccept: _acceptWorkerCounter,
                      onCounterBack: () => _counterBackToWorker(counter),
                    ),
                  ),
                ),
              ),
            );
          }

          // accepted / confirmed / pending_worker_counter →
          // काम पुष्टि — स्थिर job site (flag) + कामदारको लाइभ स्थान (worker ले
          // JobRouteScreen मार्फत पठाएको) बीच कालो live route polyline।
          final empLat = (data['employerLat'] as num?)?.toDouble();
          final empLng = (data['employerLng'] as num?)?.toDouble();
          final site = (empLat != null && empLng != null)
              ? LatLng(empLat, empLng)
              : const LatLng(fallbackLat, fallbackLng);

          final wLat = (data['workerLat'] as num?)?.toDouble();
          final wLng = (data['workerLng'] as num?)?.toDouble();
          final liveWorkerPos =
              (wLat != null && wLng != null) ? LatLng(wLat, wLng) : null;
          // लाइभ स्थान अझै नआएको भए — प्रोफाइलमा बचत भएको अन्तिम थाहा भएको
          // स्थान fallback (job_actions.dart ले accept/counter गर्ने बेलै
          // लेखिसकेको हुनुपर्ने हो, तर पुरानो data/edge-case भेटिए पनि
          // employer को नक्सा कहिल्यै स्थायी रूपमा खाली नरहोस्)।
          final workerUid = (data['workerUid'] ?? '').toString();
          if (liveWorkerPos == null && workerUid.isNotEmpty) {
            _maybeLoadFallbackWorkerPos(workerUid);
          }
          final workerPos = liveWorkerPos ?? _fallbackWorkerPos;
          final travelMode = TravelMode.fromValue(data['travelMode'] as String?);
          if (workerPos != null) {
            _maybeFetchLiveRoute(workerPos, site, travelMode);
          } else {
            _liveRoute = null;
          }

          return Stack(
            children: [
              // ── साझा route-map widget — worker/employer दुवैतिर उही class ──
              RouteMapView(
                origin: workerPos,
                originLabel:
                    (data['workerName'] ?? S.workerRoleWord).toString(),
                destination: site,
                destinationLabel: S.jobLocationTitle,
                destinationAddress: (data['address'] ?? '').toString(),
                route: _liveRoute,
                travelMode: travelMode,
                // employer यहाँ आफैं कतै जाँदैन — worker कहाँ पुग्दैछ भनेर हेर्ने
                // (Live Track on Map) मात्र हो, त्यसैले `navigateTarget`
                // जानाजानी दिइएको छैन: worker-तर्फको JobRouteScreen जस्तो
                // पूर्ण "Open in Google Maps" turn-by-turn navigation बटन
                // employer को स्क्रिनमा नआओस् भनेर। त्यो नियन्त्रण worker कै
                // (आफ्नो गन्तव्यसम्म पुग्ने) एपमा मात्र सीमित हुनुपर्छ।
                //
                // आफ्नै (employer) GPS यहाँ अप्रासंगिक — यो worker को स्थान
                // नआएको हो, "आफ्नो location on गर्नुहोस्" भन्दा भ्रमपूर्ण हुन्थ्यो।
                originMissingMessage: S.waitingForWorkerLocation,
                mapPadding: const EdgeInsets.only(bottom: 210, top: 64),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ProviderTrackCard(
                  requestId: widget.requestId,
                  data: data,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Searching — live नक्सा पृष्ठभूमि + InDrive-style radar overlay ────────────
class _Searching extends StatefulWidget {
  final String service;
  final LatLng center;
  final VoidCallback onCancel;
  const _Searching({
    required this.service,
    required this.center,
    required this.onCancel,
  });

  @override
  State<_Searching> createState() => _SearchingState();
}

class _SearchingState extends State<_Searching>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  GoogleMapController? _map;
  BitmapDescriptor? _meIcon;

  // झन्डाकै फेदमुनिको radar-wave — छुट्टै Flutter overlay/getScreenCoordinate
  // ट्र्याकिङ होइन, झन्डाकै ठ्याक्कै उही `position` मा अर्को native Marker
  // हो। यसैले zoom/pan गर्दा झन्डाको केन्द्रबिन्दुबाट यो कहिल्यै
  // विचलित/छुट्टिँदैन — दुवै marker लाई Google Maps आफैंले एउटै क्यामेरा
  // transform बाट सँगसँगै कोर्छ।
  List<BitmapDescriptor>? _waveFrames;

  @override
  void initState() {
    super.initState();
    destinationFlagPin().then((b) {
      if (mounted) setState(() => _meIcon = b);
    });
    radarWaveFrames(AppColors.igPink).then((frames) {
      if (mounted) setState(() => _waveFrames = frames);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // ── प्रत्यक्ष Google Map पृष्ठभूमि — radar-wave frame छान्ने काम
        // यहीँ `AnimatedBuilder` भित्रै मात्र (पहिले जस्तो State-level
        // `setState` हरेक tick मा (~सेकेन्डको ५-६ पटक) पूरै build() — तल्लो
        // info card/shadow/Column सहित — दोहोर्‍याउँदैनथ्यो, अब नक्सा
        // widget मात्र फेरि बन्छ, बाँकी सबै एकपटक मात्र)।
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final frames = _waveFrames;
            final idx = frames == null
                ? 0
                : (_c.value * frames.length).floor() % frames.length;
            return GoogleMap(
              // Close-up — street/house-level, घर/क्षेत्रको वरपर प्रष्ट देखिने।
              initialCameraPosition:
                  CameraPosition(target: widget.center, zoom: 18.5),
              onMapCreated: (c) => _map = c,
              myLocationEnabled: _meIcon == null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर "उल्टो"
              // देखिने बग नआओस्।
              rotateGesturesEnabled: false,
              markers: {
                // radar-wave झन्डाकै फेदमुनि — ठ्याक्कै उही `position`
                // भएकोले कहिल्यै छुट्टिँदैन (माथि class-doc हेर्नुहोस्)।
                if (frames != null)
                  Marker(
                    markerId: const MarkerId('wave'),
                    position: widget.center,
                    icon: frames[idx],
                    anchor: const Offset(0.5, 0.5),
                    zIndexInt: 1,
                  ),
                if (_meIcon != null)
                  Marker(
                    markerId: const MarkerId('me'),
                    position: widget.center,
                    icon: _meIcon!,
                    anchor: FlagPinGeometry.markerAnchorFraction,
                    zIndexInt: 2,
                  ),
              },
            );
          },
        ),

        // ── तल्लो जानकारी कार्ड (full-screen gradient होइन) ──
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation(AppColors.igPink),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(S.findingProviders,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(S.waitingAccept,
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(S.cancelRequest),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Ended state ──────────────────────────────────────────────────────────────
class _Ended extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onBack;
  const _Ended({required this.icon, required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.igGradient),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white70),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
                child:
                    Text(S.back, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Job status card (assigned worker + fixed address) ───────────────────────
// नक्सा/दूरी/समय/"Open in Google Maps" अब माथिको साझा RouteMapView ले नै
// देखाउँछ — यो card ले काम (नाम, मूल्य, ठेगाना) + Call/Message मात्र देखाउँछ।
class _ProviderTrackCard extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  const _ProviderTrackCard({
    required this.requestId,
    required this.data,
  });

  Future<void> _callWorker(BuildContext context, String phone) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.noPhoneOnFile)));
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (data['workerName'] ?? 'Provider').toString();
    final service = (data['service'] ?? '').toString();
    final phone = (data['workerPhone'] ?? '').toString();
    // सधैँ पछिल्लो मूल्य देखाउने — पुरानो proposedPrice मा नअड्किने।
    final price = data['finalPrice'] ??
        data['employerCounterPrice'] ??
        data['workerCounterPrice'] ??
        data['proposedPrice'];
    final address = (data['address'] ?? '').toString();
    final status = (data['status'] ?? 'accepted').toString();
    final arrived = data['arrivedAt'] != null;
    final travelMode = TravelMode.fromValue(data['travelMode'] as String?);

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.igGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        boxShadow: [
          BoxShadow(
              color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            JobProgressBar(status: status, onDark: true),
            // "Worker has arrived at the location" — arrival हुनेबित्तिकै
            // (push notification कै सँगसँगै) यहाँ पनि प्रस्ट देखिने, ताकि
            // employer app भित्रै हुँदा पनि तुरुन्तै थाहा पाओस्।
            if (arrived) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(S.workerArrivedNotifTitle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(jobStatusMeta(status).icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(jobStatusMeta(status).label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0x22833AB4),
                        child: Icon(serviceIconFor(service),
                            color: AppColors.igViolet),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(
                              [
                                S.serviceName(service),
                                if (price != null) 'Rs. $price',
                              ].join('  ·  '),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Multi-modal यातायात — दुवैतिरबाट (worker वा employer)
                  // छान्न मिल्ने एउटै interactive chip row, JobRouteScreen
                  // मा भएकै जस्तै। जसले पनि tap गरे पनि उही Firestore
                  // फिल्डमा लेखिन्छ र अर्को पक्षले पनि तुरुन्तै देख्छ।
                  const SizedBox(height: 10),
                  TravelModeChips(
                    selected: travelMode,
                    onChanged: (m) => FirebaseFirestore.instance
                        .collection('serviceRequests')
                        .doc(requestId)
                        .set({'travelMode': m.value}, SetOptions(merge: true)),
                  ),
                  if (address.isNotEmpty) ...[
                    const Divider(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 15, color: Colors.black45),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(address,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ),
                      ],
                    ),
                  ],
                  // फोन नम्बर सिधै देखिने — Call बटन थिच्नुअघि नै थाहा
                  // होस्/कल गर्न सजिलो होस् भनेर, लुकेको Call बटनमा मात्र
                  // सीमित नराखी। तर worker साँच्चै आइपुगेपछि मात्र — Arrival-
                  // Gated Communication (job_actions.dart::isCommunicationUnlocked)।
                  if (isCommunicationUnlocked(status) && phone.isNotEmpty) ...[
                    const Divider(height: 16),
                    GestureDetector(
                      onTap: () => _callWorker(context, phone),
                      child: Row(
                        children: [
                          const Icon(Icons.call_rounded,
                              size: 15, color: AppColors.igViolet),
                          const SizedBox(width: 6),
                          Text(phone,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.igViolet)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Arrival-Gated Communication — worker साँच्चै आइपुगेर status
            // `in_progress` नभएसम्म Call/Video/Message लुकेका रहन्छन्।
            if (isCommunicationUnlocked(status))
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callWorker(context, phone),
                      icon:
                          const Icon(Icons.call_rounded, color: Colors.white),
                      label: Text(S.callWord,
                          style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => startInAppCall(
                        context,
                        requestId: requestId,
                        otherName: name,
                        video: true,
                      ),
                      icon: const Icon(Icons.videocam_rounded,
                          color: Colors.white),
                      label: Text(S.videoCall,
                          style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            requestId: requestId,
                            workerName: name,
                            initialStatus: status,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: Text(S.messageWord,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.igViolet,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(S.contactLockedAwaitingArrival,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
