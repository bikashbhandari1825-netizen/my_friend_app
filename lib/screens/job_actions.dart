// screens/job_actions.dart
// Job feed र Requests दुवैले प्रयोग गर्ने साझा action: broadcast काम स्वीकार्ने,
// मूल्य प्रस्ताव (counter) गर्ने, वा अस्वीकार गर्ने।
//
// नोट: Phase 3 (full multi-bid) मा accept/counter ले bids sub-collection प्रयोग
// गर्नेछ; अहिले पहिलो जवाफ दिने कामदारले काम claim गर्छ।
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'call_screen.dart';
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
      // Ride (Bike/Car) मात्र — राइड सुरु भएपछि नक्साले यतातिर हेर्ने
      // (job_route_screen.dart::_target हेर्नुहोस्)।
      destinationLat: (data['destinationLat'] as num?)?.toDouble(),
      destinationLng: (data['destinationLng'] as num?)?.toDouble(),
      destinationAddress: (data['destinationAddress'] ?? '').toString(),
    ),
  ));
}

/// यो request मा हाल लगइन भएको व्यक्ति नभएको अर्को पक्ष (employer↔worker)
/// को uid — `serviceRequests/{requestId}` बाट। इन-एप कल सुरु गर्ने ठाउँहरू
/// (route/arrival screen जस्ता, जहाँ अर्को पक्षको uid पहिल्यै थाहा नहुन
/// सक्छ) ले प्रयोग गर्छन्।
Future<String?> otherPartyUid(String requestId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(requestId)
        .get();
    final data = doc.data();
    if (data == null) return null;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final employerUid = (data['employerUid'] ?? '').toString();
    final workerUid = (data['workerUid'] ?? '').toString();
    if (me == employerUid) return workerUid.isEmpty ? null : workerUid;
    if (me == workerUid) return employerUid.isEmpty ? null : employerUid;
    return null;
  } catch (_) {
    return null;
  }
}

/// Chat/route/arrival जुनसुकै screen बाट इन-एप (WebRTC) कल सुरु गर्ने साझा
/// बाटो — `CallScreen` push + अर्को पक्षलाई incoming-call notification
/// दुवै एकै ठाउँमा, दोहोरिनबाट जोगिन। `myName`/`otherUid` पहिल्यै थाहा भए
/// (caller ले cache गरेको) दिनुहोस् — नत्र यहीँ एकपटक Firestore बाट लिन्छ।
Future<void> startInAppCall(
  BuildContext context, {
  required String requestId,
  required String otherName,
  required bool video,
  String? myName,
  String? otherUid,
}) async {
  final resolvedMyName =
      myName ?? await myWorkerName(FirebaseAuth.instance.currentUser?.uid);
  if (!context.mounted) return;
  final resolvedOtherUid = otherUid ?? await otherPartyUid(requestId) ?? '';
  if (!context.mounted) return;

  // अर्को पक्षलाई कल सुरु हुनेबित्तिकै (screen खुल्दाकै क्षणमा, कल सकिएपछि
  // होइन) — background/बन्द एपमा भए पनि थाहा पाओस् भनेर fire-and-forget।
  if (resolvedOtherUid.isNotEmpty) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    unawaited(createNotificationForUser(
      resolvedOtherUid,
      S.incomingCallTitle,
      '$resolvedMyName  ·  ${video ? S.videoCall : S.voiceCall}',
      data: {
        'requestId': requestId,
        'type': 'incoming_call',
        'mode': video ? 'video' : 'audio',
        'callerName': resolvedMyName,
        'callerUid': myUid,
      },
    ));
  }

  await Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen(
        requestId: requestId,
        otherName: otherName,
        myName: resolvedMyName,
        video: video,
        isCaller: true,
        otherUid: resolvedOtherUid,
      ),
    ),
  );
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

/// प्रयोगकर्ताको साँचो सम्पर्क नम्बर — Firebase Auth कै `user.phoneNumber`
/// त्यही खाता फोन-OTP मार्फत साइन-इन भएको बेला मात्र भरिन्छ; इमेल/पासवर्डबाट
/// दर्ता भएका (आजकल धेरैजसो) प्रयोगकर्ताको हकमा त्यो सधैँ खाली हुन्छ, जबकि
/// रजिस्ट्रेसनकै बेला उनीहरूले भरेको नम्बर भने `users/{uid}.phone` मा
/// बचत भइसकेको हुन्छ। यहीं नै हो "Call गर्दा फोन नम्बर भेटिएन" गुनासोको
/// मूल कारण — accept/counter गर्ने हरेक ठाउँले यो function प्रयोग गर्नुपर्छ,
/// सिधै `user?.phoneNumber` होइन।
Future<String> myPhoneNumber(String? uid) async {
  final user = FirebaseAuth.instance.currentUser;
  String phone = user?.phoneNumber ?? '';
  try {
    final u =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final p = (u.data()?['phone'] ?? '').toString().trim();
    if (p.isNotEmpty) phone = p;
  } catch (_) {}
  return phone;
}

// ── Single Active Job Restriction ───────────────────────────────────────
// worker ले एकैचोटि एउटा मात्र सक्रिय काम (accepted/confirmed/in_progress)
// राख्न पाउँछ — अघिल्लो काम completed/cancelled/declined नभएसम्म नयाँ कुनै
// पनि बाटोबाट (सिधा accept, counter-offer accept, employer ले worker कै
// counter accept गर्दा) accept हुनै नपाओस्। यो नियम बाँकी सबैतिर प्रयोग हुने
// उस्तै status set हो — `main_container.dart` कै `_activeJobStatuses` र
// `worker_profile_screen.dart` कै `_kActiveRequestStatuses` सँगै मिल्ने।
const kActiveJobStatuses = {'accepted', 'confirmed', 'in_progress'};

