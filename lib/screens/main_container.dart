// screens/main_container.dart
// Role अनुसार tab हरू सहितको मुख्य Shell + inDrive-style bottom bar।
// यहीँ negotiation (counter-offer) अलर्ट पनि — कुन tab मा भए पनि, employer र
// worker दुवैलाई अर्को पक्षले नयाँ मूल्य पठाउनेबित्तिकै sound + banner देखियोस्
// भनेर एउटै persistent shell मा राखिएको (कुनै एक screen मात्र खुला हुँदा
// होइन)।
import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../services/online_location_service.dart';
import '../services/presence_service.dart';
import '../theme/app_theme.dart';
import '../watchlist_screen.dart';
import '../widgets/active_job_bar.dart';
import '../widgets/glass_ui.dart';
import '../widgets/job_alert_sound.dart';
import '../widgets/spring_tap.dart';
import 'bookings_screen.dart';
import 'call_screen.dart';
import 'home_screen.dart';
import 'job_actions.dart' show openJobRoute, takeCancelNoticeReason;
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'request_tracking_screen.dart';

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  bool _loading = true;

  // negotiation (counter-offer) अलर्ट — role थाहा भएपछि एकपटक मात्र subscribe
  // हुन्छ; कुनै काम अहिले "मेरो जवाफ पर्खिरहेको" (worker को हकमा
  // pending_worker_counter, employer को हकमा pending_employer_approval) मा
  // नयाँ पसेको भेटियो भने sound + banner। पहिलो snapshot मा भएका सबैलाई
  // "नयाँ" ठान्दैन — पछि थपिनेलाई मात्र।
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _negotiationSub;
  final Set<String> _waitingOnMeIds = {};
  bool _firstNegotiationSnapshot = true;

  // NOTE: यहाँ पहिले driver आफैंले पठाएका ride-offer हरूमध्ये passenger ले
  // counter गरेकालाई tab-independent देखाउने watcher थियो
  // (`collectionGroup('rideOffers').where('workerUid', ...)`)। त्यो हटाइयो
  // — Firestore ले यो query लाई rules-स्तरमा कहिल्यै अनुमति दिएन (live
  // device मा दोहोरिएर PERMISSION_DENIED), र त्यो अनुमति दिने एकमात्र
  // सुरक्षित तरिका (`get()`-विनाको छुट्टै `allow list`) ले employer-तर्फको
  // *पहिल्यैदेखि काम गरिरहेको* "मेरो ride मा भएका सबै प्रतिस्पर्धी offer
  // हेर्ने" feature नै भत्काउँथ्यो (firestore.rules मा नै त्यो जोखिम
  // नलिने निर्णयको टिप्पणी हेर्नुहोस्)। driver ले आफ्नो offer card
  // त्यही Job Feed tab मा भएसम्म अझै live देखिन्छ
  // (`job_feed_screen.dart::_SendRideOfferButtonState._offerStream`) —
  // अन्तै गए in-app notification मात्र, पहिले जस्तै।

  // सक्रिय काम (accepted/confirmed/in_progress) भेटिनेबित्तिकै — कुन tab मा
  // भए पनि, तुरुन्तै route-map screen खोल्ने (InDrive/Uber जस्तै, tap गर्नु
  // नपरोस्)। पहिलो snapshot मा नै भेटिए (app भर्खर खोलेको — cold start) पनि,
  // र पछि नयाँ एउटा status यही सूचीमा पसेको भेटिए (अर्को party ले counter
  // approve गर्‍यो, वा आफैंले accept गर्‍यो) पनि — दुवै अवस्थामा खोल्ने।
  static const _activeJobStatuses = {'accepted', 'confirmed', 'in_progress'};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeJobSub;
  bool _firstActiveJobSnapshot = true;
  final Set<String> _knownActiveJobIds = {};
  String? _autoOpenedForJobId;

  // pinned ActiveJobBar (nav माथि, हरेक tab मा) र employer कै Bookings tab को
  // badge दुवैका लागि — सबैभन्दा पछिल्लो सक्रिय काम को id मात्र चाहिन्छ, बाँकी
  // तथ्याङ्क ActiveJobBar आफैंले doc सिधै सुनेर लिन्छ।
  String? _pinnedActiveJobId;
  Map<String, dynamic>? _pinnedActiveJobData;
  int _activeJobCount = 0;
  bool _pinnedIsWorker = false;

  // worker ले JobRouteScreen नखोलेको बेला (अर्को tab मा भए पनि) कामको live
  // location Firestore मा लगातार पठाउने — नत्र pinned bar/employer को नक्सा
  // worker ले route screen नखोलेसम्म पुरानै स्थानमा अड्किन्थ्यो।
  StreamSubscription<Position>? _workerPosSub;
  String? _workerTrackingForJobId;

  // ── आउँदो कल (incoming call) — tab-independent, ChatScreen नै खुला
  // नभए पनि ──
  // पहिले यो केवल ChatScreen भित्रै (त्यही screen खुला हुँदा मात्र) पत्ता
  // लाग्थ्यो — त्यसैले employer/worker अर्को कुनै tab/screen मा हुँदा कल
  // गरे callee लाई कहिल्यै थाहै हुँदैनथ्यो ("रिङ नहुने" गुनासोको साँचो जड)।
  // अब यहाँ MainContainer कै साझा shell मा नै — active job भएसम्म (जति
  // वटा भए पनि) ती हरेकको `calls/{id}` doc सुन्ने, ringing भेटिए जुनसुकै
  // tab/screen मा भए पनि तुरुन्तै incoming-call dialog देखाउने।
  String _myName = '';
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _callWatchers =
      {};
  final Set<String> _ringingHandledFor = {};
  bool _inCall = false;

  // Hotel Booking Call-Ring Fix — माथिको ride/job watcher ले मात्र
  // `_syncCallWatchers` चलाउँथ्यो, confirmed/checked-in hotel booking कहिल्यै
  // होइन — त्यसैले त्यस्तो booking मा गरिएको Call/Video कल अर्को पक्ष (guest
  // वा hotel partner, दुवैतिरबाट) को फोनमा foreground मा कहिल्यै रिङ
  // हुँदैनथ्यो ("Calling…" मै अड्किने गुनासोको साँचो जड — push notification
  // tap बाटै मात्र जोडिन्थ्यो, app खुला छँदा होइन)। अब ride/job + hotel-guest
  // + hotel-partner तीनै source लाई संयुक्त गरेर एकैचोटि `_syncCallWatchers`
  // लाई दिने (हेर्नुहोस् `_recomputeCallWatchers`)।
  Set<String> _activeRideCallIds = {};
  Set<String> _hotelGuestCallIds = {};
  Set<String> _hotelPartnerCallIds = {};
  // Salon ग्राहक↔मालिक chat (`salon_chats`) — दुवै पक्षको लागि एउटै query
  // (`participants` मा आफ्नो uid)।
  Set<String> _salonChatCallIds = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _salonChatCallSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _hotelGuestCallSub;
  // Partner तर्फ प्रति-होटल एउटा equality (`hotelId == X`) listener — firestore
  // rules ले `hotel_bookings` पढ्न partner लाई त्यो होटल चिन्ने हिसाबले मात्र
  // दिने भएकोले `whereIn` (धेरै होटल एकैचोटि) query rule-ले प्रमाणित गर्न
  // सक्दैन।
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _hotelPartnerCallSubs = [];
  final Map<String, Set<String>> _hotelPartnerCallIdsByHotel = {};

  void _recomputeCallWatchers() {
    _syncCallWatchers({
      ..._activeRideCallIds,
      ..._hotelGuestCallIds,
      ..._hotelPartnerCallIds,
      ..._salonChatCallIds,
    });
  }

  void _startSalonChatCallWatcher(String uid) {
    _salonChatCallSub?.cancel();
    _salonChatCallSub = FirebaseFirestore.instance
        .collection('salon_chats')
        .where('participants', arrayContains: uid)
        .limit(50)
        .snapshots()
        .listen((snap) {
      _salonChatCallIds = snap.docs.map((d) => d.id).toSet();
      _recomputeCallWatchers();
    }, onError: (_) {});
  }

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadMyName();
    PresenceService.start();
    OnlineLocationService.start();
    // Worker/Driver Dashboard (job_feed_screen.dart) कै आफ्नै bottom nav बाट
    // "Home" (वा अरू कुनै ट्याब) थिचेपछि यहाँ फर्कँदा सही tab मै पुगोस् भनेर
    // (app_globals.dart::requestedMainTabIndex हेर्नुहोस्)।
    requestedMainTabIndex.addListener(_onRequestedTabChanged);
  }

  void _onRequestedTabChanged() {
    if (!mounted) return;
    final target = requestedMainTabIndex.value;
    if (target != _currentIndex) setState(() => _currentIndex = target);
  }

  @override
  void dispose() {
    requestedMainTabIndex.removeListener(_onRequestedTabChanged);
    _negotiationSub?.cancel();
    _activeJobSub?.cancel();
    _workerPosSub?.cancel();
    _hotelGuestCallSub?.cancel();
    _salonChatCallSub?.cancel();
    for (final s in _hotelPartnerCallSubs) {
      s.cancel();
    }
    for (final s in _callWatchers.values) {
      s.cancel();
    }
    PresenceService.stop();
    OnlineLocationService.stop();
    super.dispose();
  }

  Future<void> _loadMyName() async {
    final user = FirebaseAuth.instance.currentUser;
    var name = user?.displayName ?? '';
    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .get();
      final n = (u.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) name = n;
    } catch (_) {}
    _myName = name.isEmpty ? 'सहयात्री' : name;
  }

  /// सक्रिय काम (जति वटा भए पनि) को सेटसँग मिलाएर `calls/{id}` watcher
  /// थप्ने/हटाउने — काम अब सक्रिय नरहेको बित्तिकै त्यसको कल-listener पनि बन्द।
  void _syncCallWatchers(Set<String> activeIds) {
    final toRemove =
        _callWatchers.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in toRemove) {
      _callWatchers.remove(id)?.cancel();
      _ringingHandledFor.remove(id);
    }
    for (final id in activeIds) {
      if (_callWatchers.containsKey(id)) continue;
      _callWatchers[id] =
          CallService.watch(id).listen((c) => _onCallDocChanged(id, c));
    }
  }

  void _onCallDocChanged(String requestId, Map<String, dynamic>? c) {
    if (c == null) {
      _ringingHandledFor.remove(requestId);
      return;
    }
    final status = (c['status'] ?? '').toString();
    if (status != 'ringing') {
      _ringingHandledFor.remove(requestId);
      return;
    }
    final me = FirebaseAuth.instance.currentUser?.uid;
    final callerUid = (c['callerUid'] ?? '').toString();
    // आफैंले सुरु गरेको कल (caller side) लाई "आउँदो कल" ठान्दैन।
    if (callerUid.isEmpty || callerUid == me) return;
    // यही requestId कै लागि CallScreen पहिल्यै कतैबाट (यहीँ, वा
    // push-notification tap बाट) खुलिसकेको भए दोहोर्‍याएर नखोल्ने।
    if (activeCallRequestId == requestId) return;
    if (_inCall || _ringingHandledFor.contains(requestId)) return;
    _ringingHandledFor.add(requestId);
    _showIncomingCall(
      requestId: requestId,
      video: (c['mode'] ?? 'audio').toString() == 'video',
      callerName: (c['callerName'] ?? S.customerWord).toString(),
      callerUid: callerUid,
    );
  }

  /// आउँदो कल — सिधै full-screen `CallScreen` (needsAcceptance: true) push
  /// गर्ने, कुनै सानो `AlertDialog` होइन। त्यो dialog-आधारित पुरानो बाटोले
  /// दुई ठाउँमा समस्या दिन्थ्यो: (१) साना overlay ले map/chat माथि टाँसिएर
  /// "messy" देखिन्थ्यो, (२) Accept थिचेपछि dialog बन्द भएर फेरि छुट्टै
  /// `Navigator.push` गर्दा (दुई अलग-अलग navigation event) कहिलेकाहीं
  /// त्यसैको बीचमा कुनै कारणले (context stale, exception, आदि) map मा
  /// फर्किन्थ्यो। अब एउटै route ले नै ringing UI र साँचो कल UI दुवै
  /// सम्हाल्छ (CallScreen भित्रैको `_awaitingAccept` हेर्नुहोस्) — Accept ले
  /// कहिल्यै दोस्रो push/pop गर्दैन, त्यसैले त्यो race सम्भवै छैन।
  Future<void> _showIncomingCall({
    required String requestId,
    required bool video,
    required String callerName,
    required String callerUid,
  }) async {
    _inCall = true;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen(
        requestId: requestId,
        otherName: callerName,
        myName: _myName,
        video: video,
        isCaller: false,
        otherUid: callerUid,
        needsAcceptance: true,
      ),
    ));
    _ringingHandledFor.remove(requestId);
    _inCall = false;
  }

  // यो session मा background-location rationale पहिल्यै देखाइसकेको भए
  // फेरि नदेखाउने (हरेक काम accept गर्दा पटक-पटक दोहोरिनु हुँदैन)।
  bool _askedBackgroundLocationThisSession = false;

  /// Android 10+ मा foreground service चलिरहँदा पनि, screen लक भएको धेरै
  /// बेरपछि वा अर्को app मा गएपछि पनि निरन्तर location fix पाउन छुट्टै
  /// "Allow all the time" अनुमति चाहिन्छ (foreground/"while using the app"
  /// भन्दा फरक, र यो सँगै एकैचोटि माग्न मिल्दैन — Android आफैंले क्रमैसँग
  /// मात्र दिन्छ)। यो नपाए पनि tracking रोकिँदैन — फेरि foreground-मात्र
  /// (पहिलेकै व्यवहार) मा चल्छ, अनुमति नदिए पनि काम/भुक्तानी flow कहीं
  /// नअड्किओस् भनेर।
  Future<void> _ensureBackgroundLocationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_askedBackgroundLocationThisSession) return;
    _askedBackgroundLocationThisSession = true;
    try {
      final status = await Permission.locationAlways.status;
      if (status.isGranted) return;
      if (!mounted) return;
      final proceed = await showKmDialog<bool>(
        context: context,
        title: S.backgroundLocationRationaleTitle,
        message: S.backgroundLocationRationaleBody,
        icon: Icons.location_on_rounded,
        actions: [
          KmDialogAction(
            label: S.notNow,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          KmDialogAction(
            label: S.allowWord,
            filled: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
      if (proceed == true) {
        await Permission.locationAlways.request();
      }
    } catch (_) {
      // अनुमति flow असफल भए पनि foreground tracking चलिरहन्छ।
    }
  }

  /// worker मात्र — सक्रिय काम भएसम्म आफ्नो GPS लगातार Firestore मा लेख्ने,
  /// चाहे JobRouteScreen खुला होस् वा नहोस् (त्यो स्क्रिनले पनि आफ्नै छुट्टै
  /// route-fetch/arrival-detection सहितको live tracking राख्छ — यहाँको भने
  /// स्थान मात्र लेख्ने हल्का संस्करण हो, दुवै एकैसाथ चले पनि हानि छैन)।
  ///
  /// Android मा persistent foreground-service notification सहित चल्छ —
  /// worker ले app minimize गरे वा screen लक गरे पनि employer ले live
  /// tracking हेर्न सकून् भनेर (नत्र Android ले केही समयमै background
  /// isolate/location stream रोकिदिन्थ्यो, जुन "ट्र्याकिङ अड्किएको/frozen"
  /// गुनासोको एउटा साँचो कारण थियो)। Web/अन्य platform मा साधारण
  /// foreground-मात्र stream (Android-specific settings त्यहाँ लागू हुँदैन)।
  void _startWorkerLocationTracking(String jobId) {
    if (_workerTrackingForJobId == jobId && _workerPosSub != null) return;
    _workerPosSub?.cancel();
    _workerTrackingForJobId = jobId;
    unawaited(_ensureBackgroundLocationPermission());

    final LocationSettings settings = (!kIsWeb && Platform.isAndroid)
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: S.locationTrackingNotifTitle,
              notificationText: S.locationTrackingNotifBody,
              notificationChannelName: 'सहयात्री Location',
              // app कै आफ्नै launcher icon — कुनै तेस्रो-पक्षको branding/
              // default Android icon होइन (white-label)।
              notificationIcon:
                  const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
              color: AppColors.igViolet,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
          );

    _workerPosSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((p) async {
      try {
        await FirebaseFirestore.instance
            .collection('serviceRequests')
            .doc(jobId)
            .update({
          'workerLat': p.latitude,
          'workerLng': p.longitude,
          'workerLocationUpdatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }, onError: (_) {});
  }

  void _stopWorkerLocationTracking() {
    _workerPosSub?.cancel();
    _workerPosSub = null;
    _workerTrackingForJobId = null;
  }

  // role एकपटक मात्र read — पहिले local cache बाट instant, अनि background sync।
  // यसले हरेक bottom-nav tap मा full-screen spinner देखिने बग हटाउँछ।
  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    String role = 'employer';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid ?? '__none__')
          .get();
      role = (snap.data()?['role'] ?? 'employer').toString();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    _startNegotiationWatcher(uid, role == 'worker');
    _startActiveJobWatcher(uid, role == 'worker');
    if (uid != null) {
      _startHotelBookingCallWatchers(uid);
      _startSalonChatCallWatcher(uid);
    }
  }

  /// employer/worker दुवैका लागि — आफ्नो कुनै काम accepted/confirmed/
  /// in_progress मा पुगेबित्तिकै (आफैंले accept गरेर होस् वा अर्को पक्षले
  /// counter-offer approve गरेर), हामी जुनसुकै tab/screen मा भए पनि सिधै
  /// त्यसको route-map screen खोल्ने। बटन/banner थिच्नु पर्दैन।
  void _startActiveJobWatcher(String? uid, bool isWorker) {
    if (uid == null) return;
    final field = isWorker ? 'workerUid' : 'employerUid';
    // status पनि सर्भर-साइडमै (whereIn) फिल्टर गर्ने — पहिले client-side
    // मात्र फिल्टर गर्थ्यो, जसले गर्दा यो प्रत्येक user को *सम्पूर्ण*
    // serviceRequests history (अब completed job हरू सधैँका लागि रहने
    // भएकोले महिनौं-वर्षौंमा ठूलो हुँदै जाने) हरेकपटक डाउनलोड गर्थ्यो —
    // जबकि यो watcher लाई active (accepted/confirmed/in_progress) बाहेक
    // अरू कुनै doc कहिल्यै चाहिँदैन। धेरै हजार प्रयोगकर्ता एकैचोटि
    // signed-in हुँदा (यो watcher app खुल्नेबित्तिकै सधैँ चलिरहन्छ) यही
    // नै सबैभन्दा ठूलो बचत हो।
    _activeJobSub = FirebaseFirestore.instance
        .collection('serviceRequests')
        .where(field, isEqualTo: uid)
        .where('status', whereIn: _activeJobStatuses.toList())
        .snapshots()
        .listen((snap) {
      final activeDocs = snap.docs
          .where((d) => _activeJobStatuses.contains(d.data()['status']))
          .toList()
        ..sort((a, b) {
          final ta = a.data()['acceptedAt'];
          final tb = b.data()['acceptedAt'];
          if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
          return 0;
        });
      final activeIds = activeDocs.map((d) => d.id).toSet();
      final isFirst = _firstActiveJobSnapshot;
      _firstActiveJobSnapshot = false;

      if (activeDocs.isEmpty) {
        // Cross-Screen Cancellation Notice — अर्को पक्षले (employer/worker
        // जो भए पनि) cancel गर्दा `deleteCancelledBooking()` ले सिधै doc
        // नै मेटाइदिन्छ (कुनै 'cancelled' status होइन) — यो watcher ले
        // त्यही क्षणमा नै `activeDocs.isEmpty` देख्छ र माथिकै pinned
        // bar/badge/location-tracking सबै सफा गर्छ, तर पहिले यहाँ कुनै
        // देखिने संकेत (toast/dialog) थिएन — `job_route_screen.dart` मै
        // भएको बेला मात्र त्यहाँको आफ्नै dialog देखिन्थ्यो। अर्को पक्ष
        // Driver/Earnings dashboard, Home, वा जुनसुकै अर्को screen मा भए
        // active-job indicator चुपचाप हराउँथ्यो — "मेरो तर्फ cancel
        // भएकै देखिएन" भन्ने गुनासोको साँचो जड। अब यहीं (app-shell तहमै,
        // कुन screen मा छु भन्दा स्वतन्त्र) एकपटक मात्र doc साँच्चै मेटिएको
        // हो (cancel) वा होइन (जस्तै स्वाभाविक रूपमा 'completed' मा गएर
        // active-set बाट बाहिरिएको) जाँचेर, मेटिएकोमा मात्र global
        // SnackBar।
        final previouslyActive = Set<String>.from(_knownActiveJobIds);
        _knownActiveJobIds.clear();
        _autoOpenedForJobId = null;
        _activeRideCallIds = const {};
        _recomputeCallWatchers();
        if (isWorker) _stopWorkerLocationTracking();
        if (mounted && (_pinnedActiveJobId != null || _activeJobCount != 0)) {
          setState(() {
            _pinnedActiveJobId = null;
            _pinnedActiveJobData = null;
            _activeJobCount = 0;
          });
        }
        if (previouslyActive.isNotEmpty) {
          unawaited(_notifyIfCancelledElsewhere(previouslyActive, isWorker));
        }
        return;
      }
      _activeRideCallIds = activeIds;
      _recomputeCallWatchers();

      // pinned ActiveJobBar + Bookings tab badge — सधैँ सबैभन्दा पछिल्लो
      // सक्रिय काम, cold start मा र नयाँ थपिँदा दुवैमा (माथि नै sort भइसकेको)।
      //
      // यो listener ले उही active job doc मा भएको JUनसुकै field-level
      // update (जस्तै worker को हरेक ~25m GPS movement मा लेखिने
      // workerLat/workerLng) मा पनि फेरि snapshot पाउँछ — तर pinned id/
      // गन्ती/role साँच्चै फेरिएको बेला मात्र setState गर्ने, नत्र
      // (position-मात्रको update मा) यो widget-tree (BottomBar/badge)
      // अनावश्यक रूपमा फेरि नरिबिल्ड होस्।
      final samePin = _pinnedActiveJobId == activeDocs.first.id &&
          _activeJobCount == activeDocs.length &&
          _pinnedIsWorker == isWorker;
      if (mounted && !samePin) {
        setState(() {
          _pinnedActiveJobId = activeDocs.first.id;
          _pinnedActiveJobData = activeDocs.first.data();
          _activeJobCount = activeDocs.length;
          _pinnedIsWorker = isWorker;
        });
      } else {
        // pin अपरिवर्तित — तर cached data (badge/sheet ले पढ्ने) चाहिँ
        // ताजै राख्ने, rebuild नगराई।
        _pinnedActiveJobData = activeDocs.first.data();
      }
      if (isWorker) _startWorkerLocationTracking(activeDocs.first.id);

      final newlyActive = activeIds.difference(_knownActiveJobIds);
      _knownActiveJobIds
        ..clear()
        ..addAll(activeIds);

      // cold start (app भर्खर खोलेको, पहिलो snapshot) मा सबैभन्दा पछिल्लो
      // सक्रिय काम; त्यसपछि भने भर्खरै सक्रिय भएको (नयाँ) मात्र — GPS/अन्य
      // field-मात्र अपडेटमा बारम्बार नखुलियोस्।
      final target = isFirst
          ? activeDocs.first
          : (newlyActive.isEmpty
              ? null
              : activeDocs.firstWhere((d) => newlyActive.contains(d.id)));
      if (target == null) return;
      if (_autoOpenedForJobId == target.id) return;
      // उपयोगकर्ता पहिल्यै त्यही काम को route screen मा हुँदा (जस्तै
      // RequestTrackingScreen बाटै counter-offer accept गर्दा) दोहोरिएर
      // अर्को उही screen नखोल्ने — त्यो आफैं reactively अपडेट हुन्छ।
      if (visibleRouteScreenRequestId == target.id) {
        _autoOpenedForJobId = target.id;
        return;
      }
      _autoOpenedForJobId = target.id;

      if (!mounted) return;
      final data = target.data();
      if (isWorker) {
        openJobRoute(context, target.id, data);
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RequestTrackingScreen(requestId: target.id),
        ));
      }
    });
  }

  /// माथिको watcher ले active-set बाट बाहिरिएको हरेक doc एक-एक गरेर साँच्चै
  /// मेटिएको (cancel) हो कि अरू कुनै सामान्य कारण (जस्तै 'completed' मा
  /// पुगेर status नै active-set बाहिर गएको) हो भनेर एकपटक (one-shot `.get()`,
  /// कुनै थप listener होइन) जाँच्छ — मेटिएकोमा मात्र, जुनसुकै screen/tab मा
  /// भए पनि, एउटै प्रस्ट SnackBar।
  Future<void> _notifyIfCancelledElsewhere(
      Set<String> previouslyActiveIds, bool isWorker) async {
    for (final id in previouslyActiveIds) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('serviceRequests')
            .doc(id)
            .get();
        if (!snap.exists) {
          if (!mounted) return;
          // Role-Aware Confirmation — worker-तर्फ ठ्याक्कै "cancelled by
          // the employer" भन्ने स्पष्ट शब्द (directive कै अनुरोध अनुसार,
          // `S.taskCancelledByEmployerBody` — job_route_screen.dart कै
          // भित्रैको dialog ले पनि उही शब्द प्रयोग गर्छ, यहाँ केवल त्यही
          // screen मा नभई अन्त कतै भए पनि उस्तै शब्द देखियोस् भनेर)।
          // employer-तर्फ (worker ले cancel गर्दा) भने सोही-अनुरूप साँचो
          // "cancelled by the worker" भन्ने छुट्टै string अहिलेसम्म
          // अवस्थित छैन — त्यो दिशाको लागि request_tracking_screen.dart
          // कै उस्तै प्रमाणित generic `S.requestCancelled` मा नै।
          // cancel गर्नेले छानेको कारण (भए) सँगै देखाउने।
          final reason = await takeCancelNoticeReason(id);
          if (!mounted) return;
          final base =
              isWorker ? S.taskCancelledByEmployerBody : S.requestCancelled;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(reason == null
                  ? base
                  : '$base\n${S.cancelReasonLabel}: $reason')));
          return; // एकैचोटि धेरै job सकिए पनि एउटा सूचना नै पर्याप्त।
        }
      } catch (_) {
        // best-effort — Firestore अफलाइन/अस्थायी त्रुटि भए पनि चुपचाप।
      }
    }
  }

  /// Hotel Booking Call-Ring Fix — माथिको ride/job watcher कै उस्तै
  /// tab-independent shell-level pattern, `hotel_bookings` का लागि।
  /// Guest-तर्फ (आफैंले बुक गरेको) र partner-तर्फ (आफूले managed गर्ने
  /// होटलको), दुवै एकैचोटि (एउटै user guest र partner दुवै हुन सक्ने
  /// भएकोले) सुरु गरिन्छ। Communication Never Locks — यहाँ *कुनै* status
  /// filter छैन (पहिले `kActiveHotelBookingStatuses` मात्र थियो, completed/
  /// cancelled भइसकेको booking को कल कहिल्यै सुनिँदैनथ्यो) — booking जे
  /// स्थितिमा भए पनि त्यसको `calls/{bookingId}` सधैं सुनिन्छ। कुनै
  /// auto-navigate छैन (ride/job watcher भन्दा फरक) — केवल
  /// `_recomputeCallWatchers` लाई खुवाउने मात्र हो।
  void _startHotelBookingCallWatchers(String uid) {
    _hotelGuestCallSub = FirebaseFirestore.instance
        .collection('hotel_bookings')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      _hotelGuestCallIds = snap.docs.map((d) => d.id).toSet();
      _recomputeCallWatchers();
    });

    // "कुन होटल मैले managed गर्छु" (`users/{uid}.partnerHotelIds`) एकपटक
    // मात्र पढ्ने (negotiation/active-job watcher हरू कै उस्तै "role
    // एकपटक मात्र read" pattern)।
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((u) {
      if (!mounted) return;
      final hotelIds = List<String>.from(
          u.data()?['partnerHotelIds'] as List? ?? const []);
      if (hotelIds.isEmpty) return;
      for (final hotelId in hotelIds.take(10)) {
        _hotelPartnerCallSubs.add(FirebaseFirestore.instance
            .collection('hotel_bookings')
            .where('hotelId', isEqualTo: hotelId)
            .snapshots()
            .listen((snap) {
          _hotelPartnerCallIdsByHotel[hotelId] =
              snap.docs.map((d) => d.id).toSet();
          _hotelPartnerCallIds = {
            for (final ids in _hotelPartnerCallIdsByHotel.values) ...ids,
          };
          _recomputeCallWatchers();
        }, onError: (_) {}));
      }
    }).catchError((_) {});
  }

  /// employer/worker दुवैका लागि उही tab-independent listener — worker लाई
  /// employer ले counter गर्दा, employer लाई worker ले counter गर्दा, दुवैतिर
  /// (कुनै round-सीमा बिना) तुरुन्तै sound + banner। App खुला भएसम्म काम
  /// गर्छ — यो साँचो push notification (FCM, app बन्द हुँदा पनि) होइन, किनभने
  /// यो project मा हाल push-notification backend छैन।
  void _startNegotiationWatcher(String? uid, bool isWorker) {
    if (uid == null) return;
    final ownerField = isWorker ? 'workerUid' : 'employerUid';
    final waitingStatus =
        isWorker ? 'pending_worker_counter' : 'pending_employer_approval';
    _negotiationSub = FirebaseFirestore.instance
        .collection('serviceRequests')
        .where(ownerField, isEqualTo: uid)
        // केवल "मेरो जवाफ पर्खिरहेको" स्थिति — पहिले यो user को सबै इतिहास
        // (हरेक पूरा/रद्द काम) सुनिन्थ्यो, जुन समयसँगै अनन्त बढ्छ।
        .where('status', isEqualTo: waitingStatus)
        .snapshots()
        .listen((snap) {
      final currentlyWaiting = snap.docs
          .where((d) => d.data()['status'] == waitingStatus)
          .map((d) => d.id)
          .toSet();

      if (!_firstNegotiationSnapshot) {
        final newlyWaiting = currentlyWaiting.difference(_waitingOnMeIds);
        if (newlyWaiting.isNotEmpty) {
          playCounterOfferAlert();
          if (mounted) {
            final latest =
                snap.docs.firstWhere((d) => newlyWaiting.contains(d.id));
            final price = isWorker
                ? (latest.data()['employerCounterPrice'] as num?)
                : (latest.data()['workerCounterPrice'] as num?);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(price != null
                    ? S.newCounterOfferNotifBody(price)
                    : S.newCounterOfferNotifTitle),
              ),
            );
          }
        }
      }
      _waitingOnMeIds
        ..clear()
        ..addAll(currentlyWaiting);
      _firstNegotiationSnapshot = false;
    });
  }

  /// pinned ActiveJobBar थिच्दा वा auto-nav ले जस्तै — कामअनुसार सही route/
  /// tracking screen खोल्ने। पहिल्यै त्यही screen मा भए दोहोरिएर नखोल्ने।
  void _openPinnedJob() {
    final id = _pinnedActiveJobId;
    final data = _pinnedActiveJobData;
    if (id == null || data == null) return;
    if (visibleRouteScreenRequestId == id) return;
    if (_pinnedIsWorker) {
      openJobRoute(context, id, data);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RequestTrackingScreen(requestId: id),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Home tab जहिले पनि मुख्य Super-App Home Screen (3x2 neon grid) नै —
    // role जे भए पनि (worker/driver/hotel partner लगायत)। Job Feed/My
    // Requests जस्ता worker-विशेष dashboard अब यहाँ मुख्य tab bar मा होइन,
    // बरु profile_screen.dart कै "Dashboard" बटनबाट मात्र पुगिने (push
    // गरिएको छुट्टै screen) — साझा Home experience सबैलाई उस्तै रहोस्
    // भनेर।
    // Localization Live-Toggle Fix — यहाँ पहिले `const screens = [...]`
    // थियो। माथिको `MainContainer()` आफैं (app.dart) बाट `const` हटाइए
    // पनि, यो भित्री सूची स्वयं const भएकोले हरेक तत्व (HomeScreen(),
    // ProfileScreen() आदि) पनि Dart-मा छुट्टै canonicalize हुन्थ्यो —
    // `MainContainer.build()` फेरि चले पनि, `IndexedStack`-ले उही पुरानो
    // (identical) child-list भेट्दा हरेक ट्याबको भित्री content कहिल्यै
    // rebuild नगर्ने (bottom-nav label त अपडेट हुने तर Home/Profile ट्याब
    // भित्रकै banner/tile/row जस्ता कुरा पुरानै भाषामा अडकिरहने) बग यहीँ
    // थियो। `const` हटाउँदा पनि IndexedStack-ले tab-state (same runtimeType
    // + null key) अझै जोगाइरहन्छ — केवल build() फेरि चल्छ, re-init/spinner
    // होइन।
    final screens = [
      HomeScreen(), // ignore: prefer_const_constructors
      BookingsScreen(), // ignore: prefer_const_constructors
      WatchlistScreen(), // ignore: prefer_const_constructors
      MessagesScreen(), // ignore: prefer_const_constructors
      ProfileScreen(), // ignore: prefer_const_constructors
    ];

    final items = [
      _NavItem(Icons.home_rounded, S.navHome),
      _NavItem(Icons.assignment_rounded, S.navBookings,
          badgeCount: _activeJobCount),
      _NavItem(Icons.bookmark_rounded, S.navWatchlist),
      _NavItem(Icons.chat_bubble_rounded, S.navMessages),
      _NavItem(Icons.person_rounded, S.navProfile),
    ];

    // IndexedStack ले सबै tab जीवितै राख्छ — switch गर्दा re-init/spinner छैन।
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // हरेक tab मा देखिने pinned bar — accepted/confirmed/in_progress
          // भएको बित्तिकै Firestore बाटै आफैं देखिन्छ/हराउँछ, कुनै tap चाहिँदैन।
          if (_pinnedActiveJobId != null)
            ActiveJobBar(
              key: ValueKey(_pinnedActiveJobId),
              requestId: _pinnedActiveJobId!,
              isWorker: _pinnedIsWorker,
              onOpenMap: _openPinnedJob,
            ),
          _BottomBar(
            items: items,
            currentIndex: _currentIndex,
            onTap: (i) {
              if (i != _currentIndex) setState(() => _currentIndex = i);
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int badgeCount;
  const _NavItem(this.icon, this.label, {this.badgeCount = 0});
}

class _BottomBar extends StatelessWidget {
  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        child: GlassPanel2(
          radius: 26,
          child: SizedBox(
            height: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < items.length; i++)
                  _NavTab(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const muted = AppColors.kmMuted2;
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.86,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.symmetric(horizontal: selected ? 16 : 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.kmCtaGradient : null,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 240),
                  tween: ColorTween(end: selected ? AppColors.kmInk : muted),
                  builder: (_, c, __) => Icon(item.icon, size: 23, color: c),
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.kmPink,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color:
                                selected ? AppColors.kmInk : Colors.transparent,
                            width: 1.4),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 15, minHeight: 15),
                      child: Text(
                        '${item.badgeCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            height: 1.15),
                      ),
                    ),
                  ),
              ],
            ),
            // selected हुँदा मात्र label — pill width animate हुन्छ
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.kmInk,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
