// worker_requests_page.dart
// कामदारको "अनुरोध" tab — आफूले लिएका / bid गरेका कामहरू मात्र।
//  • pending_worker (सिधा अनुरोध) → यही मूल्यमा Accept वा मूल्य बदल्ने
//  • pending_employer_approval → ग्राहकको जवाफ पर्खँदै
//  • accepted / confirmed → सक्रिय काम (Message + स्थान हेर्ने)
// नयाँ खुला कामहरू "कामको सूची" (JobFeedScreen) मा देखिन्छन्।
// कुनै live location tracking छैन (ride-style हटाइयो)।
import 'utils/price_input.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/strings.dart';
import 'screens/chat_screen.dart';
import 'screens/earnings_screen.dart';
import 'screens/job_actions.dart';
import 'screens/job_feed_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/wallet_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';
import 'widgets/counter_offer_card.dart';
import 'widgets/futuristic_ui.dart';
import 'widgets/glass_ui.dart';
import 'widgets/status_badge.dart';
import 'widgets/skeleton.dart';

class WorkerRequestsPage extends StatefulWidget {
  const WorkerRequestsPage({super.key});

  @override
  State<WorkerRequestsPage> createState() => _WorkerRequestsPageState();
}

class _WorkerRequestsPageState extends State<WorkerRequestsPage> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  // stream एकपटक मात्र — tab फर्किंदा spinner नआओस्; sort client-side।
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('workerUid', isEqualTo: _uid)
          .snapshots();

  // Single Active Job Restriction — Accept/Offer बटन देखाउनुअघि हाल कुनै
  // अर्को काम accepted/confirmed/in_progress छ कि भनेर live जाँच्ने।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? '__none__')
          .snapshots();

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    // Ride vs Job Terminology — राइड-मात्र ड्राइभरलाई
                    // "Job requests" भन्दा "Ride requests" बुझ्न सजिलो
                    // (`main_container.dart::_isRideDriver` कै उस्तै
                    // self-profile service जाँच, यहाँ _userStream बाट)।
                    Expanded(
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _userStream,
                        builder: (context, snap) {
                          final myService = (snap.data?.data()?['service'] ??
                                  snap.data?.data()?['serviceType'] ??
                                  '')
                              .toString();
                          final isRideDriver = myService == 'Bike' ||
                              myService == 'Car' ||
                              myService == 'Auto';
                          return KmScreenHeader(
                              title: isRideDriver
                                  ? S.rideRequests
                                  : S.jobRequests);
                        },
                      ),
                    ),
                    GlassIconButton(
                      icon: Icons.calendar_month_rounded,
                      tooltip: S.scheduleTitle,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ScheduleScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: Icons.account_balance_wallet_rounded,
                      tooltip: S.earningsTitle,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EarningsScreen()),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Login गर्नुहोस्',
                            style: TextStyle(color: AppColors.kmText)))
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _userStream,
                        builder: (context, userSnap) {
                          final myActiveJobId =
                              (userSnap.data?.data()?['activeJobId'] ?? '')
                                  .toString();
                          final myWalletBlocked =
                              (userSnap.data?.data()?['isEligibleForJobs']
                                      as bool?) ==
                                  false;
                          return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: _stream,
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return const SkeletonList();
                              }
                              final docs = (snap.data?.docs ?? [])
                                  .where((d) {
                                    final status =
                                        (d.data()['status'] ?? '').toString();
                                    if (!kStaleTerminalJobStatuses
                                        .contains(status)) {
                                      return true;
                                    }
                                    final createdAt = d.data()['createdAt'];
                                    if (createdAt is! Timestamp) return true;
                                    return DateTime.now()
                                            .difference(createdAt.toDate()) <
                                        kDashboardStaleAfter;
                                  })
                                  .toList()
                                ..sort((a, b) {
                                  // ग्राहकले पठाएको live counter-offer सधैँ
                                  // सबैभन्दा माथि।
                                  final pa = a.data()['status'] ==
                                          'pending_worker_counter'
                                      ? 0
                                      : 1;
                                  final pb = b.data()['status'] ==
                                          'pending_worker_counter'
                                      ? 0
                                      : 1;
                                  if (pa != pb) return pa - pb;
                                  final ta = a.data()['createdAt'];
                                  final tb = b.data()['createdAt'];
                                  if (ta is Timestamp && tb is Timestamp) {
                                    return tb.compareTo(ta);
                                  }
                                  return 0;
                                });

                              if (docs.isEmpty) {
                                return const _EmptyState();
                              }

                              return ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 24),
                                itemCount: docs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) => _RequestCard(
                                  key: ValueKey(docs[i].id),
                                  docId: docs[i].id,
                                  data: docs[i].data(),
                                  blockedByOtherActiveJob:
                                      myActiveJobId.isNotEmpty &&
                                          myActiveJobId != docs[i].id,
                                  walletBlocked: myWalletBlocked,
                                ),
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_outlined,
                size: 60, color: AppColors.kmMuted),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(S.onlineForJobs,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.kmText)),
            ),
          ],
        ),
      );
}

