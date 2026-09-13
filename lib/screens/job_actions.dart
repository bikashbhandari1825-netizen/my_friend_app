// screens/job_actions.dart
// Job feed र Requests दुवैले प्रयोग गर्ने साझा action: broadcast काम स्वीकार्ने,
// मूल्य प्रस्ताव (counter) गर्ने, वा अस्वीकार गर्ने।
//
// नोट: Phase 3 (full multi-bid) मा accept/counter ले bids sub-collection प्रयोग
// गर्नेछ; अहिले पहिलो जवाफ दिने कामदारले काम claim गर्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import 'job_route_screen.dart';

/// worker ले काम स्वीकार्ने/counter गर्ने ठ्याक्कै क्षणमा उसको स्थान — लाइभ
/// GPS कोसिस गर्ने, नभए प्रोफाइलमा बचत भएको अन्तिम थाहा भएको स्थान। यसैले
/// employer को नक्सा worker ले पछि आफ्नै JobRouteScreen नखोलेसम्म पनि खाली
/// नरहोस् (पहिले त्यही थियो — यही bug को root cause)। Public — accept/counter
/// गर्ने अर्को ठाउँ (worker_requests_page.dart, सिधा offer भएको काम) ले पनि
/// यही एउटै function प्रयोग गर्छ, आफ्नै छुट्टै copy बनाउँदैन।
Future<Map<String, dynamic>> workerLocationForWrite(String? uid) async {
  final live = await getCurrentLocation();
  if (live.ok) {
    return {'workerLat': live.lat, 'workerLng': live.lng};
  }
  if (uid != null) {
    final last = await lastKnownProfileLocation(uid);
    if (last != null) {
      return {'workerLat': last.lat, 'workerLng': last.lng};
    }
  }
  return const {};
}

/// काम स्वीकार भएपछि तुरुन्तै नक्सा (कामदार ↔ ग्राहक बाटो) खोल्ने।
/// ग्राहकको GPS नभए केही गर्दैन।
void openJobRoute(
    BuildContext context, String docId, Map<String, dynamic> data) {
  final eLat = (data['employerLat'] as num?)?.toDouble();
  final eLng = (data['employerLng'] as num?)?.toDouble();
  if (eLat == null || eLng == null) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => JobRouteScreen(
      requestId: docId,
      employerLat: eLat,
      employerLng: eLng,
      employerName: (data['employerName'] ?? S.customerWord).toString(),
      service: (data['service'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      employerPhone: (data['employerPhone'] ?? '').toString(),
    ),
  ));
}

Future<String> myWorkerName(String? uid) async {
  final user = FirebaseAuth.instance.currentUser;
  String name = user?.displayName ?? '';
  try {
    final u =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final n = (u.data()?['name'] ?? '').toString().trim();
    if (n.isNotEmpty) name = n;
  } catch (_) {}
  return name;
}

Future<bool> _stillOpen(String docId) async {
  final fresh = await FirebaseFirestore.instance
      .collection('serviceRequests')
      .doc(docId)
      .get();
  return (fresh.data()?['status'] ?? '') == 'broadcasting';
}

/// कामदारको दर्ता सीप जागिरको सेवा-श्रेणीसँग मिल्छ कि जाँच्ने — काम हेर्न
/// जोसुकैले सक्छन् (कुनै फिल्टर छैन), तर Accept/मूल्य प्रस्ताव भने आफ्नै
/// दर्ता सीप-श्रेणीको काममा मात्र मिल्छ। `workerService` थाहा भए (caller
/// सँग पहिल्यै भएकोले, जस्तै job feed/map screen ले आफ्नै StreamBuilder बाट)
/// पास गर्नुहोस् — दोहोरो Firestore पढाइ जोगिन्छ। नत्र यहीँ लिन्छ (defence-in-
/// depth: UI ले बटन disable गरे पनि, यो function-level check ले फेरि जाँच्छ,
/// किनभने UI state कहिलेकाहीं stale हुन सक्छ)।
Future<bool> workerSkillMatchesJob(Map<String, dynamic> data,
    {String? workerService}) async {
  final jobService = (data['service'] ?? '').toString();
  if (jobService.isEmpty) return true; // category नै नभएको काम — रोक्दैन

  var mine = workerService;
  if (mine == null) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      mine = (snap.data()?['service'] ?? snap.data()?['serviceType'] ?? '')
          .toString();
    } catch (_) {
      return true; // पढ्न सकिएन — UI-level check नै मुख्य गेट हो, यहाँ block गर्दैन
    }
  }
  if (mine.isEmpty) return true; // प्रोफाइलमा सीप नै सेट नभएको — रोक्दैन
  return mine.toLowerCase() == jobService.toLowerCase();
}