// ── Acceptance-Gated Communication ───────────────────────────────────────
// Call/Video/Chat स्वीकृति (`accepted`/`confirmed`/`in_progress` — उही
// `kActiveJobStatuses` माथि) भएको क्षणदेखि नै स्थायी रूपमा खुल्ला रहन्छन्,
// worker साँच्चै employer को स्थानमा आइपुगे/नआइपुगे भन्ने कुराले फरक नपार्ने
// गरी — त्यसैले यो एउटै साझा ठाउँबाट जाँच्ने, हरेक call/video/chat button ले
// आफ्नै छुट्टै status-set नबनाओस्।
bool isCommunicationUnlocked(String? status) =>
    status != null && kActiveJobStatuses.contains(status);

/// worker आफैं व्यस्त भएकोले (अर्को सक्रिय काम भइरहेको) यो काम accept/confirm
/// गर्न नमिल्ने भएको बेला throw हुने — caller ले पक्डेर स्पष्ट सन्देश देखाउनुहोस्।
class WorkerBusyException implements Exception {
  const WorkerBusyException();
  @override
  String toString() => 'worker_busy_with_active_job';
}

// ── Rating-Based Monthly Order Quota ────────────────────────────────────
// Owner ले तोकेको नियम: rating जति उच्च भयो, worker ले महिनाभरि लिन पाउने
// नयाँ काम (order) त्यति धेरै। यो केवल "नजिकको सूचीमा देखिने/नदेखिने" होइन
// — काम साँच्चै accept/confirm हुने ठ्याक्कै क्षणमा नै यहाँ रोकिन्छ, ताकि
// जुनसुकै बाटो (broadcast claim, counter-offer accept, employer ले
// counter approve गर्दा) प्रयोग गरे पनि उही सीमा लागू होस्।
//
// Tier → महिनाको अधिकतम order:
//   ०-review (सर्वथा नयाँ worker) — starter quota (३-star बराबर, ८) — नत्र
//   पहिलो review नै कहिल्यै नपाउने ("0-star भएकोले 0 order, त्यसैले कहिल्यै
//   पहिलो काम नै नपाई rating सुधारिनै नसक्ने") chicken-and-egg पर्थ्यो।
//   १ star  → २      २ star → ४      ३ star → ८
//   ४ star  → १८     ५ star → ३५     (owner ले दिएको दायराभित्रैका मान)
//
// Admin ले `users/{uid}.ratingOverride`/`orderLimitOverride` (Owner
// Dashboard बाट) म्यानुअली सेट गरे त्यही अन्तिम — computed tier लाई बाइपास
// गर्छ (जस्तै नयाँ worker लाई थप grace, वा कुनै विशेष अवस्था)।
int monthlyOrderQuotaForRating({required num ratingSum, required int reviewCount}) {
  if (reviewCount <= 0) return 8; // starter quota
  final avg = ratingSum / reviewCount;
  final stars = avg.round().clamp(0, 5);
  return switch (stars) {
    0 => 0,
    1 => 2,
    2 => 4,
    3 => 8,
    4 => 18,
    _ => 35, // 5
  };
}

String currentQuotaMonthKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

/// Quota सकिएको worker लाई नयाँ काम accept/confirm गर्न खोज्दा throw हुने।
class WorkerQuotaExceededException implements Exception {
  const WorkerQuotaExceededException();
  @override
  String toString() => 'worker_order_quota_exceeded';
}

/// Transaction भित्रै (पहिल्यै [tx.get]) पढिसकेको worker doc कै [userData]
/// पुनः-प्रयोग गरेर यो महिनाको order-quota जाँच्ने + (ठाउँ भए) एक थप खपत
/// गर्ने — थप कुनै अतिरिक्त read नचाहिने गरी। महिना बदलिएको भेटिए counter
/// आफैं शून्यबाट फेरि सुरु हुन्छ। Quota सकिएको भए [WorkerQuotaExceededException]
/// throw हुन्छ — [userRef] मा कुनै लेखाइ हुँदैन, caller ले transaction नै रोकिन्छ।
void consumeOrderQuotaInTransaction(
  Transaction tx,
  DocumentReference<Map<String, dynamic>> userRef,
  Map<String, dynamic>? userData,
) {
  final month = currentQuotaMonthKey();
  final storedMonth = (userData?['orderQuotaMonth'] ?? '').toString();
  final usedSoFar =
      storedMonth == month ? ((userData?['orderQuotaUsed'] as num?) ?? 0).toInt() : 0;

  final overrideLimit = (userData?['orderLimitOverride'] as num?)?.toInt();
  int limit;
  if (overrideLimit != null) {
    limit = overrideLimit;
  } else {
    final ratingOverride = (userData?['ratingOverride'] as num?);
    if (ratingOverride != null) {
      // ratingOverride सिधै star मान (०-५) हो — sum/count बनावट चाहिँदैन।
      limit = monthlyOrderQuotaForRating(ratingSum: ratingOverride, reviewCount: 1);
    } else {
      final ratingSum = (userData?['ratingSum'] as num?) ?? 0;
      final reviewCount = ((userData?['ratingCount'] as num?) ?? 0).toInt();
      limit = monthlyOrderQuotaForRating(ratingSum: ratingSum, reviewCount: reviewCount);
    }
  }

  if (usedSoFar >= limit) {
    throw const WorkerQuotaExceededException();
  }

  tx.set(userRef, {
    'orderQuotaMonth': month,
    'orderQuotaUsed': usedSoFar + 1,
  }, SetOptions(merge: true));
}

