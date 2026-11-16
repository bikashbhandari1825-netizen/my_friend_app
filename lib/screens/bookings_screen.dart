// screens/bookings_screen.dart
import '../utils/price_input.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hotel_mock_data.dart' show mockHotels, mockRooms;
import '../l10n/strings.dart';
import '../models/hotel_models.dart';
import '../services/hotel_booking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/complete_job_sheet.dart';
import '../widgets/counter_offer_card.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/status_badge.dart';
import 'chat_screen.dart';
import 'hotel_booking_pass_screen.dart';
import 'hotel_common.dart' show formatHotelPrice;
import 'job_actions.dart';
import 'request_tracking_screen.dart';
import '../widgets/skeleton.dart';

// 9. Bookings Screen (Firestore सँग जोडिएको, Counter-offer Accept/Decline सहित)
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  // Active/Pending List Flicker Fix — पहिले यो स्क्रिन `StatelessWidget`
  // थियो, र दुवै live stream (`myHotelBookings()` र serviceRequests कै
  // `.snapshots()`) सिधै `build()` भित्रै (हरेक पटक, outer hotel-booking
  // StreamBuilder फेरि emit हुँदा समेत) ताजा बनिन्थे। `StreamBuilder` ले
  // फरक (नयाँ) `Stream` instance पाएपछि पुरानो listener तुरुन्तै unlisten
  // गरेर नयाँ फेरि listen गर्छ — त्यो क्षणभर `ConnectionState.waiting` मा
  // फर्केर पूरै list स्पिनरमा बदलिन्छ, अनि डेटा आएपछि फेरि देखिन्छ —
  // ठ्याक्कै "हरेक केही सेकेन्डमा ब्लिंक/फ्ल्यास" गुनासोको साँचो जड (उस्तै
  // root cause request_tracking_screen.dart मा पहिल्यै फेला परेर fix
  // भइसकेको, हेर्नुहोस् त्यहाँको "Firestore Internal Assertion Failed Fix"
  // doc-comment)। अब दुवै stream widget जीवनभर एकपटक मात्र (`initState`)
  // बन्छन् — screen बन्द नभएसम्म कहिल्यै फेरि listen/unlisten हुँदैन।
  String? _uid;
  late final Stream<List<HotelBooking>> _hotelBookingsStream;
  Stream<QuerySnapshot>? _serviceRequestsStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _uid = uid;
    _hotelBookingsStream = myHotelBookings();
    if (uid != null) {
      _serviceRequestsStream = FirebaseFirestore.instance
          .collection('serviceRequests')
          .where('employerUid', isEqualTo: uid)
          .snapshots();
    }
  }

  // post-acceptance flow (transaction + agreedAmount/acceptedAt + worker लाई
  // notification) `job_actions.dart` को साझा function मार्फत — यहाँ र
  // request_tracking_screen.dart दुवैले उही एउटा logic प्रयोग गर्छन्।
  Future<void> _acceptCounterOffer(BuildContext context, String docId) =>
      acceptWorkerCounterOffer(context, docId);

  /// ग्राहकले कामदारको मूल्यमाथि आफ्नो नयाँ मूल्य फिर्ता पठाउने। यसले
  /// कामदारको स्क्रिनमा live animated counter-offer alert देखाउँछ।
  Future<void> _counterOfferToWorker(
      BuildContext context, String docId, num current) async {
    final controller = TextEditingController(text: current.toString());
    // Dead Send/Cancel Fix — यो `context` एउटा live StreamBuilder row
    // (booking list item) कै हो — job_actions.dart::counterDirectOffer/
    // counterBroadcastJob र request_tracking_screen.dart::
    // _counterBackToWorker कै उस्तै साँचो जड: dialog खुलिरहेको बेला (मूल्य
    // टाइप गर्दै) त्यो row पछिको snapshot मा हराए/rebuild भए यो context
    // unmounted हुन्छ — `context.mounted` जाँचले मात्रै पुग्दैन, पहिले नै
    // "no-op" भएर Send/Cancel दुवै "dead/frozen" देखिन्थे। अब context
    // होइन, सधैं mounted रहने NavigatorState/ScaffoldMessengerState नै
    // dialog खोल्नुअघि नै समातेर राख्ने।
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    await showKmDialog(
      context: context,
      title: 'नयाँ मूल्य प्रस्ताव गर्नुहोस्',
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
            _declineRequest(context, docId);
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

  Future<void> _declineRequest(BuildContext context, String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(docId)
          .update({'status': 'declined'});
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Request अस्वीकृत गरियो।'),
            backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(offerErrorSnackBar(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return DefaultTabController(
      length: 2,
      child: OledBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: KmScreenHeader(title: 'My Bookings & Requests'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: GlassPanel(
                    radius: 22,
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      dividerColor: Colors.transparent,
                      labelColor: AppColors.kmInk,
                      unselectedLabelColor: AppColors.kmMuted2,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.kmText,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      tabs: const [
                        Tab(text: 'Active/Pending'),
                        Tab(text: 'Completed'),
                      ],
                    ),
                  ),
                ),
                Expanded(child: _bookingsBody(uid)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hotel Booking Pass & QR Visibility — "My Bookings" मा देखिने hotel
  /// card ट्याप गर्दा पूरा Booking Pass/QR screen खोल्ने। `myHotelBookings()`
  /// ले `HotelBooking` मात्र दिने भएकोले (Hotel/HotelRoom resolve नगरिएको),
  /// पहिले in-memory `mockHotels`/`mockRooms` (तुरुन्तै, धेरै अवस्थामा
  /// पहिल्यै hydrate भइसकेको) मा खोज्ने — नभेटे मात्र (guest यो session मा
  /// कहिल्यै search/partner-dashboard नखोलेको भए) Firestore बाट सिधै।
  Future<void> _openHotelBookingPass(
      BuildContext context, HotelBooking booking) async {
    Hotel? hotel;
    for (final h in mockHotels) {
      if (h.id == booking.hotelId) hotel = h;
    }
    HotelRoom? room;
    for (final r in mockRooms) {
      if (r.id == booking.roomId) room = r;
    }
    if (hotel == null) {
      final doc = await FirebaseFirestore.instance
          .collection('hotels')
          .doc(booking.hotelId)
          .get();
      if (doc.exists) hotel = Hotel.fromDoc(doc);
    }
    if (room == null) {
      final doc = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(booking.roomId)
          .get();
      if (doc.exists) room = HotelRoom.fromDoc(doc);
    }
    if (!context.mounted) return;
    if (hotel == null || room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Couldn't load this booking's details.")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HotelBookingPassScreen(booking: booking, hotel: hotel!, room: room!),
      ),
    );
  }

  Widget _bookingsBody(String? uid) {
    // दुवै tab (Active/Pending, Completed) ले उही `employerUid == uid`
    // query हो — पहिले tab-पिच्छे आफ्नै छुट्टै StreamBuilder (आफ्नै
    // छुट्टै live listener + बारम्बार उही पूरा history डाउनलोड) थियो,
    // दुवै सधैँ एकैचोटि subscribe भइरहन्थे (TabBarView ले दुवै tab
    // सुरुमै build गर्छ) — एउटै डेटा दोब्बर पटक तानिने। अब एउटै
    // बाहिरी StreamBuilder ले एकपटक मात्र सुन्ने, दुवै tab ले त्यही
    // snapshot बाँड्ने। धेरै हजार user ले एकैचोटि यो खोल्दा Firestore
    // bandwidth/listener गन्ती आधाभन्दा बढी घट्छ। Hotel Booking Visibility
    // — त्यही साझा-listener pattern मै `myHotelBookings()` पनि थपिएको, एउटा
    // थप बाहिरी StreamBuilder तर दुवै tab ले उही hotel-booking list बाँड्ने।
    return uid == null
        ? const Center(
            child: Text('Login गर्नुहोस्',
                style: TextStyle(color: AppColors.kmText)))
        : StreamBuilder<List<HotelBooking>>(
            stream: _hotelBookingsStream,
            builder: (context, hotelSnap) {
              final hotelBookings = hotelSnap.data ?? const <HotelBooking>[];
              return _serviceRequestsBody(uid, hotelBookings);
            },
          );
  }

  Widget _serviceRequestsBody(String uid, List<HotelBooking> hotelBookings) {
    return StreamBuilder<QuerySnapshot>(
            stream: _serviceRequestsStream,
            builder: (context, outerSnapshot) {
              return TabBarView(
                children: [
                  // Tab 1: Active/Pending
                  Builder(builder: (context) {
                    final snapshot = outerSnapshot;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SkeletonList();
                    }
                    final allDocs = snapshot.data?.docs ?? [];
                    final docs = allDocs.where((d) {
                      final status =
                          (d.data() as Map<String, dynamic>)['status'];
                      return status != 'declined' &&
                          status != 'cancelled' &&
                          status != 'completed';
                    }).toList()
                      // कामदारको नयाँ counter-offer (जवाफ चाहिने) सधैँ माथि।
                      ..sort((a, b) {
                        final sa = (a.data() as Map<String, dynamic>)['status'];
                        final sb = (b.data() as Map<String, dynamic>)['status'];
                        final pa = sa == 'pending_employer_approval' ? 0 : 1;
                        final pb = sb == 'pending_employer_approval' ? 0 : 1;
                        return pa - pb;
                      });

                    // Hotel Booking Pass & QR Visibility — Active/Pending
                    // tab मा हालसम्म अझै stay सकिएको hotel booking (checked-
                    // in सम्मका) पनि सँगै, ride/job booking कै उस्तै tap-
                    // to-open card को रूपमा।
                    final activeHotel = hotelBookings
                        .where((b) =>
                            b.status != HotelBookingStatus.completed &&
                            b.status != HotelBookingStatus.cancelled &&
                            b.status != HotelBookingStatus.noShow)
                        .toList();

                    if (docs.isEmpty && activeHotel.isEmpty) {
                      return const Center(
                          child: Text('No active bookings yet',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      itemCount: activeHotel.length + docs.length,
                      itemBuilder: (context, rawIndex) {
                        if (rawIndex < activeHotel.length) {
                          return Padding(
                            key: ValueKey(activeHotel[rawIndex].id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _HotelBookingCard(
                              booking: activeHotel[rawIndex],
                              onTap: () => _openHotelBookingPass(
                                  context, activeHotel[rawIndex]),
                            ),
                          );
                        }
                        final index = rawIndex - activeHotel.length;
                        final data = docs[index].data() as Map<String, dynamic>;
                        final docId = docs[index].id;
                        final status =
                            (data['status'] ?? 'pending_worker').toString();
                        final proposedPrice = data['proposedPrice'] ?? 0;
                        final counterPrice = data['workerCounterPrice'];
                        final employerCounter = data['employerCounterPrice'];

                        // कामदारले मूल्य काउन्टर गर्‍यो → सामान्य कार्डको सट्टा
                        // high-impact animated CounterOfferCard। "previous" =
                        // ग्राहकको आफ्नै पछिल्लो प्रस्ताव — पहिलो round मा
                        // proposedPrice, त्यसपछि भने employerCounterPrice
                        // (नत्र round 2+ मा सधैँ मूल budget मात्र देखिन्थ्यो,
                        // असीमित counter-offer round सहीसँग नदेखिने bug)।
                        if (status == 'pending_employer_approval') {
                          final prevRaw = employerCounter ?? proposedPrice;
                          final prev = prevRaw is num
                              ? prevRaw
                              : num.tryParse('$prevRaw') ?? 0;
                          final theirOffer = counterPrice is num
                              ? counterPrice
                              : num.tryParse('$counterPrice') ?? prev;
                          return Padding(
                            // list सधैँ पछिल्लो status अनुसार पुनः-क्रमबद्ध
                            // हुन्छ, र यो item त्यही index मा फरक widget
                            // (CounterOfferCard ⇄ सामान्य Card) मा बदलिन
                            // सक्छ — docId कै key नभए Flutter ले element
                            // गलत item सँग जोड्न सक्छ (negotiation छिटो
                            // बदलिँदा देखिने असीमित counter-offer flow मा
                            // विशेष गरी)।
                            key: ValueKey(docId),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: CounterOfferCard(
                              heading:
                                  '${data['workerName'] ?? 'Worker'}  ·  ${S.serviceName((data['service'] ?? '').toString())}',
                              title: S.workerCounteredTitle,
                              body: S.workerCounteredBody,
                              previousPrice: prev,
                              newPrice: theirOffer,
                              acceptLabel: S.acceptCounterOffer,
                              onAccept: () =>
                                  _acceptCounterOffer(context, docId),
                              onCounterBack: () => _counterOfferToWorker(
                                  context, docId, theirOffer),
                            ),
                          );
                        }

                        final canTrack = status == 'broadcasting' ||
                            status == 'accepted' ||
                            status == 'confirmed' ||
                            status == 'in_progress';

                        final isActive = status == 'accepted' ||
                            status == 'confirmed' ||
                            status == 'in_progress';
                        return Padding(
                          key: ValueKey(docId),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NeonCard(
                            radius: 24,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isActive) ...[
                                  Row(
                                    children: [
                                      const Icon(Icons.bolt_rounded,
                                          size: 15, color: AppColors.kmOrange),
                                      const SizedBox(width: 4),
                                      Text(
                                          (data['service'] == 'Bike' ||
                                                  data['service'] == 'Car' ||
                                                  data['service'] == 'Auto')
                                              ? S.activeRideTitle
                                              : S.activeJobTitle,
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
                                      child: Text(
                                        '${data['workerName'] ?? 'Worker'} (${data['service'] ?? ''})',
                                        style: const TextStyle(
                                          color: AppColors.kmText,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    StatusBadge(status: status),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('विवरण: ${data['details'] ?? ''}',
                                    style: const TextStyle(
                                        color: AppColors.kmMuted)),
                                Text('सुरुको मूल्य: Rs. $proposedPrice',
                                    style: const TextStyle(
                                        color: AppColors.kmMuted)),
                                if (status == 'pending_worker_counter') ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'तपाईंको प्रस्ताव: Rs. ${data['employerCounterPrice']}',
                                      style: const TextStyle(
                                        color: AppColors.kmPink,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      S.waitingWorkerCounterReply,
                                      style: const TextStyle(
                                          color: AppColors.kmMuted,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                                if (status == 'confirmed' ||
                                    status == 'accepted')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'अन्तिम मूल्य: Rs. ${data['finalPrice'] ?? proposedPrice}',
                                      style: const TextStyle(
                                        color: AppColors.kmTeal,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (canTrack)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: GradientActionButton(
                                        icon: Icons.place_rounded,
                                        label: S.trackOnMap,
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                RequestTrackingScreen(
                                                    requestId: docId),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (status == 'confirmed' ||
                                    status == 'accepted' ||
                                    status == 'in_progress' ||
                                    status == 'completed')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        // Arrival-Gated Communication —
                                        // worker साँच्चै आइपुगेर status
                                        // `in_progress` नभएसम्म Call/
                                        // Message देखिँदैनन्, स्वीकृति
                                        // भइसकेको भए पनि।
                                        if (isCommunicationUnlocked(
                                            status)) ...[
                                          GradientActionButton(
                                            icon: Icons.call_rounded,
                                            label: S.callWord,
                                            onPressed: () async {
                                              final phone =
                                                  (data['workerPhone'] ?? '')
                                                      .toString()
                                                      .trim();
                                              if (phone.isEmpty) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(
                                                            S.noPhoneOnFile)));
                                                return;
                                              }
                                              try {
                                                await launchUrl(Uri(
                                                    scheme: 'tel',
                                                    path: phone));
                                              } catch (_) {}
                                            },
                                          ),
                                          GradientActionButton(
                                            icon: Icons.chat_bubble_rounded,
                                            label: S.messageWord,
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    ChatScreen(
                                                  requestId: docId,
                                                  workerName:
                                                      data['workerName'] ??
                                                          'Worker',
                                                  initialStatus: status,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        // Job Completion & Rating Control —
                                        // worker होइन, EMPLOYER ले मात्र
                                        // काम completed मार्क गर्न सक्छ
                                        // (नगद कारोबार दुवैबीचै हुने भएकोले)।
                                        // "Complete Job" थिच्नेबित्तिकै
                                        // भुक्तानी विधि + 5-star rating
                                        // एउटै sheet मा — rating submit
                                        // नगरेसम्म status completed हुँदैन।
                                        //
                                        // Dual-Confirmation Completion —
                                        // Worker/Employer job-portal मात्र
                                        // (Ride होइन) — worker आफैंले
                                        // job_route_screen.dart मा "Job
                                        // Completed" नथिचेसम्म यो बटन
                                        // disabled रहन्छ (request_tracking_
                                        // screen.dart कै उस्तै gate)।
                                        if (status == 'in_progress') ...[
                                          Builder(builder: (context) {
                                            final svc =
                                                (data['service'] ?? '')
                                                    .toString();
                                            final isRide = svc == 'Bike' ||
                                                svc == 'Car' ||
                                                svc == 'Auto';
                                            final workerConfirmed = isRide ||
                                                data['workerConfirmedComplete'] ==
                                                    true;
                                            return GradientActionButton(
                                              icon:
                                                  Icons.check_circle_rounded,
                                              label: workerConfirmed
                                                  ? S.completeJobTitle
                                                  : S
                                                      .waitingForWorkerToConfirmComplete,
                                              onPressed: !workerConfirmed
                                                  ? () => ScaffoldMessenger
                                                          .of(context)
                                                      .showSnackBar(SnackBar(
                                                          content: Text(S
                                                              .waitingForWorkerToConfirmComplete)))
                                                  : () => showCompleteJobSheet(
                                                        context,
                                                        docId: docId,
                                                        amount: (data[
                                                                    'finalPrice'] ??
                                                                data[
                                                                    'proposedPrice'] ??
                                                                0)
                                                            as num,
                                                        workerUid: (data[
                                                                    'workerUid'] ??
                                                                '')
                                                            .toString(),
                                                        workerName: (data[
                                                                    'workerName'] ??
                                                                'Worker')
                                                            .toString(),
                                                        service: svc,
                                                      ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),

                  // Tab 2: Completed
                  Builder(builder: (context) {
                    final snapshot = outerSnapshot;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SkeletonList();
                    }
                    final docs = (snapshot.data?.docs ?? []).where((d) {
                      final s = (d.data() as Map<String, dynamic>)['status'];
                      return s == 'completed' || s == 'cancelled';
                    }).toList();
                    final doneHotel = hotelBookings
                        .where((b) =>
                            b.status == HotelBookingStatus.completed ||
                            b.status == HotelBookingStatus.cancelled ||
                            b.status == HotelBookingStatus.noShow)
                        .toList();
                    if (docs.isEmpty && doneHotel.isEmpty) {
                      return const Center(
                          child: Text('No completed bookings yet',
                              style: TextStyle(color: AppColors.kmMuted)));
                    }
                    // वर्षौंको completed/cancelled history जम्मा भएर
                    // सयौँ हुनसक्ने — `.builder` ले स्क्रोलमा देखिने
                    // card मात्र lazily बनाउँछ (पहिले सबै एकैचोटि,
                    // सुरुमै नै बनिन्थ्यो, जुन लामो history भएका
                    // प्रयोगकर्तामा स्क्रिन खोल्दा jank को कारण थियो)।
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      itemCount: doneHotel.length + docs.length,
                      itemBuilder: (context, rawIndex) {
                        if (rawIndex < doneHotel.length) {
                          return Padding(
                            key: ValueKey(doneHotel[rawIndex].id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _HotelBookingCard(
                              booking: doneHotel[rawIndex],
                              onTap: () => _openHotelBookingPass(
                                  context, doneHotel[rawIndex]),
                            ),
                          );
                        }
                        final i = rawIndex - doneHotel.length;
                        final d = docs[i];
                        final data = d.data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NeonCard(
                            radius: 24,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${data['workerName'] ?? 'Worker'} (${data['service'] ?? ''})',
                                        style: const TextStyle(
                                            color: AppColors.kmText,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    StatusBadge(
                                        status:
                                            (data['status'] ?? '').toString()),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    'अन्तिम मूल्य: Rs. ${data['finalPrice'] ?? data['proposedPrice'] ?? '—'}',
                                    style: const TextStyle(
                                        color: AppColors.kmOrange,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ],
              );
            },
          );
  }
}

/// Hotel Booking Pass & QR Visibility — "My Bookings & Requests" मा देखिने
/// hotel booking card, ride/job card (माथि) भन्दा फरक shape (hotel name,
/// stay-मिति, status) तर उस्तै tap-to-open behaviour: पूरा ट्याप गर्दा
/// Booking Pass/QR screen (`BookingsScreen._openHotelBookingPass`) खुल्छ।
class _HotelBookingCard extends StatelessWidget {
  final HotelBooking booking;
  final VoidCallback onTap;
  const _HotelBookingCard({required this.booking, required this.onTap});

  String _label(String s) => switch (s) {
        HotelBookingStatus.pending => 'Pending',
        HotelBookingStatus.confirmed => 'Confirmed',
        HotelBookingStatus.checkedIn => 'Checked In',
        HotelBookingStatus.completed => 'Checked Out',
        HotelBookingStatus.cancelled => 'Cancelled',
        HotelBookingStatus.noShow => 'No-Show',
        _ => s,
      };

  Color _color(String s) => switch (s) {
        HotelBookingStatus.confirmed => AppColors.kmTeal,
        HotelBookingStatus.checkedIn => AppColors.kmOrange,
        HotelBookingStatus.completed => AppColors.kmTeal,
        HotelBookingStatus.cancelled => AppColors.kmMuted,
        HotelBookingStatus.noShow => AppColors.kmPink,
        _ => AppColors.kmPurple,
      };

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  /// Guest-Side Call/Message Visibility — यो card ले अहिलेसम्म tap गरे मात्र
  /// (पूरा Booking Pass स्क्रिन खोलेर) Call/Video/Message देखाउँथ्यो, सिधै
  /// "My Bookings" list बाटै होइन। अब Booking Pass (`hotel_booking_pass_
  /// screen.dart::_canCommunicate`) कै उस्तै जाँच — confirmed/checked_in
  /// मात्र, र त्यो होटलको साँचो partner खाता (`ownerId`) भए मात्र।
  Future<void> _dialHotel(BuildContext context, String ownerId) async {
    final phone = await hotelOwnerPhone(ownerId);
    if (!context.mounted) return;
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No phone number on file for this hotel.')),
      );
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  Widget _communicationRow(BuildContext context, HotelBooking b, Hotel hotel) {
    final btnStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.kmText,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      padding: const EdgeInsets.symmetric(vertical: 9),
      minimumSize: const Size(0, 36),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _dialHotel(context, hotel.ownerId),
            icon: const Icon(Icons.call_rounded, size: 15),
            label: const Text('Call', style: TextStyle(fontSize: 12)),
            style: btnStyle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => startInAppCall(
              context,
              requestId: b.id,
              otherName: hotel.name,
              video: true,
              otherUid: hotel.ownerId,
            ),
            icon: const Icon(Icons.videocam_rounded, size: 15),
            label: const Text('Video', style: TextStyle(fontSize: 12)),
            style: btnStyle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  requestId: b.id,
                  workerName: hotel.name,
                  initialStatus: b.status,
                  statusCollection: 'hotel_bookings',
                  otherUid: hotel.ownerId,
                  unlockedStatuses: kActiveHotelBookingStatuses,
                ),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_rounded, size: 15),
            label: const Text('Message',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.kmOrange,
              foregroundColor: AppColors.kmInk,
              padding: const EdgeInsets.symmetric(vertical: 9),
              minimumSize: const Size(0, 36),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    Hotel? hotel;
    for (final h in mockHotels) {
      if (h.id == b.hotelId) hotel = h;
    }
    final canCommunicate = isHotelCommunicationUnlocked(b.status) &&
        hotel != null &&
        hotel.ownerId.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: NeonCard(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hotel_rounded,
                    size: 15, color: AppColors.kmOrange),
                const SizedBox(width: 4),
                const Text('HOTEL',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.kmOrange)),
                const Spacer(),
                Icon(Icons.qr_code_rounded,
                    size: 16, color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                      b.guestName.isEmpty ? 'Hotel Booking' : b.guestName,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _color(b.status).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_label(b.status),
                      style: TextStyle(
                          color: _color(b.status),
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${_fmt(b.checkInDate)} → ${_fmt(b.checkOutDate)}',
                style: const TextStyle(color: AppColors.kmMuted)),
            Text(formatHotelPrice(b.totalPrice),
                style: const TextStyle(
                    color: AppColors.kmOrange, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      size: 14, color: AppColors.kmTeal),
                  SizedBox(width: 4),
                  Text('Tap to view Booking Pass / QR',
                      style: TextStyle(
                          color: AppColors.kmTeal,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5)),
                ],
              ),
            ),
            if (canCommunicate) ...[
              const SizedBox(height: 10),
              _communicationRow(context, b, hotel),
            ],
          ],
        ),
      ),
    );
  }
}