/// काम सूचीबद्ध मूल्यमै स्वीकार्ने (claim)। `myService` दिए स्किप-जाँचमा
/// प्रयोग हुन्छ (नदिए Firestore बाट लिइन्छ) — फरक सीप भए रोकिन्छ।
Future<void> acceptBroadcastJob(
    BuildContext context, String docId, Map<String, dynamic> data,
    {String? myService}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await workerSkillMatchesJob(data, workerService: myService)) {
    messenger.showSnackBar(
        SnackBar(content: Text(S.notAuthorizedForJobCategory)));
    return;
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final user = FirebaseAuth.instance.currentUser;
  try {
    if (!await _stillOpen(docId)) {
      messenger.showSnackBar(
          const SnackBar(content: Text('यो काम अर्को कामदारले लिइसक्नुभयो।')));
      return;
    }
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'workerUid': uid,
      'workerName': await myWorkerName(uid),
      'workerPhone': user?.phoneNumber ?? '',
      'status': 'accepted',
      'finalPrice': data['proposedPrice'],
      'acceptedAt': FieldValue.serverTimestamp(),
      // route-map तुरुन्तै काम गरोस् भनेर accept गर्ने क्षणमै worker को
      // स्थान लेख्ने — JobRouteScreen खोलेपछि मात्र पर्खनुपर्दैन।
      ...await workerLocationForWrite(uid),
    });
    messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));
    // यहाँबाट सिधै openJobRoute() नबोलाउने — MainContainer कै साझा
    // active-job watcher ले यो status बदलिएको Firestore बाटै (लगभग तुरुन्तै)
    // देखेर आफैं route screen खोल्छ। यहीँबाट पनि खोल्ने हो भने, अर्को
    // party (employer) ले counter-offer approve गर्दा जस्तो अर्को device बाट
    // भएको acceptance मा भने कहिल्यै नखुल्ने असंगति हुन्थ्यो — एउटै बाटो
    // (watcher) ले सबै केस ह्यान्डल गरोस् भनेर।
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
  }
}

/// काममा नयाँ मूल्य प्रस्ताव गर्ने (InDrive-style)। फरक सीप भए मूल्य dialog
/// नै नखोली रोकिन्छ — counter मार्फत पनि आफ्नो श्रेणी बाहिरको काम लिन नपाइयोस्।
Future<void> counterBroadcastJob(
    BuildContext context, String docId, Map<String, dynamic> data,
    {String? myService}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await workerSkillMatchesJob(data, workerService: myService)) {
    messenger.showSnackBar(
        SnackBar(content: Text(S.notAuthorizedForJobCategory)));
    return;
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final user = FirebaseAuth.instance.currentUser;
  final suggested = (data['proposedPrice'] as num?)?.toInt() ?? 500;
  final controller = TextEditingController(text: suggested.toString());

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(S.offerPrice),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'तपाईंको मूल्य (Rs.)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(S.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.igViolet),
          onPressed: () async {
            final newPrice = num.tryParse(controller.text.trim());
            if (newPrice == null) return;
            Navigator.of(dialogContext).pop();
            try {
              if (!await _stillOpen(docId)) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('यो काम अर्को कामदारले लिइसक्नुभयो।')));
                return;
              }
              await FirebaseFirestore.instance
                  .collection('serviceRequests')
                  .doc(docId)
                  .update({
                'workerUid': uid,
                'workerName': await myWorkerName(uid),
                'workerPhone': user?.phoneNumber ?? '',
                'status': 'pending_employer_approval',
                'workerCounterPrice': newPrice,
                'counteredAt': FieldValue.serverTimestamp(),
                ...await workerLocationForWrite(uid),
              });
              messenger.showSnackBar(const SnackBar(
                  content: Text('नयाँ मूल्य ग्राहकलाई पठाइयो।')));
            } catch (e) {
              messenger
                  .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
            }
          },
          child: const Text('Send', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// यो काम आफ्नो feed बाट हटाउने।
Future<void> declineBroadcastJob(String docId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  try {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'rejectedBy': FieldValue.arrayUnion([uid]),
    });
  } catch (_) {}
}

