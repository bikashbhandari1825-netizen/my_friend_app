// screens/request_tracking_screen.dart
// अनुरोध पठाएपछि ग्राहकले यहाँ स्थिति हेर्छ।
//  • status broadcasting/pending_worker → "नजिकका प्रदायक खोज्दै…" (radar animation)
//  • status accepted/confirmed        → साझा RouteMapView (झन्डा = स्थिर सेवा-
//                                        ठेगाना, दिशा-सूचक marker + कालो
//                                        polyline = कामदारको लाइभ स्थान/बाटो)
//                                        + Call/Message (Arrival-Gated)
//  • status declined/cancelled        → समाप्त सन्देश
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/counter_offer_card.dart';
import '../widgets/glass_ui.dart';
import '../widgets/status_badge.dart';
import '../widgets/worker_avatar.dart';
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
    // किन cancel गर्दै भन्ने छोटो कारण — sheet बन्द गरे (null) भने cancel
    // नै नगर्ने, यही स्क्रिनमै बसिरहने।
    final reason = await pickCancellationReason(context);
    if (reason == null || !mounted) return;
    // Cancelled Bookings Cleanup — status मात्र बदल्ने होइन, पूरै मेट्ने
    // (कुनै अवशेष history नरहोस्)। यो चरणमा (broadcasting/pending_worker)
    // अझै कुनै worker assign नभएकोले workerUid दिनु पर्दैन।
    await deleteCancelledBooking(widget.requestId, reason: reason);
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
      SnackBar(content: Text(S.decline), backgroundColor: AppColors.kmRose),
    );
    Navigator.pop(context);
  }

  /// "Decline / Counter back" — ग्राहकले आफ्नो नयाँ मूल्य कामदारलाई फिर्ता
  /// पठाउँछ, वा अनुरोध अस्वीकार गर्छ।
  Future<void> _counterBackToWorker(num current) async {
    final controller = TextEditingController(text: current.toString());
    await showKmDialog(
      context: context,
      title: S.counterBack,
      icon: Icons.price_change_rounded,
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        style: const TextStyle(color: AppColors.kmText),
        decoration: kmInputDecoration(S.yourPriceRs),
      ),
      actions: [
        KmDialogAction(
          label: S.declineJob,
          destructive: true,
          onPressed: () {
            Navigator.of(context).pop();
            _declineWorkerCounter();
          },
        ),
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        KmDialogAction(
          label: S.sendNewPrice,
          filled: true,
          onPressed: () async {
            final newPrice = num.tryParse(controller.text.trim());
            if (newPrice == null) return;
            Navigator.of(context).pop();
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
        ),
      ],
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
        foregroundColor: AppColors.kmText,
        elevation: 0,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.kmVoid.withValues(alpha: 0.82)),
        ),
        title: Text(S.trackOnMap,
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w800)),
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
              status == 'cancelled_by_admin' ||
              status == 'no_provider') {
            final isRide = (data['isRide'] ?? false) == true;
            return _Ended(
              icon: Icons.cancel_outlined,
              title: status == 'declined'
                  ? (isRide ? S.noDriverAccepted : S.noProviderAccepted)
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
              requestId: widget.requestId,
              service: (data['service'] ?? '').toString(),
              center: LatLng(myLat, myLng),
              onCancel: _cancel,
              isRide: (data['isRide'] ?? false) == true,
              autoOffer: (data['autoOffer'] ?? false) == true,
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
            return AuroraBackground(
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
          //
          // Ride (Bike/Car) मा राइड 'in_progress' भइसकेपछि (OTP मिलेर सुरु
          // भएपछि) "flag" अब pickup होइन — driver अब गन्तव्य (destinationLat/
          // Lng) तर्फ जाँदैछ, त्यसैले नक्साको स्थिर बिन्दु पनि त्यतै सर्नुपर्छ।
          final isRideJob = (data['isRide'] ?? false) == true;
          final destLat = (data['destinationLat'] as num?)?.toDouble();
          final destLng = (data['destinationLng'] as num?)?.toDouble();
          final empLat = (data['employerLat'] as num?)?.toDouble();
          final empLng = (data['employerLng'] as num?)?.toDouble();
          final useDestination =
              isRideJob && status == 'in_progress' && destLat != null && destLng != null;
          final site = useDestination
              ? LatLng(destLat, destLng)
              : (empLat != null && empLng != null)
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
                destinationLabel:
                    useDestination ? S.destinationLabel : S.jobLocationTitle,
                destinationAddress: useDestination
                    ? (data['destinationAddress'] ?? '').toString()
                    : (data['address'] ?? '').toString(),
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
  final String requestId;
  final String service;
  final LatLng center;
  final VoidCallback onCancel;
  // Ride-Hailing (Bike/Car) मात्र — driver प्रस्तावहरूको live list पनि
  // यहीँ देखिन्छ (नत्र सामान्य सेवाको उही पुरानो radar-मात्र UI)।
  final bool isRide;
  final bool autoOffer;
  const _Searching({
    required this.requestId,
    required this.service,
    required this.center,
    required this.onCancel,
    this.isRide = false,
    this.autoOffer = false,
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
  // Auto-Offer — पहिलो pending प्रस्ताव आउनेबित्तिकै एकपटक मात्र auto-accept
  // गर्न — StreamBuilder हरेक अपडेटमा फेरि बन्ने भएकोले दोहोरिन नदिन guard।
  bool _autoAccepting = false;

  // झन्डाकै फेदमुनिको radar-wave — छुट्टै Flutter overlay/getScreenCoordinate
  // ट्र्याकिङ होइन, झन्डाकै ठ्याक्कै उही `position` मा अर्को native Marker
  // हो। यसैले zoom/pan गर्दा झन्डाको केन्द्रबिन्दुबाट यो कहिल्यै
  // विचलित/छुट्टिँदैन — दुवै marker लाई Google Maps आफैंले एउटै क्यामेरा
  // transform बाट सँगसँगै कोर्छ।
  List<BitmapDescriptor>? _waveFrames;

  // Ride-Hailing — प्रस्ताव पठाउँदा driver-ले snapshot गरेको स्थान
  // (`job_actions.dart::submitRideOffer`) बाट बनेका marker — offers
  // StreamBuilder ले अद्यावधिक गर्छ (नयाँ/हटेको प्रस्ताव आए यही set फेरि
  // बन्छ, GoogleMap ले तुरुन्तै देखाउँछ)।
  Set<Marker> _driverMarkers = const {};

  @override
  void initState() {
    super.initState();
    destinationFlagPin().then((b) {
      if (mounted) setState(() => _meIcon = b);
    });
    radarWaveFrames(AppColors.kmPink).then((frames) {
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
    return PopScope(
      // Back Navigation (Ride-Hailing मात्र) — यो widget सधैँ status
      // 'broadcasting'/'pending_worker' हुँदा मात्र देखिन्छ (parent कै
      // StreamBuilder ले नै त्यही बेला यसलाई देखाउने निर्णय गर्छ), त्यसैले
      // `widget.isRide` लाई नै पर्याप्त/सधैँ ताजा जाँच मान्न सकिन्छ — कुनै
      // stale-outer-build जोखिम छैन (यो State आफैं हरेक snapshot मा ताजा
      // widget property पाउँछ)। सिधै pop हुन नदिई पहिले खोजी नै cancel
      // गर्ने (`onCancel` आफैंले pop पनि गर्छ), नत्र यो request Firestore
      // मा orphan "broadcasting" भई बसिरहन्थ्यो।
      canPop: !widget.isRide,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        widget.onCancel();
      },
      child: Stack(
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
                ..._driverMarkers,
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
            child: GlassPanel(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              radius: AppRadius.lg,
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
                          valueColor: AlwaysStoppedAnimation(AppColors.kmPink),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.isRide ? S.findingDrivers : S.findingProviders,
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(widget.isRide ? S.waitingDriverAccept : S.waitingAccept,
                                style: const TextStyle(color: AppColors.kmMuted)),
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
                        foregroundColor: AppColors.kmRose,
                        side: const BorderSide(color: AppColors.kmRose),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Ride-Hailing (Bike/Car) — driver प्रस्तावहरूको live list ──
        if (widget.isRide)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 12,
            bottom: 200,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(widget.requestId)
                  .collection('rideOffers')
                  .where('status', whereIn: ['pending', 'passenger_countered'])
                  .snapshots(),
              builder: (context, snap) {
                final offers = snap.data?.docs ?? const [];
                // Driver marker — हरेक प्रस्तावको snapshot स्थान (माथि
                // class-doc हेर्नुहोस्)। यो नेस्टेड StreamBuilder फेरि build
                // हुँदैमा parent `_SearchingState` (माथिको GoogleMap जसले
                // `_driverMarkers` पढ्छ) आफैं भने फेरि build हुँदैन — त्यसैले
                // सिधै field मात्र बदल्नुको सट्टा अर्को frame मा explicit
                // `setState` तानिनुपर्छ (यही build को बीचमा setState गर्न
                // मिल्दैन)।
                final newMarkers = {
                  for (final d in offers)
                    if ((d.data()['workerLat'] as num?) != null &&
                        (d.data()['workerLng'] as num?) != null)
                      Marker(
                        markerId: MarkerId('driver_${d.id}'),
                        position: LatLng(
                            (d.data()['workerLat'] as num).toDouble(),
                            (d.data()['workerLng'] as num).toDouble()),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueViolet),
                        anchor: const Offset(0.5, 0.5),
                        zIndexInt: 3,
                        infoWindow: InfoWindow(
                            title: (d.data()['workerName'] ?? '').toString()),
                      ),
                };
                if (newMarkers.length != _driverMarkers.length ||
                    !newMarkers.containsAll(_driverMarkers)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _driverMarkers = newMarkers);
                  });
                }
                // Auto-Offer — पहिलो साँच्चै 'pending' (negotiate भइरहेको
                // होइन) प्रस्ताव आउनेबित्तिकै एकपटक मात्र auto-accept।
                final pendingOnly = offers
                    .where((d) => (d.data()['status'] ?? '') == 'pending')
                    .toList();
                if (widget.autoOffer && !_autoAccepting && pendingOnly.isNotEmpty) {
                  _autoAccepting = true;
                  final first = pendingOnly.first;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      acceptRideOffer(
                          context, widget.requestId, first.id, first.data());
                    }
                  });
                }
                if (offers.isEmpty) return const SizedBox.shrink();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                          '${S.driverOffersLabel} (${offers.length})',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: offers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final d = offers[i];
                          return RepaintBoundary(
                            key: ValueKey(d.id),
                            child: _RideOfferCard(
                              requestId: widget.requestId,
                              offerId: d.id,
                              offer: d.data(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
      ),
    );
  }
}

/// एउटा driver-प्रस्ताव — नाम, सवारी, rating, भाडा + Accept/Decline।
class _RideOfferCard extends StatelessWidget {
  final String requestId;
  final String offerId;
  final Map<String, dynamic> offer;
  const _RideOfferCard({
    required this.requestId,
    required this.offerId,
    required this.offer,
  });

  @override
  Widget build(BuildContext context) {
    final name = (offer['workerName'] ?? '—').toString();
    final make = (offer['vehicleMake'] ?? '').toString();
    final model = (offer['vehicleModel'] ?? '').toString();
    final plate = (offer['vehiclePlate'] ?? '').toString();
    // पुरानो worker record (structured field अझै नभएको) मा composed
    // सारांशमा नै फर्कने — कहिल्यै खाली नदेखियोस्।
    final vehicleLine = [make, model].where((s) => s.isNotEmpty).join(' ');
    final vehicle = vehicleLine.isNotEmpty
        ? vehicleLine
        : (offer['vehicleDetails'] ?? '').toString();
    final rating = (offer['rating'] as num?)?.toDouble() ?? 0;
    final completedRides = (offer['completedRides'] as num?)?.toInt() ?? 0;
    final price = offer['offerPrice'];
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      radius: AppRadius.md,
      fill: AppColors.kmSurface.withValues(alpha: 0.88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // driver-को साँचो फोटो (registration selfie) — कहिल्यै अपलोड
              // नभएको/लोड नभएको भए आफैं generic icon मा fallback गर्छ।
              WorkerAvatar(
                uid: (offer['workerUid'] ?? '').toString(),
                size: 36,
                iconColor: AppColors.kmInk,
                backgroundColor: AppColors.kmOrange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: AppColors.kmText,
                            fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (vehicle.isNotEmpty)
                      Text(vehicle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.kmMuted)),
                    if (plate.isNotEmpty)
                      Text('${S.vehiclePlateLabel}: $plate',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.kmMuted)),
                    if (rating > 0 || completedRides > 0)
                      Row(
                        children: [
                          if (rating > 0) ...[
                            const Icon(Icons.star_rounded,
                                size: 14, color: AppColors.kmAmber),
                            const SizedBox(width: 2),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                          ],
                          if (rating > 0 && completedRides > 0)
                            const Text(' · ',
                                style: TextStyle(
                                    color: AppColors.kmMuted, fontSize: 11.5)),
                          if (completedRides > 0)
                            Text(S.ridesCountShort(completedRides),
                                style: const TextStyle(
                                    color: AppColors.kmMuted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),
              ),
              Text('Rs. $price',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.kmOrange)),
            ],
          ),
          const SizedBox(height: 10),
          if ((offer['status'] ?? 'pending') == 'passenger_countered')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.kmOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${S.waitingAccept} · Rs. ${offer['passengerCounterPrice']}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.kmOrange),
              ),
            )
          else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => declineRideOffer(requestId, offerId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kmRose,
                    side: const BorderSide(color: AppColors.kmRose),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(S.decline),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => negotiateRideOffer(
                      context, requestId, offerId, (price as num?) ?? 0),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kmOrange,
                    side: const BorderSide(color: AppColors.kmOrange),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(S.counterBack, style: const TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      acceptRideOffer(context, requestId, offerId, offer),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.kmOrange,
                    foregroundColor: AppColors.kmInk,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(S.accept,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
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
    return AuroraBackground(
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.kmText, size: 64),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.kmMuted),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
                child: Text(S.back,
                    style: const TextStyle(color: AppColors.kmText)),
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
    // Ride-Start OTP — driver आइपुगेपछि यही कोड सुनाउनुपर्छ; राइड
    // 'in_progress' नभएसम्म (अझै driver ले verify नगरेसम्म) मात्र देखिने।
    final isRide = service == 'Bike' || service == 'Car';
    final rideStartCode = (data['rideStartCode'] ?? '').toString();

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
      decoration: BoxDecoration(
        color: AppColors.kmSurface.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        boxShadow: const [
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
            // Ride-Start OTP — driver आइपुगेर राइड सुरु नगरेसम्म (status अझै
            // 'in_progress' नभएसम्म) पासेन्जरलाई सधैँ प्रस्ट देखिने।
            if (isRide && rideStartCode.isNotEmpty && status != 'in_progress') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppColors.kmCtaGradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.password_rounded,
                        color: AppColors.kmInk, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.shareCodeWithDriver,
                              style: const TextStyle(
                                  color: AppColors.kmInk,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11)),
                          Text(rideStartCode,
                              style: const TextStyle(
                                  color: AppColors.kmInk,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  letterSpacing: 6)),
                        ],
                      ),
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
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // driver को साँचो फोटो (registration selfie)।
                      WorkerAvatar(
                        uid: (data['workerUid'] ?? '').toString(),
                        size: 44,
                        iconColor: AppColors.kmInk,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(
                              [
                                S.serviceName(service),
                                if (price != null) 'Rs. $price',
                              ].join('  ·  '),
                              style: const TextStyle(color: AppColors.kmMuted),
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
                    Divider(height: 16, color: Colors.white.withValues(alpha: 0.1)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 15, color: AppColors.kmMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(address,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.kmMuted)),
                        ),
                      ],
                    ),
                  ],
                  // फोन नम्बर सिधै देखिने — Call बटन थिच्नुअघि नै थाहा
                  // होस्/कल गर्न सजिलो होस् भनेर, लुकेको Call बटनमा मात्र
                  // सीमित नराखी। स्वीकृति भएकै क्षणदेखि — Acceptance-Gated
                  // Communication (job_actions.dart::isCommunicationUnlocked)।
                  if (isCommunicationUnlocked(status) && phone.isNotEmpty) ...[
                    Divider(height: 16, color: Colors.white.withValues(alpha: 0.1)),
                    GestureDetector(
                      onTap: () => _callWorker(context, phone),
                      child: Row(
                        children: [
                          const Icon(Icons.call_rounded,
                              size: 15, color: AppColors.kmOrange),
                          const SizedBox(width: 6),
                          Text(phone,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.kmOrange)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Acceptance-Gated Communication — स्वीकृति भएकै क्षणदेखि
            // (accepted/confirmed/in_progress) Call/Video/Message स्थायी
            // रूपमा खुल्ला।
            if (isCommunicationUnlocked(status))
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callWorker(context, phone),
                      icon: const Icon(Icons.call_rounded,
                          color: AppColors.kmText),
                      label: Text(S.callWord,
                          style: const TextStyle(color: AppColors.kmText)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
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
                          color: AppColors.kmText),
                      label: Text(S.videoCall,
                          style: const TextStyle(color: AppColors.kmText)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
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
                        backgroundColor: AppColors.kmOrange,
                        foregroundColor: AppColors.kmInk,
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
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: AppColors.kmMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(S.contactLockedAwaitingArrival,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.kmMuted)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
      ),
    );
  }
}
