// screens/job_feed_screen.dart
// कामदारको "कामको सूची" (live job radar) — नजिकका खुला स्थानीय कामहरू।
//  • दूरी filter (सबै / ५ / १० / १५ किमी) — कामदारको एकपटकको GPS fix अनुसार
//  • सीप filter (मेरो सीप / सबै / निश्चित पेसा)
// हरेक card: काम के हो, कहिले (मिति + समय), कहाँ (स्थिर ठेगाना), ग्राहकको बजेट,
// र कति टाढा। कुनै route/movement tracking छैन।
import 'dart:async';
import '../utils/price_input.dart';
import '../utils/request_timeout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_exit_bar.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/job_alert_sound.dart';
import '../widgets/worker_menu_drawer.dart';
import 'job_actions.dart';
import 'job_map_screen.dart';
import 'nearby_common.dart';
import 'notification_screen.dart';
import 'wallet_screen.dart';

class JobFeedScreen extends StatefulWidget {
  const JobFeedScreen({super.key});

  @override
  State<JobFeedScreen> createState() => _JobFeedScreenState();
}

class _JobFeedScreenState extends State<JobFeedScreen> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  double? _lat;
  double? _lng;
  // GPS असफल/अस्वीकृत भए काठमाडौं केन्द्रमा fallback गरिन्छ (nearby_map_screen.dart
  // कै pattern) — नत्र फिल्टर/सूची पूरै खाली देखिन्छ। यो true भएसम्म दूरी "अनुमानित"।
  bool _approxLocation = false;

  int? _radiusKm; // null = सबै
  String _tradeFilter = '__mine__'; // '__mine__' | '__all__' | 'Plumber' ...

  // Driver Control Dashboard कै "Ride Preferences" बाट सेट हुने — users/{uid}
  // मा नै बचत हुन्छ (driverSearchRadiusKm/driverVehicleFilter/driverOnBreak)।
  // पहिलो snapshot मा मात्र radius/trade प्रारम्भिक मान यहीँबाट लिने
  // (त्यसपछि chip tap ले session भरि override गर्न सक्ने — Firestore बाट
  // फेरि नफर्किने)।
  bool _prefsApplied = false;
  bool _onBreak = false;

  // नयाँ काम आउनेबित्तिकै ting-ting बजाउन पहिले देखिसकेका job id हरू ट्र्याक।
  final Set<String> _seenJobIds = {};
  bool _firstJobSnapshot = true;
  // Direct Offer स्ट्रिमकै आफ्नै छुट्टै seen-tracking — broadcast स्ट्रिमसँग
  // कुनै id कहिल्यै ठोक्किँदैन भए पनि, आआफ्नो "पहिलोपटक लोड" अवस्था छुट्टै
  // राख्न (नत्र एउटा स्ट्रिमको पहिलो snapshot अर्कोको भन्दा अघि/पछि आउँदा
  // गलत "नयाँ" ठान्न सक्छ)।
  final Set<String> _seenDirectOfferIds = {};
  bool _firstDirectOfferSnapshot = true;

  // '__mine__' trade filter resolve गर्न — overlay कार्ड छान्दा पनि चाहिने।
  String _myService = '';
  // Test Mode — debug-only, हेर्नुहोस् AppBar::actions (माथि) को टिप्पणी।
  bool _testMode = false;
  // Single Active Job Restriction — हाल कुनै अर्को साँच्चै-अझै-सक्रिय काम
  // (accepted/confirmed/in_progress) भए त्यसको requestId, नत्र खाली।
  String _myActiveJobId = '';
  // Worker Cancellation Penalty — बारम्बार आफैं cancel गर्ने worker ले
  // क्रमशः कम नयाँ job देख्ने (job_actions.dart::shouldShowJobToWorker)।
  int _myCancelCount = 0;
  // Wallet Commission Debt Gate — widgets/complete_job_sheet.dart::
  // _confirm()/admin_settlement_screen.dart::_markSettled() ले नै लेख्छन्।
  // field नै नभए (पुरानो doc) eligible मानिन्छ — activeJobId कै उस्तै idiom।
  bool _myEligible = true;

  // Multi-Request Floating Stack — पहिले यहाँ एकपटकमा एउटै मात्र ("सबैभन्दा
  // नजिकको") अनुरोध queue बाट क्रमैसँग देखिन्थ्यो, बाँकी तल bottom sheet को
  // अलग्गै list मा लुकेका हुन्थे — scroll नगरी भेट्टिँदैनथे। प्रयोगकर्ताले
  // स्पष्ट रूपमा यो नै गुनासो गरे (screenshot सहित, पटक-पटक): Decline/Offer
  // price/Accept भएको कार्ड list भित्र "थिचिएको" देखिन्छ, एकैचोटि धेरै
  // अनुरोध आए सबै top मै floating देखिनुपर्छ, कुनै छुट्नु हुँदैन। अब
  // eligible भएका सबै अनुरोध यही एउटा (scrollable) list मा, live map
  // माथि नै floating — bottom sheet मा छुट्टै job-card list छैन।
  List<({String id, Map<String, dynamic> data})> _incomingList = const [];
  // "X" ले बन्द गरेका (कारबाही नगरी) job id हरू — यो session भर फेरि नदेखियोस्।
  final Set<String> _skippedIds = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastJobDocs = const [];
  // Direct Offer (worker_list_screen.dart/worker_profile_screen.dart बाट
  // employer ले सिधै यही worker लाई पठाएको, status: 'pending_worker') —
  // पहिले यो floating overlay मा कहिल्यै देखिँदैनथ्यो (केवल `broadcasting`
  // मात्र सुनिन्थ्यो), त्यसैले Plumber/Electrician जस्ता trade (जो सधैँ
  // direct-offer बाटोबाट मात्र अनुरोध पाउँछन्, Bike/Car जस्तो broadcast
  // कहिल्यै होइन) ले यो "Open jobs near you" dashboard मा कुनै live popup
  // कहिल्यै नदेख्ने गुनासोको साँचो जड यही थियो। अब दुवै स्रोत एउटै
  // floating list मा मर्ज हुन्छन्।
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastDirectOfferDocs =
      const [];

  // Stream एकपटक मात्र बनाइन्छ — filter chip tap (setState) मा re-subscribe
  // नभएर spinner flash नहोस्; trade/radius filter client-side हुन्छ।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? '__none__')
          .snapshots();
  /// खुला अनुरोधको stream। ROOT CAUSE (नापेर पुष्टि, फोनको लग): पहिले यहाँ
  /// `orderBy` बिना `.limit(50)` थियो — Firestore ले document-id क्रममा
  /// पहिलो ५० मात्र दिन्थ्यो, जबकि ९४ खुला (धेरैजसो पुराना/अनाथ) अनुरोध थिए।
  /// नयाँ अनुरोधको random id पछाडि पर्‍यो भने ५० मा नै नपरी driver ले
  /// कहिल्यै नदेख्ने (पहिलो कहिलेकाहीँ देखिने, दोस्रो नदेखिने — id भाग्य)।
  ///
  /// अब: नयाँ-पहिले क्रम (`createdAt` घट्दो) + पछिल्लो ३० मिनेट + limit —
  /// नयाँ अनुरोध सधैँ पहिलो ५० मै पर्छ, पुराना जति भए पनि। यो query लाई
  /// composite index (`status`, `createdAt`) चाहिन्छ (firestore.indexes.json);
  /// index अझै बनेको छैन भने (`failed-precondition`) आफैं पुरानो (limit-रहित)
  /// query मा झर्छ — कहिल्यै खाली नरहने।
  bool _jobsIndexed = true;

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildJobsStream() {
    var q = FirebaseFirestore.instance
        .collection('serviceRequests')
        .where('status', isEqualTo: 'broadcasting');
    if (_jobsIndexed) {
      final cutoff = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 30)));
      return q
          .where('createdAt', isGreaterThan: cutoff)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();
    }
    return q.snapshots();
  }
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _directOffersStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('workerUid', isEqualTo: _uid ?? '__none__')
          .where('status', isEqualTo: 'pending_worker')
          .snapshots();

  // COLD-START AUTH-TOKEN RACE — cold app start मा persisted session
  // restore हुँदा `FirebaseAuth.instance.currentUser` client-side मा
  // चाँडै populate हुन्छ, तर Firestore SDK कै channel मा त्यो auth token
  // साँच्चै attach हुन अलिकति (सामान्यतया १ सेकेन्डभित्रै) ढिलो हुन सक्छ।
  // त्यही छोटो झ्यालमा यो screen को पहिलो subscribe भए, `users/{uid}`
  // (rules ले `isSignedIn()` मात्र मागे पनि) र `serviceRequests` दुवै
  // `permission-denied` मा टुट्छन् — live device मा नै पक्रिएको, user
  // साँच्चै signed-in हुँदाहुँदै पनि। एकपटक मात्र छोटो delay पछि फेरि
  // subscribe गर्दा (token हुनेबित्तिकै) ठीक हुन्छ — असीमित retry होइन,
  // अरू कुनै साँचो permission त्रुटि (जस्तै rules नै साँच्चै रोकेको) लाई
  // लुकाउँदैन, केवल यही एकपटकको cold-start race लाई।
  bool _directOffersRetried = false;
  bool _userRetried = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _subscribeJobs();
    if (_uid != null) {
      _subscribeDirectOffers();
      _subscribeUser();
    }
  }

  // Firestore listener हरू — screen बन्द हुँदा cancel नगरे सर्भर/फोन दुवैमा
  // बाँकी रहन्थे (leak); अब dispose मा बन्द।
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _jobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  void _subscribeJobs() {
    _jobsSub?.cancel();
    _jobsSub = _buildJobsStream().listen(_onJobsSnapshot, onError: (e) {
      debugPrint('JobFeedScreen jobsStream error: $e');
      // index अझै बनेको छैन — limit-रहित पुरानो query मा झरेर तुरुन्तै फेरि सुन्ने।
      if (_jobsIndexed && e is FirebaseException && e.code == 'failed-precondition') {
        _jobsIndexed = false;
        if (mounted) _subscribeJobs();
        return;
      }
      // कुनै पनि त्रुटिमा (permission-denied मात्र होइन) stream चुपचाप मर्न नदिने
      // — बढ्दो पर्खाइसहित फेरि सुन्ने, ताकि नयाँ अनुरोध कहिल्यै नछुटोस्।
      _jobsRetries++;
      final wait = Duration(seconds: (_jobsRetries * 2).clamp(2, 20));
      Future.delayed(wait, () {
        if (mounted) _subscribeJobs();
      });
    }, onDone: () {
      if (mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _subscribeJobs();
        });
      }
    }, cancelOnError: true);
  }

  int _jobsRetries = 0;

  void _subscribeDirectOffers() {
    _offersSub?.cancel();
    _offersSub = _directOffersStream.listen(_onDirectOffersSnapshot, onError: (e) {
      debugPrint('JobFeedScreen directOffersStream error: $e');
      if (!_directOffersRetried && _isPermissionDenied(e)) {
        _directOffersRetried = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _subscribeDirectOffers();
        });
      }
    });
  }

  bool _isPermissionDenied(Object e) =>
      e is FirebaseException && e.code == 'permission-denied';

  void _subscribeUser() {
    _userSub?.cancel();
    _userSub = _userStream.listen((snap) {
      final d = snap.data() ?? {};
      final s = (d['service'] ?? d['serviceType'] ?? '').toString();
      final activeId = (d['activeJobId'] ?? '').toString();
      final cancelCount = (d['workerCancelCount'] as num?) ?? 0;
      if (mounted) {
        setState(() {
          _myService = s;
          _myActiveJobId = activeId;
          _myCancelCount = cancelCount.toInt();
          _myEligible = (d['isEligibleForJobs'] as bool?) ?? true;
          _onBreak = d['driverOnBreak'] == true;
          if (!_prefsApplied) {
            _prefsApplied = true;
            final savedRadius = d['driverSearchRadiusKm'];
            if (savedRadius is num) _radiusKm = savedRadius.toInt();
            final savedTrade = (d['driverVehicleFilter'] ?? '').toString();
            if (savedTrade.isNotEmpty) _tradeFilter = savedTrade;
          }
        });
        _recomputeIncoming();
      }
    }, onError: (e) {
      debugPrint('JobFeedScreen userStream error: $e');
      if (!_userRetried && _isPermissionDenied(e)) {
        _userRetried = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _subscribeUser();
        });
      }
    });
  }

  /// नयाँ broadcasting job आएमा sound बजाउने, अनि floating stack मा
  /// देखिनुपर्ने eligible अनुरोधहरूको पूरै सूची पुनः-गणना — नयाँ होस् वा
  /// पहिल्यैदेखि broadcasting भइरहेको (पहिलो load मा नै भए पनि), दुवैलाई।
  /// अहिलेको trade filter (`_tradeFilter`) अनुसार यो service मिल्छ कि —
  /// `_pickEligibleCandidates` भित्रैको उही `wantTrade` तर्क, यहाँ साझा
  /// गरिएको (तल `_onJobsSnapshot` ले पनि उही जाँच प्रयोग गरोस् भनेर)।
  bool _matchesTradeFilter(String svc) {
    final wantTrade = _tradeFilter == '__mine__'
        ? _myService
        : (_tradeFilter == '__all__' ? '' : _tradeFilter);
    return wantTrade.isEmpty || svc.toLowerCase() == wantTrade.toLowerCase();
  }

  void _onJobsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    if (kDebugMode) {
      for (final ch in snap.docChanges) {
        final t = ch.doc.data()?['createdAt'];
        debugPrint('FEED_SNAPSHOT ${ch.type.name} ${ch.doc.id} '
            'status=${ch.doc.data()?['status']} createdAt=$t '
            'fromCache=${snap.metadata.isFromCache}');
      }
    }
    _jobsRetries = 0;
    _lastJobDocs = snap.docs;
    final ids = snap.docs.map((d) => d.id).toSet();
    if (!_firstJobSnapshot) {
      // Break Mode Sound Mismatch — यहाँ पहिले `_onBreak` जाँचिँदैनथ्यो,
      // तर `_pickEligibleCandidates` (floating card देखाउने) ले जाँच्थ्यो
      // — break मोडमा हुँदा sound बज्ने तर कुनै कार्ड नै नदेखिने (sound-
      // only, no visible box) गुनासोको सम्भावित जड यही mismatch थियो।
      //
      // Cross-Trade/Vehicle Sound Leak — उस्तै जड, फरक field: यहाँ trade/
      // service मिलान कहिल्यै जाँचिँदैनथ्यो — Bike driver (डिफल्ट filter
      // `__mine__` मा समेत) ले Car राइड/Plumber/Mechanic जस्तो आफ्नो सीपसँग
      // सर्वथा नमिल्ने जुनसुकै नयाँ broadcasting अनुरोधमा पनि sound-अलर्ट
      // पाउँथ्यो, जबकि कार्ड-सूची (`_pickEligibleCandidates`) भने पहिल्यैदेखि
      // सही फिल्टर गर्थ्यो — ठ्याक्कै "sound मात्र, देखिने कार्ड केही छैन"
      // गुनासोकै अर्को वर्ग। अब sound-योग्यता पनि उही `_matchesTradeFilter`
      // (कार्ड-सूचीसँग साझा) बाट गुज्रिन्छ।
      final newIds = ids.difference(_seenJobIds);
      final hasNewRelevant = !_onBreak &&
          snap.docs.any((d) {
            if (!newIds.contains(d.id)) return false;
            final data = d.data();
            if ((data['employerUid'] ?? '') == _uid &&
                !_isVisibleSelfTestRequest(data)) {
              return false;
            }
            final rejected = (data['rejectedBy'] as List?) ?? const [];
            if (rejected.contains(_uid)) return false;
            if (!_matchesTradeFilter((data['service'] ?? '').toString())) {
              return false;
            }
            return shouldShowJobToWorker(d.id, _myCancelCount);
          });
      if (hasNewRelevant) playNewJobAlert();
    }
    _seenJobIds
      ..clear()
      ..addAll(ids);
    _firstJobSnapshot = false;
    _recomputeIncoming();
  }

  /// `_onJobsSnapshot` कै उस्तै — तर Direct Offer (worker_list_screen.dart/
  /// worker_profile_screen.dart बाट सिधै यही worker लाई addressed,
  /// `status: 'pending_worker'`) स्ट्रिमका लागि। यसैले Plumber/Electrician
  /// जस्ता trade ले पनि Driver मोडकै जस्तो तुरुन्तै floating popup + sound
  /// अलर्ट पाउँछन्।
  void _onDirectOffersSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _lastDirectOfferDocs = snap.docs;
    final ids = snap.docs.map((d) => d.id).toSet();
    if (!_firstDirectOfferSnapshot) {
      final newIds = ids.difference(_seenDirectOfferIds);
      final hasNewRelevant = !_onBreak &&
          snap.docs.any((d) {
            if (!newIds.contains(d.id)) return false;
            if ((d.data()['employerUid'] ?? '') == _uid) return false;
            return shouldShowJobToWorker(d.id, _myCancelCount);
          });
      if (hasNewRelevant) playNewJobAlert();
    }
    _seenDirectOfferIds
      ..clear()
      ..addAll(ids);
    _firstDirectOfferSnapshot = false;
    _recomputeIncoming();
  }

  /// `_incomingList` सेट गर्ने एकमात्र ठाउँ — हरेक eligible अनुरोध यहीँबाट
  /// floating stack मा देखिन्छ। कुनै पनि स्वत: (manual tap बिना) स्वीकृति
  /// यहाँबाट कहिल्यै हुँदैन — Accept/Decline/Counter Offer सधैं driver
  /// आफैंले ट्याप गर्नुपर्छ (पहिले यहीँबाट चल्ने Auto-Accept फिचरले driver
  /// कै अनुमति बिना नै पहिलो राइड आफैं स्वीकार गरिदिने गुनासोको जड थियो —
  /// त्यसैले पूर्ण रूपमा हटाइयो, कुनै toggle बाट पनि फेरि सक्रिय हुँदैन)।
  void _setIncomingList(List<({String id, Map<String, dynamic> data})> list) {
    if (!mounted) return;
    final hadIncoming = _incomingList.isNotEmpty;
    setState(() => _incomingList = list);
    // Floating Card Breathing Room — तल्लो sheet डिफल्टमा स्क्रिनको 62%
    // ओगट्छ, जसले गर्दा नयाँ अलर्ट कार्ड (माथि, floating) र sheet बीच
    // मानचित्रमा लगभग कुनै खाली ठाउँ नै बाँकी रहँदैनथ्यो — कार्ड sheet
    // भित्रै/टाँसिएको जस्तो, "Distance भित्र थिचिएको" देखिने गुनासोको
    // साँचो जड। नयाँ अलर्ट आउनेबित्तिकै sheet क्षणिक संघारेर स्पष्ट
    // floating ठाउँ दिने, अलर्ट सकिएपछि फेरि सामान्य उचाइमा फर्काउने।
    if (_sheetController.isAttached) {
      if (list.isNotEmpty && !hadIncoming) {
        _sheetController.animateTo(_sheetMin,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic);
      } else if (list.isEmpty && hadIncoming) {
        _sheetController.animateTo(_sheetInitial,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic);
      }
    }
  }

  /// Self-Ride Prevention फिल्टरले कहिल्यै नरोक्ने एउटै अपवाद — आफैंले Test
  /// Mode बाट बनाएको, स्पष्ट रूपमा चिन्ने (`isTestRequest: true`) अनुरोध।
  /// Production build मा `kDebugMode` नै false हुने भएकोले यो सँधै false
  /// compile हुन्छ (tree-shaken) — real user ले कहिल्यै यसको फाइदा लिन
  /// सक्दैनन्।
  bool _isVisibleSelfTestRequest(Map<String, dynamic> data) =>
      kDebugMode && _testMode && data['isTestRequest'] == true;

  /// Test Mode — आफ्नै खातामा एउटा simulated broadcasting अनुरोध बनाउने
  /// ताकि दोस्रो खाता/फोन बिनै नै incoming-job card, sound, र filter एक्लै
  /// device मा जाँच्न मिलोस्। Firestore rules ले अझै employerUid आफ्नै uid
  /// नै हुनुपर्छ भन्छ (अर्को कसैको नक्कल गर्न मिल्दैन), त्यसैले यो सधैँ
  /// `employerUid == _uid` नै लेख्छ — self-booking सुरक्षा सीमा अछुतो।
  Future<void> _createTestRequest() async {
    if (_uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('serviceRequests').add({
        'employerUid': _uid,
        'employerName': '[TEST] Simulated passenger',
        'employerPhone': '',
        'service': _myService.isNotEmpty ? _myService : 'bike',
        'details': 'Test Mode — simulated request, safe to ignore/skip.',
        'proposedPrice': 100,
        'status': 'broadcasting',
        'isTestRequest': true,
        'createdAt': FieldValue.serverTimestamp(),
        'employerLat': _lat ?? fallbackLat,
        'employerLng': _lng ?? fallbackLng,
      });
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Simulated test request created.')));
    } catch (e) {
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  /// अहिलेको filter (सीप/दूरी) र session भरिको skip/reject अनुसार उपलब्ध
  /// सबै उपयुक्त काम — overlay मा देखाउनुपर्ने एउटा मात्र होइन, queue
  /// व्यवस्थापनका लागि पूरै सूची चाहिन्छ।
  ///
  /// Chronological Sorting — पहिले यहाँ दूरी (नजिकबाट टाढा) अनुसार क्रमबद्ध
  /// हुन्थ्यो; अब सबैभन्दा नयाँ अनुरोध सधैँ सबैभन्दा माथि (`createdAt`
  /// descending) — टाढाको भए पनि भर्खरैको अनुरोध पुरानो (नजिकैको भए पनि)
  /// कार्ड मुनि नदबियोस् भनेर।
  List<({String id, Map<String, dynamic> data})> _pickEligibleCandidates(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // Break Mode — online रहे पनि नयाँ काम/राइड देखिनु/मिल्नु हुँदैन।
    if (_onBreak) return const [];

    final candidates =
        <({String id, Map<String, dynamic> data, Timestamp? createdAt})>[];
    // debug मात्र: कुन अनुरोध किन नदेखिएको भन्ने कारण लगमा (`FEED_FILTER`)।
    var staleCount = 0;
    void why(String id, String reason) {
      if (kDebugMode) debugPrint('FEED_FILTER $id hidden: $reason');
    }
    if (kDebugMode) {
      debugPrint('FEED_FILTER docs=${docs.length} uid=$_uid '
          'radius=$_radiusKm trade=$_tradeFilter cancelCount=$_myCancelCount '
          'onBreak=$_onBreak lat=$_lat');
    }
    for (final d in docs) {
      if (_skippedIds.contains(d.id)) {
        why(d.id, 'skipped by user');
        continue;
      }
      final data = d.data();
      // म्याद सकिएको (१० मिनेटभन्दा पुरानो) खुला अनुरोध driver लाई नदेखाउने।
      if (isRequestStale(data)) {
        staleCount++;
        continue;
      }
      // Self-Ride Prevention — आफैंले पोस्ट गरेको अनुरोध आफैं (worker मोडमा)
      // कहिल्यै देख्न/स्वीकार गर्न नपाओस् (एउटै खाता दुवै employer र worker
      // भूमिकामा हुन सक्ने भएकोले)। साँचो सुरक्षा सीमा `firestore.rules` मा
      // हो — यो client-side filter त्यही भन्दा अगाडि (UI मा नदेखाउने) मात्र।
      if ((data['employerUid'] ?? '') == _uid &&
          !_isVisibleSelfTestRequest(data)) {
        why(d.id, 'own request (same account as passenger)');
        continue;
      }
      final rejected = (data['rejectedBy'] as List?) ?? const [];
      if (rejected.contains(_uid)) {
        why(d.id, 'rejectedBy me');
        continue;
      }
      if (!shouldShowJobToWorker(d.id, _myCancelCount)) {
        why(d.id, 'cancel-penalty filter');
        continue;
      }
      final svc = (data['service'] ?? '').toString();
      if (!_matchesTradeFilter(svc)) {
        why(d.id, 'service "$svc" != my filter "$_tradeFilter" (mine=$_myService)');
        continue;
      }
      double? km;
      final jLat = (data['employerLat'] as num?)?.toDouble();
      final jLng = (data['employerLng'] as num?)?.toDouble();
      if (_lat != null && jLat != null && jLng != null) {
        km = haversineKm(_lat!, _lng!, jLat, jLng);
      }
      if (_radiusKm != null && (km == null || km > _radiusKm!)) {
        why(d.id, 'outside radius (km=$km radius=$_radiusKm)');
        continue;
      }
      candidates.add(
          (id: d.id, data: data, createdAt: data['createdAt'] as Timestamp?));
    }
    if (kDebugMode) {
      debugPrint('FEED_FILTER result: shown=${candidates.length} '
          'stale=$staleCount total=${docs.length} '
          'ids=${candidates.map((c) => c.id).toList()}');
    }
    candidates.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return [for (final c in candidates) (id: c.id, data: c.data)];
  }

  /// "X" — यो काम कारबाही नगरी लुकाउने, तुरुन्तै (Firestore पर्खनु नपरी)
  /// स्टैकबाट हटाउने।
  void _skipIncoming(String id) {
    _skippedIds.add(id);
    _setIncomingList(_incomingList.where((c) => c.id != id).toList());
  }

  /// Accept/Decline/Counter पछि — Firestore पर्खनु नपरी तुरुन्तै त्यही एक
  /// कार्ड मात्र स्टैकबाट हटाउने (बाँकी सबै उस्तैको-उस्तै देखिरहन्छन्)।
  void _clearIncomingAfterAction(String id) {
    _setIncomingList(_incomingList.where((c) => c.id != id).toList());
  }

  Future<void> _initLocation() async {
    final r = await getCurrentLocation();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _lat = r.lat;
        _lng = r.lng;
        _approxLocation = false;
      } else {
        // GPS भेटिएन — खाली सूची देखाउनुभन्दा अनुमानित (काठमाडौं केन्द्र) बाट
        // देखाउने, ताकि सीप/दूरी filter अझै प्रयोग गर्न मिलोस्।
        _lat = fallbackLat;
        _lng = fallbackLng;
        _approxLocation = true;
      }
    });
    // App खोल्दा नै worker को अन्तिम थाहा भएको स्थान प्रोफाइलमा अद्यावधिक —
    // यसैले employer को route-map (RequestTrackingScreen) मा कहिल्यै पूर्ण
    // खाली नरहोस्, worker ले accept गर्दा/online हुँदा लाइभ GPS नपाए पनि।
    if (r.ok && _uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(_uid).set({
          'lat': r.lat,
          'lng': r.lng,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// दूरी chip थिचेको बेला — अझै अनुमानित location मात्र भए यहीं फेरि सही GPS
  /// लिने प्रयास गर्छ, ताकि पहिलो पटक अनुमति नदिए पनि button ले काम गरोस्।
  Future<void> _onRadiusTap(int? v) async {
    if (v != null && _approxLocation) {
      final r = await getCurrentLocation();
      if (!mounted) return;
      if (r.ok) {
        setState(() {
          _lat = r.lat;
          _lng = r.lng;
          _approxLocation = false;
        });
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.locationDeniedShort)));
      }
    }
    if (!mounted) return;
    setState(() => _radiusKm = v);
    _recomputeIncoming();
  }

  /// फिल्टर (सीप/दूरी) बदलिएपछि वा नयाँ snapshot आएपछि — floating stack मा
  /// देखिनुपर्ने eligible अनुरोधहरूको पूरै सूची पुनः-गणना। broadcast +
  /// direct offer दुवै स्रोतका doc एकैचोटि (id ले unique, कहिल्यै नठोक्किने
  /// दुई फरक query भएकोले) एउटै पाइपलाइनबाट गुज्रिन्छन्।
  void _recomputeIncoming() {
    _setIncomingList(
        _pickEligibleCandidates([..._lastJobDocs, ..._lastDirectOfferDocs]));
  }

  /// अनलाइन/अफलाइन toggle — रोजगारदाताको नक्सामा देखिने/नदेखिने।
  Future<void> _setOnline(bool on) async {
    if (_uid == null) return;
    final db = FirebaseFirestore.instance;
    final loc = <String, dynamic>{};
    if (on) {
      final r = await getCurrentLocation();
      if (r.ok) {
        _lat = r.lat;
        _lng = r.lng;
        loc['lat'] = r.lat;
        loc['lng'] = r.lng;
        loc['locationUpdatedAt'] = FieldValue.serverTimestamp();
      }
    }
    try {
      await db
          .collection('users')
          .doc(_uid)
          .set({'isOnline': on, ...loc}, SetOptions(merge: true));
      final snap = await db
          .collection('registeredWorkers')
          .where('uid', isEqualTo: _uid)
          .get();
      for (final d in snap.docs) {
        await d.reference
            .set({'isOnline': on, ...loc}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // शुरुको sheet उचाइ (screen अनुपात) — पहिले 0.42 थियो, जसले गर्दा online
  // banner + distance/trade filter chip हरूले नै त्यो ठाउँको ठूलो हिस्सा
  // ओगट्थे, बाँकी बचेको ठाउँमा job card (Accept/Decline/Offer Price भएको
  // scrollable feed) प्रायः पूर्ण/आंशिक रूपमा नै तल लुकिरहन्थ्यो — driver
  // ले सानो drag-handle तानेको थाहै नपाई "एकैचोटि धेरै अनुरोध देखिने feed
  // नै छैन" जस्तो देखिन्थ्यो (Cancel बटन जस्तै — काम त गर्थ्यो, तर पत्ता
  // नलाग्ने)। अब सुरुमै नै (कुनै tान्नु नपरी) कम्तिमा १-२ वटा job card
  // देखिने गरी ठूलो बनाइयो।
  static const double _sheetInitial = 0.62;
  static const double _sheetMin = 0.16;
  static const double _sheetMax = 0.86;

  // नयाँ incoming अलर्ट कार्डलाई तल्लो sheet भन्दा माथि स्पष्ट खाली
  // (floating) ठाउँ दिन — `_setIncoming` हेर्नुहोस्।
  final _sheetController = DraggableScrollableController();

  @override
  void dispose() {
    _jobsSub?.cancel();
    _offersSub?.cancel();
    _userSub?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return PartnerDashboardGuard(
      child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.kmVoid,
      drawer: const WorkerMenuDrawer(),
      appBar: AppBar(
        title: Text(
            S.isRideServiceName(_myService)
                ? S.openRidesNearby
                : S.openJobsNearby,
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.kmCtaGradient),
        ),
        actions: [
          // Dashboard-Stuck Fix (v2) — DraggableScrollableSheet (तल)
          // `_sheetMax` सम्म तानिँदा पूरै स्क्रिन (र `DashboardExitBar`
          // समेत) ढाक्न सक्छ। AppBar भने सधैँ sheet भन्दा माथि नै (Scaffold
          // कै आफ्नै तह) रहने भएकोले, यहाँको "Home" बटन नै एकमात्र जहिले
          // पनि देखिने/थिच्न मिल्ने ग्यारेन्टी बाटो हो।
          const GoHomeAction(),
          // Test Mode — DEBUG BUILDS ONLY (`kDebugMode`, tree-shaken out of
          // every release build — कहिल्यै real user ले देख्दैन/प्रयोग गर्न
          // पाउँदैन)। "Simulate" ले आफ्नै खाताबाट एउटा स्पष्ट रूपमा चिन्ने
          // (`isTestRequest: true`, employerName मा "[TEST]") broadcasting
          // अनुरोध बनाउँछ, ताकि दोस्रो फोन/खाता बिनै नै incoming-job card,
          // sound alert, र skill/दूरी filter एक्लै device मा हेर्न मिलोस्।
          // यसले Self-Ride Prevention (job_actions.dart/firestore.rules)
          // लाई कहिल्यै bypass गर्दैन — त्यो सुरक्षा सीमा पूर्ण रूपमा उस्तै
          // रहन्छ, त्यसैले Accept थिच्दा अझै [S.cannotAcceptOwnRequest] नै
          // देखिन्छ (स्वयं यो सुरक्षा काम गर्छ भन्ने पुष्टि)। test मोडले
          // केवल client-side self-request भिजिबिलिटी फिल्टर मात्र शिथिल
          // पार्छ, त्यो पनि यही टगल खुला हुँदा मात्र।
          if (kDebugMode)
            IconButton(
              icon: Icon(Icons.bug_report_rounded,
                  color: _testMode ? Colors.amberAccent : null),
              tooltip: 'Test Mode${_testMode ? ' (ON)' : ''}',
              onPressed: () => setState(() => _testMode = !_testMode),
            ),
          if (kDebugMode && _testMode)
            IconButton(
              icon: const Icon(Icons.add_alert_rounded),
              tooltip: 'Simulate incoming request',
              onPressed: _createTestRequest,
            ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: S.menuNotifications,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
          ),
        ],
      ),
      // Dashboard-Stuck Fix — यो screen MainContainer को IndexedStack भित्रको
      // tab होइन (profile_screen.dart बाट छुट्टै push गरिएको), त्यसैले
      // MainContainer कै साझा bottom nav यहाँ कहिल्यै देखिँदैनथ्यो। अब
      // आफ्नै (देखिनमा उस्तै) bar — "Home" लगायत कुनै पनि ट्याप तुरुन्तै
      // MainContainer कै सही tab मा फर्काउँछ (app_globals.dart::
      // requestedMainTabIndex हेर्नुहोस्)।
      bottomNavigationBar: const DashboardExitBar(),
      body: _uid == null
          ? const Center(
              child: Text('Login गर्नुहोस्',
                  style: TextStyle(color: AppColors.kmText)))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userStream,
              builder: (context, userSnap) {
                final uData = userSnap.data?.data() ?? {};
                final myService =
                    (uData['service'] ?? uData['serviceType'] ?? '').toString();
                final online = uData['isOnline'] != false;

                return Stack(
                  children: [
                    // ── पृष्ठभूमिमा InDrive/Pathao-शैली Live Map ──
                    JobsMapLayer(
                      lat: _lat ?? fallbackLat,
                      lng: _lng ?? fallbackLng,
                      radiusKm: _radiusKm,
                      trade: _tradeFilter,
                      myService: myService,
                      myEligible:
                          (uData['isEligibleForJobs'] as bool?) ?? true,
                      bottomInset: screenH * _sheetInitial,
                      cancelCount: _myCancelCount,
                    ),
                    // ── माथि तान्न मिल्ने (draggable) सूची — online banner +
                    // दूरी/सीप filter + job card हरू, सबै एउटै scroll मा
                    // (sheet handle बाट पनि तान्न मिलोस् भनेर) ──
                    DraggableScrollableSheet(
                      controller: _sheetController,
                      initialChildSize: _sheetInitial,
                      minChildSize: _sheetMin,
                      maxChildSize: _sheetMax,
                      builder: (context, scrollController) => Container(
                        decoration: BoxDecoration(
                          color: AppColors.kmVoid2.withValues(alpha: 0.97),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadius.lg)),
                          border: Border(
                            top: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black45,
                                blurRadius: 18,
                                offset: Offset(0, -4)),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CustomScrollView(
                          controller: scrollController,
                          slivers: [
                            SliverToBoxAdapter(
                              child: Center(
                                child: Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: _FilterBar(
                                radiusKm: _radiusKm,
                                hasLocation: !_approxLocation,
                                onRadius: _onRadiusTap,
                              ),
                            ),
                            // काम-कार्डहरू अब यहाँ छैनन् — सबै eligible
                            // अनुरोध तल्लो floating stack (live map माथि)
                            // मा नै एकैचोटि देखिन्छन्, यो sheet मा दोहोरिएर
                            // scroll गर्नुपर्दैन (bottom-list-buried गुनासो)।
                            SliverToBoxAdapter(
                              child: _OnlineBanner(
                                online: online,
                                onChanged: _setOnline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ── Multi-Request Floating Stack — eligible भएका सबै
                    // अनुरोध (एकैचोटि १५-२० जनासम्म भए पनि) live map माथि
                    // नै, bottom sheet भित्र लुकेर/scroll गर्नुपर्ने होइन।
                    // धेरै भए यही स्टैक आफैं भित्रभित्रै scroll हुन्छ
                    // (तल्लो collapsed sheet — _sheetMin — मुनि नछिरोस्
                    // भनेर bottom bound)। Accept/Decline/Counter थिचेपछि
                    // त्यही एक कार्ड मात्र तुरुन्तै हराउँछ (Auto-Dismiss),
                    // बाँकी जस्ताको-तस्तै रहन्छन्। सक्रिय काम देखाउने काम
                    // MainContainer कै साझा ActiveJobBar (bottom nav माथि)
                    // ले गर्छ — यहाँ छुट्टै दोहोरो banner होइन।
                    if (_incomingList.isNotEmpty)
                      Positioned(
                        top: MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            10,
                        left: 12,
                        right: 12,
                        bottom: screenH * _sheetMin + 12,
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _incomingList.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final c = _incomingList[i];
                            return IncomingOfferOverlay(
                              key: ValueKey(c.id),
                              docId: c.id,
                              data: c.data,
                              myService: myService,
                              blockedByOtherActiveJob:
                                  _myActiveJobId.isNotEmpty &&
                                      _myActiveJobId != c.id,
                              walletBlocked: !_myEligible,
                              distanceKm: (_lat != null &&
                                      c.data['employerLat'] is num &&
                                      c.data['employerLng'] is num)
                                  ? haversineKm(
                                      _lat!,
                                      _lng!,
                                      (c.data['employerLat'] as num).toDouble(),
                                      (c.data['employerLng'] as num).toDouble())
                                  : null,
                              onSkip: () => _skipIncoming(c.id),
                              onAction: () => _clearIncomingAfterAction(c.id),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

// ── नयाँ अफर आउनेबित्तिकै — live map माथि नै floating overlay (Uber/InDrive
// "incoming ride request" शैली)। bottom sheet/list मा लुकाउनुको सट्टा AppBar
// मुनि तुरुन्तै देखिन्छ; Accept/Decline/Counter थिचेपछि आफैं हराउँछ। ─────────
class IncomingOfferOverlay extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final double? distanceKm;

  /// कामदारको दर्ता सीप — यो काम नमिले Accept/मूल्य प्रस्ताव बटन disable हुन्छ।
  final String myService;

  /// Single Active Job Restriction — true भए worker सँग हाल पहिल्यै अर्को
  /// साँच्चै सक्रिय काम छ, Accept/Offer दुवै बटन disable हुन्छन्।
  final bool blockedByOtherActiveJob;

  /// Wallet Commission Debt Gate — true भए unpaid commission debt
  /// threshold भन्दा बढी भएकोले Accept/Offer दुवै बटन disable हुन्छन्।
  final bool walletBlocked;

  /// "X" — कारबाही नगरी लुकाउने (session भर फेरि नदेखियोस्)।
  final VoidCallback onSkip;

  /// Accept/Decline/Counter पछि — Firestore बाट अर्को आफैं आउने भएकाले यहाँ
  /// overlay मात्र खाली गर्ने।
  final VoidCallback onAction;

  const IncomingOfferOverlay({
    super.key,
    required this.docId,
    required this.data,
    required this.distanceKm,
    required this.myService,
    this.blockedByOtherActiveJob = false,
    this.walletBlocked = false,
    required this.onSkip,
    required this.onAction,
  });

  // active_job_bar.dart::_openInGoogleMaps कै उस्तै ढाँचा — accept गर्नुअघि
  // नै customer को ठेगाना कता हो भनेर बाह्य Google Maps app मा हेर्न।
  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final service = (data['service'] ?? '').toString();
    final customerName = (data['employerName'] ?? '').toString();
    final desc = (data['details'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final destinationAddress = (data['destinationAddress'] ?? '').toString();
    final budget = data['proposedPrice'];
    final employerLat = (data['employerLat'] as num?)?.toDouble();
    final employerLng = (data['employerLng'] as num?)?.toDouble();
    // Direct Offer (worker_list_screen.dart/worker_profile_screen.dart बाट
    // सिधै यही worker लाई addressed) vs Broadcast (`broadcasting`, धेरै
    // worker एकैचोटि हेर्न सक्ने) — दुवैको Accept/Counter/Decline पछाडिको
    // Firestore semantics फरक भएकोले (job_actions.dart::acceptDirectOffer
    // हेर्नुहोस्), बटन action यही अनुसार छुट्याइन्छ।
    final isDirectOffer = (data['status'] ?? '').toString() == 'pending_worker';
    final skillMismatch = myService.isNotEmpty &&
        myService.toLowerCase() != service.toLowerCase();
    final blocked = skillMismatch || blockedByOtherActiveJob || walletBlocked;

    // नोट: यहाँ कुनै key दिनु पर्दैन — parent (`IncomingOfferOverlay` आफैं,
    // job id ले keyed) बदलिँदा Flutter ले यो पूरै subtree नयाँ बनाउँछ, त्यसैले
    // entrance animation आफैं फेरि चल्छ। पहिले यहाँ बाहिरी widget कै `key`
    // (outer StatelessWidget को आफ्नै key) भित्री child मा पनि दोहोर्‍याइएको
    // थियो — त्यो कुनै फाइदा नदिने मात्र होइन, बरु parent हटेर तुरुन्तै फेरि
    // (उस्तै id सहित) थपिँदा Flutter को element-lifecycle tracking
    // (`_InactiveElements`) भ्रमित हुने जोखिम राख्थ्यो — हटाइयो।
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t.clamp(0.0, 1.0)) * -24),
          child: child,
        ),
      ),
      child: GlassPanel(
        radius: AppRadius.lg,
        padding: const EdgeInsets.all(14),
        fill: AppColors.kmVoid2.withValues(alpha: 0.94),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    size: 15, color: AppColors.kmPink),
                const SizedBox(width: 5),
                Text(
                    S.isRideServiceName(myService)
                        ? S.newRideNotifTitle
                        : S.newJobNotifTitle,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.kmPink)),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 18,
                  icon:
                      const Icon(Icons.close_rounded, color: AppColors.kmMuted),
                  onPressed: onSkip,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ServicePhotoTile(
                      service: service, iconColor: AppColors.kmOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.serviceName(service),
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5)),
                      if (distanceKm != null)
                        Text(S.distanceLabel(distanceKm!),
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.kmMuted)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.kmPink.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('${S.customerBudget}: Rs. $budget',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.kmPink)),
                ),
              ],
            ),
            if (customerName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 14, color: AppColors.kmMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.kmText)),
                  ),
                ],
              ),
            ],
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.kmMuted)),
            ],
            if (address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined,
                      size: 14, color: AppColors.kmMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.kmMuted)),
                  ),
                ],
              ),
            ],
            if (destinationAddress.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_outlined,
                      size: 14, color: AppColors.kmOrange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('${S.destinationLabel}: $destinationAddress',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.kmOrange)),
                  ),
                ],
              ),
            ],
            if (skillMismatch) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 14, color: AppColors.kmRose),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(S.notAuthorizedForJobCategory,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.kmRose)),
                  ),
                ],
              ),
            ] else if (blockedByOtherActiveJob) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.lock_clock_rounded,
                      size: 14, color: AppColors.kmAmber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(S.finishCurrentJobFirst,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.kmAmber)),
                  ),
                  const TestingClearActiveJobButton(),
                ],
              ),
            ] else if (walletBlocked) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      size: 14, color: AppColors.kmRose),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(S.walletBlockedWarning,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.kmRose)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const WalletScreen())),
                    child: Text(S.topUpLabel),
                  ),
                ],
              ),
            ],
            if (employerLat != null && employerLng != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openInMaps(employerLat, employerLng),
                  icon: const Icon(Icons.location_on_outlined, size: 16),
                  label: Text(S.viewLocation),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kmTealBlue,
                    side: const BorderSide(color: AppColors.kmTealBlue),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if ((data['isRide'] ?? false) == true)
              SendRideOfferButton(
                  docId: docId,
                  data: data,
                  blocked: blocked,
                  onAction: onAction)
            else
              Row(
                children: [
                  Expanded(
                    child: NeonActionButton(
                      label: S.decline,
                      color: kNeonRose,
                      onTap: () {
                        if (isDirectOffer) {
                          declineDirectOffer(docId);
                        } else {
                          declineBroadcastJob(docId);
                        }
                        onAction();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeonActionButton(
                      label: S.offerPrice,
                      color: kNeonBlue,
                      onTap: blocked
                          ? null
                          : () {
                              onAction();
                              if (isDirectOffer) {
                                counterDirectOffer(context, docId, data,
                                    myService: myService);
                              } else {
                                counterBroadcastJob(context, docId, data,
                                    myService: myService);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeonActionButton(
                      label: S.accept,
                      color: kNeonTeal,
                      color2: kNeonViolet,
                      filled: true,
                      onTap: blocked
                          ? null
                          : () {
                              onAction();
                              if (isDirectOffer) {
                                acceptDirectOffer(context, docId, data);
                              } else {
                                acceptBroadcastJob(context, docId, data,
                                    myService: myService);
                              }
                            },
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

/// Ride-Hailing (Bike/Car) मात्र — सामान्य Decline/Offer/Accept row को सट्टा
/// यो देखिन्छ। धेरै driver ले एकैचोटि प्रस्ताव पठाउन सक्ने भएकोले (parent
/// doc कहिल्यै claim नगरी), आफूले पहिल्यै यो राइडका लागि प्रस्ताव
/// पठाइसकेको भए फेरि नपठाइयोस् भनेर आफ्नै `rideOffers/{myUid}` doc लाइभ
/// जाँच्छ।
class SendRideOfferButton extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool blocked;
  // Accept/Decline/Counter पछि floating stack बाट यो card तुरुन्तै (Firestore
  // snapshot को पर्खाइ नगरी — "Rs. 200 को अफर बक्स" accept पछि पनि केही
  // समय/सेकेन्ड बसिरहेको गुनासोको जड) हटाउन — non-ride card (माथि) ले यो
  // पहिल्यैदेखि प्रयोग गर्थ्यो, ride card मा यो callback नै थपिएको थिएन।
  final VoidCallback onAction;
  const SendRideOfferButton({
    super.key,
    required this.docId,
    required this.data,
    required this.blocked,
    required this.onAction,
  });

  @override
  State<SendRideOfferButton> createState() => SendRideOfferButtonState();
}

class SendRideOfferButtonState extends State<SendRideOfferButton> {
  // Firestore Internal Assertion Failed Fix — यो widget job feed को हरेक
  // ride-request card मा एउटा-एउटा बन्छ (धेरै एकैचोटि screen मा हुन सक्छन्)।
  // पहिले `stream:` सिधै (Stateless) `build()` भित्रै बन्थ्यो — त्यसैले
  // parent (`_jobsStream`, नयाँ अनुरोध आउँदा) रिबिल्ड हुनेबित्तिकै स्क्रिनमा
  // भएका सबै card ले एकैचोटि आफ्नो Firestore listener त्याग्थे र नयाँ
  // बनाउँथे — ठ्याक्कै त्यही बेला (passenger ले नयाँ request पठाउँदा) धेरै
  // listener एकैचोटि churn हुँदा Firestore Web SDK को WatchChangeAggregator
  // मा "INTERNAL ASSERTION FAILED: Unexpected state" आउने गुनासोको (live
  // browser console मा नै पक्रिएको) यो नै मुख्य जड हो — त्यसपछि यही
  // widget (Accept/Decline/Counter देखाउने कि "already offered" भन्ने
  // निर्णय गर्ने) आफैं सही अपडेट नहुन सक्छ, अनि driver ले request accept
  // गर्नै नपाएको जस्तो देखिन्छ। अब stream एकपटक मात्र बन्छ — parent
  // रिबिल्ड जतिपटक भए पनि कहिल्यै फेरि listen/unlisten हुँदैन।
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _offerStream;

  // Instant Tap Feedback — Accept/Decline थिचेपछि Firestore transaction
  // (~१-३ सेकेन्ड network round-trip) फर्कुन्जेल बटनमा कुनै दृश्य प्रतिक्रिया
  // नै नदेखिने भएकोले, "थिचेको काम नगरेको/frozen" जस्तो देखिन्थ्यो — actual
  // UI thread कहिल्यै block भएको थिएन (onPressed भित्रको Future await
  // नगरिएकोले frame रेन्डर रोकिँदैन), तर प्रयोगकर्ताले देख्ने कुनै संकेत
  // नभएकोले त्यस्तै अनुभव हुन्थ्यो। अब थिचेकै bittikai spinner देखाउने —
  // साँचो Firestore पुष्टि नआएसम्म status भने कहिल्यै फेरिँदैन (त्यो नै हो,
  // केवल तत्काल प्रतिक्रिया मात्र थपिएको)।
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
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant SendRideOfferButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docId != widget.docId) _subscribe();
  }

  void _subscribe() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _offerStream = FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(widget.docId)
        .collection('rideOffers')
        .doc(uid)
        .snapshots();
  }

  Future<void> _openOfferDialog(BuildContext context) async {
    final data = widget.data;
    final docId = widget.docId;
    final suggested = (data['proposedPrice'] as num?)?.toInt() ?? 200;
    final controller = TextEditingController(text: suggested.toString());
    // Dead Send/Cancel Fix — live Firestore listener ले यो card (job feed
    // मा, यो अनुरोध अर्को driver ले claim गरेर वा status बदलिएर) डायलग
    // खुलिरहेकै बेला हटाइदिए, बाहिरी context unmounted हुन्छ — पहिले
    // `context.mounted` मात्र जाँचिँदा Send/Cancel दुवै त्यो दुर्लभ race मा
    // चुपचाप "dead/frozen" देखिन्थे (कहिलेकाहीं null-check crash पनि)।
    // request_tracking_screen.dart::_counterBackToWorker/bookings_screen.
    // dart::_counterOfferToWorker कै उस्तै साँचो fix — context होइन, सधैं
    // mounted रहने NavigatorState/ScaffoldMessengerState नै dialog
    // खोल्नुअघि नै समातेर राख्ने।
    final navigator = Navigator.of(context, rootNavigator: true);
    await showKmDialog(
      context: context,
      title: S.offerPrice,
      icon: Icons.local_offer_rounded,
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        style: const TextStyle(color: AppColors.kmText),
        decoration: kmInputDecoration(S.yourPriceRs),
      ),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () {
            if (!navigator.mounted) return;
            navigator.pop();
          },
        ),
        KmDialogAction(
          label: 'Send',
          filled: true,
          onPressed: () {
            final price = parseSanePrice(controller.text);
            if (!navigator.mounted) return;
            navigator.pop();
            if (price == null) return;
            submitRideOffer(navigator.context, docId, data, price: price);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final docId = widget.docId;
    final data = widget.data;
    final blocked = widget.blocked;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _offerStream,
      builder: (context, snap) {
        final existing = snap.data?.data();
        if (existing != null) {
          final status = (existing['status'] ?? 'pending').toString();
          // passenger ले फरक मूल्य प्रस्ताव फिर्ता पठाएको — यहीँबाट
          // driver ले accept/decline गर्न पाउँछ।
          if (status == 'passenger_countered') {
            final counter = existing['passengerCounterPrice'];
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.kmOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ठूलो, स्पष्ट counter-offer — ग्राहकको बजेट (काटिएको) → नयाँ
                  // मूल्य (ठूलो, हजार-विभाजक सहित) र फरक (+/−)।
                  _CounterPriceHero(
                    budget: data['proposedPrice'] as num?,
                    counter: counter as num?,
                  ),
                  const SizedBox(height: 10),
                  // Tap-Lock Fix — यी तीन बटनले अरू ठाउँ (माथि, `_busy`/
                  // `_runBusy` भएको sibling branch) कै साझा `_busy` state
                  // प्रयोग नगरेको बेला, Accept थिचेपछि card पुन:निर्माण
                  // हुँदा/अर्को state मा सर्दा (वा दोहोरो-tap मा) त्यही
                  // ठाउँमा सरेको फरक बटनमा दोस्रो/द्रुत tap landed भएर
                  // "Accept थिच्दा Counter चलेको जस्तो" देखिन सक्थ्यो — अब
                  // पहिलो tap बित्तिकै तीनै बटन instantly disabled हुन्छन्।
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _runBusy(() =>
                                  driverDeclinePassengerCounter(
                                      context, docId, uid,
                                      employerUid: (data['employerUid'] ?? '')
                                          .toString())),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.kmRose,
                            side: const BorderSide(color: AppColors.kmRose),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 10),
                          ),
                          child: Text(S.decline,
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _runBusy(() => driverCounterOffer(
                                  context, docId, uid, counter ?? 0,
                                  employerUid: (data['employerUid'] ?? '')
                                      .toString())),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.kmOrange,
                            side: const BorderSide(color: AppColors.kmOrange),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 10),
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
                              : () => _runBusy(() =>
                                  driverAcceptPassengerCounter(
                                      context, docId, uid,
                                      counter ?? 0,
                                      employerUid: (data['employerUid'] ?? '')
                                          .toString())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.kmOrange,
                            foregroundColor: AppColors.kmInk,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 10),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.kmInk),
                                )
                              : Text(S.accept,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          final label = status == 'declined'
              ? S.offerNoLongerAvailable
              : S.youAlreadySentOffer;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.kmMuted)),
          );
        }
        // Ride request card — passenger ले प्रस्ताव गरेकै मूल्यमा driver ले
        // तुरुन्तै एकै tap मा "Accept" गर्न पाओस् भनेर, अनि त्यो सिधै/तुरुन्तै
        // confirm होस् (passenger को थप अनुमोदन नचाहिने — Ride Direct-Accept,
        // job_actions.dart::acceptRideAtListedPrice हेर्नुहोस्)। Offer Price
        // भने अझै छुट्टै custom-मूल्य चाहनेका लागि उपलब्ध नै रहन्छ — त्यो
        // भने अझै passenger ले नै छान्नुपर्छ (passenger आफैंले तोकेको मूल्य
        // होइन)।
        return Row(
          children: [
            Expanded(
              child: NeonActionButton(
                label: S.decline,
                color: kNeonRose,
                loading: _busy,
                onTap: _busy
                    ? null
                    : () {
                        widget.onAction();
                        _runBusy(() => declineBroadcastJob(docId));
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NeonActionButton(
                label: S.offerPrice,
                color: kNeonBlue,
                onTap: (blocked || _busy)
                    ? null
                    : () {
                        widget.onAction();
                        _openOfferDialog(context);
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NeonActionButton(
                label: S.accept,
                color: kNeonTeal,
                color2: kNeonViolet,
                filled: true,
                loading: _busy,
                onTap: (blocked || _busy)
                    ? null
                    : () {
                        widget.onAction();
                        _runBusy(() =>
                            acceptRideAtListedPrice(context, docId, data));
                      },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Online / offline banner ─────────────────────────────────────────────────
class _OnlineBanner extends StatelessWidget {
  final bool online;
  final ValueChanged<bool> onChanged;
  const _OnlineBanner({required this.online, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: online ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: online
                ? AppColors.kmTeal
                : Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: online ? AppColors.kmTeal : AppColors.kmMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online ? S.youAreOnline : S.youAreOffline,
              style: const TextStyle(color: AppColors.kmText, fontSize: 11.5),
            ),
          ),
          Switch(
            value: online,
            activeTrackColor: AppColors.kmTeal,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final int? radiusKm;
  final bool hasLocation;
  final ValueChanged<int?> onRadius;

  const _FilterBar({
    required this.radiusKm,
    required this.hasLocation,
    required this.onRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: active ? AppColors.kmCtaGradient : null,
                color: active ? null : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: active
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.16)),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? AppColors.kmInk : AppColors.kmText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ),
        );

    // Strict Trade Isolation — worker ले आफ्नो दर्ता भएको trade बाहेक अर्को
    // कुनै पनि श्रेणी (Mechanic/Electrician/...आदि, वा Driver) कहिल्यै
    // browse गर्न पाउँदैन — त्यसैले अब यो trade-chip picker नै पूर्ण
    // रूपमा हटाइयो (पहिले "All trades" + हरेक individual trade chip
    // देखिन्थ्यो, जसले Plumber ले पनि Electrician/Mechanic काम देख्न
    // सक्ने गर्थ्यो)। `_tradeFilter` सधैँ डिफल्ट `'__mine__'` मै बस्छ —
    // अब कुनै UI ले त्यो बदल्दैन, त्यसैले feed सधैँ आफ्नै trade/
    // vehicle-type मा lock रहन्छ।

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.social_distance_rounded,
                  color: AppColors.kmMuted, size: 16),
              const SizedBox(width: 6),
              Text(S.filterDistance,
                  style: const TextStyle(
                      color: AppColors.kmMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (!hasLocation) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(S.enableLocationForDistance,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 10.5),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(S.isNepali ? 'सबै' : 'All', radiusKm == null,
                    () => onRadius(null)),
                for (final km in [5, 10, 15])
                  chip(S.kmRadius(km), radiusKm == km, () => onRadius(km)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// कामको स्थिर ठेगाना नक्सामा देखाउने (एउटा pin मात्र — route/tracking छैन)।
class JobLocationScreen extends StatelessWidget {
  final double lat;
  final double lng;
  final String title;
  final String address;
  const JobLocationScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.title,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.jobLocationTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.kmCtaGradient),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            // Close-up — street/house-level, घर/क्षेत्रको वरपर प्रष्ट देखिने।
            initialCameraPosition:
                CameraPosition(target: LatLng(lat, lng), zoom: 18.5),
            mapId: kCloudMapId,
            markers: {
              Marker(
                markerId: const MarkerId('job'),
                position: LatLng(lat, lng),
                infoWindow: InfoWindow(title: title, snippet: address),
              ),
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // नक्सा सधैँ उत्तर-माथि रहोस् — gesture ले घुमाएर "उल्टो" देखिने
            // बग नआओस्।
            rotateGesturesEnabled: false,
          ),
          if (address.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: GlassPanel(
                radius: AppRadius.lg,
                padding: const EdgeInsets.all(14),
                fill: AppColors.kmVoid2.withValues(alpha: 0.92),
                child: Row(
                  children: [
                    const Icon(Icons.place_rounded, color: AppColors.kmPink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(address,
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppColors.kmMuted)),
                          const SizedBox(height: 2),
                          Text(S.serviceAddressNote,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.kmMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Driver ले देख्ने "passenger ले फिर्ता पठाएको मूल्य" — ठूलो मूल्य, काटिएको
/// ग्राहक-बजेट, र बजेटसँगको फरक (+/−) एकैपटक स्पष्ट देखाउने।
class _CounterPriceHero extends StatelessWidget {
  final num? budget;
  final num? counter;
  const _CounterPriceHero({required this.budget, required this.counter});

  @override
  Widget build(BuildContext context) {
    final c = counter;
    if (c == null) return const SizedBox.shrink();
    final b = budget;
    final diff = b == null ? null : c - b;
    final up = diff != null && diff > 0;
    final diffColor = diff == null || diff == 0
        ? Colors.white70
        : (up ? AppColors.kmTeal : AppColors.kmRose);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.kmOrange.withValues(alpha: 0.28),
          AppColors.kmOrange.withValues(alpha: 0.10),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.kmOrange.withValues(alpha: 0.7), width: 1.4),
      ),
      child: Column(
        children: [
          Text(S.counterBack.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.kmOrange.withValues(alpha: 0.95))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Rs ${formatRs(c)}',
                style: const TextStyle(
                    fontSize: 34,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          if (b != null) ...[
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('Rs ${formatRs(b)}',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.white60)),
                if (diff != null && diff != 0)
                  Text('${up ? '+' : '−'}Rs ${formatRs(diff.abs())}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: diffColor)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