/// Employer ले कामदारको counter-offer (workerCounterPrice) Accept गर्दा —
/// `request_tracking_screen.dart` र `bookings_screen.dart` दुवैले यही एउटा
/// साझा function बोलाउँछन् (post-acceptance flow दुईतिर नदोहोरियोस् भनेर)।
///
/// नोट (status naming): यो app मा 'accepted' = worker ले employer कै मूल्यमा
/// काम स्वीकार्‍यो, र 'confirmed' = employer ले worker कै counter-offer
/// स्वीकार्‍यो — दुवै status लाई बाँकी सबैतिर (JobProgressBar, StatusBadge,
/// active-job जाँच) उस्तै "काम पुष्टि भयो" चरणको रूपमा हेरिन्छ। त्यसैले यहाँ
/// पनि सोही existing convention (`confirmed`) प्रयोग गरिएको छ, नयाँ समानान्तर
/// status होइन।
///
/// Transaction प्रयोग गरिएको — Accept बटन थिचेको र लेखिने बीचको समयमा worker
/// ले अर्को counter पठाइहाले पनि, transaction ले त्यही क्षणको ताजा
/// workerCounterPrice पढेर त्यही final मान्छ (stale/race price कहिल्यै
/// लेखिँदैन); बीचमै अरू परिवर्तन भइसकेको भेटिए (status अब pending_employer_
/// approval छैन भने) transaction रोकिन्छ र स्पष्ट सन्देश देखिन्छ।
Future<void> acceptWorkerCounterOffer(
    BuildContext context, String docId) async {
  final messenger = ScaffoldMessenger.of(context);
  final ref =
      FirebaseFirestore.instance.collection('serviceRequests').doc(docId);
  Map<String, dynamic>? finalData;

  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null || data['status'] != 'pending_employer_approval') {
        throw StateError('stale_offer');
      }
      final price = (data['workerCounterPrice'] as num?) ??
          (data['proposedPrice'] as num?) ??
          0;
      final update = <String, dynamic>{
        'status': 'confirmed',
        'finalPrice': price,
        // अनुरोध गरिएको field नाम — 'finalPrice' कै alias, बाँकी सबैतिर
        // (payment sheet, job card, यो app भरि) 'finalPrice' नै पढिन्छ,
        // त्यसैले दुवै लेखिन्छ — कुनै display नबिग्रियोस्।
        'agreedAmount': price,
        'acceptedAt': FieldValue.serverTimestamp(),
        'employerUid': (data['employerUid'] ?? '').toString(),
        'workerUid': (data['workerUid'] ?? '').toString(),
      };
      // Call बटनका लागि employer को फोन — job सिर्जना हुँदा नलेखिएको भए
      // अहिले (accept गर्ने बेला) भरिदिने।
      final existingPhone = (data['employerPhone'] as String?)?.trim() ?? '';
      if (existingPhone.isEmpty) {
        final myPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
        if (myPhone.isNotEmpty) update['employerPhone'] = myPhone;
      }
      tx.update(ref, update);
      finalData = {...data, ...update};
    });
  } on StateError {
    messenger.showSnackBar(SnackBar(content: Text(S.staleOfferError)));
    return;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(S.bookingConfirmed)));

  // in-app notification — push (FCM) miss भए पनि worker ले यो अवश्य देख्छ।
  final data = finalData;
  if (data == null) return;
  final workerUid = (data['workerUid'] ?? '').toString();
  if (workerUid.isEmpty) return;
  final employerName = (data['employerName'] ?? S.customerWord).toString();
  final amount = (data['finalPrice'] as num?) ?? 0;
  try {
    await createNotificationForUser(
      workerUid,
      S.offerAcceptedNotifTitle,
      S.offerAcceptedNotifBody(employerName, amount),
      data: {'requestId': docId, 'type': 'offer_accepted'},
    );
  } catch (_) {}
}
