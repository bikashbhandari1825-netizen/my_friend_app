// screens/job_feed_screen.dart
// कामदारको "कामको सूची" (live job radar) — नजिकका खुला स्थानीय कामहरू।
//  • दूरी filter (सबै / ५ / १० / १५ किमी) — कामदारको एकपटकको GPS fix अनुसार
//  • सीप filter (मेरो सीप / सबै / निश्चित पेसा)
// हरेक card: काम के हो, कहिले (मिति + समय), कहाँ (स्थिर ठेगाना), ग्राहकको बजेट,
// र कति टाढा। कुनै route/movement tracking छैन।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/job_alert_sound.dart';
import 'job_actions.dart';
import 'job_map_screen.dart';
import 'nearby_common.dart';

class JobFeedScreen extends StatefulWidget {
  const JobFeedScreen({super.key});

  @override
  State<JobFeedScreen> createState() => _JobFeedScreenState();
}

class _JobFeedScreenState extends State<JobFeedScreen> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  double? _lat;
  double? _lng;
  bool _locTried = false;
  // GPS असफल/अस्वीकृत भए काठमाडौं केन्द्रमा fallback गरिन्छ (nearby_map_screen.dart
  // कै pattern) — नत्र फिल्टर/सूची पूरै खाली देखिन्छ। यो true भएसम्म दूरी "अनुमानित"।
  bool _approxLocation = false;

  int? _radiusKm; // null = सबै
  String _tradeFilter = '__mine__'; // '__mine__' | '__all__' | 'Plumber' ...

  // नयाँ काम आउनेबित्तिकै ting-ting बजाउन पहिले देखिसकेका job id हरू ट्र्याक।
  final Set<String> _seenJobIds = {};
  bool _firstJobSnapshot = true;

  // '__mine__' trade filter resolve गर्न — overlay कार्ड छान्दा पनि चाहिने।
  String _myService = '';
  // Single Active Job Restriction — हाल कुनै अर्को साँच्चै-अझै-सक्रिय काम
  // (accepted/confirmed/in_progress) भए त्यसको requestId, नत्र खाली।
  String _myActiveJobId = '';
  // Worker Cancellation Penalty — बारम्बार आफैं cancel गर्ने worker ले
  // क्रमशः कम नयाँ job देख्ने (job_actions.dart::shouldShowJobToWorker)।
  int _myCancelCount = 0;

  // अहिले उपलब्ध सबैभन्दा नजिकको/उपयुक्त काम सधैँ live map माथि नै (top
  // overlay) देखिन्छ — bottom sheet को list मा लुकेर बस्दैन। नयाँ होस् वा
  // पहिल्यैदेखि broadcasting भइरहेको, दुवै अवस्थामा यही एउटा slot देखिन्छ।
  ({String id, Map<String, dynamic> data})? _currentIncoming;
  // "X" ले बन्द गरेका (कारबाही नगरी) job id हरू — यो session भर फेरि नदेखियोस्।
  final Set<String> _skippedIds = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastJobDocs = const [];

  // Stream एकपटक मात्र बनाइन्छ — filter chip tap (setState) मा re-subscribe
  // नभएर spinner flash नहोस्; trade/radius filter client-side हुन्छ।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? '__none__')
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _jobsStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('status', isEqualTo: 'broadcasting')
          .snapshots();

  @override
  void initState() {
    super.initState();
    _initLocation();
    _jobsStream.listen(_onJobsSnapshot);
    _userStream.listen((snap) {
      final s = (snap.data()?['service'] ?? snap.data()?['serviceType'] ?? '')
          .toString();
      final activeId = (snap.data()?['activeJobId'] ?? '').toString();
      final cancelCount = (snap.data()?['workerCancelCount'] as num?) ?? 0;
      if (mounted) {
        setState(() {
          _myService = s;
          _myActiveJobId = activeId;
          _myCancelCount = cancelCount.toInt();
        });
      }
    });
  }

  /// नयाँ broadcasting job आएमा sound बजाउने, अनि अहिले "top overlay" मा
  /// देखिनुपर्ने सबैभन्दा नजिकको/उपयुक्त काम पुनः-छान्ने — नयाँ होस् वा
  /// पहिल्यैदेखि broadcasting भइरहेको (पहिलो load मा नै भए पनि), दुवैलाई।
  void _onJobsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    _lastJobDocs = snap.docs;
    final ids = snap.docs.map((d) => d.id).toSet();
    if (!_firstJobSnapshot) {
      final newIds = ids.difference(_seenJobIds);
      final hasNewRelevant = snap.docs.any((d) {
        if (!newIds.contains(d.id)) return false;
        final rejected = (d.data()['rejectedBy'] as List?) ?? const [];
        if (rejected.contains(_uid)) return false;
        return shouldShowJobToWorker(d.id, _myCancelCount);
      });
      if (hasNewRelevant) playNewJobAlert();
    }
    _seenJobIds
      ..clear()
      ..addAll(ids);
    _firstJobSnapshot = false;

    // अहिले देखिरहेको overlay अझै उपलब्ध/eligible छ भने नछुने (बीचमै अर्कोमा
    // नफेरियोस्); नत्र (खाली छ, वा त्यो काम अरूले लिइसक्यो/हट्यो) पुनः-छान्ने।
    if (_currentIncoming != null &&
        ids.contains(_currentIncoming!.id) &&
        !_skippedIds.contains(_currentIncoming!.id)) {
      return;
    }
    final candidate = _pickIncomingCandidate(snap.docs);
    if (mounted) setState(() => _currentIncoming = candidate);
  }

  /// अहिलेको filter (सीप/दूरी) र session भरिको skip/reject अनुसार सबैभन्दा
  /// नजिकको उपलब्ध काम छान्ने (कोही नभए null)।
  ({String id, Map<String, dynamic> data})? _pickIncomingCandidate(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final wantTrade = _tradeFilter == '__mine__'
        ? _myService
        : (_tradeFilter == '__all__' ? '' : _tradeFilter);

    final candidates = <({String id, Map<String, dynamic> data, double? km})>[];
    for (final d in docs) {
      if (_skippedIds.contains(d.id)) continue;
      final data = d.data();
      final rejected = (data['rejectedBy'] as List?) ?? const [];
      if (rejected.contains(_uid)) continue;
      if (!shouldShowJobToWorker(d.id, _myCancelCount)) continue;
      final svc = (data['service'] ?? '').toString();
      if (wantTrade.isNotEmpty &&
          svc.toLowerCase() != wantTrade.toLowerCase()) {
        continue;
      }
      double? km;
      final jLat = (data['employerLat'] as num?)?.toDouble();
      final jLng = (data['employerLng'] as num?)?.toDouble();
      if (_lat != null && jLat != null && jLng != null) {
        km = haversineKm(_lat!, _lng!, jLat, jLng);
      }
      if (_radiusKm != null && (km == null || km > _radiusKm!)) continue;
      candidates.add((id: d.id, data: data, km: km));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      if (a.km == null && b.km == null) return 0;
      if (a.km == null) return 1;
      if (b.km == null) return -1;
      return a.km!.compareTo(b.km!);
    });
    final c = candidates.first;
    return (id: c.id, data: c.data);
  }

  /// "X" — यो काम कारबाही नगरी लुकाउने, अनि तुरुन्तै (Firestore पर्खनु नपरी)
  /// बाँकीबाट अर्को उपयुक्त काम देखाउने।
  void _skipIncoming(String id) {
    _skippedIds.add(id);
    final candidate = _pickIncomingCandidate(_lastJobDocs);
    setState(() => _currentIncoming = candidate);
  }

  /// Accept/Decline/Counter पछि — तुरुन्तै overlay हटाउने (Auto-Dismiss)।
  /// अर्को उपयुक्त काम भए, Firestore ले यो काम हटाएको live snapshot आएपछि
  /// (`_onJobsSnapshot`) आफैं देखिन्छ — स्थानीय (stale) cache बाट तुरुन्तै
  /// पुनः-छान्दा त्यही अहिले-कारबाही-भएको काम फेरि झलक्क देखिन सक्छ, त्यसैले
  /// जानाजान पर्खिने।
  void _clearIncomingAfterAction() {
    setState(() => _currentIncoming = null);
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
      _locTried = true;
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

  /// फिल्टर (सीप/दूरी) बदलिएपछि — Firestore बाट नयाँ snapshot नआए पनि,
  /// overlay मा देखिने काम अद्यावधिक (नयाँ फिल्टरसँग नमिल्ने भए हटाउने/बदल्ने)।
  void _recomputeIncoming() {
    final candidate = _pickIncomingCandidate(_lastJobDocs);
    if (_currentIncoming?.id == candidate?.id) return;
    setState(() => _currentIncoming = candidate);
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

  // शुरुको sheet उचाइ (screen अनुपात) — background map को camera padding र
  // recentre FAB को स्थान यही अनुमानित उचाइमाथि राख्न प्रयोग हुन्छ। प्रयोगकर्ताले
  // पछि तान्दा (drag) FAB/padding लाइभ ट्र्याक हुँदैन — साधारण राख्न जानाजान
  // छोडिएको (डिजाइन trade-off)।
  static const double _sheetInitial = 0.42;
  static const double _sheetMin = 0.16;
  static const double _sheetMax = 0.86;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(S.openJobsNearby,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: _uid == null
          ? const Center(
              child: Text('Login गर्नुहोस्',
                  style: TextStyle(color: Colors.white)))
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
                      bottomInset: screenH * _sheetInitial,
                      cancelCount: _myCancelCount,
                    ),
                    // ── माथि तान्न मिल्ने (draggable) सूची — online banner +
                    // दूरी/सीप filter + job card हरू, सबै एउटै scroll मा
                    // (sheet handle बाट पनि तान्न मिलोस् भनेर) ──
                    DraggableScrollableSheet(
                      initialChildSize: _sheetInitial,
                      minChildSize: _sheetMin,
                      maxChildSize: _sheetMax,
                      builder: (context, scrollController) => Container(
                        decoration: const BoxDecoration(
                          gradient: AppColors.igGradient,
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(AppRadius.lg)),
                          boxShadow: [
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
                              child: _OnlineBanner(
                                online: online,
                                onChanged: _setOnline,
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: _FilterBar(
                                radiusKm: _radiusKm,
                                trade: _tradeFilter,
                                myService: myService,
                                hasLocation: !_approxLocation,
                                onRadius: _onRadiusTap,
                                onTrade: (v) {
                                  setState(() => _tradeFilter = v);
                                  _recomputeIncoming();
                                },
                              ),
                            ),
                            _jobListSliver(myService),
                          ],
                        ),
                      ),
                    ),
                    // ── नयाँ अफर आउनेबित्तिकै — bottom sheet मा नलुकाई, live
                    // map माथि नै तुरुन्तै देखिने floating card। Accept/Decline/
                    // Counter थिचेपछि आफैं हराउँछ (Auto-Dismiss)। सक्रिय काम
                    // देखाउने काम अब MainContainer कै साझा ActiveJobBar (bottom
                    // nav माथि, हरेक tab मा) ले गर्छ — यहाँ छुट्टै दोहोरो banner
                    // होइन।
                    if (_currentIncoming != null)
                      Positioned(
                        top: MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            10,
                        left: 12,
                        right: 12,
                        child: _IncomingOfferOverlay(
                          key: ValueKey(_currentIncoming!.id),
                          docId: _currentIncoming!.id,
                          data: _currentIncoming!.data,
                          myService: myService,
                          blockedByOtherActiveJob: _myActiveJobId.isNotEmpty &&
                              _myActiveJobId != _currentIncoming!.id,
                          distanceKm: (_lat != null &&
                                  _currentIncoming!.data['employerLat']
                                      is num &&
                                  _currentIncoming!.data['employerLng'] is num)
                              ? haversineKm(
                                  _lat!,
                                  _lng!,
                                  (_currentIncoming!.data['employerLat'] as num)
                                      .toDouble(),
                                  (_currentIncoming!.data['employerLng'] as num)
                                      .toDouble())
                              : null,
                          onSkip: () => _skipIncoming(_currentIncoming!.id),
                          onAction: _clearIncomingAfterAction,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _jobListSliver(String myService) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _jobsStream,
      builder: (context, snap) {
        // memoized stream — waiting केवल पहिलो पटक; cache हुँदा तुरुन्तै data।
        if (!snap.hasData) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child:
                Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        final wantTrade = _tradeFilter == '__mine__'
            ? myService
            : (_tradeFilter == '__all__' ? '' : _tradeFilter);

        final rows = <({String id, Map<String, dynamic> data, double? km})>[];
        for (final d in snap.data?.docs ?? []) {
          final data = d.data();
          final svc = (data['service'] ?? '').toString();
          final rejected = (data['rejectedBy'] as List?) ?? const [];
          if (rejected.contains(_uid)) continue;
          if (!shouldShowJobToWorker(d.id, _myCancelCount)) continue;
          if (wantTrade.isNotEmpty &&
              svc.toLowerCase() != wantTrade.toLowerCase()) {
            continue;
          }

          double? km;
          final jLat = (data['employerLat'] as num?)?.toDouble();
          final jLng = (data['employerLng'] as num?)?.toDouble();
          if (_lat != null && jLat != null && jLng != null) {
            km = haversineKm(_lat!, _lng!, jLat, jLng);
          }
          if (_radiusKm != null) {
            if (km == null || km > _radiusKm!) continue;
          }
          rows.add((id: d.id, data: data, km: km));
        }

        rows.sort((a, b) {
          if (a.km == null && b.km == null) {
            final ta = a.data['createdAt'];
            final tb = b.data['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          }
          if (a.km == null) return 1;
          if (b.km == null) return -1;
          return a.km!.compareTo(b.km!);
        });

        if (rows.isEmpty) {
          return SliverFillRemaining(hasScrollBody: false, child: _empty());
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverList.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _JobCard(
              docId: rows[i].id,
              data: rows[i].data,
              distanceKm: rows[i].km,
              myService: myService,
              blockedByOtherActiveJob:
                  _myActiveJobId.isNotEmpty && _myActiveJobId != rows[i].id,
            ),
          ),
        );
      },
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.radar_rounded, size: 60, color: Colors.white70),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(S.noOpenJobs,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
            if (_locTried && _approxLocation) ...[
              const SizedBox(height: 8),
              Text(S.enableLocationForDistance,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ],
        ),
      );
}

// ── नयाँ अफर आउनेबित्तिकै — live map माथि नै floating overlay (Uber/InDrive
// "incoming ride request" शैली)। bottom sheet/list मा लुकाउनुको सट्टा AppBar
// मुनि तुरुन्तै देखिन्छ; Accept/Decline/Counter थिचेपछि आफैं हराउँछ। ─────────
class _IncomingOfferOverlay extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final double? distanceKm;

  /// कामदारको दर्ता सीप — यो काम नमिले Accept/मूल्य प्रस्ताव बटन disable हुन्छ।
  final String myService;

  /// Single Active Job Restriction — true भए worker सँग हाल पहिल्यै अर्को
  /// साँच्चै सक्रिय काम छ, Accept/Offer दुवै बटन disable हुन्छन्।
  final bool blockedByOtherActiveJob;

  /// "X" — कारबाही नगरी लुकाउने (session भर फेरि नदेखियोस्)।
  final VoidCallback onSkip;

  /// Accept/Decline/Counter पछि — Firestore बाट अर्को आफैं आउने भएकाले यहाँ
  /// overlay मात्र खाली गर्ने।
  final VoidCallback onAction;

  const _IncomingOfferOverlay({
    super.key,
    required this.docId,
    required this.data,
    required this.distanceKm,
    required this.myService,
    this.blockedByOtherActiveJob = false,
    required this.onSkip,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final service = (data['service'] ?? '').toString();
    final desc = (data['details'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final budget = data['proposedPrice'];
    final skillMismatch = myService.isNotEmpty &&
        myService.toLowerCase() != service.toLowerCase();
    final blocked = skillMismatch || blockedByOtherActiveJob;

    // नोट: यहाँ कुनै key दिनु पर्दैन — parent (`_IncomingOfferOverlay` आफैं,
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    size: 15, color: AppColors.igRed),
                const SizedBox(width: 5),
                Text(S.newJobNotifTitle,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.igRed)),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 18,
                  icon: const Icon(Icons.close_rounded, color: Colors.black38),
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
                    color: const Color(0x11833AB4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    serviceImageFor(service),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(serviceIconFor(service),
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
                      if (distanceKm != null)
                        Text(S.distanceLabel(distanceKm!),
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
              const SizedBox(height: 8),
              Text(desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
            if (address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined,
                      size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
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
            ] else if (blockedByOtherActiveJob) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.lock_clock_rounded,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(S.finishCurrentJobFirst,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      declineBroadcastJob(docId);
                      onAction();
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
                    onPressed: blocked
                        ? null
                        : () {
                            onAction();
                            counterBroadcastJob(context, docId, data,
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
                    onPressed: blocked
                        ? null
                        : () {
                            onAction();
                            acceptBroadcastJob(context, docId, data,
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
        color: Colors.white.withValues(alpha: online ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: online
                ? AppColors.success
                : Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: online ? AppColors.success : Colors.white70, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online ? S.youAreOnline : S.youAreOffline,
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
            ),
          ),
          Switch(
            value: online,
            activeTrackColor: AppColors.success,
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
  final String trade;
  final String myService;
  final bool hasLocation;
  final ValueChanged<int?> onRadius;
  final ValueChanged<String> onTrade;

  const _FilterBar({
    required this.radiusKm,
    required this.trade,
    required this.myService,
    required this.hasLocation,
    required this.onRadius,
    required this.onTrade,
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
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? AppColors.igViolet : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ),
        );

    final trades = <(String, String)>[
      ('__mine__', S.myTrade),
      ('__all__', S.allTrades),
      for (final s in serviceFilters)
        (s['name'] as String, S.serviceName(s['name'] as String)),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.social_distance_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(S.filterDistance,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (!hasLocation) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(S.enableLocationForDistance,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10.5),
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
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in trades)
                  chip(t.$2, trade == t.$1, () => onTrade(t.$1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Job card ────────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final double? distanceKm;

  /// कामदारको दर्ता सीप — यो काम नमिले Accept/मूल्य प्रस्ताव बटन disable हुन्छ।
  final String myService;

  /// Single Active Job Restriction — true भए worker सँग हाल पहिल्यै अर्को
  /// साँच्चै सक्रिय काम छ, Accept/Offer दुवै बटन disable हुन्छन्।
  final bool blockedByOtherActiveJob;
  const _JobCard({
    required this.docId,
    required this.data,
    required this.distanceKm,
    required this.myService,
    this.blockedByOtherActiveJob = false,
  });

  String _fmtDate(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.day}/${d.month}/${d.year}';
    }
    return '';
  }

  String _slotLabel(String s) => switch (s) {
        'morning' => S.slotMorning,
        'afternoon' => S.slotAfternoon,
        'evening' => S.slotEvening,
        _ => S.slotAnytime,
      };

  @override
  Widget build(BuildContext context) {
    final service = (data['service'] ?? '').toString();
    final desc = (data['details'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final budget = data['proposedPrice'];
    final date = _fmtDate(data['preferredDate']);
    final slot = _slotLabel((data['timeSlot'] ?? 'anytime').toString());
    final lat = (data['employerLat'] as num?)?.toDouble();
    final lng = (data['employerLng'] as num?)?.toDouble();
    // सीप-आधारित प्रतिबन्ध: हेर्न सबैलाई खुला, तर Accept/मूल्य प्रस्ताव आफ्नै
    // दर्ता सीप-श्रेणीको काममा मात्र। प्रोफाइलमा सीप नै सेट नभए (myService
    // खाली) रोक्दैन।
    final skillMismatch = myService.isNotEmpty &&
        myService.toLowerCase() != service.toLowerCase();
    final blocked = skillMismatch || blockedByOtherActiveJob;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
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
                  errorBuilder: (_, __, ___) =>
                      Icon(serviceIconFor(service), color: AppColors.igViolet),
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
                    if (distanceKm != null)
                      Text(S.distanceLabel(distanceKm!),
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
                style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
          ],
          const SizedBox(height: 8),
          _row(Icons.event_rounded, '$date  ·  $slot'),
          if (address.isNotEmpty) _row(Icons.place_outlined, address),
          const SizedBox(height: 10),
          if (lat != null && lng != null)
            Align(
              alignment: Alignment.centerLeft,
              child: GradientActionButton(
                icon: Icons.place_rounded,
                label: S.viewJobLocation,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JobLocationScreen(
                      lat: lat,
                      lng: lng,
                      title: S.serviceName(service),
                      address: address,
                    ),
                  ),
                ),
              ),
            ),
          const Divider(height: 20),
          if (skillMismatch) ...[
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
            const SizedBox(height: 8),
          ] else if (blockedByOtherActiveJob) ...[
            Row(
              children: [
                const Icon(Icons.lock_clock_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(S.finishCurrentJobFirst,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => declineBroadcastJob(docId),
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
                  onPressed: blocked
                      ? null
                      : () => counterBroadcastJob(context, docId, data,
                          myService: myService),
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
                  onPressed: blocked
                      ? null
                      : () => acceptBroadcastJob(context, docId, data,
                          myService: myService),
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
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: Colors.black45),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ],
        ),
      );
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
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.buttonGradient),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            // Close-up — street/house-level, घर/क्षेत्रको वरपर प्रष्ट देखिने।
            initialCameraPosition:
                CameraPosition(target: LatLng(lat, lng), zoom: 18.5),
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
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 14,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place_rounded, color: AppColors.igRed),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(address,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.black54)),
                          const SizedBox(height: 2),
                          Text(S.serviceAddressNote,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black38)),
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
