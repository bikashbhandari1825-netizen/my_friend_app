// screens/driver_dashboard_screen.dart
// Driver Control Dashboard — profile_screen.dart कै पुराना ३ वटा worker-only
// विकल्प (My Earnings / My Schedule / Work Portfolio) को साटो Driver का
// लागि यहाँ एकै ठाउँमा:
//   १. Online/Offline toggle
//   २. Ride Preferences (inDrive-शैली): खोजी दायरा, सवारी फिल्टर, Break Mode
//   ३. Active Rides & History
//   ४. Earnings & Payouts Summary
//   ५. Profile & Document Status
// सबै existing collection/field हरू (serviceRequests, users/{uid}) नै
// पुनः प्रयोग गर्छ — earnings_screen.dart/job_feed_screen.dart सँगै उस्तै
// तरिकाले। Ride Preferences का field हरू (driverSearchRadiusKm/
// driverVehicleFilter/driverOnBreak) users/{uid} मै बचत हुन्छन्, र
// job_feed_screen.dart ले पढेर वास्तविक filtering मा लागू गर्छ। (पहिले यहाँ
// driverAutoAccept — राइड आफैं स्वीकार हुने फिचर — पनि थियो, driver कै
// अनुमति बिना स्वीकृति हुने र त्यसपछिका अनुरोध अड्किने गुनासो आएपछि पूर्ण
// रूपमा हटाइयो।)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../driver_registration_flow.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart' show SecondaryButton;
import '../widgets/dashboard_exit_bar.dart';
import '../widgets/glass_ui.dart';
import '../widgets/worker_avatar.dart';
import '../widgets/worker_menu_drawer.dart';
import '../widgets/worker_stats.dart';
import '../worker_requests_page.dart';
import 'document_resync_page.dart';
import 'earnings_screen.dart';
import 'job_actions.dart'
    show releaseWorkerActiveJob, workerJobVisibilityRate;