/// Review थपिएपछि (`complete_job_sheet.dart::_confirm()`) worker को
/// `registeredWorkers` entry (nearby list ले पढ्ने cached rating/reviews)
/// लाई पनि ताजा राख्ने — नत्र त्यहाँ admin approve गरेको दिनकै (वा पुरानो)
/// मान सधैंभरि देखिन्थ्यो, साँचो review जति आए पनि कहिल्यै नबदलिने।
/// Best-effort/fire-and-forget — असफल भए पनि completion flow लाई असर पर्दैन।
Future<void> syncWorkerRatingToRegisteredWorkers(String workerUid) async {
  if (workerUid.isEmpty) return;
  try {
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(workerUid).get();
    final data = userSnap.data();
    final sum = (data?['ratingSum'] as num?) ?? 0;
    final count = ((data?['ratingCount'] as num?) ?? 0).toInt();
    final avg = count == 0 ? 0.0 : sum / count;
    final snap = await FirebaseFirestore.instance
        .collection('registeredWorkers')
        .where('uid', isEqualTo: workerUid)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'rating': avg.toStringAsFixed(1),
        'reviews': count.toString(),
      });
    }
    await batch.commit();
  } catch (_) {}
}

/// [workerUid] लाई हाल कुनै अर्को साँच्चै-अझै-सक्रिय काम (यो [excludeDocId]
/// बाहेक) छ भने त्यसको requestId फर्काउँछ, नत्र null। `users/{uid}.
/// activeJobId` (accept हुनेबित्तिकै [claimJobForWorker] ले लेख्ने पोइन्टर)
/// बाट — UI ले Accept/Offer बटन देखाउनुअघि (disable/hide गर्न) प्रयोग गर्ने
/// छिटो, non-transactional जाँच। स्टेल पोइन्टर (काम completed भइसकेको तर
/// पोइन्टर clear हुन नपाएको दुर्लभ अवस्था) भेटिए त्यो job doc कै ताजा status
/// पनि पक्का जाँचिन्छ, र स्टेल भेटिए null नै फर्कन्छ (block गर्दैन)।
Future<String?> workerActiveJobId(String? workerUid,
    {String? excludeDocId}) async {
  if (workerUid == null || workerUid.isEmpty) return null;
  try {
    final u = await FirebaseFirestore.instance
        .collection('users')
        .doc(workerUid)
        .get();
    final id = (u.data()?['activeJobId'] ?? '').toString();
    if (id.isEmpty || id == excludeDocId) return null;
    final job = await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(id)
        .get();
    final status = (job.data()?['status'] ?? '').toString();
    return kActiveJobStatuses.contains(status) ? id : null;
  } catch (_) {
    return null;
  }
}

/// काम [docId] लाई [workerUid] का लागि atomic रूपमा "claim" गर्ने — [docId]
/// को [updateFields] लेख्नुको साथसाथै `users/{workerUid}.activeJobId` पनि
/// यही transaction भित्रै सेट हुन्छ, ताकि "दुई काम लगभग एकैचोटि accept" जस्तो
/// race-condition सम्भवै नहोस्। worker लाई हाल अर्को साँच्चै-अझै-सक्रिय काम
/// (transaction भित्रै ताजा पढेर पक्का गरिएको, केवल पोइन्टर हेरेर होइन)
/// भेटिए [WorkerBusyException] throw हुन्छ, doc लेखिँदैन।
Future<void> claimJobForWorker({
  required String docId,
  required String workerUid,
  required Map<String, dynamic> updateFields,
}) async {
  final jobRef =
      FirebaseFirestore.instance.collection('serviceRequests').doc(docId);
  final userRef = FirebaseFirestore.instance.collection('users').doc(workerUid);
  await FirebaseFirestore.instance.runTransaction((tx) async {
    final userSnap = await tx.get(userRef);
    final existingId = (userSnap.data()?['activeJobId'] ?? '').toString();
    if (existingId.isNotEmpty && existingId != docId) {
      final otherSnap = await tx.get(FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(existingId));
      final otherStatus = (otherSnap.data()?['status'] ?? '').toString();
      if (kActiveJobStatuses.contains(otherStatus)) {
        throw const WorkerBusyException();
      }
    }
    // Rating-Based Monthly Order Quota — यही transaction भित्रै पहिल्यै
    // पढिसकेको [userSnap] पुनः-प्रयोग गर्दै (थप read नचाहिने), quota
    // सकिएको भए यहीँ throw भएर काम कहिल्यै claim हुँदैन।
    consumeOrderQuotaInTransaction(tx, userRef, userSnap.data());
    tx.update(jobRef, updateFields);
    tx.set(userRef, {'activeJobId': docId}, SetOptions(merge: true));
  });
}

