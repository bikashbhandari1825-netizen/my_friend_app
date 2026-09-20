// screens/bookings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/complete_job_sheet.dart';
import '../widgets/counter_offer_card.dart';
import '../widgets/status_badge.dart';
import 'chat_screen.dart';
import 'job_actions.dart';
import 'request_tracking_screen.dart';

// 9. Bookings Screen (Firestore सँग जोडिएको, Counter-offer Accept/Decline सहित)
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

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
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('नयाँ मूल्य प्रस्ताव गर्नुहोस्'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.yourPriceRs,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _declineRequest(context, docId);
            },
            child: Text(S.declineJob,
                style: const TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.igViolet),
            onPressed: () async {
              final newPrice = num.tryParse(controller.text.trim());
              if (newPrice == null) return;
              Navigator.of(dialogContext).pop();
              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'status': 'pending_worker_counter',
                'employerCounterPrice': newPrice,
                'counterFrom': 'employer',
                'employerCounteredAt': FieldValue.serverTimestamp(),
              });
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(S.counterSentToWorker)),
              );
            },
            child: Text(S.sendNewPrice,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _declineRequest(BuildContext context, String docId) async {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({'status': 'declined'});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Request अस्वीकृत गरियो।'),
          backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings & Requests',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          // नोट: TabBar (`bottom:`) सँगै `flexibleSpace` gradient DecoratedBox
          // ले यो device मा AppBar पूरै कालो देखाउँथ्यो (bottom भएको बेला
          // flexibleSpace सही रूपमा नरेन्डर हुने देखियो) — त्यसैले सोझो ठोस
          // रङ नै भरपर्दो।
          backgroundColor: AppColors.igViolet,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Active/Pending'), Tab(text: 'Completed')],
          ),
        ),
        // दुवै tab (Active/Pending, Completed) ले उही `employerUid == uid`
        // query हो — पहिले tab-पिच्छे आफ्नै छुट्टै StreamBuilder (आफ्नै
        // छुट्टै live listener + बारम्बार उही पूरा history डाउनलोड) थियो,
        // दुवै सधैँ एकैचोटि subscribe भइरहन्थे (TabBarView ले दुवै tab
        // सुरुमै build गर्छ) — एउटै डेटा दोब्बर पटक तानिने। अब एउटै
        // बाहिरी StreamBuilder ले एकपटक मात्र सुन्ने, दुवै tab ले त्यही
        // snapshot बाँड्ने। धेरै हजार user ले एकैचोटि यो खोल्दा Firestore
        // bandwidth/listener गन्ती आधाभन्दा बढी घट्छ।
        body: uid == null
            ? const Center(child: Text('Login गर्नुहोस्'))
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('serviceRequests')
                    .where('employerUid', isEqualTo: uid)
                    .snapshots(),
                builder: (context, outerSnapshot) {
                  return TabBarView(
                    children: [
                      // Tab 1: Active/Pending
                      Builder(builder: (context) {
                        final snapshot = outerSnapshot;
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
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
                            final sa =
                                (a.data() as Map<String, dynamic>)['status'];
                            final sb =
                                (b.data() as Map<String, dynamic>)['status'];
                            final pa =
                                sa == 'pending_employer_approval' ? 0 : 1;
                            final pb =
                                sb == 'pending_employer_approval' ? 0 : 1;
                            return pa - pb;
                          });

                        if (docs.isEmpty) {
                          return const Center(
                              child: Text('No active bookings yet',
                                  style: TextStyle(color: Colors.grey)));
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data =
                                docs[index].data() as Map<String, dynamic>;
                            final docId = docs[index].id;
                            final status =
                                (data['status'] ?? 'pending_worker').toString();
                            final proposedPrice = data['proposedPrice'] ?? 0;
                            final counterPrice = data['workerCounterPrice'];
                            final employerCounter =
                                data['employerCounterPrice'];

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
                            return Card(
                              key: ValueKey(docId),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isActive) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.bolt_rounded,
                                              size: 15,
                                              color: AppColors.igViolet),
                                          const SizedBox(width: 4),
                                          Text(S.activeJobTitle,
                                              style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.igViolet)),
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
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        StatusBadge(status: status),
                                      ],
                                    ),
                                    if (status == 'accepted' ||
                                        status == 'confirmed' ||
                                        status == 'in_progress' ||
                                        status == 'completed') ...[
                                      const SizedBox(height: 10),
                                      JobProgressBar(status: status),
                                    ],
                                    const SizedBox(height: 6),
                                    Text('विवरण: ${data['details'] ?? ''}'),
                                    Text('सुरुको मूल्य: Rs. $proposedPrice'),
                                    if (status == 'pending_worker_counter') ...[
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'तपाईंको प्रस्ताव: Rs. ${data['employerCounterPrice']}',
                                          style: const TextStyle(
                                            color: AppColors.igPink,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          S.waitingWorkerCounterReply,
                                          style: const TextStyle(
                                              color: Colors.grey, fontSize: 12),
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
                                            color: AppColors.success,
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
                                                      (data['workerPhone'] ??
                                                              '')
                                                          .toString()
                                                          .trim();
                                                  if (phone.isEmpty) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(SnackBar(
                                                            content: Text(S
                                                                .noPhoneOnFile)));
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
                                            if (status == 'in_progress')
                                              GradientActionButton(
                                                icon:
                                                    Icons.check_circle_rounded,
                                                label: S.completeJobTitle,
                                                onPressed: () =>
                                                    showCompleteJobSheet(
                                                  context,
                                                  docId: docId,
                                                  amount: (data['finalPrice'] ??
                                                      data['proposedPrice'] ??
                                                      0) as num,
                                                  workerUid:
                                                      (data['workerUid'] ?? '')
                                                          .toString(),
                                                  workerName:
                                                      (data['workerName'] ??
                                                              'Worker')
                                                          .toString(),
                                                  service:
                                                      (data['service'] ?? '')
                                                          .toString(),
                                                ),
                                              ),
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
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final docs = (snapshot.data?.docs ?? []).where((d) {
                          final s =
                              (d.data() as Map<String, dynamic>)['status'];
                          return s == 'completed' || s == 'cancelled';
                        }).toList();
                        if (docs.isEmpty) {
                          return const Center(
                              child: Text('No completed bookings yet',
                                  style: TextStyle(color: Colors.grey)));
                        }
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final d in docs)
                              Builder(builder: (context) {
                                final data = d.data() as Map<String, dynamic>;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${data['workerName'] ?? 'Worker'} (${data['service'] ?? ''})',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                            StatusBadge(
                                                status: (data['status'] ?? '')
                                                    .toString()),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                            'अन्तिम मूल्य: Rs. ${data['finalPrice'] ?? data['proposedPrice'] ?? '—'}'),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                          ],
                        );
                      }),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