import 'job_feed_screen.dart';
import 'nearby_common.dart';
import 'notification_screen.dart';
import 'wallet_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  bool _togglingOnline = false;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? '__none__')
          .snapshots();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requestsStream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('workerUid', isEqualTo: _uid ?? '__none__')
          .snapshots();

  static const _activeStatuses = {'accepted', 'confirmed', 'in_progress'};

  DateTime _dateOf(Map<String, dynamic> d) {
    for (final k in ['completedAt', 'acceptedAt', 'createdAt']) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return DateTime.now();
  }

  num _amountOf(Map<String, dynamic> d) =>
      (d['finalPrice'] ?? d['proposedPrice'] ?? 0) as num;

  // job_feed_screen.dart::_setOnline सँग उस्तै — users/{uid} + registeredWorkers
  // दुवैमा isOnline लेख्ने, अनलाइन हुँदा हालको स्थान पनि साथमा।
  Future<void> _setOnline(bool on) async {
    if (_uid == null || _togglingOnline) return;
    setState(() => _togglingOnline = true);
    final db = FirebaseFirestore.instance;
    final loc = <String, dynamic>{};
    if (on) {
      final r = await getCurrentLocation();
      if (r.ok) {
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
    } catch (_) {
      // बेस्ट-इफर्ट — असफल भए पनि UI stream ले पुरानै मान देखाउँछ, retry मिल्छ।
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PartnerDashboardGuard(
      child: AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: const WorkerMenuDrawer(),
        appBar: AppBar(
          title: Text(S.driverDashboardTitle,
              style: const TextStyle(
                  color: AppColors.kmText, fontWeight: FontWeight.w800)),
          iconTheme: const IconThemeData(color: AppColors.kmText),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.kmText,
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.kmCtaGradient),
          ),
          actions: [
            const GoHomeAction(),
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
        // Dashboard-Stuck Fix — job_feed_screen.dart कै उस्तै जड: यो screen
        // पनि MainContainer बाहिर push गरिएको, drawer भएकोले AppBar ले back
        // बटन होइन hamburger मात्र देखाउँछ। आफ्नै bottom nav ले "Home" सधैं
        // पुग्ने बनाउँछ।
        bottomNavigationBar: const DashboardExitBar(),
        body: SafeArea(
          child: _uid == null
              ? Center(
                  child: Text(S.errorWord,
                      style: const TextStyle(color: AppColors.kmText)))
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _userStream,
                  builder: (context, userSnap) {
                    final userData = userSnap.data?.data() ?? {};
                    final online = userData['isOnline'] != false;
                    final myActiveJobId =
                        (userData['activeJobId'] ?? '').toString();
                    final myEligible =
                        (userData['isEligibleForJobs'] as bool?) ?? true;
                    final myService =
                        (userData['service'] ?? userData['serviceType'] ?? '')
                            .toString();

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _requestsStream,
                      builder: (context, reqSnap) {
                        // Driver Dashboard — ड्राइभरको लागि मात्र, ride
                        // (Bike/Car) बाहेक अरू कुनै पनि सेवा-प्रकार यहाँ
                        // कहिल्यै नदेखियोस् (Active/History/Earnings तीनै
                        // कार्ड यही एउटै फिल्टर गरिएको सूचीबाट बन्छन्)। यो
                        // फिल्टर यही dashboard मात्र स्कोप गरिएको हो — बाँकी
                        // एपका general gig-work screen (job feed, admin
                        // dashboard, registration) अझै अपरिवर्तित।
                        final docsRaw = reqSnap.data?.docs ?? [];
                        final docs = docsRaw
                            .map((d) => d.data())
                            .where((d) => d['isRide'] == true)
                            .toList();
                        final active = docs
                            .where((d) => _activeStatuses
                                .contains((d['status'] ?? '').toString()))
                            .toList();
                        final completed = docs
                            .where((d) =>
                                (d['status'] ?? '').toString() == 'completed')
                            .toList()
                          ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
                        // Prominent Incoming-Request Cards — पहिले employer
                        // ले सिधै यो driver लाई पठाएको राइड (status ==
                        // 'pending_worker') केवल silent push notification
                        // मात्र थियो, dashboard भित्र कतै देखिँदैनथ्यो —
                        // JobFeedScreen (map) खोलेमा मात्र भेटिने। अब
                        // dashboard कै सुरुमै (map नखोली नै) Accept/Decline
                        // सहित देखिन्छ — job_feed_screen.dart कै उही
                        // IncomingOfferOverlay कार्ड पुनः-प्रयोग गरेर।
                        final pendingOffers = docsRaw
                            .where((d) =>
                                d.data()['isRide'] == true &&
                                (d.data()['status'] ?? '').toString() ==
                                    'pending_worker')
                            .toList();

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          children: [
                            _profileHeaderCard(userData),
                            const SizedBox(height: 14),
                            for (final d in pendingOffers) ...[
                              IncomingOfferOverlay(
                                key: ValueKey(d.id),
                                docId: d.id,
                                data: d.data(),
                                myService: myService,
                                blockedByOtherActiveJob:
                                    myActiveJobId.isNotEmpty &&
                                        myActiveJobId != d.id,
                                walletBlocked: !myEligible,
                                distanceKm: null,
                                onSkip: () {},
                                onAction: () {},
                              ),
                              const SizedBox(height: 14),
                            ],
                            // TEMPORARY, TESTING-ONLY — live-testing बेला
                            // mock/test active job "activeJobId" pointer
                            // (users/{uid}) अड्किएर Accept/Offer price बटन
                            // "Finish your current job first" ले सधैँ
                            // ब्लक भइरहँदा, हरेकपटक साँच्चै काम सक्नु
                            // नपरोस् भनेर यो बटनले सिधै त्यो pointer खाली
                            // गर्छ। असली launch अघि यो कार्ड हटाउने
                            // (उपयोगकर्ताले पूरा गर्नुपर्ने real
                            // restriction लाई bypass गर्ने बाटो हो)।
                            if (_showTestingClearCard(userData))
                              _testingClearActiveJobCard(
                                  (userData['activeJobId'] ?? '').toString()),
                            if (_showTestingClearCard(userData))
                              const SizedBox(height: 14),
                            _onlineToggleCard(online),
                            const SizedBox(height: 14),
                            _findNearbyJobsCard(),
                            const SizedBox(height: 14),
                            _ridePreferencesCard(userData),
                            const SizedBox(height: 14),
                            _activeRidesCard(active),
                            const SizedBox(height: 14),
                            _historyCard(completed),
                            const SizedBox(height: 14),
                            _earningsCard(completed),
                            const SizedBox(height: 14),
                            _documentStatusCard(userData),
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ),
      ),
    );
  }

  // ── TESTING ONLY — असली launch अघि यो पूरा method हटाउने ────────────────
  // Car/Auto मा सधैँ देखिने (activeJobId अड्किए नअड्किए पनि, जुनसुकै बेला
  // Test Kill थिच्न मिलोस् भनेर) — Bike मा पहिलेकै जस्तै साँच्चै अड्किएको
  // बेला मात्र देखिने, यो आफैं अपरिवर्तित।
  bool _showTestingClearCard(Map<String, dynamic> userData) {
    final hasStuckJob = (userData['activeJobId'] ?? '').toString().isNotEmpty;
    final service =
        (userData['service'] ?? userData['serviceType'] ?? '').toString();
    return hasStuckJob || service == 'Car' || service == 'Auto';
  }

  Widget _testingClearActiveJobCard(String activeJobId) {
    final hasStuckJob = activeJobId.isNotEmpty;
    return GlassPanel(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(14),
      fill: AppColors.kmRose.withValues(alpha: 0.12),
      border: AppColors.kmRose,
      child: Row(
        children: [
          const Icon(Icons.science_rounded, color: AppColors.kmRose, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasStuckJob
                  ? 'TESTING ONLY: an active job is blocking Accept/Offer price.'
                  : 'TESTING ONLY: clear a stuck active job anytime.',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.kmRose),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.kmRose,
              side: const BorderSide(color: AppColors.kmRose),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!hasStuckJob) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('No stuck active job right now.')),
                );
                return;
              }
              await releaseWorkerActiveJob(_uid, activeJobId);
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Active job cleared (testing).')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => GlassPanel(
        radius: AppRadius.lg,
        padding: const EdgeInsets.all(16),
        child: child,
      );

  // ── ०. Driver Profile Header — फोटो + नाम + रेटिङ + सवारी ────────────────
  // inDrive को driver-mode menu मा जस्तै (avatar + star rating सधैँ माथि
  // देखिने) — पहिले dashboard सिधै toggle कार्डबाटै सुरु हुन्थ्यो, आफ्नै
  // पहिचान (फोटो/रेटिङ) कतै देखिँदैनथ्यो।
  Widget _profileHeaderCard(Map<String, dynamic> userData) {
    final name = (userData['name'] ?? '').toString();
    final vehicle = (userData['vehicleDetails'] ?? '').toString();
    final plate = (userData['vehiclePlate'] ?? '').toString();
    final vehicleLine = [
      if (vehicle.isNotEmpty) vehicle,
      if (plate.isNotEmpty) plate
    ].join(' · ');

    return _card(
      child: Row(
        children: [
          WorkerAvatar(uid: _uid ?? '', size: 58, iconColor: AppColors.kmInk),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? S.workerRoleWord : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16.5)),
                const SizedBox(height: 3),
                WorkerRatingBadge(uid: _uid ?? '', onDark: true),
                if (vehicleLine.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(vehicleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.kmMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── १. Online/Offline Toggle — inDrive जस्तै ठूलो, पूर्ण-चौडाइको CTA ─────
  // पहिले सानो row+Switch थियो — inDrive को driver home screen मा जस्तो
  // "GO ONLINE" एउटा ठूलो, टाँच्न-मिल्ने बटन नै मुख्य पहिलो कार्य हो, त्यही
  // अनुभव दिन पूरै कार्ड नै tappable बनाइयो र status अझ प्रमुख देखियोस्।
  // On-Demand Map Access — Profile → "Driver Hub" बटनले पहिले सिधै
  // live-map job radar (JobFeedScreen) नै खोल्थ्यो (dashboard भन्दा पहिले
  // नै full-screen Google Map देखिने, requested fix कै उद्देश्य विपरीत)।
  // अब त्यो बटनले यो data-driven dashboard (earnings/history/requests/
  // notifications) नै सिधै खोल्छ, र map भने यहाँबाट मात्र — driver आफैं
  // यो कार्ड थिचेर — on-demand देखिन्छ। यो नै `JobFeedScreen` सम्म पुग्ने
  // एकमात्र बाटो भएकोले यो कार्ड हटाइएन, नत्र नजिकका काम कहिल्यै ब्राउज
  // गर्न नमिल्ने हुन्थ्यो।
  Widget _findNearbyJobsCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const JobFeedScreen()),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            // CTA कार्ड — app को बैजनी (route/halo कै रङ) gradient, सेतो
            // लेखाइ पढ्न मिल्ने। (`kmCtaGradient` ~सेतो हो — सेतो लेखाइसँग
            // मिल्दैन।)
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.kmPurple, AppColors.kmPurpleDeep],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.kmGlassBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.kmPurple.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // यो चालक (Bike/Car/Auto) dashboard हो — "Jobs" होइन "Rides"।
                    Text(S.findNearbyRides,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    const Text(
                        'Open the live map to browse & accept nearby rides',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _onlineToggleCard(bool online) {
    final Color accent = online ? AppColors.kmTeal : AppColors.kmMuted2;
    return GestureDetector(
      onTap: _togglingOnline ? null : () => _setOnline(!online),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: online
                ? AppColors.kmTeal.withValues(alpha: 0.12)
                : AppColors.kmGlassFill,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
                color: online
                    ? AppColors.kmTeal.withValues(alpha: 0.5)
                    : AppColors.kmGlassBorder,
                width: online ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  online
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_off_rounded,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(online ? S.onlineNow : S.offlineWord,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color:
                                online ? AppColors.kmTeal : AppColors.kmText)),
                    const SizedBox(height: 2),
                    Text(online ? S.goOnlineHint : S.goOfflineHint,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.kmMuted)),
                  ],
                ),
              ),
              _togglingOnline
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Switch(
                      value: online,
                      activeThumbColor: AppColors.kmTeal,
                      onChanged: _setOnline,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ── २. Ride Preferences (inDrive-शैली) ───────────────────────────────────
  Future<void> _setDriverPref(Map<String, dynamic> fields) async {
    if (_uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set(fields, SetOptions(merge: true));
    } catch (_) {
      // बेस्ट-इफर्ट — असफल भए पनि stream ले पुरानै मान देखाउँछ, retry मिल्छ।
    }
  }

  Widget _ridePreferencesCard(Map<String, dynamic> userData) {
    final radiusKm = (userData['driverSearchRadiusKm'] as num?)?.toInt();
    final vehicleFilter =
        (userData['driverVehicleFilter'] ?? '__mine__').toString();
    final onBreak = userData['driverOnBreak'] == true;
    final cancelCount = (userData['workerCancelCount'] as num?)?.toInt() ?? 0;

    Widget chip(String label, bool active, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.kmOrange.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: active
                      ? AppColors.kmOrange
                      : Colors.white.withValues(alpha: 0.16)),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.kmOrange : AppColors.kmMuted)),
          ),
        );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: AppColors.kmOrange),
              SizedBox(width: 8),
              Text('Ride Preferences',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          // (१) दूरी दायरा — जति टाढासम्मका राइड देखिने/मिल्ने।
          const Text('Search Radius',
              style: TextStyle(fontSize: 12.5, color: AppColors.kmMuted)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(
                    S.isNepali ? 'सबै' : 'All',
                    radiusKm == null,
                    () => _setDriverPref(
                        {'driverSearchRadiusKm': FieldValue.delete()})),
                for (final km in [5, 10, 15, 20])
                  chip(S.kmRadius(km), radiusKm == km,
                      () => _setDriverPref({'driverSearchRadiusKm': km})),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // (२) सवारी साधन फिल्टर — केवल मेरो प्रकार, वा सबै किसिमका अनुरोध।
          const Text('Ride Filter',
              style: TextStyle(fontSize: 12.5, color: AppColors.kmMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              chip('My vehicle only', vehicleFilter == '__mine__',
                  () => _setDriverPref({'driverVehicleFilter': '__mine__'})),
              chip('All ride types', vehicleFilter == '__all__',
                  () => _setDriverPref({'driverVehicleFilter': '__all__'})),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 14),
          // (३) Break Mode — Online नै रहेर पनि केही बेर नयाँ राइड नआउने।
          // नोट: पहिले यहाँ "Auto-Accept Rides" टगल पनि थियो — driver कै
          // अनुमति बिना नै राइड आफैं स्वीकार हुने (र त्यसपछिका अरू अनुरोध
          // "अर्को सक्रिय काम" भनेर अड्किने) गुनासोको जड भेटिएपछि पूर्ण
          // रूपमा हटाइयो (job_feed_screen.dart हेर्नुहोस्) — हरेक अनुरोध
          // अब सधैं driver आफैंले Accept/Decline/Counter Offer ट्याप
          // गरेपछि मात्र अघि बढ्छ।
          _prefSwitchRow(
            icon: Icons.free_breakfast_rounded,
            title: 'Break Mode',
            subtitle: 'Stay online but pause new ride requests for a while',
            value: onBreak,
            onChanged: (v) => _setDriverPref({'driverOnBreak': v}),
          ),
          // TESTING ONLY — असली launch अघि हटाउने। Worker Cancellation
          // Penalty (job_actions.dart::shouldShowJobToWorker/
          // workerJobVisibilityRate) ले `workerCancelCount` 2 भन्दा बढी
          // भएपछि नयाँ broadcast job हरू मध्ये केही (hash-based, random
          // जस्तो देखिने) लुकाउन थाल्छ — कुनै संकेत/सूचना बिना नै। बारम्बार
          // cancel-flow manual testing गर्दा यही गन्ती चुपचाप बढ्दै गई
          // "३ पटकपछि अनुरोध देखिन छोड्छ" जस्तो देखिने गुनासोको साँचो जड
          // यही थियो — बग होइन, तर testing बेला यो देखिनु/रिसेट हुनु जरुरी।
          if (cancelCount > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.kmRose.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded,
                      size: 16, color: AppColors.kmRose),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancellation penalty active ($cancelCount) — '
                      '${(workerJobVisibilityRate(cancelCount) * 100).round()}% '
                      'of new rides shown',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.kmRose),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _setDriverPref({'workerCancelCount': 0}),
                    child: const Text('TEST: Reset',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _prefSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.kmMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.kmMuted)),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.kmOrange,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ── ३. Active Rides & History ────────────────────────────────────────────
  Widget _activeRidesCard(List<Map<String, dynamic>> active) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_taxi_rounded, color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Text(S.activeRidesSection,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              if (active.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.kmOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${active.length}',
                      style: const TextStyle(
                          color: AppColors.kmOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (active.isEmpty)
            Text(S.noActiveRides,
                style:
                    const TextStyle(fontSize: 12.5, color: AppColors.kmMuted))
          else
            for (final r in active.take(3)) _activeRideRow(r),
          const SizedBox(height: 10),
          SecondaryButton(
            label: S.manageRides,
            icon: Icons.list_alt_rounded,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WorkerRequestsPage())),
          ),
        ],
      ),
    );
  }

  Widget _activeRideRow(Map<String, dynamic> d) {
    final service = (d['service'] ?? '').toString();
    final employer = (d['employerName'] ?? '').toString();
    final status = (d['status'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          ServiceGlyph(service: service, size: 18, color: AppColors.kmOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${S.serviceName(service)} · $employer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ),
          Text(status,
              style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.kmMuted,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _historyCard(List<Map<String, dynamic>> completed) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Text(S.recentHistorySection,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          if (completed.isEmpty)
            Text(S.noRideHistory,
                style:
                    const TextStyle(fontSize: 12.5, color: AppColors.kmMuted))
          else
            for (final d in completed.take(5)) _historyRow(d),
          const SizedBox(height: 10),
          SecondaryButton(
            label: S.viewFullHistory,
            icon: Icons.receipt_long_rounded,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EarningsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> d) {
    final service = (d['service'] ?? '').toString();
    final dt = _dateOf(d);
    final amount = _amountOf(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          ServiceGlyph(service: service, size: 18, color: AppColors.kmMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                '${S.serviceName(service)} · ${dt.day}/${dt.month}/${dt.year}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ),
          Text('Rs. ${amount.round()}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── ४. Earnings & Payouts Summary ────────────────────────────────────────
  Widget _earningsCard(List<Map<String, dynamic>> completed) {
    final now = DateTime.now();
    final gross = completed.fold<num>(0, (a, d) => a + _amountOf(d));
    final net = gross * (1 - PaymentConfig.commissionRate);
    final weekDocs = completed
        .where((d) => _dateOf(d).isAfter(now.subtract(const Duration(days: 7))))
        .toList();
    final weekGross = weekDocs.fold<num>(0, (a, d) => a + _amountOf(d));
    final weekNet = weekGross * (1 - PaymentConfig.commissionRate);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Text(S.earningsSummarySection,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statTile(S.walletBalance, 'Rs. ${net.round()}'),
              ),
              Expanded(
                child: _statTile(S.thisWeekLabel, 'Rs. ${weekNet.round()}'),
              ),
              Expanded(
                child: _statTile(S.jobsCompletedLabel, '${completed.length}'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: S.viewFullEarnings,
            icon: Icons.bar_chart_rounded,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EarningsScreen())),
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: S.walletLabel,
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.kmMuted)),
        ],
      );

  // ── ५. Profile & Document Status ─────────────────────────────────────────
  Widget _documentStatusCard(Map<String, dynamic> userData) {
    final status = (userData['verificationStatus'] ??
            userData['workerVerificationStatus'] ??
            '')
        .toString();
    final rejected = status == 'rejected';
    final approved = status == 'approved';
    final documentsPending = userData['documentsPending'] == true;

    final statusColor = approved
        ? AppColors.kmTeal
        : rejected
            ? AppColors.kmRose
            : AppColors.kmAmber;
    final statusLabel = approved
        ? S.statusApproved
        : rejected
            ? S.statusRejected
            : S.statusPending;

    DateTime? licenseExpiry;
    final rawExpiry = userData['licenseExpiryDate'];
    if (rawExpiry is String && rawExpiry.isNotEmpty) {
      licenseExpiry = DateTime.tryParse(rawExpiry);
    }
    final expiringSoon = licenseExpiry != null &&
        licenseExpiry.isAfter(DateTime.now()) &&
        licenseExpiry.difference(DateTime.now()).inDays < 30;
    final expired =
        licenseExpiry != null && licenseExpiry.isBefore(DateTime.now());

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(S.documentStatusSection,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(S.verificationStatusLabel,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.kmMuted)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ],
          ),
          if (rejected &&
              (userData['rejectionReason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${S.reasonLabel}: ${userData['rejectionReason']}',
                style: const TextStyle(fontSize: 12, color: AppColors.kmRose)),
          ],
          if (documentsPending) ...[
            const SizedBox(height: 8),
            Text(S.docsNotUploadedBody,
                style: const TextStyle(fontSize: 12, color: AppColors.kmMuted)),
          ],
          if (expired) ...[
            const SizedBox(height: 8),
            Text(S.licenseExpiredBanner,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.kmRose,
                    fontWeight: FontWeight.w700)),
          ] else if (expiringSoon) ...[
            const SizedBox(height: 8),
            Text(S.licenseExpiringSoon,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.kmAmber,
                    fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          SecondaryButton(
            label: S.updateDocuments,
            icon: Icons.upload_file_rounded,
            onPressed: () {
              if (rejected) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DriverRegistrationFlow()));
              } else {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DocumentResyncPage()));
              }
            },
          ),
        ],
      ),
    );
  }
}