/// काम active अवस्थाबाट बाहिरिँदा (completed/cancelled/declined) worker को
/// `activeJobId` पोइन्टर खाली गर्ने — तर मात्र त्यो पोइन्टरले अझै यही
/// [docId] लाई देखाइरहेको भए (नत्र बीचमा अर्को नयाँ काम claim भइसकेको भए
/// त्यसैलाई गलतीले नहटाइयोस्)।
Future<void> releaseWorkerActiveJob(String? workerUid, String docId) async {
  if (workerUid == null || workerUid.isEmpty) return;
  final userRef = FirebaseFirestore.instance.collection('users').doc(workerUid);
  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if ((snap.data()?['activeJobId'] ?? '').toString() == docId) {
        tx.update(userRef, {'activeJobId': FieldValue.delete()});
      }
    });
  } catch (_) {}
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
    messenger
        .showSnackBar(SnackBar(content: Text(S.notAuthorizedForJobCategory)));
    return;
  }
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  try {
    if (!await _stillOpen(docId)) {
      messenger.showSnackBar(
          const SnackBar(content: Text('यो काम अर्को कामदारले लिइसक्नुभयो।')));
      return;
    }
    await claimJobForWorker(
      docId: docId,
      workerUid: uid,
      updateFields: {
        'workerUid': uid,
        'workerName': await myWorkerName(uid),
        'workerPhone': await myPhoneNumber(uid),
        'status': 'accepted',
        'finalPrice': data['proposedPrice'],
        'acceptedAt': FieldValue.serverTimestamp(),
        // route-map तुरुन्तै काम गरोस् भनेर accept गर्ने क्षणमै worker को
        // स्थान लेख्ने — JobRouteScreen खोलेपछि मात्र पर्खनुपर्दैन।
        ...await workerLocationForWrite(uid),
      },
    );
    messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));
    // यहाँबाट सिधै openJobRoute() नबोलाउने — MainContainer कै साझा
    // active-job watcher ले यो status बदलिएको Firestore बाटै (लगभग तुरुन्तै)
    // देखेर आफैं route screen खोल्छ। यहीँबाट पनि खोल्ने हो भने, अर्को
    // party (employer) ले counter-offer approve गर्दा जस्तो अर्को device बाट
    // भएको acceptance मा भने कहिल्यै नखुल्ने असंगति हुन्थ्यो — एउटै बाटो
    // (watcher) ले सबै केस ह्यान्डल गरोस् भनेर।
  } on WorkerBusyException {
    messenger.showSnackBar(SnackBar(content: Text(S.workerBusyWithOtherJob)));
  } on WorkerQuotaExceededException {
    messenger.showSnackBar(SnackBar(content: Text(S.workerQuotaExceeded)));
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
    messenger
        .showSnackBar(SnackBar(content: Text(S.notAuthorizedForJobCategory)));
    return;
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final suggested = (data['proposedPrice'] as num?)?.toInt() ?? 500;
  final controller = TextEditingController(text: suggested.toString());

  if (!context.mounted) return;
  await showKmDialog(
    context: context,
    title: S.offerPrice,
    icon: Icons.local_offer_rounded,
    content: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: AppColors.kmText),
      decoration: kmInputDecoration('तपाईंको मूल्य (Rs.)'),
    ),
    actions: [
      KmDialogAction(
        label: S.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      KmDialogAction(
        label: 'Send',
        filled: true,
        onPressed: () async {
          final newPrice = num.tryParse(controller.text.trim());
          if (newPrice == null) return;
          Navigator.of(context).pop();
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
              'workerPhone': await myPhoneNumber(uid),
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
      ),
    ],
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

// ── Ride-Hailing (Bike/Car) — inDrive-style simultaneous bidding ───────────
// माथिको note (फाइलको टाउको) मै भनिएको "Phase 3 multi-bid" यहाँ Bike/Car
// राइडका लागि मात्र लागू — `counterBroadcastJob` जस्तो parent doc को
// workerUid सिधै claim गर्दैन, बरु धेरै driver ले एकैचोटि आ-आफ्नै मूल्य
// `serviceRequests/{docId}/rideOffers/{workerUid}` मा राख्न सक्छन्, र
// passenger ले तीमध्ये एउटा छान्छ (`acceptRideOffer`)। अरू सेवा (plumber,
// electrician, ...) यो बाटो कहिल्यै छुँदैनन् — तिनको पुरानै single-claim
// व्यवहार यथावत।

/// driver ले आफ्नो भाडा प्रस्ताव पठाउने — parent doc कहिल्यै छुँदैन,
/// त्यसैले एकैचोटि धेरै driver ले प्रस्ताव पठाउँदा कुनै race/टकराव हुँदैन।
Future<void> submitRideOffer(
    BuildContext context, String docId, Map<String, dynamic> data,
    {required num price}) async {
  final messenger = ScaffoldMessenger.of(context);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    final name = await myWorkerName(uid);
    final phone = await myPhoneNumber(uid);
    double rating = 0;
    int completedRides = 0;
    String vehicleDetails = '';
    String vehicleMake = '';
    String vehicleModel = '';
    String vehiclePlate = '';
    try {
      final u =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      vehicleDetails = (u.data()?['vehicleDetails'] ?? '').toString();
      vehicleMake = (u.data()?['vehicleMake'] ?? '').toString();
      vehicleModel = (u.data()?['vehicleModel'] ?? '').toString();
      vehiclePlate = (u.data()?['vehiclePlate'] ?? '').toString();
      final sum = (u.data()?['ratingSum'] as num?) ?? 0;
      final count = (u.data()?['ratingCount'] as num?) ?? 0;
      if (count > 0) rating = sum / count;
      completedRides = ((u.data()?['completedRidesCount'] as num?) ?? 0).toInt();
    } catch (_) {}
    // प्रस्ताव पठाउने ठ्याक्कै क्षणको driver-स्थान — passenger को खोजी
    // स्क्रिनमा नक्सामा देखाउन (worker प्रस्ताव पठाउनेबित्तिकै कहाँ थियो
    // भन्ने एउटा स्थिर snapshot; लगातार लाइभ movement होइन — त्यो चाहिँदा
    // worker-तर्फ background GPS stream चाहिन्छ, अझै छैन)।
    final loc = await workerLocationForWrite(uid);
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .collection('rideOffers')
        .doc(uid)
        .set({
      'workerUid': uid,
      'workerName': name,
      'workerPhone': phone,
      'vehicleDetails': vehicleDetails,
      'vehicleMake': vehicleMake,
      'vehicleModel': vehicleModel,
      'vehiclePlate': vehiclePlate,
      'rating': rating,
      'completedRides': completedRides,
      'offerPrice': price,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      ...loc,
    });
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(S.offerSentToPassenger)));
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
  }
}

