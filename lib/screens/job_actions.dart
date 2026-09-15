// screens/job_actions.dart
// Job feed र Requests दुवैले प्रयोग गर्ने साझा action: broadcast काम स्वीकार्ने,
// मूल्य प्रस्ताव (counter) गर्ने, वा अस्वीकार गर्ने।
//
// नोट: Phase 3 (full multi-bid) मा accept/counter ले bids sub-collection प्रयोग
// गर्नेछ; अहिले पहिलो जवाफ दिने कामदारले काम claim गर्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
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

/// worker आफैं व्यस्त भएकोले (अर्को सक्रिय काम भइरहेको) यो काम accept/confirm
/// गर्न नमिल्ने भएको बेला throw हुने — caller ले पक्डेर स्पष्ट सन्देश देखाउनुहोस्।
class WorkerBusyException implements Exception {
  const WorkerBusyException();
  @override
  String toString() => 'worker_busy_with_active_job';
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
}) async {
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
  } catch (_) {
    // safety-net मात्र — मुख्य serviceRequests delete माथिकै batch भित्रै
    // भइसकेको हुन्छ, यहाँको असफलताले "cancelled" अनुभव नरोकोस्।
  }
  if (workerUid != null && workerUid.isNotEmpty) {
    unawaited(releaseWorkerActiveJob(workerUid, docId));
  }
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
