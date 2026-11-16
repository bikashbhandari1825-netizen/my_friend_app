// screens/request_tracking_screen.dart
// अनुरोध पठाएपछि ग्राहकले यहाँ स्थिति हेर्छ।
//  • status broadcasting/pending_worker → "नजिकका प्रदायक खोज्दै…" (radar animation)
//  • status accepted/confirmed        → साझा RouteMapView (झन्डा = स्थिर सेवा-
//                                        ठेगाना, दिशा-सूचक marker + कालो
//                                        polyline = कामदारको लाइभ स्थान/बाटो)
//                                        + Call/Message (Arrival-Gated)
//  • status declined/cancelled        → समाप्त सन्देश
import '../utils/live_gps_metrics.dart';
import '../utils/price_input.dart';
import '../utils/request_timeout.dart';
import 'dart:async' show Timer, unawaited;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui show Gradient;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/complete_job_sheet.dart';
import '../widgets/counter_offer_card.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/status_badge.dart';
import '../widgets/worker_avatar.dart';
import 'chat_screen.dart';
import 'job_actions.dart';
import 'nearby_common.dart';
import 'route_map_view.dart';

class RequestTrackingScreen extends StatefulWidget {
  final String requestId;
  // Optimistic Navigation (service_map_screen.dart::_submitJob) — दिइएमा,
  // Firestore मा वास्तविक लेखाइ (`pendingDispatch`) अझै नसेटल भएको बेला
  // पनि यो seed data प्रयोग गरेर सिधै "खोज्दै…" UI तुरुन्तै देखाउँछ — doc
  // अझै नभएकोलाई "Request Cancelled" ठान्दैन (त्यो केवल doc साँच्चै
  // मेटिएको/कहिल्यै नबनेको असल अवस्थाका लागि मात्र हो)। `pendingDispatch`
  // सफल भएपछि Firestore कै live listener ले नै आफैं वास्तविक doc देखाउँछ;
  // असफल भए यहीं स्पष्ट (raw होइन) त्रुटि UI। अरू जहाँबाट पनि
  // (bookings_screen.dart/main_container.dart) यी नयाँ param नदिई उस्तै
  // पुरानै व्यवहार (doc सधैं पहिल्यै बनिसकेको मान्ने) कायमै रहन्छ।
  final Future<void>? pendingDispatch;
  final String? seedService;
  final LatLng? seedPickup;
  final bool? seedIsRide;
  const RequestTrackingScreen({
    super.key,
    required this.requestId,
    this.pendingDispatch,
    this.seedService,
    this.seedPickup,
    this.seedIsRide,
  });

  @override
  State<RequestTrackingScreen> createState() => _RequestTrackingScreenState();
}

// Destination-Arrival Threshold (Auto-Open Payment Sheet + Manual "Complete
// Job/Ride" बटन दुवैले साझा गर्ने, `_RequestTrackingScreenState` र
// `_ProviderTrackCard` दुवैबाट प्रयोग हुने भएकोले library-level) — पहिले
// 0.03 (30m) थियो, pickup-arrival गेट (job_route_screen.dart
// ::_arrivalThresholdKm) सँगै मिलाउन। त्यो pickup-OTP जस्तो सटीक-हुनैपर्ने
// सन्दर्भमा ठीकै हो, तर drop-off मा साँचो consumer GPS (भवन भित्र/बाहिर,
// सहरी क्षेत्र) प्रायः ३०-५०m सम्म तान्छ — नतिजा: driver दृश्य रूपमा
// ठ्याक्कै पिनमै देखिए पनि payment sheet कहिल्यै auto-खुल्दैनथ्यो/बटन
// disabled नै रहन्थ्यो ("राइड सकिए पनि payment कहिल्यै आफैं नदेखिने"
// गुनासोको जड)। 0.05 (50m) ले अझै साँच्चै नजिकै नपुगी ट्रिगर नहोस् भन्ने
// सुरक्षा कायम राख्छ, तर साधारण GPS ड्रिफ्टले रोक्दैन।
const double _destinationArrivalThresholdKm = 0.05;

class _RequestTrackingScreenState extends State<RequestTrackingScreen> {
  // Firestore Internal Assertion Failed Fix — पहिले तल्लो `StreamBuilder`
  // ले `stream: _ref.snapshots()` भनेर सिधै `build()` भित्रै हरेक पटक
  // (यो widget को `setState` — जस्तै `_liveRoute`/`_fallbackWorkerPos`
  // अपडेट हुँदा — जति पटक चले पनि) नयाँ `Stream` instance बनाउँथ्यो।
  // `StreamBuilder` ले फरक (नयाँ) `stream` पाएपछि पुरानो listener तुरुन्तै
  // unlisten गरेर नयाँ फेरि listen गर्छ — live route (हरेक ~१५s मा) वा
  // fallback स्थान लोड हुँदा यो दोहोरिरहन्थ्यो। Firestore Web SDK
  // (`@firebase/firestore` भित्रैको `WatchChangeAggregator`) मा यस्तो
  // छिटो-छिटो listen/unlisten दोहोरिँदा कहिलेकाहीं internal target-state
  // बेमेल भई "FIRESTORE INTERNAL ASSERTION FAILED: Unexpected state"
  // crash दिन्छ — ठ्याक्कै त्यही गुनासोको साँचो जड (live browser console
  // मा नै पक्रिएको)। अब यो stream एकपटक मात्र (`initState` मा) बन्छ,
  // widget जीवनभर उही एउटै instance रहन्छ — पूरै screen बन्द नभएसम्म
  // कहिल्यै फेरि listen/unlisten हुँदैन।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _reqStream;

  // Auto-Open Payment Sheet On Arrival — पहिले यो sheet (payment+rating)
  // manually "Complete Job/Ride" बटन थिचेपछि मात्र खुल्थ्यो — गन्तव्य
  // पुगिसकेपछि पनि प्रयोगकर्ताले आफैं थिच्नुपर्ने। अब गन्तव्यको ~30m
  // भित्र (ठ्याक्कै त्यही बटनले पहिल्यै प्रयोग गर्ने threshold) पुगेकै
  // क्षणमा स्वतः खुल्छ — यो flag ले एकपटक मात्र auto-open गराउने ग्यारेन्टी
  // गर्छ (नत्र हरेक नयाँ Firestore snapshot मा दोहोरिएर पटक-पटक sheet
  // फेरि-फेरि देखिने)। प्रयोगकर्ताले सिट बन्द गरिहाले पनि तल्लो
  // `_ProviderTrackCard` कै बटन अझै manually पुनः-खोल्न उपलब्धै रहन्छ।
  bool _autoOpenedPaymentSheet = false;

  // Optimistic Navigation — widget.pendingDispatch को नतिजा (माथिको
  // class-doc हेर्नुहोस्)। `_dispatchSettled` नभएसम्म (र doc अझै नभएसम्म)
  // seed data प्रयोग गरेर "खोज्दै…" UI देखाउने। असफल भए पनि (False-Timeout
  // Fix) build() ले अझै उस्तै Searching UI नै देखाउँछ — raw error चाहिँ यहीं
  // (नतिजा local `e` बाट, छुट्टै field नचाहिँदै) toast मार्फत मात्र।
  bool _dispatchSettled = false;