/// passenger ले धेरै driver-प्रस्तावमध्ये एउटा छान्दा — `acceptWorkerCounterOffer`
/// कै उही transaction ढाँचा (single-active-job busy check + monthly quota +
/// `activeJobId` pointer employer कै transaction भित्रै, security rules मा
/// पहिल्यै भएको carve-out प्रयोग गर्दै), तर मूल्य/driver विवरण parent doc
/// बाट होइन यही एउटा `rideOffers/{offerId}` subdoc बाट।
/// राइड सुरु गर्ने ४-अंकको OTP — passenger लाई देखाइन्छ, driver ले "On
/// Arrival" पछि यही टाइप गरेर मात्र राइड 'in_progress' मा सार्न पाउँछ।
String _generateRideStartCode() =>
    (1000 + Random().nextInt(9000)).toString();

Future<void> acceptRideOffer(BuildContext context, String docId,
    String offerId, Map<String, dynamic> offer) async {
  final messenger = ScaffoldMessenger.of(context);
  final ref =
      FirebaseFirestore.instance.collection('serviceRequests').doc(docId);
  final workerUid = (offer['workerUid'] ?? '').toString();
  Map<String, dynamic>? finalData;

  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final status = (data?['status'] ?? '').toString();
      if (data == null ||
          (status != 'broadcasting' && status != 'pending_worker')) {
        throw StateError('stale_offer');
      }
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(workerUid);
      final userSnap = await tx.get(userRef);
      final existingActiveId =
          (userSnap.data()?['activeJobId'] ?? '').toString();
      if (existingActiveId.isNotEmpty && existingActiveId != docId) {
        final otherSnap = await tx.get(FirebaseFirestore.instance
            .collection('serviceRequests')
            .doc(existingActiveId));
        final otherStatus = (otherSnap.data()?['status'] ?? '').toString();
        if (kActiveJobStatuses.contains(otherStatus)) {
          throw const WorkerBusyException();
        }
      }
      consumeOrderQuotaInTransaction(tx, userRef, userSnap.data());
      final price = (offer['offerPrice'] as num?) ??
          (data['proposedPrice'] as num?) ??
          0;
      final update = <String, dynamic>{
        'status': 'accepted',
        'finalPrice': price,
        'agreedAmount': price,
        'acceptedAt': FieldValue.serverTimestamp(),
        'workerUid': workerUid,
        'workerName': offer['workerName'],
        'workerPhone': offer['workerPhone'],
        // Ride-Start OTP — driver आइपुगेपछि passenger ले भनेको यही ४-अंकको
        // कोड नमिलाईकन राइड 'in_progress' मा सार्न मिल्दैन (JobRouteScreen
        // हेर्नुहोस्) — गलत यात्री/गलत pickup बाट जोगाउने।
        'rideStartCode': _generateRideStartCode(),
      };
      tx.update(ref, update);
      if (workerUid.isNotEmpty) {
        tx.set(userRef, {'activeJobId': docId}, SetOptions(merge: true));
      }
      tx.update(ref.collection('rideOffers').doc(offerId), {'status': 'accepted'});
      finalData = {...data, ...update};
    });
  } on StateError {
    messenger.showSnackBar(SnackBar(content: Text(S.offerNoLongerAvailable)));
    return;
  } on WorkerBusyException {
    messenger.showSnackBar(SnackBar(content: Text(S.workerBusyWithOtherJob)));
    return;
  } on WorkerQuotaExceededException {
    messenger.showSnackBar(SnackBar(content: Text(S.workerQuotaExceeded)));
    return;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));

  // अरू pending प्रस्ताव declined — transaction भन्दा बाहिर (best-effort)।
  try {
    final others = await ref
        .collection('rideOffers')
        .where('status', isEqualTo: 'pending')
        .get();
    for (final d in others.docs) {
      if (d.id == offerId) continue;
      d.reference.update({'status': 'declined'});
    }
  } catch (_) {}

  final data = finalData;
  if (data == null || workerUid.isEmpty) return;
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

/// passenger ले एउटा मात्र प्रस्ताव अस्वीकार गर्दा — बाँकी अरू driverका
/// प्रस्ताव अझै जीवितै रहन्छन् (पूरै broadcast कहिल्यै रोकिँदैन)।
Future<void> declineRideOffer(String docId, String offerId) async {
  try {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .collection('rideOffers')
        .doc(offerId)
        .update({'status': 'declined'});
  } catch (_) {}
}