class _RequestCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  // Single Active Job Restriction — true भए यो worker सँग हाल यो बाहेक अर्को
  // साँच्चै सक्रिय (accepted/confirmed/in_progress) काम छ; Accept/Offer बटन
  // देखाउनुको सट्टा "पहिले हालको काम सक्नुहोस्" भन्ने सूचना देखिन्छ।
  final bool blockedByOtherActiveJob;
  // Wallet Commission Debt Gate — job_feed_screen.dart::_IncomingOfferOverlay
  // कै उस्तै — true भए unpaid commission debt threshold भन्दा बढी भएकोले
  // Accept/Offer बटनको साटो "Top Up" सूचना देखिन्छ।
  final bool walletBlocked;
  const _RequestCard({
    super.key,
    required this.docId,
    required this.data,
    this.blockedByOtherActiveJob = false,
    this.walletBlocked = false,
  });

  Future<void> _callEmployer(BuildContext context) async {
    final phone = (data['employerPhone'] ?? '').toString().trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.noPhoneOnFile)));
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  Future<void> _acceptAtListedPrice(BuildContext context, num price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await claimJobForWorker(
        docId: docId,
        workerUid: uid,
        updateFields: {
          'status': 'accepted',
          'finalPrice': price,
          'acceptedAt': FieldValue.serverTimestamp(),
          // employer ले Call थिच्दा नम्बर भेट्टाओस् भनेर — पहिले यहाँ
          // कहिल्यै लेखिँदैनथ्यो, त्यसैले accepted भइसकेपछि पनि "no phone
          // on file" देखिन्थ्यो।
          'workerPhone': await myPhoneNumber(uid),
          // route-map तुरुन्तै काम गरोस् भनेर accept गर्ने क्षणमै worker को
          // स्थान लेख्ने — job_actions.dart कै साझा function (JobRouteScreen
          // खोलेपछि मात्र पर्खनुपर्दैन)।
          ...await workerLocationForWrite(uid),
        },
      );
      messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));
      // MainContainer कै active-job watcher ले यो status बदलिएको देखेर आफैं
      // route screen खोल्छ — यहाँबाट छुट्टै नखोल्ने (double-open नहोस् भनेर)।
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  Future<void> _counterDialog(BuildContext context, num current) async {
    final controller = TextEditingController(text: current.toString());
    // Dead Send/Cancel Fix — यो dialog खोल्ने caller प्रायः job-card को
    // context हो, जुन त्यही tap मा चलेको Auto-Dismiss ले dialog खुल्नेबित्तिकै
    // disposed हुन्छ। पहिले यहाँ केवल `if (!context.mounted) return;` गार्ड
    // थपिएको थियो (crash त रोकियो, तर Send/Cancel दुवै चुपचाप केही नगरी
    // "dead/frozen" देखिने साइड-इफेक्ट आयो)। nearby_common.dart::_send() कै
    // उस्तै साँचो fix — context होइन, सधैं mounted रहने NavigatorState/
    // ScaffoldMessengerState नै dialog खोल्नुअघि नै समातेर राख्ने।
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    await showKmDialog(
      context: context,
      title: 'नयाँ मूल्य प्रस्ताव गर्नुहोस्',
      icon: Icons.price_change_rounded,
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: AppColors.kmText),
        decoration: kmInputDecoration('तपाईंको मूल्य (Rs.)'),
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
          onPressed: () async {
            final newPrice = parseSanePrice(controller.text);
            if (newPrice == null) return;
            if (!navigator.mounted) return;
            navigator.pop();
            try {
              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'status': 'pending_employer_approval',
                'workerCounterPrice': newPrice,
                'counterFrom': 'worker',
                'counteredAt': FieldValue.serverTimestamp(),
              });
              messenger.showSnackBar(
                const SnackBar(content: Text('नयाँ मूल्य ग्राहकलाई पठाइयो।')),
              );
            } catch (e) {
              if (!navigator.mounted) return;
              messenger.showSnackBar(offerErrorSnackBar(navigator.context, e));
            }
          },
        ),
      ],
    );
  }

  // ── ग्राहकको live counter-offer मा जवाफ ─────────────────────
  Future<void> _acceptEmployerCounter(BuildContext context, num price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await claimJobForWorker(
        docId: docId,
        workerUid: uid,
        updateFields: {
          'status': 'accepted',
          'finalPrice': price,
          'acceptedAt': FieldValue.serverTimestamp(),
          'workerPhone': await myPhoneNumber(uid),
          ...await workerLocationForWrite(uid),
        },
      );
      messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));
      // MainContainer कै active-job watcher ले यो status बदलिएको देखेर आफैं
      // route screen खोल्छ — यहाँबाट छुट्टै नखोल्ने (double-open नहोस् भनेर)।
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  Future<void> _declineFromCounter(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(docId)
          .update({
        'status': 'declined',
        'declinedAt': FieldValue.serverTimestamp(),
      });
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(S.decline), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  /// "Decline / Counter back" — कामदारले आफ्नो नयाँ मूल्य ग्राहकलाई फिर्ता
  /// पठाउँछ, वा काम अस्वीकार गर्छ।
  Future<void> _counterBackToEmployer(BuildContext context, num current) async {
    final controller = TextEditingController(text: current.toString());
    // Dead Send/Cancel Fix — माथि _counterDialog() कै उस्तै जड/fix: context
    // होइन, सधैं mounted रहने NavigatorState/ScaffoldMessengerState नै
    // dialog खोल्नुअघि नै समातेर राख्ने।
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
            _declineFromCounter(navigator.context);
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
              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'status': 'pending_employer_approval',
                'workerCounterPrice': newPrice,
                'counterFrom': 'worker',
                'counteredAt': FieldValue.serverTimestamp(),
              });
              messenger.showSnackBar(
                SnackBar(content: Text(S.newPriceSentToCustomer)),
              );
            } catch (e) {
              if (!navigator.mounted) return;
              messenger.showSnackBar(offerErrorSnackBar(navigator.context, e));
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending_worker').toString();
    final service = (data['service'] ?? '').toString();
    // Ride vs Job Terminology — ride (Bike/Car) item मा "Job"/"काम" भन्दा
    // "Ride"/"राइड" बुझ्न सजिलो, सामान्य job-portal (plumber/electrician)
    // item मा भने पहिलेकै "Job" terminology यथावत्।
    final isRide =
        service == 'Bike' || service == 'Car' || service == 'Auto';
    final price = data['proposedPrice'] ?? 0;
    final desc = (data['details'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final lat = (data['employerLat'] as num?)?.toDouble();
    final lng = (data['employerLng'] as num?)?.toDouble();
    final employer = (data['employerName'] ?? 'Customer').toString();
    final active = status == 'accepted' ||
        status == 'confirmed' ||
        status == 'in_progress';

    // ग्राहकले मूल्य काउन्टर गरेको छ → सामान्य कार्डको सट्टा high-impact
    // animated alert देखाउने। Single Active Job Restriction — यहाँ पनि
    // `pending_worker` (सूचीबद्ध मूल्य) बाटो जस्तै worker सँग हाल अर्को
    // साँच्चै सक्रिय काम भए Accept/Counter-back बटनको सट्टा स्पष्ट सूचना
    // देखाउने (नत्र ट्याप गर्दा ripple देखिएर पनि transaction भित्रैको
    // guard ले चुपचाप रोक्थ्यो — click "dead" जस्तो देखिने गुनासोको जड)।
    if (status == 'pending_worker_counter') {
      if (blockedByOtherActiveJob) {
        return NeonCard(
          radius: 24,
          padding: const EdgeInsets.all(16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.kmRose.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_rounded,
                    size: 14, color: AppColors.kmRose),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(S.finishCurrentJobFirst,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.kmRose)),
                ),
                const TestingClearActiveJobButton(),
              ],
            ),
          ),
        );
      }
      if (walletBlocked) {
        return NeonCard(
          radius: 24,
          padding: const EdgeInsets.all(16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.kmRose.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    size: 14, color: AppColors.kmRose),
                const SizedBox(width: 6),
                Flexible(
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
          ),
        );
      }
      final prev =
          (data['workerCounterPrice'] ?? data['proposedPrice'] ?? 0) as num;
      final theirOffer = (data['employerCounterPrice'] ?? 0) as num;
      return CounterOfferCard(
        heading: '$employer  ·  ${S.serviceName(service)}',
        previousPrice: prev,
        newPrice: theirOffer,
        onAccept: () => _acceptEmployerCounter(context, theirOffer),
        onCounterBack: () => _counterBackToEmployer(context, prev),
      );
    }

    return NeonCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active) ...[
            Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 15, color: AppColors.kmOrange),
                const SizedBox(width: 4),
                Text(isRide ? S.activeRideTitle : S.activeJobTitle,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.kmOrange)),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: Text('$employer  ·  ${S.serviceName(service)}',
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              StatusBadge(status: status),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc,
                style: const TextStyle(color: AppColors.kmMuted, fontSize: 13)),
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
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.kmMuted)),
                ),
              ],
            ),
          ],
          // काम स्वीकार भइसकेपछि ग्राहकको फोन नम्बर सिधै देखिने — Call
          // बटन थिच्नुअघि नै थाहा होस्, लुकेको बटनमा मात्र सीमित नराखी।
          if (active &&
              (data['employerPhone'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _callEmployer(context),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded,
                      size: 14, color: AppColors.kmOrange),
                  const SizedBox(width: 4),
                  Text((data['employerPhone']).toString().trim(),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.kmOrange)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          // काम पहिल्यै confirm भइसकेपछि (finalPrice सेट भइसकेपछि) त्यही
          // अन्तिम/सहमत मूल्य मात्र देखाउने — प्रस्तावित मूल्य र (भए) आफ्नै
          // counter मूल्य दुवै अब इतिहास मात्र हुन् (Uber जस्तै, अहिलेकै
          // भाडा मात्र देखिने, त्यो कसरी सहमत भयो भन्ने history होइन)।
          if (data['finalPrice'] != null)
            Text('मूल्य: Rs. ${data['finalPrice']}',
                style: const TextStyle(
                    color: AppColors.kmTeal, fontWeight: FontWeight.w700))
          else ...[
            Text('प्रस्तावित मूल्य: Rs. $price',
                style: const TextStyle(
                    color: AppColors.kmText, fontWeight: FontWeight.w700)),
            if (data['workerCounterPrice'] != null)
              Text('तपाईंको मूल्य: Rs. ${data['workerCounterPrice']}',
                  style: const TextStyle(
                      color: AppColors.kmOrange, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (active)
                GradientActionButton(
                  icon: Icons.call_rounded,
                  label: S.callWord,
                  onPressed: () => _callEmployer(context),
                ),
              // सक्रिय काम (accept भइसकेको) भए — साझा RouteMapView कै
              // JobRouteScreen (सडक मार्ग + दूरी/समय + live tracking), स्थिर
              // pin मात्र देखाउने पुरानो JobLocationScreen होइन। अझै स्वीकार
              // नगरेको (browsing मात्र) भए स्थिर pin नै ठीक हो।
              if (active && lat != null && lng != null)
                GradientActionButton(
                  icon: Icons.route_rounded,
                  // Ride (Bike/Car) मा राइड अझै सुरु नभएसम्म (OTP/arrival
                  // अझै बाँकी) यही बटनले नै "Start Ride" देखाउँछ — तलको
                  // छुट्टै `_startWork` बटन (OTP बिना सिधै status
                  // 'in_progress' लेख्ने) ride मा कहिल्यै देखिँदैन (तल हेर्नुहोस्)।
                  // यही बटनले सधैँ `openJobRoute` खोल्छ, जहाँ arrival-confirm
                  // + ४-अंक OTP मिलेपछि मात्र साँच्चै राइड सुरु हुन्छ।
                  label: (isRide && status != 'in_progress')
                      ? S.startRideLabel
                      : S.viewJobLocation,
                  onPressed: () => openJobRoute(context, docId, data),
                )
              else if (status != 'completed' && lat != null && lng != null)
                GradientActionButton(
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
              // काम completed भइसकेपछि live location/message दुवै हट्छन् —
              // Post-Completion: History मा मात्र बस्छ (माथिको card नै त्यो
              // record हो — StatusBadge + अन्तिम मूल्य)।
              if (active)
                GradientActionButton(
                  icon: Icons.chat_bubble_rounded,
                  label: S.messageWord,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        requestId: docId,
                        workerName: employer,
                        initialStatus: status,
                      ),
                    ),
                  ),
                ),
              // Arrival-Gated Start Work — यो बटन अब यहाँ छैन। "Start Work"
              // अब JobRouteScreen (live tracking) मा मात्र, worker साँच्चै
              // काम-स्थलमा पुगेर "On Arrival" confirm गरेपछि मात्र देखिन्छ
              // (job_route_screen.dart::_startWork हेर्नुहोस्) — पहिले यहाँ
              // accepted/confirmed हुनासाथै (कुनै arrival/geofence जाँच
              // बिना) सिधै status 'in_progress' लेखिने बाइपास बटन थियो।
              // Job Completion & Rating Control — worker होइन, EMPLOYER ले
              // मात्र काम completed मार्क गर्न सक्छ (नगद कारोबार दुवैबीचै
              // प्रत्यक्ष हुने भएकोले)। worker ले यहाँ केवल पर्खनुपर्छ।
              if (status == 'in_progress')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.kmOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          size: 14, color: AppColors.kmOrange),
                      const SizedBox(width: 6),
                      Text(S.waitingEmployerComplete,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.kmOrange)),
                    ],
                  ),
                ),
              // Single Active Job Restriction — worker सँग हाल अर्को साँच्चै
              // सक्रिय काम भए Accept/Offer बटनको सट्टा स्पष्ट सूचना, ताकि
              // व्यवहारमा कहिल्यै दुई सक्रिय काम एकैचोटि नहोस्।
              if (status == 'pending_worker' && blockedByOtherActiveJob)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.kmRose.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_clock_rounded,
                          size: 14, color: AppColors.kmRose),
                      const SizedBox(width: 6),
                      Text(S.finishCurrentJobFirst,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.kmRose)),
                      const TestingClearActiveJobButton(),
                    ],
                  ),
                )
              else if (status == 'pending_worker' && walletBlocked)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.kmRose.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded,
                          size: 14, color: AppColors.kmRose),
                      const SizedBox(width: 6),
                      Text(S.walletBlockedWarning,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.kmRose)),
                      TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const WalletScreen())),
                        child: Text(S.topUpLabel),
                      ),
                    ],
                  ),
                )
              else if (status == 'pending_worker') ...[
                // Three-Choice Request Response — पहिले यहाँ Accept/Offer
                // Price मात्र थिए, स्पष्ट "Decline" बटन नै थिएन (counter-
                // offer चरणमा मात्र, dialog भित्र लुकेको थियो)। नयाँ, अझै
                // निर्णय नलिएको direct-offer अनुरोधमा पनि Accept/Decline/
                // Counter Offer तीनै सुरुदेखि नै स्पष्ट देखियोस् भनेर।
                OutlinedButton(
                  onPressed: () => _declineFromCounter(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  child: Text(S.decline),
                ),
                OutlinedButton(
                  onPressed: () => _counterDialog(context, price),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.kmOrange,
                    side: const BorderSide(color: AppColors.kmOrange),
                  ),
                  child: Text(S.offerPrice),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kmTeal,
                      foregroundColor: AppColors.kmInk),
                  onPressed: () => _acceptAtListedPrice(context, price),
                  child: Text(S.accept),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