  @override
  void initState() {
    super.initState();
    visibleRouteScreenRequestId = widget.requestId;
    _reqStream = _ref.snapshots();
    final pending = widget.pendingDispatch;
    if (pending != null) {
      pending.then((_) {
        if (mounted) setState(() => _dispatchSettled = true);
      }).catchError((Object e) {
        if (!mounted) return;
        setState(() => _dispatchSettled = true);
        // False-Timeout Fix — सबै background retry (`retryTransient`,
        // service_map_screen.dart) साँच्चै असफल भइसकेपछि पनि अब पूरा-स्क्रिन
        // "Network looks slow" त्रुटिमा कहिल्यै फर्काउँदैन (तल build() हेर्नुहोस्)
        // — यही एउटा सानो, non-intrusive SnackBar मात्र। Searching/map UI
        // (ripple + Cancel बटन) यथावत् रहन्छ, प्रयोगकर्ताले आफैं Cancel थिच्न
        // वा पर्खन रोज्न सक्छन्।
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isTransientDispatchError(e)
                ? S.requestTimedOutMessage
                : S.requestSendFailedMessage),
          ),
        );
      });
    }
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

  // Full-Journey Preview — driver pickup तिर आउँदै गर्दा (अझै राइड सुरु
  // नभएको बेला) अन्तिम drop-off सम्मको खण्ड पनि (हल्का/dimmed, RouteMapView
  // कै secondaryRoute) देखाउन — pickup/destination दुवै स्थिर coordinate
  // भएकोले एकपटक मात्र चाहिन्छ, `_liveRoute` जस्तो throttled refresh होइन।
  RoadRoute? _secondLegRoute;
  bool _secondLegFetched = false;

  Future<void> _maybeLoadSecondLeg(
      LatLng pickup, LatLng destination, TravelMode mode) async {
    if (_secondLegFetched) return;
    _secondLegFetched = true;
    final result = await fetchRoadRoute(pickup, destination, mode: mode);
    if (mounted) setState(() => _secondLegRoute = result);
  }

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
    // Minimum-Interval Guard — `moved` (30m) माथि पहिले कुनै समय-आधारित
    // तल्लो सीमा नै थिएन — real GPS (bike ~6 मी/से) मा 30m पार गर्न
    // करिब 5s लाग्ने भएकोले यो व्यवहारमा कहिल्यै समस्या थिएन। तर debug
    // "Simulate GPS" (~25m प्रति ~800ms, अर्थात् ~31 मी/से — जानाजान
    // छिटो, टेस्टका लागि मात्र) ले यो 30m threshold लाई लगभग हरेक tick
    // मै पार गराउँथ्यो — नतिजा: हरेक ~1s मा नयाँ (network + पूरै polyline
    // पुनः-निर्माण) route-fetch दोहोरिँदा मुख्य थ्रेड बारम्बार (1-2s
    // सम्म) ब्लक हुने, लाइभ फोनमा नै प्रमाणित भएको गुनासो। अब `moved`
    // आफैंले पनि यो न्यूनतम अन्तराल (3s) नकटाई कहिल्यै fetch नदोहोर्‍याउने
    // — साँचो/छिटो-छिटो दुवै हालतमा सुरक्षित, `due` (15s) कै उस्तै
    // mechanism, फरक मात्र threshold।
    final minIntervalOk = _lastRouteFetch == null ||
        now.difference(_lastRouteFetch!) > const Duration(seconds: 3);
    if ((!moved || !minIntervalOk) && !due && !modeChanged) return;
    _lastRoutedWorkerPos = worker;
    _lastRouteFetch = now;
    _travelMode = mode;
    fetchRoadRoute(worker, site, mode: mode).then((r) {
      if (mounted) setState(() => _liveRoute = r);
    });
  }

  Future<void> _cancel({String? presetReason}) async {
    // किन cancel गर्दै भन्ने छोटो कारण — sheet बन्द गरे (null) भने cancel
    // नै नगर्ने, यही स्क्रिनमै बसिरहने। म्याद सकिएर रद्द हुँदा कारण सोधिँदैन।
    final reason = presetReason ?? await pickCancellationReason(context);
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Cancelled Bookings Cleanup — status मात्र बदल्ने होइन, पूरै मेट्ने
      // (कुनै अवशेष history नरहोस्)। यो स्क्रिन pure broadcasting/pending_
      // worker (कुनै worker अझै assign नभएको) देखि negotiation (pending_
      // employer_approval/pending_worker_counter, जहाँ counterBroadcastJob/
      // counterDirectOffer ले पहिल्यै workerUid लेखिसकेको हुन्छ) सम्मै साझा
      // "Cancel" ले ह्यान्डल गर्छ — त्यसैले workerUid सधैं हुन्छ भन्ने अनुमान
      // नगरी, हालको doc बाटै ताजा पढेर दिने (भए मात्र releaseWorkerActiveJob
      // चल्छ — नत्र त्यो worker फेरि नयाँ काम लिन नपाउने, driver-side stuck
      // active-job गुनासोकै अर्को सम्भावित जड)।
      final snap = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get();
      final workerUid = (snap.data()?['workerUid'] ?? '').toString();
      await deleteCancelledBooking(widget.requestId,
          reason: reason, workerUid: workerUid.isEmpty ? null : workerUid);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // पहिले यहाँ असफल भए पनि कुनै संकेत नै नदेखिने थियो — "Cancel बटन
      // थिचेर पनि केही नहुने" गुनासोको सम्भाव्य जड (job_actions.dart::
      // deleteCancelledBooking कै silent-catch हटाइएको हेर्नुहोस्)। अब
      // स्पष्ट त्रुटि, screen भने नपप नहुने (cancel साँच्चै भएन भने यही
      // स्क्रिनमै बसिरहनु ठीक)।
      if (!mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _ref.update({'status': 'declined'});
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(S.decline), backgroundColor: AppColors.kmRose),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  /// "Decline / Counter back" — ग्राहकले आफ्नो नयाँ मूल्य कामदारलाई फिर्ता
  /// पठाउँछ, वा अनुरोध अस्वीकार गर्छ।
  Future<void> _counterBackToWorker(num current) async {
    final controller = TextEditingController(text: current.toString());
    // Dead Send/Cancel Fix — job_actions.dart::counterDirectOffer/
    // counterBroadcastJob र worker_requests_page.dart::_counterDialog कै
    // उस्तै साँचो जड: यो dialog खुलिरहेको बेला (मूल्य टाइप गर्दै), अर्को
    // पक्षको live StreamBuilder अपडेटले (जस्तै कामदारले आफैं cancel गरे, वा
    // status अर्कै तिर बदलिए) यो screen कै State disposed/rebuilt हुन सक्छ
    // — त्यसपछि `context` प्रयोग गर्दा `if (!mounted) return;` ले चुपचाप
    // केही नगरी फर्किन्थ्यो, Send/Cancel दुवै "dead/frozen" देखिने गुनासोको
    // जड यही थियो। अब context होइन, सधैं mounted रहने NavigatorState/
    // ScaffoldMessengerState नै dialog खोल्नुअघि नै समातेर राख्ने।
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
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
            if (!navigator.mounted) return;
            navigator.pop();
            _declineWorkerCounter();
          },
        ),
        KmDialogAction(
          label: S.cancel,
          onPressed: () {
            if (!navigator.mounted) return;
            navigator.pop();
          },
        ),
        KmDialogAction(
          label: S.sendNewPrice,
          filled: true,
          onPressed: () async {
            final newPrice = parseSanePrice(controller.text);
            if (newPrice == null) return;
            if (!navigator.mounted) return;
            navigator.pop();
            try {
              await _ref.update({
                'status': 'pending_worker_counter',
                'employerCounterPrice': newPrice,
                'counterFrom': 'employer',
                'employerCounteredAt': FieldValue.serverTimestamp(),
              });
              messenger.showSnackBar(
                SnackBar(content: Text(S.counterSentToWorker)),
              );
            } catch (e) {
              messenger
                  .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
            }
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
          decoration:
              BoxDecoration(color: AppColors.kmVoid.withValues(alpha: 0.82)),
        ),
        title: Text(S.trackOnMap,
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w800)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _reqStream,
        builder: (context, snap) {
          // Optimistic Navigation — यो स्क्रिन सिधै tap भएकै क्षण (कुनै
          // Firestore event नपर्खी) पुगेको भएकोले, `.snapshots()` कै पहिलो
          // event (ConnectionState.waiting) आउनुअघि नै seed data प्रयोग
          // गरेर तुरुन्तै "खोज्दै…" UI देखाउने — बीचमा कुनै खाली/plain
          // spinner frame कहिल्यै नदेखियोस् भनेर।
          if (snap.connectionState == ConnectionState.waiting) {
            if (widget.pendingDispatch != null && !_dispatchSettled) {
              return _Searching(
                requestId: widget.requestId,
                service: widget.seedService ?? '',
                center: widget.seedPickup ??
                    const LatLng(fallbackLat, fallbackLng),
                onCancel: _cancel,
                isRide: widget.seedIsRide ?? false,
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          // Stream-Level Error Guard — `data == null` ले doc-नभएको अवस्था
          // मात्र समात्छ; यदि live listener आफैं error भयो भने (जस्तै
          // नेटवर्क/TLS तह बिग्रिएको) `snap.data` पनि null नै हुन्छ, तर
          // त्यो "doc deleted/cancelled" होइन — छुट्टै, स्पष्ट रूपमा
          // ह्यान्डल गर्नुपर्छ, नत्र तल्लो fallback (`requestCancelled`)
          // मा गलत रूपमा झर्न सक्छ।
          if (snap.hasError) {
            // False-Timeout Fix — dispatch अझै pending/settling भएसम्म (seed
            // data भएसम्म) stream-level error ले पनि कहिल्यै पूरा-स्क्रिन
            // त्रुटिमा नफर्काउने, जस्तै दिगो पहिले नै थियो — अब `_dispatchSettled`
            // भइसकेपछि पनि उस्तै (`!_dispatchSettled` जाँच हटाइयो) जबसम्म
            // `pendingDispatch` उपलब्ध छ, Searching/map UI नै कायम रहने
            // (toast माथि `initState` कै catchError मा पहिल्यै देखिसकेको)।
            // `pendingDispatch == null` (bookings_screen.dart बाट पुरानो
            // बुकिङ फेरि खोलेको, साँचो live-tracking reentry, कुनै seed डेटा
            // नै छैन) भएको दुर्लभ अवस्थामा मात्र पहिलेकै honest त्रुटि UI
            // यथावत् — त्यहाँ कुनै active map/marker state हराउने जोखिम छैन
            // (त्यो स्क्रिन अझै वास्तविक doc डेटा कहिल्यै पाएकै थिएन)।
            if (widget.pendingDispatch != null) {
              return _Searching(
                requestId: widget.requestId,
                service: widget.seedService ?? '',
                center: widget.seedPickup ??
                    const LatLng(fallbackLat, fallbackLng),
                onCancel: _cancel,
                isRide: widget.seedIsRide ?? false,
              );
            }
            return _Ended(
              icon: Icons.wifi_off_rounded,
              title: S.requestTimedOutMessage,
              onBack: () => _safeBack(context),
            );
          }
          final data = snap.data?.data();
          if (data == null) {
            // Optimistic Navigation — widget.pendingDispatch अझै नसेटल भएको
            // बेला (doc अझै Firestore मा नपुगेको, लेखाइ चलिरहेकै) seed data
            // प्रयोग गरेर सिधै "खोज्दै…" UI — doc नभएकै भरमा "Request
            // Cancelled" (झूटो/भ्रामक) कहिल्यै नदेखियोस्।
            //
            // False-Timeout Fix — पहिले यहाँ `_dispatchSettled` भइसकेपछि र
            // `_dispatchError != null` भए (सबै background retry साँच्चै
            // असफल भइसकेपछि) पूरा-स्क्रिन "Network looks slow"/"Couldn't
            // send" त्रुटिमा फर्काउँथ्यो — ठ्याक्कै प्रयोगकर्ताले गुनासो
            // गरेको bug। अब `_dispatchSettled`/`_dispatchError` जे भए पनि,
            // `pendingDispatch` दिइएसम्म सधैँ यही Searching/map UI नै कायम
            // (toast माथि `initState` कै catchError मा एकपटक मात्र देखिसकेको,
            // Cancel बटन सधैँ उपलब्ध)। `pendingDispatch == null` (साँचो
            // doc-नभएको/मेटिएको, जस्तै अरू device बाट cancel गरेको) भएको
            // बेला मात्र साँचो "Request Cancelled"।
            if (widget.pendingDispatch != null) {
              return _Searching(
                requestId: widget.requestId,
                service: widget.seedService ?? '',
                center: widget.seedPickup ??
                    const LatLng(fallbackLat, fallbackLng),
                onCancel: _cancel,
                isRide: widget.seedIsRide ?? false,
              );
            }
            return _Ended(
              icon: Icons.info_outline_rounded,
              title: S.requestCancelled,
              onBack: () => _safeBack(context),
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
              onBack: () => _safeBack(context),
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
              onExpire: () => _cancel(presetReason: 'No driver accepted in time'),
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

          // ग्राहकले worker कै मूल्यमा फेरि counter गर्‍यो → worker को जवाफ
          // पर्खँदै। पहिले यहाँ छुट्टै branch नै नभएकोले यो status फेरि
          // तलको "accepted/confirmed" generic tracking card मा नै पुगेर
          // (काम अझै पुष्टि नै नभएको बेला) route/Complete-Job UI अनुचित
          // रूपमा देखाउँथ्यो — ग्राहकले आफ्नै पठाएको counter-offer को कुनै
          // स्पष्ट "पर्खँदै" संकेत नै नपाउने (bookings_screen.dart कै list
          // card मा भने यो उस्तै संकेत पहिल्यैदेखि थियो, यहाँ मात्र छुटेको)।
          if (status == 'pending_worker_counter') {
            final myPrice = (data['employerCounterPrice'] as num?) ??
                (data['proposedPrice'] as num?) ??
                0;
            return AuroraBackground(
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: GlassPanel(
                      radius: 26,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hourglass_top_rounded,
                              size: 42, color: AppColors.kmOrange),
                          const SizedBox(height: 14),
                          Text('Rs ${myPrice.toInt()}',
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26)),
                          const SizedBox(height: 8),
                          Text(S.waitingWorkerCounterReply,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.kmMuted, fontSize: 13)),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: _cancel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.kmRose,
                              side:
                                  const BorderSide(color: AppColors.kmRose),
                            ),
                            child: Text(S.cancelRequest),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          // accepted / confirmed / in_progress →
          // काम पुष्टि — स्थिर job site (flag) + कामदारको लाइभ स्थान (worker ले
          // JobRouteScreen मार्फत पठाएको) बीच कालो live route polyline।
          //
          // Ride (Bike/Car) मा राइड 'in_progress' भइसकेपछि (OTP मिलेर सुरु
          // भएपछि) "flag" अब pickup होइन — driver अब गन्तव्य (destinationLat/
          // Lng) तर्फ जाँदैछ, त्यसैले नक्साको स्थिर बिन्दु पनि त्यतै सर्नुपर्छ।
          final isRideJob = (data['isRide'] ?? false) == true;
          // Synchronized Zoom — driver ले "Start Ride" (arrival-confirm)
          // थिचेकै क्षणमा नै (OTP को पर्खाइ नगरी) यता पनि उही building-
          // level जुम लक होस् भनेर, driver-तर्फ Firestore मा लेखिने
          // `arrivedAt` (job_route_screen.dart::_confirmArrival) लाई नै
          // trigger मान्ने — दुवैतिर एउटै क्षणमा एउटै जुम हुन्छ।
          final driverArrived = data['arrivedAt'] != null;
          final destLat = (data['destinationLat'] as num?)?.toDouble();
          final destLng = (data['destinationLng'] as num?)?.toDouble();
          final empLat = (data['employerLat'] as num?)?.toDouble();
          final empLng = (data['employerLng'] as num?)?.toDouble();
          final useDestination = isRideJob &&
              status == 'in_progress' &&
              destLat != null &&
              destLng != null;
          final site = useDestination
              ? LatLng(destLat, destLng)
              : (empLat != null && empLng != null)
                  ? LatLng(empLat, empLng)
                  : const LatLng(fallbackLat, fallbackLng);

          LiveGpsMetrics.sample(data); // debug: ढिलाइ नाप्ने
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
          // Auto-Open Payment Sheet On Arrival — `_ProviderTrackCard` कै
          // "Complete Job/Ride" बटनले प्रयोग गर्ने उही threshold
          // (`_destinationArrivalThresholdKm`) — Ride मा साँचो गन्तव्य
          // (destinationLat/Lng), सामान्य job-portal मा employerLat/Lng
          // (त्यहाँ नै काम-स्थल हो)।
          //
          // Dual-Confirmation Bypass Fix — यो auto-open पहिले
          // `workerConfirmedComplete` कहिल्यै नजाँच्दा, सामान्य job-portal
          // कामका लागि worker ले "Job Completed" नथिचे पनि (arrival +
          // proximity मात्रैले) भुक्तानी sheet सिधै खुल्थ्यो — ठ्याक्कै
          // "Complete Job" बटनमा लागू गरिएकै dual-confirmation गेट
          // (हेर्नुहोस् तल `canComplete`) बाइपास गर्दै। Ride मा यो गेट
          // लागू हुँदैन (त्यहाँ dual-confirmation नियम छैन)।
          if (!_autoOpenedPaymentSheet && status == 'in_progress') {
            final payTargetLat = isRideJob ? destLat : empLat;
            final payTargetLng = isRideJob ? destLng : empLng;
            final workerConfirmedDone =
                isRideJob || data['workerConfirmedComplete'] == true;
            final nearPaymentTarget = workerConfirmedDone &&
                payTargetLat != null &&
                payTargetLng != null &&
                wLat != null &&
                wLng != null &&
                haversineKm(wLat, wLng, payTargetLat, payTargetLng) <=
                    _destinationArrivalThresholdKm;
            if (nearPaymentTarget) {
              _autoOpenedPaymentSheet = true;
              final payPrice = data['finalPrice'] ??
                  data['employerCounterPrice'] ??
                  data['workerCounterPrice'] ??
                  data['proposedPrice'];
              final payWorkerName =
                  (data['workerName'] ?? 'Provider').toString();
              final payService = (data['service'] ?? '').toString();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                showCompleteJobSheet(
                  context,
                  docId: widget.requestId,
                  amount: (payPrice ?? 0) as num,
                  workerUid: workerUid,
                  workerName: payWorkerName,
                  service: payService,
                );
              });
            }
          }
          // Ride (Bike/Car) मा auto-derived साँचो सवारी-प्रकार अनुसार नै
          // (picker लुकाइएको, Firestore को `travelMode` field अब कहिल्यै
          // लेखिँदैन) — नत्र default (`driving`) कै कारण Bike राइडमा पनि
          // गलत कार-आइकन देखिने बग हुन्थ्यो। सामान्य (non-ride) काममा पनि
          // अब Driving नै स्थायी/एकमात्र mode हो (TravelModeChips बाट
          // Walking/Bike चयन गर्ने विकल्प नै हटाइसकियो) — यो fix भन्दा
          // अघिको पुरानो/stale `travelMode` field (कसैले साँच्चै Walking/
          // Bike छानेको भए) अब कहिल्यै फर्काइँदैन।
          final travelMode = isRideJob
              ? travelModeForVehicle((data['service'] ?? '').toString())
              : TravelMode.driving;
          if (workerPos != null) {
            _maybeFetchLiveRoute(workerPos, site, travelMode);
          } else {
            _liveRoute = null;
          }
          if (isRideJob && !useDestination && empLat != null && empLng != null &&
              destLat != null && destLng != null) {
            unawaited(_maybeLoadSecondLeg(
                LatLng(empLat, empLng), LatLng(destLat, destLng), travelMode));
          }

          final mapPadding = status == 'completed'
              ? const EdgeInsets.only(top: 64)
              : const EdgeInsets.only(bottom: 130, top: 64);

          return Stack(
            children: [
              // ── साझा route-map widget — worker/employer दुवैतिर उही class ──
              // Mapbox Removal — पहिले यहाँ Ride (bike/car) मा मात्र native
              // Kotlin/Mapbox (`NativeVehicleMapView.kt`) मार्फत चल्थ्यो;
              // off-road drift/choppy रेन्डरिङ गुनासो पछि पूरै हटाइयो। अब
              // सबै job-type (Ride लगायत) ले उही Dart-based `RouteMapView`
              // (google_maps_flutter) प्रयोग गर्छन्।
              RouteMapView(
                origin: workerPos,
                originLabel:
                    (data['workerName'] ?? S.workerRoleWord).toString(),
                destination: site,
                destinationLabel: !isRideJob
                    ? S.jobLocationTitle
                    : (useDestination
                        ? S.dropPointLabel
                        : S.pickupPointLabel),
                destinationAddress: useDestination
                    ? (data['destinationAddress'] ?? '').toString()
                    : (data['address'] ?? '').toString(),
                route: _liveRoute,
                travelMode: travelMode,
                vehicleIconOverride:
                    (data['service'] ?? '').toString() == 'Auto'
                        ? 'assets/images/auto_top.png'
                        : null,
                rideStarted: isRideJob && driverArrived,
                primaryIsDropoff: useDestination,
                showPointLabels: isRideJob,
                // Full-Journey Preview — "अर्को" बिन्दु सधैं (दुवै phase मा)
                // देखिने: pickup तिर आउँदै गर्दा त्यो destination हो, राइड
                // सुरु भइसकेपछि (in_progress) चाहिँ pickup आफैं (अब "पछाडि
                // छुटेको" सन्दर्भ-बिन्दु) बन्छ। secondary ROUTE भने केवल
                // pickup-तिरको चरणमा मात्र (in_progress मा मुख्य route
                // आफैं लगभग यही बाटो देखाइसक्छ, दोहोरिएर overlap हुने थिएन)।
                secondaryDestination: !isRideJob
                    ? null
                    : (useDestination
                        ? ((empLat != null && empLng != null)
                            ? LatLng(empLat, empLng)
                            : null)
                        : ((destLat != null && destLng != null)
                            ? LatLng(destLat, destLng)
                            : null)),
                secondaryDestinationLabel:
                    useDestination ? S.pickupPointLabel : S.dropPointLabel,
                secondaryRoute:
                    (isRideJob && !useDestination) ? _secondLegRoute : null,
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
                // Draggable Collapsible Bottom Sheet — तल्लो card अब collapsed
                // बेला सानो (~17% screen) मात्र हुने भएकोले, नक्साको padding
                // पनि त्यही अनुसार घटाइएको (पहिले 210, fixed ठूलो card-को
                // लागि)। Sheet माथि तानिँदा चाहिँ map-padding dynamically
                // नबदलिने (Uber/inDrive कै जस्तै — sheet ले नक्सामाथि नै
                // overlay गर्छ, नक्सा आफैं resize हुँदैन)।
                mapPadding: mapPadding,
              ),
              // Auto-Dismiss on Completion — राइड/काम 'completed' भइसकेपछि
              // (payment + rating `showCompleteJobSheet` बाटै भइसकेको) यो
              // तल्लो card (OTP banner, pickup/drop, Call/Video/Message सबै
              // अब अर्थहीन भइसकेका) आफैं पूर्ण रूपमा हराउँछ — पूरै नक्सा
              // (सकिएको पूरा route सहित) देखिन्छ, screen block हुँदैन।
              // Flutter Web Zero-Height Sheet Fix — यो `Positioned` मा पहिले
              // `bottom: 0` मात्र (कुनै `top`/`height` बिना) दिइएको थियो।
              // Android/iOS मा loose constraint भए पनि Stack-कै bounded
              // height बाटै DraggableScrollableSheet ले आफैं ठीकसँग माप
              // पाउँथ्यो — तर Flutter Web (CanvasKit/HTML दुवै) मा उस्तै
              // अवस्थामा यो sheet भित्रको `LayoutBuilder` ले शून्य/अमान्य
              // height पायो, र पूरै card नै चुपचाप (कुनै error/exception
              // बिना) नरेन्डर भएर हराउँथ्यो — ride-code banner, driver info,
              // Call/Video/Message सबै (live browser मा नै पुष्टि भएको बग)।
              // `Positioned.fill` ले Stack-कै पूरा bounded height सिधै
              // दिन्छ — DraggableScrollableSheet आफैं अझै तल्लो
              // `initialChildSize` (17%) मा मात्र देखिन्छ, बाँकी खाली
              // माथिल्लो भाग पूरै map-तर्फ पारदर्शी (hit-test नहुने) रहन्छ।
              if (status != 'completed')
                Positioned.fill(
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
  final Future<void> Function() onCancel;
  /// म्याद सकिएपछि यात्रीले "रद्द" छानेमा (कारण नसोधी) रद्द गर्ने।
  final Future<void> Function()? onExpire;
  // Ride-Hailing (Bike/Car) मात्र — driver प्रस्तावहरूको live list पनि
  // यहीँ देखिन्छ (नत्र सामान्य सेवाको उही पुरानो radar-मात्र UI)।
  final bool isRide;
  final bool autoOffer;
  const _Searching({
    required this.requestId,
    required this.service,
    required this.center,
    required this.onCancel,
    this.onExpire,
    this.isRide = false,
    this.autoOffer = false,
  });

  @override
  State<_Searching> createState() => _SearchingState();
}

// Ripple overlay widget (CustomPaint) को वर्गाकार bounding box — भित्रको
// सबैभन्दा ठूलो घेरा (`_GlassRipplePainter.maxRadius` + blur) पूरै अटाउने
// गरी, जति ठूलो भए पनि केन्द्र सधैँ box कै बीचमै रहन्छ।
const double _kRippleBoxSize = 240;

class _SearchingState extends State<_Searching>
    with SingleTickerProviderStateMixin {
  // २.८s प्रति चक्र — ढुङ्गा हालेपछि निस्कने नरम/ढिलो पानीको लहर जस्तो
  // feel का लागि (पहिले २s थियो, "धेरै छिटो/stutter" गुनासो आएपछि ढिलो
  // पारिएको)।
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800))
    ..repeat();
  GoogleMapController? _map;
  // पिन — स्थिर, एकपटक मात्र `initState` मा लोड हुन्छ र फेरि कहिल्यै
  // बदलिँदैन। अब native `Marker` होइन, raw PNG bytes (`Image.memory`) —
  // ripple कै Flutter overlay भित्रै, उही anchor बिन्दुमा कोरिन्छ (तल
  // `_rippleScreenOffset` class-doc हेर्नुहोस्) ताकि पिन र ripple बीच
  // native-vs-Dart छुट्टै coordinate system नै नरहोस्।
  Uint8List? _meIcon;
  // Auto-Offer — पहिलो pending प्रस्ताव आउनेबित्तिकै एकपटक मात्र auto-accept
  // गर्न — StreamBuilder हरेक अपडेटमा फेरि बन्ने भएकोले दोहोरिन नदिन guard।
  bool _autoAccepting = false;

  // Optimistic UI — Cancel बटन थिचेपछि Firestore बाट जवाफ नआउँदै (पहिले
  // सम्भवतः 20-60s सम्म पर्खिनुपर्ने) बटन तुरुन्तै spinner मा बदलिन्छ।
  // असफल भए (दुर्लभ) मात्र फेरि साधारण बटनमा फिर्ता — त्यो बेला
  // `onCancel` (parent::_cancel) ले आफैं error snackbar देखाइसक्छ।
  bool _cancelling = false;

  /// inDrive-शैली "भाडा बढाउनुहोस्" — कसैले offer नदिएमा यात्रीले माग गरेको भाडा
  /// बढाउँछ; नजिकका driver को सूचीमा नयाँ मूल्य तुरुन्तै देखिन्छ। केवल खोजी
  /// चलिरहेको (broadcasting/pending_worker) अवस्थामा, transaction भित्र।
  Future<void> _raiseFare() async {
    final ref = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(widget.requestId);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    num current = 0;
    try {
      current = ((await ref.get()).data()?['proposedPrice'] as num?) ?? 0;
    } catch (_) {}
    if (!mounted) return;
    String plain(num v) => (v % 1 == 0 ? v.toInt() : v).toString();
    final controller = TextEditingController(text: plain(current + 20));
    await showKmDialog(
      context: context,
      title: S.raiseFare,
      icon: Icons.trending_up_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${S.currentFare}: Rs ${formatRs(current)}',
              style: const TextStyle(color: AppColors.kmMuted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final d in const [10, 20, 50, 100])
                ActionChip(
                  label: Text('+$d'),
                  onPressed: () => controller.text = plain(current + d),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: const TextStyle(color: AppColors.kmText),
            decoration: kmInputDecoration(S.yourPriceRs),
          ),
        ],
      ),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () {
            if (navigator.mounted) navigator.pop();
          },
        ),
        KmDialogAction(
          label: S.raiseFareConfirm,
          filled: true,
          onPressed: () async {
            final v = parseSanePrice(controller.text);
            if (v == null || v <= current) {
              messenger.showSnackBar(
                  SnackBar(content: Text(S.raiseFareInvalid)));
              return;
            }
            if (navigator.mounted) navigator.pop();
            try {
              await FirebaseFirestore.instance.runTransaction((tx) async {
                final snap = await tx.get(ref);
                final st = (snap.data()?['status'] ?? '').toString();
                if (st != 'broadcasting' && st != 'pending_worker') {
                  throw StateError('not_searching');
                }
                tx.update(ref, {
                  'proposedPrice': v,
                  'fareRaisedAt': FieldValue.serverTimestamp(),
                  'fareRaiseCount': FieldValue.increment(1),
                });
              });
              // भाडा बढेपछि म्याद फेरि सुरुबाट (सर्भरमा पनि `fareRaisedAt` ले गणना)।
              _deadline = DateTime.now()
                  .add(const Duration(seconds: kRequestTimeoutSec));
              messenger.showSnackBar(SnackBar(content: Text(S.fareRaised)));
            } catch (_) {
              messenger
                  .showSnackBar(SnackBar(content: Text(S.fareRaiseFailed)));
            }
          },
        ),
      ],
    );
  }

  Future<void> _handleCancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await widget.onCancel();
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  // झन्डाकै फेदमुनिको radar-wave — अब native Marker **होइन**, बरु ठ्याक्कै
  // `_meIcon` (पिन) मै प्रयोग हुने `widget.center` कै screen-projection
  // (`_map.getScreenCoordinate`) मा टाँसिएको, सिधै `_c` बाट ड्राइभ हुने
  // Flutter-साइड `CustomPaint` overlay हो (तल `_GlassRipplePainter` र
  // build() को Positioned हेर्नुहोस्)। पहिले यो पनि छुट्टै native Marker
  // (हरेक tick मा नयाँ bitmap-frame सहित) थियो — तर native Marker को
  // `icon` जति नै थोरै फ्रिक्वेन्सीमा फेरिए पनि Google Maps Flutter plugin
  // ले सोही marker लाई native side मा हटाएर फेरि थप्छ, जसले बेलाबखत
  // त्यो marker लाई क्षणिक रूपमा गलत/पुरानो स्थानमा देखाउँथ्यो ("ripple
  // पिनबाट टाढा छुट्टिएको" जस्तो गुनासो) — पिन (native Marker, कहिल्यै
  // नफेरिने) र ripple (अब शुद्ध Flutter widget, कुनै native marker-swap
  // नै छैन) दुवैको केन्द्र ठ्याक्कै उही `widget.center` प्रोजेक्सनमा
  // टाँसिएकोले यो structurally नै कहिल्यै छुट्टिन सक्दैन।
  Offset? _rippleScreenOffset;

  // `getScreenCoordinate` is already relative to the GoogleMap widget's
  // OWN top-left corner (physical pixels), not the full device screen —
  // that's the plugin's documented behaviour. This `Positioned` lives in
  // the same `Stack` that IS this Scaffold's `body`, and `GoogleMap` fills
  // that Stack edge-to-edge, so the Stack's local (0,0) is already below
  // the AppBar (Flutter lays `body` out under `appBar` automatically) —
  // exactly the same origin `getScreenCoordinate` already uses. Subtracting
  // `appBarMaxHeight` on top of that was double-correcting: it shifted the
  // ripple one AppBar-height too high, visibly detaching it above the pin's
  // tip instead of centering on it. No further offset is needed — `sc`
  // converted from physical to logical pixels (`/ dpr`) lands directly on
  // the same point the marker's `anchor` (tip) is drawn at.
  Future<void> _syncRipplePosition() async {
    final map = _map;
    if (map == null || !mounted) return;
    final sc = await map.getScreenCoordinate(widget.center);
    if (!mounted) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    setState(() => _rippleScreenOffset = Offset(sc.x / dpr, sc.y / dpr));
  }

  // Ride-Hailing — प्रस्ताव पठाउँदा driver-ले snapshot गरेको स्थान
  // (`job_actions.dart::submitRideOffer`) बाट बनेका marker — offers
  // StreamBuilder ले अद्यावधिक गर्छ (नयाँ/हटेको प्रस्ताव आए यही set फेरि
  // बन्छ, GoogleMap ले तुरुन्तै देखाउँछ)।
  Set<Marker> _driverMarkers = const {};

  // Firestore Internal Assertion Failed Fix — यो तल्लो `rideOffers`
  // StreamBuilder पनि पहिले आफ्नै `.snapshots()` सिधै `build()` भित्रै
  // बनाउँथ्यो — `_driverMarkers` अपडेट हुँदा (यही StreamBuilder कै
  // builder ले तानेको `setState`, हरेक नयाँ/हटेको प्रस्तावमा) पूरै
  // `_SearchingState.build()` फेरि चल्थ्यो, जसले यही stream पनि फेरि
  // (नयाँ instance) बनाउँथ्यो — आफैंले आफैंलाई unlisten/relisten
  // गराउने loop। माथिकै `_reqStream` कै उस्तै जड (Firestore Web SDK को
  // WatchChangeAggregator मा बारम्बार listen/unlisten दोहोरिँदा "INTERNAL
  // ASSERTION FAILED: Unexpected state" crash) — अब यो पनि एकपटक मात्र बन्छ।
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _offersStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .collection('rideOffers')
          .where('status',
              whereIn: ['pending', 'passenger_countered']).snapshots();

  @override
  void initState() {
    super.initState();
    sahayatriPinBytes().then((b) {
      if (mounted) setState(() => _meIcon = b);
    });
    if (widget.isRide) _initDeadline();
  }

  // ── अनुरोधको म्याद (राइड मात्र) ──
  // ५ मिनेट (`kRequestTimeoutSec`) कसैले स्वीकार नगरे यात्रीलाई छनोट सोध्ने।
  // गणना हरेक सेकेन्ड ValueNotifier मात्र बदल्छ — पूरै स्क्रिन/नक्सा rebuild हुँदैन।
  final ValueNotifier<int> _secondsLeft = ValueNotifier<int>(kRequestTimeoutSec);
  Timer? _countdown;
  DateTime _deadline =
      DateTime.now().add(const Duration(seconds: kRequestTimeoutSec));
  bool _timeoutDialogOpen = false;

  Future<void> _initDeadline() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(widget.requestId)
          .get();
      final since = requestActiveSince(snap.data() ?? const {});
      if (since != null) {
        _deadline = since.add(const Duration(seconds: kRequestTimeoutSec));
      }
    } catch (_) {}
    if (!mounted) return;
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), _tick);
    _tick(null);
  }

  void _tick(Timer? _) {
    if (!mounted) return;
    final left = _deadline.difference(DateTime.now()).inSeconds;
    _secondsLeft.value = left < 0 ? 0 : left;
    if (left <= 0 && !_timeoutDialogOpen) _showTimeoutDialog();
  }

  String _mmss(int sec) =>
      '${(sec ~/ 60).toString().padLeft(1, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  Future<void> _showTimeoutDialog() async {
    _timeoutDialogOpen = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    await showKmDialog(
      context: context,
      title: S.requestTimeoutTitle,
      icon: Icons.hourglass_bottom_rounded,
      content: Text(S.requestTimeoutBody,
          style: const TextStyle(color: AppColors.kmMuted)),
      actions: [
        KmDialogAction(
          label: S.cancelRequest,
          destructive: true,
          onPressed: () {
            if (navigator.mounted) navigator.pop();
            (widget.onExpire ?? widget.onCancel)();
          },
        ),
        KmDialogAction(
          label: S.keepWaiting,
          onPressed: () {
            if (navigator.mounted) navigator.pop();
          },
        ),
        KmDialogAction(
          label: S.raiseFare,
          filled: true,
          onPressed: () {
            if (navigator.mounted) navigator.pop();
            _raiseFare();
          },
        ),
      ],
    );
    _timeoutDialogOpen = false;
    // कुनै छनोट नगरी (बाहिर थिचेर) बन्द गरे/"पर्खिरहनुहोस्" थिचे — केही समय थप;
    // नत्र गणनाले तुरुन्तै फेरि डायलग खोल्थ्यो।
    if (mounted && !_deadline.isAfter(DateTime.now())) {
      _deadline = DateTime.now().add(const Duration(seconds: kRequestExtendSec));
    }
  }

  // Stale-Ripple-On-Center-Change Fix — यो widget (`_Searching`) लाई parent
  // StreamBuilder ले हरेक नयाँ Firestore snapshot मा फेरि build गर्छ, र कुनै
  // `key` नदिइएकोले (माथि `_RequestTrackingScreenState.build()` हेर्नुहोस्)
  // Flutter ले उही पुरानो `State` (यही class) लाई नै पुनःप्रयोग गर्छ — नयाँ
  // instance बन्दैन। समस्या: `widget.center` (जस्तै पहिलो snapshot मा
  // `employerLat/Lng` अझै नलेखिएकोले `fallbackLat/Lng` बाट सुरु भई, पछिल्लो
  // snapshot मा साँचो स्थानमा बदलिनु) बदलिए पनि — माथिको native `Marker`
  // (हरेक build मा `position: widget.center` बाट ताजै बन्ने) तुरुन्तै नयाँ
  // स्थानमा सर्छ, तर `_rippleScreenOffset` (जुन `onMapCreated`/`onCameraIdle`
  // मा मात्र पुनः-गणना हुन्छ, अनि क्यामेरा आफैं नचलेसम्म ती events कहिल्यै
  // फायर हुँदैनन्) पुरानै (पहिलो center कै) screen-projection मा अडिएर
  // बस्छ — नतिजा: पिन (ताजा) र ripple (पुरानो) देखिने गरी टाढा छुट्टिन्छन्,
  // क्यामेरा lock (माथि `scrollGesturesEnabled` आदि false) ले आफैं यो
  // निको पार्दैन (gesture त पहिल्यै थिएन, center-change बाहिरबाटै आउँछ)।
  // अब `widget.center` साँच्चै बदलिएको (LatLng मान-आधारित `==`) पत्ता लाग्नेबित्तिकै
  // क्यामेरा नै नयाँ center मा सार्छ (`animateCamera`) — त्यसको settle भएपछि
  // native plugin आफैंले `onCameraIdle` फायर गर्छ, जसले अहिले नै जोडिएको
  // `_syncRipplePosition` मार्फत ripple लाई पनि उही नयाँ बिन्दुमा ल्याउँछ।
  @override
  void didUpdateWidget(covariant _Searching oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.center != oldWidget.center) {
      _map?.animateCamera(CameraUpdate.newLatLng(widget.center));
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _secondsLeft.dispose();
    _c.dispose();
    _map?.dispose();
    super.dispose();
  }

  // पिन + ripple — दुवै यही एउटै `_rippleScreenOffset` anchor बिन्दुमा।
  // बाहिरी box ripple कै ठूलो bounding size (`_kRippleBoxSize`) को हो, र
  // त्यही box-local केन्द्र (120,120) मा दुवै layer टाँसिन्छन् — ripple
  // (जसको CustomPaint पहिल्यै box-center मा कोर्छ) र पिन (जसलाई आफ्नै
  // anchor pixel, `SahayatriPinGeometry.anchorFraction` बाट गणना गरेर,
  // ठ्याक्कै सोही box-center मा पुर्‍याइन्छ)।
  Widget _buildPinAndRippleOverlay() {
    const pinW = sahayatriPinDisplayW;
    const pinH = sahayatriPinDisplayH;
    final anchorPx = Offset(
      SahayatriPinGeometry.anchorFraction.dx * pinW,
      SahayatriPinGeometry.anchorFraction.dy * pinH,
    );
    const boxCenter = Offset(_kRippleBoxSize / 2, _kRippleBoxSize / 2);
    return Positioned(
      left: _rippleScreenOffset!.dx - boxCenter.dx,
      top: _rippleScreenOffset!.dy - boxCenter.dy,
      width: _kRippleBoxSize,
      height: _kRippleBoxSize,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: const Size(_kRippleBoxSize, _kRippleBoxSize),
                painter:
                    _GlassRipplePainter(t: _c.value, color: AppColors.kmPink),
              ),
            ),
            Positioned(
              left: boxCenter.dx - anchorPx.dx,
              top: boxCenter.dy - anchorPx.dy,
              child: Image.memory(_meIcon!, width: pinW, height: pinH),
            ),
          ],
        ),
      ),
    );
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
          // ── प्रत्यक्ष Google Map पृष्ठभूमि — पिन (native Marker, स्थिर)
          // मात्र यहाँ; ripple अब छुट्टै Flutter overlay हो (तल)।
          GoogleMap(
            // Close-up — street/house-level, घर/क्षेत्रको वरपर प्रष्ट देखिने।
            initialCameraPosition:
                CameraPosition(target: widget.center, zoom: 18.5),
            mapId: kCloudMapId,
            onMapCreated: (c) {
              _map = c;
              _syncRipplePosition();
              // Measured on-device: the very first `onCameraIdle` can fire
              // while the native MapView's PlatformView surface is still
              // settling its final size/position after being newly attached
              // — `getScreenCoordinate` then reports a transient, stale
              // projection (confirmed by two identical on-device runs
              // landing on opposite sides of the pin's tip with the same
              // code). A couple of short-delayed re-syncs catch the final,
              // settled surface without depending on a second native
              // camera event that may not fire again (camera is locked).
              for (final ms in [150, 400, 900]) {
                Future.delayed(
                    Duration(milliseconds: ms), _syncRipplePosition);
              }
            },
            onCameraIdle: _syncRipplePosition,
            // यो नक्सामा पिन (`_meIcon`) आफैं स्थान देखाउने भएकोले Google को
            // native "My Location" निलो थोप्लो (वास्तविक GPS, पिनसँग कुनै
            // सम्बन्ध नभएको) कहिल्यै देखाउनु पर्दैन — त्यसले ripple/anchor
            // गणनासँग कुनै तालमेल नभएर भ्रामक मात्र देखिन्थ्यो।
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर "उल्टो"
            // देखिने बग नआओस्।
            rotateGesturesEnabled: false,
            // Camera Lock — ripple (Flutter overlay) `onCameraIdle` मा मात्र
            // पिन/टुप्पोको screen-projection सँग फेरि sync हुन्छ, `onCameraMove`
            // (drag/pinch चलिरहेको बेलाको हरेक frame) मा होइन। यदि gesture ले
            // क्यामेरा चलाउन पाए, drag/pinch चलिरहुन्जेल नै native पिन तुरुन्तै
            // (native-side रेन्डर) नयाँ स्थानमा सर्छ तर ripple पुरानै स्थिरमा
            // अडिएर देखिन्छ — पिन र ripple देखिने गरी टाढा छुट्टिन्छन् (gesture
            // रोकेपछि मात्र फेरि मिल्छन्)। यो "Searching..." स्क्रिनमा
            // प्रयोगकर्ताले नक्सा हेर्नुबाहेक कुनै काम गर्नुपर्दैन (pan/zoom
            // गर्नुपर्ने कुनै functional आवश्यकता छैन), त्यसैले क्यामेरा नै
            // सुरुदेखि अन्त्यसम्म स्थिर (initialCameraPosition कै) राखेर यो
            // बेमेलको सम्भावना नै जरैबाट हटाइएको — पिन र ripple संरचनात्मक
            // रूपमा सधैँ उही बिन्दुमा टाँसिएर रहन्छन्।
            scrollGesturesEnabled: false,
            zoomGesturesEnabled: false,
            tiltGesturesEnabled: false,
            // पिन अब यहाँ native Marker होइन — तल एउटै unified overlay
            // (`_buildPinAndRippleOverlay`) मा छ, ripple सँगै उही anchor
            // बिन्दुमा। `_driverMarkers` (अर्कै प्रस्ताव-marker हरू, यिनको
            // आफ्नै anchor/tip सँग कुनै सम्बन्ध छैन) मात्र native रहन्छन्।
            markers: _driverMarkers,
          ),

          // ── पिन + Radar-ripple — एउटै Flutter overlay, एउटै
          // `_rippleScreenOffset` screen-projection बाट ड्राइभ (माथि
          // class-doc हेर्नुहोस्)। पिन (PNG bytes) र ripple (`CustomPaint`)
          // दुवै यही एउटै `Positioned`/anchor बिन्दुमा कोरिने भएकोले — न
          // त native-vs-Dart छुट्टै coordinate system छ, न त bitmap-frame/
          // platform-channel marker-swap — संरचनात्मक रूपमा नै एक-अर्काबाट
          // कहिल्यै छुट्टिन सक्दैनन्।
          if (_rippleScreenOffset != null && _meIcon != null)
            _buildPinAndRippleOverlay(),

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
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.kmPink),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  widget.isRide
                                      ? S.findingDrivers
                                      : S.findingProviders,
                                  style: const TextStyle(
                                      color: AppColors.kmText,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(
                                  widget.isRide
                                      ? S.waitingDriverAccept
                                      : S.waitingAccept,
                                  style: const TextStyle(
                                      color: AppColors.kmMuted)),
                              if (widget.isRide)
                                ValueListenableBuilder<int>(
                                  valueListenable: _secondsLeft,
                                  builder: (_, v, __) => Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                        '${S.waitingTimeLeft}: ${_mmss(v)}',
                                        style: const TextStyle(
                                            color: AppColors.kmOrange,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (widget.isRide) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _cancelling ? null : _raiseFare,
                          icon: const Icon(Icons.trending_up_rounded, size: 18),
                          label: Text(S.raiseFare),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.kmOrange,
                            foregroundColor: AppColors.kmInk,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancelling ? null : _handleCancel,
                        icon: _cancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.kmRose),
                              )
                            : const Icon(Icons.close_rounded, size: 18),
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
                stream: _offersStream,
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
                  if (widget.autoOffer &&
                      !_autoAccepting &&
                      pendingOnly.isNotEmpty) {
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('${S.driverOffersLabel} (${offers.length})',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                      ),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: offers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
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

/// radar-wave — frosted glass shockwave, पानीमा ढुङ्गा हालेपछि निस्कने
/// नरम/ढिलो लहर जस्तै (माथि `_rippleScreenOffset` class-doc हेर्नुहोस्)।
/// `_SearchingState._c` बाट सिधै ड्राइभ हुन्छ (continuous repaint, कुनै
/// discrete bitmap-frame होइन) — त्यसैले पूर्ण रूपमा smooth।
class _GlassRipplePainter extends CustomPainter {
  _GlassRipplePainter({required this.t, required this.color});
  final double t; // 0..1, लुप हुने animation progress
  final Color color;

  static const int _ringCount = 3;
  static const double _minRadius = 14;
  static const double _maxRadius = 80;
  static const double _peakStop = 0.78;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glass = Color.lerp(color, Colors.white, 0.45)!;
    for (var i = 0; i < _ringCount; i++) {
      // ३ घेरा १/३ फरकले सुरु हुन्छन् — एउटा हराउँदा अर्को सुरु भइरहेको
      // देखिने, निरन्तर pulsation।
      final p = (t + i / _ringCount) % 1.0;
      // वास्तविक पानीको लहर जस्तै — सुरुमा छिटो फैलिएर बिस्तारै गति घट्दै
      // जाने (ease-out), अनि लहर फैलिंदै जाँदा झन्-झन् छिटो हराउने
      // (ease-in fade)।
      final radiusP = Curves.easeOut.transform(p);
      final fadeP = Curves.easeIn.transform((1 - p).clamp(0.0, 1.0));
      final radius = _minRadius + radiusP * (_maxRadius - _minRadius);
      final outer = radius / _peakStop;
      canvas.drawCircle(
        center,
        outer,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            outer,
            [
              glass.withValues(alpha: 0),
              glass.withValues(alpha: 0),
              glass.withValues(alpha: 0.4 * fadeP),
              glass.withValues(alpha: 0),
              glass.withValues(alpha: 0),
            ],
            const [0.0, 0.6, _peakStop, 0.93, 1.0],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.2),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.5 * fadeP)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassRipplePainter old) =>
      old.t != t || old.color != color;
}

/// एउटा driver-प्रस्ताव — नाम, सवारी, rating, भाडा + Accept/Decline।
class _RideOfferCard extends StatefulWidget {
  final String requestId;
  final String offerId;
  final Map<String, dynamic> offer;
  const _RideOfferCard({
    required this.requestId,
    required this.offerId,
    required this.offer,
  });

  @override
  State<_RideOfferCard> createState() => _RideOfferCardState();
}

class _RideOfferCardState extends State<_RideOfferCard> {
  // Tap-Lock Fix — job_feed_screen.dart::_SendRideOfferButtonState कै उस्तै
  // साँचो जड: यी तीन बटन (Decline/Counter/Accept) पहिले कुनै local busy-
  // state नै राख्दैनथे, त्यसैले Accept थिचेपछि यो card पुन:निर्माण हुँदा
  // (वा दोहोरो-tap मा) त्यही ठाउँमा सरेको फरक बटनमा दोस्रो/द्रुत tap
  // landed भएर "Accept थिच्दा Counter चलेको जस्तो" देखिन सक्थ्यो। अब
  // पहिलो tap बित्तिकै तीनै बटन instantly disabled हुन्छन्।
  bool _busy = false;

  Future<void> _runBusy(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestId = widget.requestId;
    final offerId = widget.offerId;
    final offer = widget.offer;
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
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5)),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.kmOrange),
              ),
            )
          else ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _runBusy(
                            () => declineRideOffer(requestId, offerId)),
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
                    onPressed: _busy
                        ? null
                        : () => _runBusy(() => negotiateRideOffer(
                            context, requestId, offerId, (price as num?) ?? 0,
                            workerUid: (offer['workerUid'] ?? '').toString())),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.kmOrange,
                      side: const BorderSide(color: AppColors.kmOrange),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(S.counterBack,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _runBusy(() => acceptRideOffer(
                            context, requestId, offerId, offer)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kmOrange,
                      foregroundColor: AppColors.kmInk,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.kmInk),
                          )
                        : Text(S.accept,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// Dead Back-Button Fix — यो screen Firestore doc मेटिएको/cancelled भएको
// क्षणमै (माथि `data == null` वा cancelled-status branch) देखिन्छ, अनि
// `Navigator.pop(context)` लाई pop गर्न केही नभएको बेला (यो screen कुनै
// कारणले navigation stack को जग/root मै परेमा) कल गर्दा debug मा assertion
// throw हुन्छ — त्यो error कतै silently निलिंदा बटन "पूर्ण रूपमा मृत/
// unresponsive" देखिन्थ्यो (tap त हुन्थ्यो, तर pop कहिल्यै सफल नहुने)।
// अब पप गर्न साँच्चै सकिन्छ भनेर पहिल्यै जाँच्ने — सकिँदैन भने (पहिल्यै
// जग/root मै भए) चुपचाप no-op, कुनै त्रुटि/crash नहुने।
void _safeBack(BuildContext context) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
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

// Flutter Web BackdropFilter-over-PlatformView Fix — `BackdropFilter`
// (frosted-glass blur) माथि सिधै `GoogleMap` (native मा सामान्य, तर web मा
// वास्तवमै एउटा छुट्टै HTML/DOM element — PlatformView) भएको bेला, Flutter
// Web (दुवै CanvasKit/HTML renderer) ले backdrop (नक्साका पिक्सेल) नै पढ्न
// नसक्ने भएकोले त्यो BackdropFilter layer आफैं (र यसको तल्लो सबै child
// समेत) पूर्ण रूपमा अदृश्य भइदिन्छ — कुनै error/exception बिनै (ride-code
// banner, driver info, Call/Video/Message सबै सहितको तल्लो कार्ड नै
// चुपचाप हराउने बग, live browser मा नै पुष्टि भएको)। native (Android/iOS)
// मा यो समस्या छैन — त्यसैले web मा मात्र blur हटाएर उस्तै रङको ठोस
// (कुनै blur नभएको) पृष्ठभूमि; native मा पहिलेकै जस्तै साँचो frosted-glass।
Widget _glassOrSolid({required Widget child}) {
  if (kIsWeb) return child;
  return glassBackdrop(sigma: 24, child: child,
  );
}

// ── Job status card (assigned worker + fixed address) ───────────────────────
// नक्सा/दूरी/समय/"Open in Google Maps" अब माथिको साझा RouteMapView ले नै
// देखाउँछ — यो card ले काम (नाम, मूल्य, ठेगाना) + Call/Message मात्र देखाउँछ।
// OTP Auto-Reveal On Arrival — यो card `DraggableScrollableSheet` भित्र
// सधैं collapsed (17% height) मा सुरु हुन्छ (माथि doc-comment हेर्नुहोस्,
// "नक्सा/बाइक पूरै देखिन्छ" भन्ने कारणले जानाजान)। तर त्यसको मतलब driver
// आइपुगेर OTP banner (भित्रैको content मा, collapsed बेला देखिंदैन) आएको
// क्षणमा पनि passenger ले आफैं माथि नतानेसम्म देख्दैनथ्यो — "OTP sheet
// प्रस्ट देखिनुपर्छ" गुनासोको जड। Driver-side (job_route_screen.dart कै
// `_cardCollapsed`/`_restartAutoCollapseTimer`) मा उस्तै auto-expand
// पहिल्यै छ; यहाँ समान व्यवहार `DraggableScrollableController` मार्फत —
// `arrivedAt` आउनेबित्तिकै sheet माथि तानिन्छ, अनि OTP मिलेर राइड सुरु
// भएको (status 'in_progress') ३ सेकेन्डपछि आफैं फेरि संकुचित हुन्छ। यो
// StatefulWidget ले केवल controller/timer थाम्छ — वास्तविक card content
// (`_ProviderTrackCardBody`, तल) लाई जस्ताको-त्यस्तै राख्छ, जसमा कुनै
// TextField/FocusNode छैन (passenger ले OTP टाइप गर्दैन, driver ले मात्र
// — त्यो फोकस-संवेदनशील कोड यहाँ कहिल्यै छोइँदैन)।
class _ProviderTrackCard extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  const _ProviderTrackCard({
    required this.requestId,
    required this.data,
  });

  @override
  State<_ProviderTrackCard> createState() => _ProviderTrackCardState();
}