/// passenger ले driver-को प्रस्तावित भाडा accept गर्नुको सट्टा फरक मूल्य
/// फिर्ता पठाउन (negotiate) — offer doc मै `passengerCounterPrice` राखिन्छ,
/// driver ले आफ्नै (`_SendRideOfferButton`) कार्डबाट accept/decline गर्न
/// पाउँछ (security rules: driver आफ्नै offer doc, passenger employer भएकोले
/// दुवैलाई नै update अनुमति पहिल्यै दिइएको छ)।
Future<void> negotiateRideOffer(
    BuildContext context, String docId, String offerId, num currentPrice) async {
  final controller = TextEditingController(text: currentPrice.toString());
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
        label: S.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      KmDialogAction(
        label: 'Send',
        filled: true,
        onPressed: () async {
          final newPrice = num.tryParse(controller.text.trim());
          Navigator.of(context).pop();
          if (newPrice == null) return;
          try {
            await FirebaseFirestore.instance
                .collection('serviceRequests')
                .doc(docId)
                .collection('rideOffers')
                .doc(offerId)
                .update({
              'status': 'passenger_countered',
              'passengerCounterPrice': newPrice,
            });
          } catch (_) {}
        },
      ),
    ],
  );
}

/// driver ले passenger कै counter मूल्य स्वीकार्दा — offer को मूल्य त्यही
/// नयाँ मूल्यमा अपडेट भई फेरि 'pending' मा फर्किन्छ (passenger ले अब सिधै
/// Accept गर्न पाउँछ)।
Future<void> driverAcceptPassengerCounter(
    String docId, String offerId, num newPrice) async {
  try {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .collection('rideOffers')
        .doc(offerId)
        .update({
      'offerPrice': newPrice,
      'status': 'pending',
      'passengerCounterPrice': FieldValue.delete(),
    });
  } catch (_) {}
}

Future<void> driverDeclinePassengerCounter(String docId, String offerId) async {
  try {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .collection('rideOffers')
        .doc(offerId)
        .update({'status': 'declined'});
  } catch (_) {}
}

/// driver ले passenger-को counter मूल्य स्वीकार्ने वा अस्वीकार गर्नुको सट्टा
/// आफ्नै अर्को (तेस्रो) मूल्य फिर्ता पठाउन — बाइ-डाइरेक्शनल बिडिङ यहीँबाट
/// धेरै round सम्म चलिरहन सक्छ (offer फेरि 'pending' मा फर्कन्छ, passenger
/// ले फेरि Accept/Decline/Counter गर्न पाउँछ — `negotiateRideOffer` कै loop)।
Future<void> driverCounterOffer(
    BuildContext context, String docId, String offerId, num currentCounterPrice) async {
  final controller = TextEditingController(text: currentCounterPrice.toString());
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
        label: S.cancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      KmDialogAction(
        label: 'Send',
        filled: true,
        onPressed: () async {
          final newPrice = num.tryParse(controller.text.trim());
          Navigator.of(context).pop();
          if (newPrice == null) return;
          try {
            await FirebaseFirestore.instance
                .collection('serviceRequests')
                .doc(docId)
                .collection('rideOffers')
                .doc(offerId)
                .update({
              'offerPrice': newPrice,
              'status': 'pending',
              'passengerCounterPrice': FieldValue.delete(),
            });
          } catch (_) {}
        },
      ),
    ],
  );
}

/// Chat media (photo/video/voice, chat_media_service.dart ले
/// `chats/{docId}/media/*` मा अपलोड गरेको) सबै Storage बाट मेटाउने —
/// Firestore कै message doc मेटाउँदा मात्र यी असली फाइल आफैं मेटिँदैनन्,
/// यो नगरे Storage मा सधैँका लागि "अनाथ" भई बसिरहन्थे (privacy purge को
/// उद्देश्य नै अधुरो रहन्थ्यो)। कुनै फाइल नभए वा असफल भए पनि caller को
/// बाँकी काम नरोकियोस् भनेर चुपचाप।
Future<void> _deleteChatMedia(String docId) async {
  try {
    final folder = FirebaseStorage.instance.ref('chats/$docId/media');
    final list = await folder.listAll();
    await Future.wait(list.items.map((r) => r.delete().catchError((_) {})));
  } catch (_) {}
}

