// screens/main_container.dart
// Role अनुसार tab हरू सहितको मुख्य Shell + inDrive-style bottom bar।
// यहीँ negotiation (counter-offer) अलर्ट पनि — कुन tab मा भए पनि, employer र
// worker दुवैलाई अर्को पक्षले नयाँ मूल्य पठाउनेबित्तिकै sound + banner देखियोस्
// भनेर एउटै persistent shell मा राखिएको (कुनै एक screen मात्र खुला हुँदा
// होइन)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../services/call_service.dart';
import '../services/ringtone_service.dart';
import '../theme/app_theme.dart';
import '../watchlist_screen.dart';
import '../widgets/active_job_bar.dart';
import '../widgets/job_alert_sound.dart';
import '../widgets/spring_tap.dart';
import '../worker_requests_page.dart';
import 'bookings_screen.dart';
import 'call_screen.dart';
import 'home_screen.dart';
import 'job_actions.dart' show openJobRoute;
import 'job_feed_screen.dart';
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
  String? _role; // null = अझै load हुँदै
  bool _loading = true;

  // negotiation (counter-offer) अलर्ट — role थाहा भएपछि एकपटक मात्र subscribe
  // हुन्छ; कुनै काम अहिले "मेरो जवाफ पर्खिरहेको" (worker को हकमा
  // pending_worker_counter, employer को हकमा pending_employer_approval) मा
  // नयाँ पसेको भेटियो भने sound + banner। पहिलो snapshot मा भएका सबैलाई
  // "नयाँ" ठान्दैन — पछि थपिनेलाई मात्र।
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _negotiationSub;
  final Set<String> _waitingOnMeIds = {};
  bool _firstNegotiationSnapshot = true;

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
  final Map<String, StreamSubscription<Map<String, dynamic>?>>
      _callWatchers = {};
  final Set<String> _ringingHandledFor = {};
  bool _inCall = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadMyName();
  }

  @override
  void dispose() {
    _negotiationSub?.cancel();
    _activeJobSub?.cancel();
    _workerPosSub?.cancel();
    for (final s in _callWatchers.values) {
      s.cancel();
    }
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
    _myName = name.isEmpty ? 'KaamMitra' : name;
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
    if (_inCall || _ringingHandledFor.contains(requestId)) return;
    _ringingHandledFor.add(requestId);
    _showIncomingCall(
      requestId: requestId,
      video: (c['mode'] ?? 'audio').toString() == 'video',
      callerName: (c['callerName'] ?? S.customerWord).toString(),
    );
  }

  Future<void> _showIncomingCall({
    required String requestId,
    required bool video,
    required String callerName,
  }) async {
    _inCall = true;
    unawaited(RingtoneService.playIncoming());
    // Caller ले उठ्नुअघि नै कल काटिदिए (मन फेरे/गल्तिले थिचे) यो dialog
    // आफैं बन्द होस् र फेरि नबज्ने — नत्र callee को फोन ringing dialog +
    // ringtone सधैंलाई अडिरहन्थ्यो।
    StreamSubscription<Map<String, dynamic>?>? cancelWatch;
    cancelWatch = CallService.watch(requestId).listen((c) {
      if (!mounted) return;
      final status = (c?['status'] ?? '').toString();
      if (c == null || status == 'ended') {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop(false);
      }
    });
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(video ? Icons.videocam_rounded : Icons.call_rounded,
              color: AppColors.igViolet),
          const SizedBox(width: 8),
          Text(S.incomingCallTitle),
        ]),
        content: Text('$callerName  ·  ${video ? S.videoCall : S.voiceCall}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.decline,
                style: const TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(S.accept),
          ),
        ],
      ),
    );
    await cancelWatch.cancel();
    await RingtoneService.stop();
    if (accept == true) {
      if (!mounted) {
        await CallService.resetSignal(requestId);
      } else {
        await Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CallScreen(
            requestId: requestId,
            otherName: callerName,
            myName: _myName,
            video: video,
            isCaller: false,
          ),
        ));
      }
    } else {
      await CallService.resetSignal(requestId);
    }
    _ringingHandledFor.remove(requestId);
    _inCall = false;
  }

  /// worker मात्र — सक्रिय काम भएसम्म आफ्नो GPS लगातार Firestore मा लेख्ने,
  /// चाहे JobRouteScreen खुला होस् वा नहोस् (त्यो स्क्रिनले पनि आफ्नै छुट्टै
  /// route-fetch/arrival-detection सहितको live tracking राख्छ — यहाँको भने
  /// स्थान मात्र लेख्ने हल्का संस्करण हो, दुवै एकैसाथ चले पनि हानि छैन)।
  void _startWorkerLocationTracking(String jobId) {
    if (_workerTrackingForJobId == jobId && _workerPosSub != null) return;
    _workerPosSub?.cancel();
    _workerTrackingForJobId = jobId;
    _workerPosSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen((p) async {
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
    setState(() {
      _role = role;
      _loading = false;
    });
    _startNegotiationWatcher(uid, role == 'worker');
    _startActiveJobWatcher(uid, role == 'worker');
  }

  /// employer/worker दुवैका लागि — आफ्नो कुनै काम accepted/confirmed/
  /// in_progress मा पुगेबित्तिकै (आफैंले accept गरेर होस् वा अर्को पक्षले
  /// counter-offer approve गरेर), हामी जुनसुकै tab/screen मा भए पनि सिधै
  /// त्यसको route-map screen खोल्ने। बटन/banner थिच्नु पर्दैन।
  void _startActiveJobWatcher(String? uid, bool isWorker) {
    if (uid == null) return;
    final field = isWorker ? 'workerUid' : 'employerUid';
    _activeJobSub = FirebaseFirestore.instance
        .collection('serviceRequests')
        .where(field, isEqualTo: uid)
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
        _knownActiveJobIds.clear();
        _autoOpenedForJobId = null;
        _syncCallWatchers(const {});
        if (isWorker) _stopWorkerLocationTracking();
        if (mounted && (_pinnedActiveJobId != null || _activeJobCount != 0)) {
          setState(() {
            _pinnedActiveJobId = null;
            _pinnedActiveJobData = null;
            _activeJobCount = 0;
          });
        }
        return;
      }
      _syncCallWatchers(activeIds);

      // pinned ActiveJobBar + Bookings tab badge — सधैँ सबैभन्दा पछिल्लो
      // सक्रिय काम, cold start मा र नयाँ थपिँदा दुवैमा (माथि नै sort भइसकेको)।
      if (mounted) {
        setState(() {
          _pinnedActiveJobId = activeDocs.first.id;
          _pinnedActiveJobData = activeDocs.first.data();
          _activeJobCount = activeDocs.length;
          _pinnedIsWorker = isWorker;
        });
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
            final latest = snap.docs
                .firstWhere((d) => newlyWaiting.contains(d.id));
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

    final isWorker = _role == 'worker';

    final screens = isWorker
        ? const [
            JobFeedScreen(),
            WorkerRequestsPage(),
            MessagesScreen(),
            ProfileScreen(),
          ]
        : const [
            HomeScreen(),
            BookingsScreen(),
            WatchlistScreen(),
            MessagesScreen(),
            ProfileScreen(),
          ];

    final items = isWorker
        ? [
            _NavItem(Icons.radar_rounded, S.navJobFeed),
            _NavItem(Icons.assignment_rounded, S.navRequests),
            _NavItem(Icons.chat_bubble_rounded, S.navMessages),
            _NavItem(Icons.person_rounded, S.navProfile),
          ]
        : [
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.86,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.symmetric(horizontal: selected ? 16 : 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.buttonGradient : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.igPink.withValues(alpha: 0.40),
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
                  tween: ColorTween(end: selected ? Colors.white : muted),
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
                        color: AppColors.igPink,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
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
                          color: Colors.white,
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
