// screens/earnings_screen.dart
// कामदारको डिजिटल वालेट + आम्दानी विश्लेषण।
//  • वालेट ब्यालेन्स = कुल (net) आम्दानी  [gross − कमिसन]
//  • जम्मा / यो हप्ता / यो महिना toggle
//  • पछिल्ला ७ दिनको bar chart
//  • हरेक पूरा भएको कामको gross / कमिसन / net breakdown
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../worker_requests_page.dart';
import 'job_feed_screen.dart';
import 'nearby_common.dart';
import 'notification_screen.dart';

enum _Range { all, week, month }

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  _Range _range = _Range.all;

  // Stream-Identity Flicker Fix — यी दुई `.snapshots()` Stream पहिले
  // सिधै `build()` भित्रै (nested StreamBuilder को `stream:`) बनिन्थे।
  // outer (user doc) snapshot जहिले पनि नयाँ देखियो (जस्तै metadata-मात्र
  // sync event, walletBalance साँच्चै नबदलिए पनि) भने त्यसको `builder`
  // फेरि चल्छ, जसले भित्री (serviceRequests) Stream लाई फेरि नयाँ object
  // बनाउँथ्यो — `StreamBuilder` ले नयाँ Stream identity देख्नेबित्तिकै
  // पुरानो subscription त्यागेर `ConnectionState.waiting` मा फर्कन्छ
  // (फेरि पूरै स्क्रिन spinner देखाउने) अनि फेरि subscribe गर्छ — यही
  // नै "स्क्रिन निरन्तर फेरि-लोड/झिलिमिली भइरहने" गुनासोको साँचो जड
  // (request_tracking_screen.dart मा पहिल्यै उस्तै बग फेला परेर
  // fix भइसकेको, त्यही ढाँचा यहाँ पनि)। अब दुवै Stream `uid` साँच्चै
  // बदलिएको बेला (सामान्यतया लग-इनपछि एकपटक मात्र) बाहेक फेरि कहिल्यै
  // पुनः-निर्माण हुँदैनन्।
  String? _streamsForUid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;

  void _ensureStreamsFor(String uid) {
    if (_streamsForUid == uid && _userStream != null && _jobsStream != null) {
      return;
    }
    _streamsForUid = uid;
    _userStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    _jobsStream = FirebaseFirestore.instance
        .collection('serviceRequests')
        .where('workerUid', isEqualTo: uid)
        .snapshots();
  }

  DateTime _dateOf(Map<String, dynamic> d) {
    for (final k in ['completedAt', 'acceptedAt', 'createdAt']) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return DateTime.now();
  }

  num _amountOf(Map<String, dynamic> d) =>
      (d['finalPrice'] ?? d['proposedPrice'] ?? 0) as num;

  // `_confirm()` (complete_job_sheet.dart) ले हरेक completed job मा साँचो
  // `commissionAmount`/`workerPayoutAmount` लेखिसकेको हुन्छ (cash/QR मा
  // ०, company-collected eSewa/Khalti/Bank मा मात्र वास्तविक split) —
  // त्यही साँचो प्रति-job रेकर्ड पढ्ने, `PaymentConfig.commissionRate`
  // बाट हरेक job मा एकसमान/गलत रूपमा फेरि नगणना गर्ने (यसले पहिले cash
  // job मा पनि commission देखाउँथ्यो, जुन वास्तवमा कहिल्यै कटिँदैन)।
  // धेरै पुराना (यो field आउनुअघिकै) job मा भने fallback estimate।
  num _commissionOf(Map<String, dynamic> d) =>
      (d['commissionAmount'] as num?) ??
      (_amountOf(d) * PaymentConfig.commissionRate);
  num _netOf(Map<String, dynamic> d) =>
      (d['workerPayoutAmount'] as num?) ?? (_amountOf(d) - _commissionOf(d));

  String _paymentMethodLabel(Map<String, dynamic> d) {
    switch ((d['paymentMethod'] ?? '').toString()) {
      case 'cash':
        return S.cashPaymentLabel;
      case 'esewa':
        return S.payEsewa;
      case 'khalti':
        return S.payKhalti;
      case 'bank':
        return S.payBank;
      case 'qr':
        return S.payQr;
      default:
        return '';
    }
  }

  bool _inRange(DateTime dt) {
    final now = DateTime.now();
    switch (_range) {
      case _Range.all:
        return true;
      case _Range.week:
        return dt.isAfter(now.subtract(const Duration(days: 7)));
      case _Range.month:
        return dt.isAfter(DateTime(now.year, now.month - 1, now.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pct = (PaymentConfig.commissionRate * 100).round();
    if (uid != null) _ensureStreamsFor(uid);

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KmScreenHeader(
                  title: S.earningsTitle,
                  // Notifications/Requests Quick-Access — Profile →
                  // "{Service} Worker Dashboard" बटनले पहिले सिधै live-map
                  // job radar (JobFeedScreen) नै खोल्थ्यो। अब यो data-driven
                  // dashboard नै सिधै खुल्छ, त्यसैले notifications/requests
                  // हेर्ने छुट्टै बाटो यहीं चाहियो — driver_dashboard_screen.dart
                  // कै उस्तै AppBar notification-icon ढाँचा।
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded,
                          color: AppColors.kmText),
                      tooltip: S.menuNotifications,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(child: _findNearbyJobsCard(context)),
                    const SizedBox(width: 10),
                    Expanded(child: _myRequestsCard(context)),
                  ],
                ),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmMuted)))
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _userStream,
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() ?? {};
                          final walletBalance =
                              (userData['walletBalance'] as num?) ?? 0;
                          final myActiveJobId =
                              (userData['activeJobId'] ?? '').toString();
                          final myEligible =
                              (userData['isEligibleForJobs'] as bool?) ??
                                  true;
                          final myService = (userData['service'] ??
                                  userData['serviceType'] ??
                                  '')
                              .toString();
                          return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: _jobsStream,
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                    child: CircularProgressIndicator(
                                        color: AppColors.kmOrange));
                              }
                              final allDocs = snap.data?.docs ?? [];
                              // Prominent Incoming-Request Cards — पहिले
                              // employer ले सिधै यो worker लाई पठाएको काम
                              // (status == 'pending_worker') केवल silent
                              // push notification मात्र थियो, dashboard
                              // भित्र कतै देखिँदैनथ्यो — JobFeedScreen (map)
                              // खोलेमा मात्र भेटिने। अब dashboard कै सुरुमै
                              // (map नखोली नै) Accept/Decline सहित देखिन्छ —
                              // job_feed_screen.dart कै उही IncomingOfferOverlay
                              // कार्ड पुनः-प्रयोग गरेर।
                              final pendingOffers = allDocs
                                  .where((d) =>
                                      (d.data()['status'] ?? '').toString() ==
                                      'pending_worker')
                                  .toList();
                              final incomingCards = pendingOffers.isEmpty
                                  ? null
                                  : Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 14, 20, 0),
                                      child: Column(
                                        children: [
                                          for (final d in pendingOffers)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: IncomingOfferOverlay(
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
                                            ),
                                        ],
                                      ),
                                    );

                              final completed = allDocs
                                  .map((d) => d.data())
                                  .where((d) =>
                                      (d['status'] ?? '').toString() ==
                                      'completed')
                                  .toList()
                                ..sort(
                                    (a, b) => _dateOf(b).compareTo(_dateOf(a)));

                              if (completed.isEmpty) {
                                return incomingCards == null
                                    ? _empty()
                                    : Column(
                                        children: [
                                          incomingCards,
                                          Expanded(child: _empty()),
                                        ],
                                      );
                              }

                              final inRange = completed
                                  .where((d) => _inRange(_dateOf(d)))
                                  .toList();
                              final gross = inRange.fold<num>(
                                  0, (a, d) => a + _amountOf(d));
                              final commission = inRange.fold<num>(
                                  0, (a, d) => a + _commissionOf(d));
                              final net =
                                  inRange.fold<num>(0, (a, d) => a + _netOf(d));

                              // पछिल्ला ७ दिनको net (साँचो प्रति-job payout, cash/QR
                              // मा commission ० नै रहन्छ)
                              final today = DateTime.now();
                              final days = List.generate(7, (i) {
                                final day = DateTime(today.year, today.month,
                                    today.day - (6 - i));
                                return day;
                              });
                              final perDay = days.map((day) {
                                return completed.where((d) {
                                  final dt = _dateOf(d);
                                  return dt.year == day.year &&
                                      dt.month == day.month &&
                                      dt.day == day.day;
                                }).fold<num>(0, (a, d) => a + _netOf(d));
                              }).toList();

                              // 120Hz Performance — पहिले यहाँ plain
                              // `ListView(children: [...])` थियो, जसले
                              // scroll गर्नुअघि नै हरेक completed job को
                              // row एकैचोटि eagerly build गर्थ्यो (धेरै
                              // महिना/वर्ष काम गरिसकेको driver को हकमा
                              // सयौं row) — स्क्रोल गर्दा jank/frame-drop
                              // को मुख्य स्रोत हुन सक्थ्यो। अब
                              // `ListView.builder` ले स्क्रिनमा देखिने
                              // row मात्र lazily build गर्छ; माथिका fixed
                              // header widget (wallet card/chart/आदि)
                              // पहिलो १० index मै, बाँकी सबै job row lazy।
                              const headerCount = 11;
                              return ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 28),
                                itemCount: headerCount + inRange.length,
                                itemBuilder: (context, index) {
                                  switch (index) {
                                    case 0:
                                      return incomingCards ??
                                          const SizedBox.shrink();
                                    case 1:
                                      return _walletCard(net, gross, commission,
                                          pct, inRange.length);
                                    case 2:
                                      return const SizedBox(height: 14);
                                    case 3:
                                      return _SettlementCard(
                                          uid: uid,
                                          walletBalance: walletBalance);
                                    case 4:
                                      return const SizedBox(height: 14);
                                    case 5:
                                      return _rangeToggle();
                                    case 6:
                                      return const SizedBox(height: 16);
                                    case 7:
                                      return _chartCard(days, perDay);
                                    case 8:
                                      return const SizedBox(height: 16);
                                    case 9:
                                      return Text(S.perJobBreakdown,
                                          style: const TextStyle(
                                              color: AppColors.kmText,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15));
                                    case 10:
                                      return const SizedBox(height: 8);
                                    default:
                                      return _jobRow(
                                          inRange[index - headerCount]);
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // On-Demand Map Access — JobFeedScreen (live-map job radar) अघि यो
  // dashboard खोल्नु अघि नै देखिन्थ्यो; अब यहाँबाट मात्र — worker आफैं
  // यो कार्ड थिचेर — on-demand देखिन्छ। driver_dashboard_screen.dart कै
  // उस्तै कार्डको सानो (compact, 2-up row) संस्करण।
  Widget _findNearbyJobsCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const JobFeedScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.kmPurple, AppColors.kmPurpleDeep],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.kmGlassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_rounded, color: Colors.white, size: 22),
            const SizedBox(height: 6),
            // राइडर (Bike/Car/Auto) लाई "Rides", अरूलाई "Jobs"।
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userStream,
              builder: (_, snap) {
                final d = snap.data?.data() ?? {};
                final service =
                    (d['service'] ?? d['serviceType'] ?? '').toString();
                return Text(
                    S.isRideServiceName(service)
                        ? S.findNearbyRides
                        : S.findNearbyJobs,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.white));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _myRequestsCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WorkerRequestsPage()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.kmGlassFill,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.kmGlassBorder),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_rounded, color: AppColors.kmOrange, size: 22),
            SizedBox(height: 6),
            Text('My Requests',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.kmText)),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 60, color: AppColors.kmMuted),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(S.noEarningsYet,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.kmText)),
            ),
          ],
        ),
      );

  Widget _walletCard(num net, num gross, num commission, int pct, int jobs) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.kmOrange),
              const SizedBox(width: 8),
              Text(S.walletBalance,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.kmMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Rs. ${net.round()}',
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.kmText)),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat(S.grossEarnings, 'Rs. ${gross.round()}'),
              _miniStat(
                  S.commissionPctLabel(pct), '− Rs. ${commission.round()}'),
              _miniStat(S.jobsCompletedLabel, '$jobs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5)),
            Text(label,
                style:
                    const TextStyle(fontSize: 10.5, color: AppColors.kmMuted)),
          ],
        ),
      );

  Widget _rangeToggle() {
    Widget seg(String label, _Range r) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _range = r),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                gradient: _range == r ? AppColors.kmCtaGradient : null,
                color:
                    _range == r ? null : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _range == r ? AppColors.kmInk : AppColors.kmText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ),
        );
    return Row(
      children: [
        seg(S.allTime, _Range.all),
        const SizedBox(width: 8),
        seg(S.thisWeek, _Range.week),
        const SizedBox(width: 8),
        seg(S.thisMonth, _Range.month),
      ],
    );
  }

  Widget _chartCard(List<DateTime> days, List<num> perDay) {
    final maxV = perDay.fold<num>(1, (a, b) => b > a ? b : a);
    const wk = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.last7Days,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.kmMuted)),
          const SizedBox(height: 12),
          // Bottom-Overflow Fix — पहिले 120 थियो, जबकि सबैभन्दा अग्लो बार
          // (90, तलको Container height = 6 + 84) + spacing (6) ले नै ९६
          // ओगट्थ्यो, दुई text line (amount + weekday) का लागि जम्मा २४px
          // मात्र (प्रति-line १२px) बाँकी रहन्थ्यो — default font metric
          // सँगै नै निकै साँघुरो, अनि device को system font-scale १.0 भन्दा
          // अलिकति बढी भएमा (धेरै Android फोनमा सामान्य) तुरुन्तै "BOTTOM
          // OVERFLOWED BY 1.X PIXELS" देखिने/झिलिमिली हुने गुनासोको साँचो
          // जड। 136 ले प्रति-line १८px जति दिन्छ — सामान्य font-scale
          // भिन्नतामा पनि सुरक्षित।
          SizedBox(
            height: 136,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          perDay[i] > 0 ? perDay[i].round().toString() : '',
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.kmMuted),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 6 + (perDay[i] / maxV) * 84,
                          decoration: BoxDecoration(
                            gradient: AppColors.kmCtaGradient,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(wk[days[i].weekday % 7],
                            style: const TextStyle(
                                fontSize: 9.5, color: AppColors.kmMuted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobRow(Map<String, dynamic> d) {
    final gross = _amountOf(d);
    final commission = _commissionOf(d);
    final net = _netOf(d);
    final dt = _dateOf(d);
    final service = (d['service'] ?? '').toString();
    final methodLabel = _paymentMethodLabel(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        radius: AppRadius.md,
        child: Row(
          children: [
            ServiceIconBadge(
              service: service,
              size: 36,
              iconColor: AppColors.kmInk,
              gradient: AppColors.kmCtaGradient,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${S.serviceName(service)} · ${d['employerName'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(
                      commission > 0
                          ? '${dt.day}/${dt.month}/${dt.year}  ·  Rs. ${gross.round()} − ${commission.round()}'
                              '${methodLabel.isNotEmpty ? ' · $methodLabel' : ''}'
                          : '${dt.day}/${dt.month}/${dt.year}  ·  Rs. ${gross.round()}'
                              '${methodLabel.isNotEmpty ? ' · $methodLabel' : ''}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.kmMuted)),
                ],
              ),
            ),
            Text('Rs. ${net.round()}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: AppColors.kmTeal)),
          ],
        ),
      ),
    );
  }
}

/// साँचो Wallet & Commission Ledger (widgets/complete_job_sheet.dart::
/// _confirm() ले लेख्ने `users/{uid}.walletBalance` + `walletLedger`
/// collection) — worker ले आफ्नै settlement अवस्था (कति payout बाँकी छ,
/// वा कति commission तिर्न बाँकी छ) र हालैका unsettled entry हरू यहीँबाट
/// हेर्न सक्छ। Admin Settlement Dashboard (admin_settlement_screen.dart)
/// कै उस्तै data नै हो — फरक यत्ति: worker ले settle गर्न मिल्दैन (त्यो
/// admin-मात्र, firestore.rules मै लागू), हेर्न मात्र पाउँछ।
class _SettlementCard extends StatelessWidget {
  final String uid;
  final num walletBalance;
  const _SettlementCard({required this.uid, required this.walletBalance});

  String _typeLabel(String type) => switch (type) {
        'cash_commission_due' => 'Cash — commission owed',
        'p2p_commission_due' => 'QR (P2P) — commission owed',
        'online_payout_pending' => 'Online — payout pending',
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final owed = walletBalance < 0;
    final settled = walletBalance == 0;
    final statusColor = settled
        ? AppColors.kmMuted
        : (owed ? Colors.redAccent : AppColors.kmTeal);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Text(S.settlementStatusLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.kmMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            settled
                ? S.fullySettledLabel
                : (owed
                    ? S.youOwePlatformLabel((-walletBalance).round())
                    : S.payoutPendingLabel(walletBalance.round())),
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: statusColor),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('walletLedger')
                .where('workerUid', isEqualTo: uid)
                .where('settled', isEqualTo: false)
                .snapshots(),
            builder: (context, snap) {
              final entries = (snap.data?.docs ?? []).toList()
                ..sort((a, b) {
                  final at = a.data()['createdAt'];
                  final bt = b.data()['createdAt'];
                  if (at is Timestamp && bt is Timestamp) {
                    return bt.compareTo(at);
                  }
                  return 0;
                });
              if (entries.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(S.recentLedgerEntries,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.kmMuted)),
                  const SizedBox(height: 6),
                  for (final e in entries.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                _typeLabel((e.data()['type'] ?? '').toString()),
                                style: const TextStyle(
                                    fontSize: 11.5, color: AppColors.kmText)),
                          ),
                          Text(
                            'Rs. ${((e.data()['amount'] as num?) ?? 0).abs().round()}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.kmMuted),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