/// Post-Completion Data Clearance — काम "completed" भइसकेपछि chat भित्रका
/// सबै सन्देश (फोन नम्बर/ठेगाना जस्ता संवेदनशील कुरा आदान-प्रदान भएको हुन
/// सक्ने) र request doc मा cache भएका फोन नम्बर (workerPhone/employerPhone)
/// मेटाउने। Messages tab मा भने यो conversation row — कोसँग काम भएको थियो
/// भन्ने साधारण record/history — रहिरहन्छ; त्यसभित्रको संवेदनशील विवरण
/// मात्र हट्छ (`lastMessage` पनि मेटिने भएकोले त्यो row अब chat snippet
/// होइन, सेवा-नाम मात्र देखाउँछ)। Call-signaling बाट पनि (सामान्यतया
/// CallService ले प्रत्येक कल सकिनासाथ आफैं सफा गर्छ, तर safety-net) बाँकी
/// रहन सक्ने कुनै `calls/{id}` doc हटाइन्छ।
Future<void> purgeSensitiveDataOnCompletion(String docId) async {
  try {
    final msgs = await FirebaseFirestore.instance
        .collection('chats')
        .doc(docId)
        .collection('messages')
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final m in msgs.docs) {
      batch.delete(m.reference);
    }
    batch.set(
      FirebaseFirestore.instance.collection('serviceRequests').doc(docId),
      {
        'workerPhone': FieldValue.delete(),
        'employerPhone': FieldValue.delete(),
        'lastMessage': FieldValue.delete(),
        'chatClearedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    await FirebaseFirestore.instance.collection('calls').doc(docId).delete();
    unawaited(_deleteChatMedia(docId));
  } catch (_) {
    // सफाइ असफल भए पनि काम "completed" भइसकेको छ — payment flow यसले रोक्दैन।
  }
}

/// Cancelled Bookings Cleanup — काम "cancelled" भएमा केवल status update
/// (इतिहासमा बाँकी रहने) होइन, बरु `serviceRequests` doc नै पूर्ण रूपमा
/// मेटाइन्छ (साथसाथै associated `chats/{id}` + यसका सन्देश, र `calls/{id}`
/// signaling doc पनि) — रद्द भएको बुकिङको कुनै अवशेष history मा नरहोस्
/// भन्ने आवश्यकता। worker को single-active-job पोइन्टर पनि खाली हुन्छ।
Future<void> deleteCancelledBooking(
  String docId, {
  String? workerUid,
  // worker आफैंले cancel गर्‍यो कि employer ले — worker ले cancel गर्दा
  // मात्र त्यसको प्रोफाइलमा strike थपिन्छ (हेर्नुहोस्
  // `recordWorkerCancellation` तल)। Employer ले cancel गर्दा कुनै penalty
  // छैन (Employer लाई जहिले पनि cancel गर्ने अधिकार छ)।
  bool cancelledByWorker = false,
  // "किन cancel गरियो" — पूरै booking doc मेटिने भएकाले (माथिको note
  // हेर्नुहोस्) यो कारण छुट्टै हल्का `cancellations` log मा मात्र बचत हुन्छ,
  // ताकि आफैं कुनै booking history नबन्दी पनि platform-improvement/analytics
  // का लागि "किन धेरैजसो राइड cancel हुन्छन्" भन्ने थाहा पाउन सकियोस्।
  String? reason,
}) async {
  if (reason != null && reason.trim().isNotEmpty) {
    unawaited(() async {
      try {
        await FirebaseFirestore.instance.collection('cancellations').add({
          'requestId': docId,
          'reason': reason.trim(),
          'cancelledByWorker': cancelledByWorker,
          'workerUid': workerUid ?? '',
          'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }());
  }
  try {
    final msgs = await FirebaseFirestore.instance
        .collection('chats')
        .doc(docId)
        .collection('messages')
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final m in msgs.docs) {
      batch.delete(m.reference);
    }
    batch.delete(FirebaseFirestore.instance.collection('chats').doc(docId));
    batch.delete(
        FirebaseFirestore.instance.collection('serviceRequests').doc(docId));
    await batch.commit();
    await FirebaseFirestore.instance.collection('calls').doc(docId).delete();
    unawaited(_deleteChatMedia(docId));
  } catch (_) {
    // safety-net मात्र — मुख्य serviceRequests delete माथिकै batch भित्रै
    // भइसकेको हुन्छ, यहाँको असफलताले "cancelled" अनुभव नरोकोस्।
  }
  if (workerUid != null && workerUid.isNotEmpty) {
    unawaited(releaseWorkerActiveJob(workerUid, docId));
    if (cancelledByWorker) {
      unawaited(recordWorkerCancellation(workerUid));
    }
  }
}

/// राइड/काम cancel गर्दा किन भन्ने छोटो कारण छान्ने — inDrive-शैली छिटो
/// सूची + "Other" ले आफैं टाइप गर्न दिन्छ। प्रयोगकर्ताले sheet बन्द गरे
/// (cancel नै नगर्ने निर्णय) भने null फर्कन्छ — त्यो केसमा caller ले
/// booking कहिल्यै delete नगर्नु पर्छ।
Future<String?> pickCancellationReason(BuildContext context) async {
  final reasons = [
    S.cancelReasonChangedMind,
    S.cancelReasonTooLong,
    S.cancelReasonFoundAnother,
    S.cancelReasonPriceHigh,
    S.cancelReasonWrongLocation,
  ];
  final picked = await showKmSheet<String>(
    context: context,
    title: S.cancelReasonTitle,
    children: [
      for (final r in reasons)
        KmSheetOption(
          icon: Icons.circle_outlined,
          label: r,
          selected: false,
          onTap: () => Navigator.pop(context, r),
        ),
      KmSheetOption(
        icon: Icons.edit_rounded,
        label: S.cancelReasonOther,
        selected: false,
        onTap: () => Navigator.pop(context, '__other__'),
      ),
    ],
  );
  if (picked == null || picked != '__other__') return picked;
  if (!context.mounted) return null;
  final ctrl = TextEditingController();
  final custom = await showKmDialog<String>(
    context: context,
    title: S.cancelReasonOther,
    content: TextField(
      controller: ctrl,
      autofocus: true,
      maxLines: 3,
      style: const TextStyle(color: AppColors.kmText),
      decoration: kmInputDecoration('', hint: S.cancelReasonOtherHint),
    ),
    actions: [
      KmDialogAction(
        label: S.cancel,
        onPressed: () => Navigator.pop(context),
      ),
      KmDialogAction(
        label: S.confirm,
        filled: true,
        onPressed: () => Navigator.pop(context, ctrl.text.trim()),
      ),
    ],
  );
  if (custom == null || custom.isEmpty) return S.cancelReasonOther;
  return custom;
}

/// Worker Cancellation Penalty — worker ले (काम स्वीकार गरिसकेपछि) आफैं
/// cancel गर्दा हरेकपटक `users/{uid}.workerCancelCount` एक-एक बढ्दै जान्छ।
/// यो गन्ती नै भविष्यमा नयाँ broadcast job हरू कतिवटा देखिने भन्ने
/// throttle (हेर्नुहोस् `workerJobVisibilityRate` / `shouldShowJobToWorker`)
/// लाई खुवाउँछ — बारम्बार cancel गर्ने worker ले क्रमशः कम अवसर पाउँदै जान्छ।
/// Employer ले cancel गर्दा यो कहिल्यै बोलाइँदैन (employer लाई कुनै penalty छैन)।
Future<void> recordWorkerCancellation(String workerUid) async {
  try {
    await FirebaseFirestore.instance.collection('users').doc(workerUid).set(
      {'workerCancelCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );
  } catch (_) {
    // penalty tracking असफल भए पनि cancellation आफैं रोकिनु हुँदैन।
  }
}

/// [cancelCount] अनुसार worker ले नयाँ broadcast job हरू मध्ये कति % देख्ने
/// भन्ने throttle दर — बारम्बार cancel गर्ने worker लाई क्रमशः कम अवसर।
/// उदाहरण: १०-मध्ये सामान्यतया सबै देख्ने, धेरै cancel गरिसकेको worker ले
/// १०-मध्ये ३-४ वटा जति मात्र देख्ने।
double workerJobVisibilityRate(int cancelCount) {
  if (cancelCount <= 2) return 1.0; // सुरुको केही cancel — अझै पूरै पहुँच
  if (cancelCount <= 5) return 0.6; // बारम्बार हुन थाल्यो — ६०%
  if (cancelCount <= 9) return 0.4; // धेरैपटक — ४०% (लगभग "१०-मा ४")
  return 0.3; // निरन्तर cancel गर्ने — ३०% (लगभग "१०-मा ३")
}

/// [jobId] यो [cancelCount] भएको worker लाई देखाउने कि नदेखाउने — स्थिर
/// (deterministic) निर्णय, हरेक rebuild/frame मा फरक-फरक नआओस् भनेर (कुनै
/// `Random()` होइन) — उही job doc id ले उही worker लाई सधैँ उही नतिजा दिन्छ,
/// तर फरक-फरक worker/job combination बीच समान रूपमा छरिएको (hash-based)।
bool shouldShowJobToWorker(String jobId, int cancelCount) {
  final rate = workerJobVisibilityRate(cancelCount);
  if (rate >= 1.0) return true;
  final bucket = jobId.hashCode.abs() % 100;
  return bucket < (rate * 100).round();
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
      final workerUid = (data['workerUid'] ?? '').toString();
      // Single Active Job Restriction — employer ले worker कै counter-offer
      // accept गर्ने बेलासम्ममा त्यही worker बीचमा अर्को काम accept गरिसकेको
      // (साँच्चै अझै सक्रिय) भेटिए यहाँ पनि रोक्नुपर्छ, नत्र यो एउटा मात्र
      // बाटो (employer-initiated confirm) हुन्थ्यो जुन single-active-job
      // गेटबाट बाहिर रहन्थ्यो।
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(workerUid);
      final userSnap = await tx.get(userRef);
      final existingActiveId =
          (userSnap.data()?['activeJobId'] ?? '').toString();
      if (existingActiveId.isNotEmpty && existingActiveId != docId) {
        final otherSnap = await tx.get(FirebaseFirestore.instance
            .collection('serviceRequests')
            .doc(existingActiveId));
        final otherStatus = (otherSnap.data()?['status'] ?? '').toString();
        if (kActiveJobStatuses.contains(otherStatus)) {
          throw const WorkerBusyException();
        }
      }
      // Rating-Based Monthly Order Quota — यो नै worker-side तीन बाटो
      // (broadcast claim, listed-price accept, employer counter accept)
      // बाहेकको चौथो बाटो हो (employer-initiated confirm) — यहाँ पनि उही
      // साझा जाँच नगरे यो एउटै बाटोले quota गेट बाइपास गर्न सक्थ्यो।
      consumeOrderQuotaInTransaction(tx, userRef, userSnap.data());
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
      // अहिले (accept गर्ने बेला) भरिदिने। Firestore users/{uid}.phone बाट
      // (Auth कै phoneNumber होइन — इमेलबाट दर्ता भएकाको हकमा त्यो सधैँ खाली)।
      final existingPhone = (data['employerPhone'] as String?)?.trim() ?? '';
      if (existingPhone.isEmpty) {
        final myPhone =
            await myPhoneNumber(FirebaseAuth.instance.currentUser?.uid);
        if (myPhone.isNotEmpty) update['employerPhone'] = myPhone;
      }
      tx.update(ref, update);
      if (workerUid.isNotEmpty) {
        tx.set(userRef, {'activeJobId': docId}, SetOptions(merge: true));
      }
      finalData = {...data, ...update};
    });
  } on StateError {
    messenger.showSnackBar(SnackBar(content: Text(S.staleOfferError)));
    return;
  } on WorkerBusyException {
    messenger.showSnackBar(SnackBar(content: Text(S.workerBusyWithOtherJob)));
    return;
  } on WorkerQuotaExceededException {
    messenger.showSnackBar(SnackBar(content: Text(S.workerQuotaExceeded)));
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