class _ProviderTrackCardState extends State<_ProviderTrackCard> {
  final _sheetController = DraggableScrollableController();
  Timer? _autoCollapseAfterStartTimer;
  // OTP-Visible Minimum Floor — driver आइपुगेर sheet माथि तानिएकै क्षणदेखि
  // कम्तिमा 15s (OTP code पढेर driver लाई सुनाउन/driver ले टाइप गर्न
  // पर्याप्त समय) — job_route_screen.dart कै `_minCollapseAt`/
  // "Protected-Minimum Collapse Deadline" कै उस्तै ढाँचा, यहाँ
  // DraggableScrollableController मार्फत।
  DateTime? _expandedAt;

  bool get _arrived => widget.data['arrivedAt'] != null;
  String get _status => (widget.data['status'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    if (_arrived) _expandSoon();
  }

  @override
  void didUpdateWidget(covariant _ProviderTrackCard old) {
    super.didUpdateWidget(old);
    final wasArrived = old.data['arrivedAt'] != null;
    final oldStatus = (old.data['status'] ?? '').toString();
    if (!wasArrived && _arrived) _expandSoon();
    if (oldStatus != 'in_progress' && _status == 'in_progress') {
      _autoCollapseAfterStartTimer?.cancel();
      // Post-Verify Linger — Sequential, job_route_screen.dart कै उस्तै
      // ढाँचा: 15s floor अझै बाँकी भए पहिले त्यो बाँकी समय पूरै पर्खने,
      // अनि मात्र त्यसपछि थप 4s linger (floor + linger, क्रमिक) — floor
      // पहिल्यै सकिसकेको भए (सामान्य प्रयोगमा यही हुन्छ) सामान्य 4s linger।
      const verifyLinger = Duration(seconds: 4);
      var delay = verifyLinger;
      final expandedAt = _expandedAt;
      if (expandedAt != null) {
        final floorRemaining =
            expandedAt.add(const Duration(seconds: 15)).difference(DateTime.now());
        if (floorRemaining > Duration.zero) delay = floorRemaining + verifyLinger;
      }
      _autoCollapseAfterStartTimer = Timer(delay, () {
        if (!mounted || !_sheetController.isAttached) return;
        _sheetController.animateTo(0.17,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInCubic);
      });
    }
  }

  void _expandSoon() {
    _expandedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetController.isAttached) return;
      _sheetController.animateTo(0.62,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _autoCollapseAfterStartTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProviderTrackCardBody(
      requestId: widget.requestId,
      data: widget.data,
      sheetController: _sheetController,
    );
  }
}

class _ProviderTrackCardBody extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final DraggableScrollableController sheetController;
  const _ProviderTrackCardBody({
    required this.requestId,
    required this.data,
    required this.sheetController,
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

  /// Matched/active (accepted/confirmed/in_progress) job cancel गर्ने —
  /// पहिले यहाँ कुनै cancel बटन नै थिएन; `ActiveJobBar` (main_container.dart
  /// को shell मा मात्र देखिने, यो full-screen live-tracking route पुश
  /// भएपछि ढाकिने) बाहेक कतैबाट पनि cancel गर्न नमिल्ने — employer यही
  /// स्क्रिनमा हुँदा cancel गर्न यो पेज बाट बाहिरिएर main shell फर्कनुपर्ने
  /// हुन्थ्यो। `active_job_bar.dart::_confirmCancel` कै उस्तै pattern
  /// (confirm dialog + reason + `deleteCancelledBooking`) — दुवैतिर
  /// (worker को job_route_screen.dart मा पनि उस्तै) उही एउटा core function
  /// प्रयोग हुने भएकोले, यहाँबाट cancel गरे पनि worker को स्क्रिनमा
  /// Firestore doc delete भएकै क्षण (live listener, `!snap.exists`/
  /// `data == null` जाँच) तुरुन्तै देखिन्छ — छुट्टै sync code चाहिँदैन।
  Future<void> _cancelActiveJob(BuildContext context) async {
    final isRide = (data['isRide'] ?? false) == true ||
        (data['service'] ?? '') == 'Bike' ||
        (data['service'] ?? '') == 'Car' ||
        (data['service'] ?? '') == 'Auto';
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
    final reason = await pickCancellationReason(context);
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await deleteCancelledBooking(
        requestId,
        workerUid: (data['workerUid'] ?? '').toString(),
        // Employer ले cancel गर्दा कहिल्यै penalty छैन (job_actions.dart::
        // deleteCancelledBooking हेर्नुहोस्) — worker ले मात्र।
        cancelledByWorker: false,
        reason: reason,
      );
      if (navigator.mounted) navigator.pop();
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
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
    final vehicleMake = (data['vehicleMake'] ?? '').toString();
    final vehicleModel = (data['vehicleModel'] ?? '').toString();
    final vehiclePlate = (data['vehiclePlate'] ?? '').toString();
    final vehicleLine =
        [vehicleMake, vehicleModel].where((s) => s.isNotEmpty).join(' ');
    final status = (data['status'] ?? 'accepted').toString();
    final arrived = data['arrivedAt'] != null;
    // Ride-Start OTP — driver आइपुगेपछि यही कोड सुनाउनुपर्छ; राइड
    // 'in_progress' नभएसम्म (अझै driver ले verify नगरेसम्म) मात्र देखिने।
    final isRide =
        service == 'Bike' || service == 'Car' || service == 'Auto';
    // Ride मा auto-derived साँचो सवारी-प्रकार अनुसार (picker लुकाइएको,
    // Firestore को `travelMode` field अब कहिल्यै लेखिँदैन) — नत्र default
    // (`driving`) कै कारण Bike राइडमा पनि गलत कार-आइकन देखिने बग हुन्थ्यो।
    final travelMode = isRide
        ? travelModeForVehicle(service)
        : TravelMode.fromValue(data['travelMode'] as String?);

    // Draggable Collapsible Bottom Sheet — पहिले यो कार्ड (सबै content
    // सहित, fixed/full height मा) सिधै `Positioned(bottom:0)` मार्फत
    // बसेकोले नक्सा/बाइक-आइकनको ठूलो भाग नै ढाक्थ्यो (passenger-तर्फ
    // specifically गुनासो आएको)। अब `DraggableScrollableSheet` ले
    // default मा एउटा सानो compact bar (handle + status row) मात्र
    // देखाउँछ — नक्सा/बाइक पूरै देखिन्छ — र माथि तान्दा (वा snap-tap) पूरै
    // detail (driver info, Call/Video/Message, completion बटन) खुल्छ।
    // handle यहीँ scrollable content कै पहिलो item हो (छुट्टै गैर-scroll
    // header होइन) — नत्र collapsed बेला त्यहीँबाट तानिएको drag ले sheet
    // resize गर्दैनथ्यो, केवल भित्री scroll मात्र हुने जोखिम हुन्थ्यो।
    return DraggableScrollableSheet(
      controller: sheetController,
      initialChildSize: 0.17,
      minChildSize: 0.17,
      maxChildSize: 0.62,
      snap: true,
      snapSizes: const [0.17, 0.62],
      builder: (context, scrollController) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        child: _glassOrSolid(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.kmSurface.withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                children: [
                  // Drag handle — Uber/inDrive-शैली, "यो तान्न मिल्छ" भन्ने
                  // स्पष्ट संकेत।
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                // "Worker has arrived at the location" — arrival हुनेबित्तिकै
                // (push notification कै सँगसँगै) यहाँ पनि प्रस्ट देखिने, ताकि
                // employer app भित्रै हुँदा पनि तुरुन्तै थाहा पाओस्।
                if (arrived) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                          child: Text(
                              isRide
                                  ? S.riderArrivedNotifTitle
                                  : S.workerArrivedNotifTitle,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ],
                // Ride-Start OTP — driver आइपुगेर राइड सुरु नगरेसम्म (status अझै
                // 'in_progress'/'completed' नभएसम्म) पासेन्जरलाई सधैँ प्रस्ट
                // देखिने। पहिले यहाँ `status != 'in_progress'` मात्र भएकोले
                // राइड 'completed' भइसकेपछि पनि यो कोड-banner अझै देखिरहन्थ्यो
                // (अर्थहीन, राइड सकिइसकेको)।
                // सर्भर (`getRideStartCode`) ले कोड 'accepted'/'confirmed' मा मात्र
                // दिन्छ — त्यसैले banner पनि त्यतिबेला मात्र (नत्र पहिले नै
                // असफल भएको अवस्था accept पछि पनि अड्किन्थ्यो)।
                if (isRide &&
                    (status == 'accepted' || status == 'confirmed')) ...[
                  const SizedBox(height: 10),
                  _RideStartCodeBanner(
                    requestId: requestId,
                    status: status,
                    builder: (rideStartCode) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(jobStatusMeta(status).icon,
                        color: Colors.white, size: 18),
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
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15)),
                                Text(
                                  [
                                    S.serviceName(service),
                                    if (price != null) 'Rs. $price',
                                  ].join('  ·  '),
                                  style:
                                      const TextStyle(color: AppColors.kmMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Ride-Hailing — गाडी/बाइकको नम्बर प्लेट + मोडेल,
                      // accept भएकै क्षणदेखि प्रस्ट देखिने (job_actions.dart::
                      // _acceptRideOfferImpl/_acceptRideAtListedPriceImpl ले
                      // अब यी field हरू parent doc मा लेख्छन्)।
                      if (isRide &&
                          (vehicleLine.isNotEmpty ||
                              vehiclePlate.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // पहिले सधैं कार-आइकन थियो — Bike राइडमा पनि
                            // त्यही देखिने (गलत/misleading) बग (`travelMode`
                            // कै उस्तै जड, माथिको comment हेर्नुहोस्)।
                            Icon(
                                service == 'Bike' || service == 'Auto'
                                    ? serviceIconFor(service)
                                    : Icons.directions_car_filled_rounded,
                                size: 15, color: AppColors.kmMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                [
                                  if (vehicleLine.isNotEmpty) vehicleLine,
                                  if (vehiclePlate.isNotEmpty)
                                    '${S.vehiclePlateLabel}: $vehiclePlate',
                                ].join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.kmText),
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Pickup/Drop कार्डभित्रै (बाहिर/लुकाएर होइन) — सधैँ
                      // दुवै नाम स्पष्ट टेक्स्टमा, driver कै कार्डमा जस्तै।
                      if (isRide) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.radio_button_checked_rounded,
                                size: 14, color: AppColors.kmTeal),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                      text: '${S.pickupPointLabel}: ',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.kmMuted)),
                                  TextSpan(
                                      text: (data['address'] ?? '')
                                              .toString()
                                              .trim()
                                              .isEmpty
                                          ? S.jobSiteWord
                                          : (data['address']).toString(),
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.kmText)),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.flag_rounded,
                                size: 14, color: AppColors.kmOrange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                      text: '${S.dropPointLabel}: ',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.kmMuted)),
                                  TextSpan(
                                      text: (data['destinationAddress'] ?? '')
                                              .toString()
                                              .trim()
                                              .isEmpty
                                          ? S.destinationLabel
                                          : (data['destinationAddress'])
                                              .toString(),
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.kmText)),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Multi-modal यातायात — दुवैतिरबाट (worker वा employer)
                      // छान्न मिल्ने एउटै interactive chip row, JobRouteScreen
                      // मा भएकै जस्तै। जसले पनि tap गरे पनि उही Firestore
                      // फिल्डमा लेखिन्छ र अर्को पक्षले पनि तुरुन्तै देख्छ।
                      // Strict Vehicle Type Isolation — Bike/Car राइडमा भने
                      // यो कहिल्यै नदेखियोस् (सवारी-प्रकार पहिल्यै तय
                      // भइसकेको, worker आफैंले दर्ता गरेको) — सामान्य काम
                      // (mechanic/plumber) मा मात्र उपयोगी।
                      if (!isRide) ...[
                        const SizedBox(height: 10),
                        TravelModeChips(
                          selected: travelMode,
                          onChanged: (m) => FirebaseFirestore.instance
                              .collection('serviceRequests')
                              .doc(requestId)
                              .set({'travelMode': m.value},
                                  SetOptions(merge: true)),
                        ),
                      ],
                      if (address.isNotEmpty) ...[
                        Divider(
                            height: 16,
                            color: Colors.white.withValues(alpha: 0.1)),
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
                      if (isCommunicationUnlocked(status) &&
                          phone.isNotEmpty) ...[
                        Divider(
                            height: 16,
                            color: Colors.white.withValues(alpha: 0.1)),
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
                  NeonCommBar(
                    callLabel: S.callWord,
                    videoLabel: S.videoCall,
                    messageLabel: S.messageWord,
                    onCall: () => _callWorker(context, phone),
                    onVideo: () => startInAppCall(
                      context,
                      requestId: requestId,
                      otherName: name,
                      video: true,
                    ),
                    onMessage: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          requestId: requestId,
                          workerName: name,
                          initialStatus: status,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 16, color: AppColors.kmMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              isRide
                                  ? S.contactLockedAwaitingArrivalRide
                                  : S.contactLockedAwaitingArrival,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.kmMuted)),
                        ),
                      ],
                    ),
                  ),
                // Cancel (Active Job) — माथिकै `_cancelActiveJob` doc-comment
                // हेर्नुहोस्। Completed भइसकेपछि यो sheet आफैं अब नदेखिने
                // भएकोले (status completed भए caller route screen नै
                // बदल्छ), यहाँ थप `status != 'completed'` जाँच चाहिँदैन।
                const SizedBox(height: 10),
                NeonCancelPill(
                    label: S.cancelRequest,
                    onTap: () => _cancelActiveJob(context)),
                // Job Completion & Rating Control — bookings_screen.dart कै
                // उस्तै ट्रिगर, तर पहिले यहाँ (live-tracking screen, जहाँ
                // passenger राइड सकिँदा वास्तवमा हुन्छ) कहिल्यै थिएन — राइड
                // सकिएपछि rating दिन Bookings tab सम्म छुट्टै गएर खोज्नुपर्ने
                // हुन्थ्यो, "ड्रप भएपछि रेटिङ स्क्रिन देखिँदैन" गुनासोको
                // साँचो जड। `showCompleteJobSheet` आफैंले नै payment + 5-star
                // rating (अनिवार्य) एउटै sheet मा देखाउँछ।
                //
                // Destination-Proximity Gate — पहिले यो बटन `in_progress`
                // हुनेबित्तिकै (राइड साँच्चै सुरु भएकै क्षणमा, गन्तव्यबाट
                // टाढा भए पनि) तुरुन्तै थिच्न मिल्थ्यो — "गन्तव्यमा पुगेपछि
                // मात्र" भन्ने कुनै जाँच नै थिएन (पिकअप-arrival गेट
                // job_route_screen.dart::_withinArrivalRadius मा थियो,
                // drop-off मा उस्तै कहिल्यै थिएन)। अब driver को लाइभ GPS
                // (workerLat/workerLng) गन्तव्य (employerLat/employerLng)
                // को ~30m भित्र नपुगेसम्म बटन निष्क्रिय — उस्तै threshold,
                // pickup-arrival गेटसँगै मिल्दो।
                if (status == 'in_progress') ...[
                  Builder(builder: (context) {
                    // Ride (Bike/Car) मा `employerLat/Lng` भनेको pickup हो
                    // (destination होइन) — OTP ठ्याक्कै pickup मै सोधिन्छ,
                    // त्यसैले यहाँ pickup कै 30m भित्र जाँच गरे OTP मिलेको
                    // क्षणमै (ड्राइभर अझै pickup मै उभिएको बेला) बटन खुल्ने
                    // गम्भीर बग हुन्थ्यो — गन्तव्य नपुगी payment खुलेको।
                    // Ride मा साँचो गन्तव्य (destinationLat/Lng) कै 30m भित्र
                    // मात्र; सामान्य job-portal (ride नभएको) मा पहिलेकै
                    // employerLat/Lng (जो त्यहाँ नै काम-स्थल/destination हो)।
                    final targetLat = isRide
                        ? (data['destinationLat'] as num?)?.toDouble()
                        : (data['employerLat'] as num?)?.toDouble();
                    final targetLng = isRide
                        ? (data['destinationLng'] as num?)?.toDouble()
                        : (data['employerLng'] as num?)?.toDouble();
                    final wLat = (data['workerLat'] as num?)?.toDouble();
                    final wLng = (data['workerLng'] as num?)?.toDouble();
                    final nearDestination = targetLat != null &&
                        targetLng != null &&
                        wLat != null &&
                        wLng != null &&
                        haversineKm(wLat, wLng, targetLat, targetLng) <=
                            _destinationArrivalThresholdKm;
                    // Dual-Confirmation Completion — Worker/Employer
                    // job-portal मात्र (Ride होइन, त्यो पुरानै एकतर्फी
                    // flow यथावत्)। Worker आफैंले job_route_screen.dart मा
                    // "Job Completed" नथिचेसम्म यो भुक्तानी+rating बटन
                    // disabled रहन्छ — दुवैले confirm गरेपछि मात्र
                    // settlement चरण अघि बढोस् भनेर।
                    final workerConfirmed =
                        isRide || data['workerConfirmedComplete'] == true;
                    final canComplete = nearDestination && workerConfirmed;
                    final label = !nearDestination
                        ? S.arriveAtDestinationFirst
                        : !workerConfirmed
                            ? S.waitingForWorkerToConfirmComplete
                            : S.completeJobTitleFor(isRide);
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: canComplete
                                ? () => showCompleteJobSheet(
                                      context,
                                      docId: requestId,
                                      amount: (price ?? 0) as num,
                                      workerUid:
                                          (data['workerUid'] ?? '').toString(),
                                      workerName: name,
                                      service: service,
                                    )
                                : null,
                            icon: const Icon(Icons.check_circle_rounded),
                            label: Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.kmTeal,
                              foregroundColor: AppColors.kmInk,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}



/// राइड-सुरु OTP देखाउने — कोड अब दस्तावेजमा होइन, सर्भर (`getRideStartCode`,
/// केवल यात्रुलाई) बाट एकपटक ल्याइन्छ। stream rebuild ले बारम्बार कल नगरोस्
/// भनेर Future initState मा एकपटक मात्र बन्छ; असफल भए पुनः प्रयास बटन।
class _RideStartCodeBanner extends StatefulWidget {
  final String requestId;
  final String status;
  final Widget Function(String code) builder;
  const _RideStartCodeBanner(
      {required this.requestId, required this.status, required this.builder});

  @override
  State<_RideStartCodeBanner> createState() => _RideStartCodeBannerState();
}

class _RideStartCodeBannerState extends State<_RideStartCodeBanner> {
  String? _code;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RideStartCodeBanner old) {
    super.didUpdateWidget(old);
    // accepted → confirmed जस्ता बदलावमा कोड अझै आएको छैन भने फेरि ल्याउने।
    if (_code == null && old.status != widget.status) _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _failed = false);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getRideStartCode')
          .call({'requestId': widget.requestId}).timeout(
              const Duration(seconds: 20));
      final code = (res.data is Map ? res.data['code'] : null)?.toString();
      if (!mounted) return;
      setState(() => _code = (code != null && code.isNotEmpty) ? code : null);
      if (code == null || code.isEmpty) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_code != null) return widget.builder(_code!);
    if (_failed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(S.retry),
        ),
      );
    }
    return const SizedBox(
        height: 28,
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))));
  }
}
