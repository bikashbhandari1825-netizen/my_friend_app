// screens/job_actions.dart
// Job feed र Requests दुवैले प्रयोग गर्ने साझा action: broadcast काम स्वीकार्ने,
// मूल्य प्रस्ताव (counter) गर्ने, वा अस्वीकार गर्ने।
//
// नोट: Phase 3 (full multi-bid) मा accept/counter ले bids sub-collection प्रयोग
// गर्नेछ; अहिले पहिलो जवाफ दिने कामदारले काम claim गर्छ।
import '../utils/price_input.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../location_util.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'call_screen.dart';
import 'job_route_screen.dart';

// ── Rapid Double-Tap / Concurrent Transaction Guard ─────────────────────
// साझा गरिएको — काम/राइड accept गर्ने transaction-आधारित function हरू
// (claimJobForWorker, acceptRideOffer, acceptWorkerCounterOffer) ले प्रयोग
// गर्छन्। पहिले यी बटनहरूमा कुनै re-entrancy guard थिएन — छिटो double-tap
// (वा ठ्याक्कै त्यही क्षण दुई ठाउँबाट उही docId मा एकैचोटि accept गर्ने
// प्रयास) ले उही docId मा दुई समानान्तर `runTransaction` सुरु गराउँथ्यो।
// live logcat मा नै "INTERNAL ASSERTION FAILED: A transaction object
// cannot be used after its update callback has been invoked" (cloud_firestore
// plugin को native/platform-channel layer मा) यही race बाट आएको हो — दुई
// transaction ले एउटै underlying native handle साझा गर्दा। अब हरेक
// docId (key) मा एकैचोटि एउटा मात्र transaction चल्न पाउँछ — दोस्रो/तेस्रो
// ट्याप चुपचाप बेवास्ता हुन्छ (पहिलोले नै handle गरिरहेको हुन्छ), न कि
// क्र्यास वा डुप्लिकेट लेखाइ।
final Set<String> _inFlightOfferActions = {};

// Stuck-Guard Safety Net — माथिकै guard मा `finally` ले सामान्यतया key
// रिलिज गर्छ, तर `op()` (native Firestore transaction) आफैं कहिल्यै
// नसेटल भई अनन्तकालसम्म पर्खिरहे (जस्तै network partition, वा प्लगिनकै
// आफ्नै internal state बिग्रिएको दुर्लभ अवस्था) भने `finally` कहिल्यै
// नचल्ने भएकोले त्यो key सधैंभरिलाई "in-flight" नै अडिन्थ्यो — त्यसपछि
// त्यही docId मा फेरि जतिपटक ट्याप गरे पनि बटनले केही नगर्ने (हरेक ट्याप
// यही function ले चुपचाप बेवास्ता गर्ने) देखिन्थ्यो, ठ्याक्कै "बटन आफैं
// मरेको/नचल्ने" गुनासो जस्तो। अब `.timeout()` ले बढीमा यति समयपछि आफैं
// असफल मानी key रिलिज गर्छ — प्रयोगकर्ताले फेरि ट्याप गर्न पाउँछन्।
// १ मिनेटसम्म ढिलो देखिने गुनासोको साँचो जड यिनै 20s timeout हरू थिए —
// एउटा Firestore लेखाइ 20s कुरेर मात्र असफल ठहरिने, अनि retryTransient
// (तल) ले त्यही 20s फेरि-फेरि (बढीमा 3 पटक) दोहोर्‍याउँदा बढीमा ~60s
// सम्म बटन/स्क्रिन उस्तैको-उस्तै देखिन्थ्यो।
//
// GPS-Timeout Mismatch Fix — यो 10s मा घटाउँदा एउटा नयाँ बग थपियो: Accept
// (`_acceptRideAtListedPriceImpl`) ले आफ्नै transaction अघि नै
// `workerLocationForWrite()` मार्फत एउटा साँचो GPS fix माग्छ, जसको आफ्नै
// भित्री समय-सीमा (`location_util.dart::getCurrentLocation`) नै १२
// सेकेन्ड हो — यो बाहिरी १० सेकेन्ड भन्दा लामो! जहिल्यै GPS ले साँच्चै
// (ठीकै, cold-fix जस्तो सामान्य कारणले — जस्तै location अनुमति भर्खरै
// दिएकै क्षण) नजिकैको समय लिन्थ्यो, यो बाहिरी timeout नै भित्री GPS
// आफैं टुंगिनुअघि नै चलिहाल्थ्यो — Accept चुपचाप "टाइमआउट" भई असफल
// हुन्थ्यो, card पहिल्यै हराइसकेको (`onAction()`) हुँदा प्रयोगकर्ताले
// "थिचेपछि केही भएन" जस्तो देख्थे। अब भित्री GPS cap (१२s) भन्दा स्पष्ट
// बढी (कम्तिमा केही सेकेन्ड थप Firestore round-trip का लागि) राखिएको।
const _kOfferActionTimeout = Duration(seconds: 16);

/// Flutter Web-विशेष JS-interop crash बाट बच्न — `cloud_firestore_web` को
/// Future JS Promise (interop) माथि बनेको हुन्छ। बाहिरबाट `.timeout()` ले
/// बीचमै "हार मानिदिंदा" पनि underlying JS promise आफैं भने background मै
/// चलिरहन्छ — पछि त्यो साँच्चै resolve/reject हुँदा (पहिल्यै timeout
/// भइसकेको Future मा) interop glue code confuse भई `TypeError: instance of
/// 'TimeoutException': type 'TimeoutException' is not a subtype of type
/// 'JavaScriptObject'` crash दिन्छ (live Chrome screenshot मा नै समातिएको)।
/// Android/iOS मा यो जोखिम छैन (native SDK, कुनै JS interop होइन) —
/// त्यसैले web मा [future] लाई जस्ताको-त्यस्तै फर्काउने (Firestore SDK
/// आफैंको भरपर्दो internal connectivity/retry मा भर पर्दै), अरू platform मा
/// मात्र [timeout] पछि TimeoutException।
Future<T> webSafeTimeout<T>(Future<T> future, Duration timeout) =>
    kIsWeb ? future : future.timeout(timeout);

Future<void> _onceAt(String key, Future<void> Function() op) async {
  if (_inFlightOfferActions.contains(key)) return;
  _inFlightOfferActions.add(key);
  try {
    await webSafeTimeout(op(), _kOfferActionTimeout);
  } finally {
    _inFlightOfferActions.remove(key);
  }
}

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

Future<String> myWorkerName(String? uid,
    {FirebaseAuth? auth, FirebaseFirestore? firestore}) async {
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  String name = user?.displayName ?? '';
  try {
    final u = await (firestore ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(uid)
        .get();
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
Future<String> myPhoneNumber(String? uid,
    {FirebaseAuth? auth, FirebaseFirestore? firestore}) async {
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  String phone = user?.phoneNumber ?? '';
  try {
    final u = await (firestore ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(uid)
        .get();
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

/// Dashboard Clutter Cleanup — Driver/Rider Hub (worker_requests_page.dart)
/// ले यी टर्मिनल status (हेर्नुहोस् widgets/status_badge.dart माथिकै
/// lifecycle comment — step: -1/3, अब कहिल्यै फेरि active नहुने) भएका,
/// ४ दिनभन्दा पुरानो (`createdAt`) भइसकेका request आफ्नो live list बाट
/// लुकाउँछ। Firestore बाट मेटिँदैन, केवल view-level filter हो।
const kStaleTerminalJobStatuses = {
  'completed',
  'declined',
  'cancelled',
  'no_provider',
};

const kDashboardStaleAfter = Duration(days: 4);

// ── Communication Never Locks ───────────────────────────────────────────
// Call/Video/Chat booking/job status जे भए पनि (completed/cancelled/
// declined/no_provider समेत) सधैं खुला — पहिले यहाँ केवल accepted/confirmed/
// in_progress (`kActiveJobStatuses`) मात्र थियो, काम सकिएपछि "This job is
// completed. Chat & calls are closed" देखिने र tracking screen बाटै Call/
// Video/Message बटन नै हराउने गुनासोको जड। एउटै साझा ठाउँबाट जाँच्ने, हरेक
// call/video/chat button ले आफ्नै छुट्टै status-set नबनाओस्।
bool isCommunicationUnlocked(String? status) => true;

/// worker आफैं व्यस्त भएकोले (अर्को सक्रिय काम भइरहेको) यो काम accept/confirm
/// गर्न नमिल्ने भएको बेला throw हुने — caller ले पक्डेर स्पष्ट सन्देश देखाउनुहोस्।
class WorkerBusyException implements Exception {
  const WorkerBusyException();
  @override
  String toString() => 'worker_busy_with_active_job';
}

/// Self-Ride Prevention — आफैंले पोस्ट गरेको अनुरोध (employerUid == worker
/// आफैंको uid) आफैं accept/offer/claim गर्न खोज्दा throw हुने। Client-side
/// filter (`job_feed_screen.dart::_pickEligibleCandidates`) ले सामान्य
/// अवस्थामा त्यस्तो अनुरोध नदेखाइहाल्छ, तर यो transaction-तहको जाँच नै
/// साँचो सुरक्षा सीमा हो (UI bypass भए पनि यहाँ रोकिन्छ)।
class SelfBookingException implements Exception {
  const SelfBookingException();
  @override
  String toString() => 'cannot_accept_own_request';
}

/// Web-only bug — `Firestore.runTransaction()` भित्रबाट throw भएको custom
/// Dart exception (WorkerBusyException/WorkerQuotaExceededException/
/// StateError('stale_offer')) JS Promise हुँदै फर्कँदा आफ्नो *type identity*
/// गुमाउन सक्छ (dart2js/DDC को JS-interop सीमा — native Android/iOS मा यो
/// JS round-trip नै हुँदैन, त्यहाँ सधैँ सहि type भेटिन्छ)। नतिजा: web मा
/// `on WorkerBusyException catch` जस्ता typed catch कहिल्यै मेल नखाने, र
/// प्रयोगकर्ताले सधैँ Dart आफैंको असहयोगी raw म्यासेज ("Dart exception
/// thrown from converted Future...") मात्र देख्ने — त्यो म्यासेज आफैंले
/// नै सुझाएको उपाय (`.error` property बाट साँचो boxed error निकाल्ने) यहाँ
/// प्रयोग गरिएको। Type भन्दा *string* (stringification) मा जाँच्नुको कारण:
/// यो JS round-trip मा पनि `toString()` जोगिन्छ, type होइन।
String friendlyOfferErrorMessage(Object e, {String? staleOfferMessage}) {
  Object unwrapped = e;
  try {
    final inner = (e as dynamic).error;
    if (inner != null) unwrapped = inner;
  } catch (_) {}
  final s = unwrapped.toString();
  if (unwrapped is WorkerBusyException ||
      s.contains('worker_busy_with_active_job')) {
    return S.workerBusyWithOtherJob;
  }
  if (unwrapped is WorkerQuotaExceededException ||
      s.contains('worker_order_quota_exceeded')) {
    return S.workerQuotaExceeded;
  }
  if (unwrapped is SelfBookingException ||
      s.contains('cannot_accept_own_request')) {
    return S.cannotAcceptOwnRequest;
  }
  if (s.contains('stale_offer')) {
    return staleOfferMessage ?? S.offerNoLongerAvailable;
  }
  return '${S.errorWord}: $s';
}

/// TESTING ONLY — असली launch अघि हटाउने। Monthly Order Quota (rating
/// अनुसार) live-testing बेला बारम्बार भेटिने वास्तविक, सही व्यवहार हो (bug
/// होइन) — तर एउटै test account ले हरेकपटक साँच्चै अर्को महिना पर्खनु
/// नपरोस् भनेर, quota-सकियो भन्ने SnackBar मै सिधै एउटा "Reset" action
/// थपिदिने।
SnackBar offerErrorSnackBar(BuildContext context, Object e,
    {String? staleOfferMessage}) {
  final msg =
      friendlyOfferErrorMessage(e, staleOfferMessage: staleOfferMessage);
  if (msg != S.workerQuotaExceeded) return SnackBar(content: Text(msg));
  return SnackBar(
    content: Text(msg),
    action: SnackBarAction(
      label: 'TEST: Reset',
      onPressed: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({'orderQuotaUsed': 0});
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order quota reset (testing).')),
          );
        } catch (_) {}
      },
    ),
  );
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
int monthlyOrderQuotaForRating(
    {required num ratingSum, required int reviewCount}) {
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
  final usedSoFar = storedMonth == month
      ? ((userData?['orderQuotaUsed'] as num?) ?? 0).toInt()
      : 0;

  final overrideLimit = (userData?['orderLimitOverride'] as num?)?.toInt();
  int limit;
  if (overrideLimit != null) {
    limit = overrideLimit;
  } else {
    final ratingOverride = (userData?['ratingOverride'] as num?);
    if (ratingOverride != null) {
      // ratingOverride सिधै star मान (०-५) हो — sum/count बनावट चाहिँदैन।
      limit =
          monthlyOrderQuotaForRating(ratingSum: ratingOverride, reviewCount: 1);
    } else {
      final ratingSum = (userData?['ratingSum'] as num?) ?? 0;
      final reviewCount = ((userData?['ratingCount'] as num?) ?? 0).toInt();
      limit = monthlyOrderQuotaForRating(
          ratingSum: ratingSum, reviewCount: reviewCount);
    }
  }

  if (usedSoFar >= limit) {
    throw const WorkerQuotaExceededException();
  }

  tx.set(
      userRef,
      {
        'orderQuotaMonth': month,
        'orderQuotaUsed': usedSoFar + 1,
      },
      SetOptions(merge: true));
}

/// Review थपिएपछि (`complete_job_sheet.dart::_confirm()`) worker को
/// `registeredWorkers` entry (nearby list ले पढ्ने cached rating/reviews)
/// लाई पनि ताजा राख्ने — नत्र त्यहाँ admin approve गरेको दिनकै (वा पुरानो)
/// मान सधैंभरि देखिन्थ्यो, साँचो review जति आए पनि कहिल्यै नबदलिने।
/// Best-effort/fire-and-forget — असफल भए पनि completion flow लाई असर पर्दैन।
Future<void> syncWorkerRatingToRegisteredWorkers(String workerUid) async {
  if (workerUid.isEmpty) return;
  try {
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(workerUid)
        .get();
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
/// [firestore] — testability का लागि मात्र (नदिए production कै
/// `FirebaseFirestore.instance`) — कुनै हालको caller ले यो param कहिल्यै
/// नपठाउने भएकोले व्यवहार अपरिवर्तित।
Future<void> claimJobForWorker({
  required String docId,
  required String workerUid,
  required Map<String, dynamic> updateFields,
  FirebaseFirestore? firestore,
}) =>
    _onceAt(
        'claim:$docId',
        () => _claimJobForWorkerImpl(
              docId: docId,
              workerUid: workerUid,
              updateFields: updateFields,
              firestore: firestore,
            ));

Future<void> _claimJobForWorkerImpl({
  required String docId,
  required String workerUid,
  required Map<String, dynamic> updateFields,
  FirebaseFirestore? firestore,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final jobRef = db.collection('serviceRequests').doc(docId);
  final userRef = db.collection('users').doc(workerUid);
  await db.runTransaction((tx) async {
    final jobSnap = await tx.get(jobRef);
    final employerUid = (jobSnap.data()?['employerUid'] ?? '').toString();
    if (employerUid.isNotEmpty && employerUid == workerUid) {
      throw const SelfBookingException();
    }
    final userSnap = await tx.get(userRef);
    final existingId = (userSnap.data()?['activeJobId'] ?? '').toString();
    if (existingId.isNotEmpty && existingId != docId) {
      final otherSnap =
          await tx.get(db.collection('serviceRequests').doc(existingId));
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

/// TESTING ONLY — असली launch अघि हटाउने। "Finish your current job first"
/// जहाँ-जहाँ देखिन्छ त्यहीँ छेउमै राख्न मिल्ने सानो, self-contained बटन —
/// कुनै props नचाहिने (ट्याप गर्दा नै आफैं हालको `activeJobId` पढेर खाली
/// गर्छ), ताकि हरेक ठाउँमा data/callback तान्नु नपरोस्।
class TestingClearActiveJobButton extends StatelessWidget {
  const TestingClearActiveJobButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.kmRose,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        visualDensity: VisualDensity.compact,
        backgroundColor: AppColors.kmRose.withValues(alpha: 0.12),
      ),
      icon: const Icon(Icons.science_rounded, size: 15),
      label: const Text('TEST: Clear',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
      onPressed: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        final messenger = ScaffoldMessenger.of(context);
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final activeId = (snap.data()?['activeJobId'] ?? '').toString();
        if (activeId.isEmpty) return;
        await releaseWorkerActiveJob(uid, activeId);
        messenger.showSnackBar(
          const SnackBar(content: Text('Active job cleared (testing).')),
        );
      },
    );
  }
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
  } catch (e) {
    // Silent-Failure Fix — "Accept थिचेपछि केही नभएको/अड्किएको जस्तो"
    // गुनासोको साँचो जड: caller (job offer card) ले Accept थिचेकै क्षण
    // overlay/card तुरुन्तै हटाउँछ (`onAction()`, माथि अर्कै ठाउँमा — card
    // तुरुन्तै नहटाए "accept पछि पनि केही सेकेन्ड देखिरहने" भन्ने अर्कै
    // गुनासो आउँथ्यो)। accept transaction त्यो card हटिसकेपछि मात्र
    // (async round-trip) असफल भयो भने, यो `context` (card कै) प्रायः
    // त्यतिञ्जेल unmounted भइसक्छ — अघिको `if (!context.mounted) return`
    // ले त्यसैले त्रुटि-सन्देश नै चुपचाप निलिदिन्थ्यो, प्रयोगकर्ताले कुनै
    // संकेत नपाई "केही भएन/अड्कियो" जस्तो देख्थे। `messenger` भने (async
    // gap भन्दा *अघि* नै capture भएको, card होइन — माथिकै persistent
    // Scaffold सँग बाँधिएको) जहिल्यै सुरक्षित प्रयोग गर्न मिल्छ, context
    // mounted भए/नभए पनि।
    // ignore: use_build_context_synchronously
    messenger.showSnackBar(offerErrorSnackBar(context, e));
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
  // Dead Send/Cancel Fix — यो dialog खुलेको लामो बेल हुन सक्छ (मूल्य टाइप
  // गर्दै); त्यो बाहिरी context सम्बन्धित job card आफैंले यही tap मा चलाएको
  // `onAction()` (Auto-Dismiss) ले तुरुन्तै disposed भइसक्छ। पहिले यहाँ
  // केवल `if (!context.mounted) return;` गार्ड थपिएको थियो (crash त रोकियो,
  // तर त्यसको साइड-इफेक्टको रूपमा Send/Cancel दुवै चुपचाप केही नगरी
  // "dead/frozen" देखिन थाले — ठ्याक्कै यही गुनासोको जड)। nearby_common.
  // dart::_send() कै उस्तै साँचो fix — context होइन, सधैं mounted रहने
  // NavigatorState/ScaffoldMessengerState नै dialog खोल्नुअघि नै समातेर
  // राख्ने।
  final navigator = Navigator.of(context, rootNavigator: true);
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
              'counterFrom': 'worker',
              'counteredAt': FieldValue.serverTimestamp(),
              ...await workerLocationForWrite(uid),
            });
            messenger.showSnackBar(
                const SnackBar(content: Text('नयाँ मूल्य ग्राहकलाई पठाइयो।')));
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

// ── Direct Offer (status: 'pending_worker') — employer ले worker_list_
// screen.dart/worker_profile_screen.dart बाट सिधै एक worker लाई पठाएको
// अनुरोध (broadcasting होइन, त्यसैले `_stillOpen`/claimJobForWorker कै
// धेरै-worker-race assumption यहाँ लागू हुँदैन — एउटै worker लाई addressed
// भएकोले race नै हुँदैन)। worker_requests_page.dart::_RequestCard भित्रका
// private handler (_acceptAtListedPrice/_counterDialog/_declineFromCounter)
// कै उस्तै ढाँचा — job_feed_screen.dart कै "Open jobs near you" floating
// overlay मा पनि अब यही status को card देखिन थालेकोले (Driver mode सँगै
// उस्तै live popup दिन), त्यहाँबाट पनि प्रयोग हुन यी साझा गरिएका।

/// Direct Offer लाई सूचीबद्ध मूल्यमै accept गर्ने।
Future<void> acceptDirectOffer(
    BuildContext context, String docId, Map<String, dynamic> data) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final messenger = ScaffoldMessenger.of(context);
  try {
    // Instant Accept Fix — पहिले यहाँ `workerLocationForWrite(uid)` (live
    // GPS कोसिस, भित्री ~12s cap) नै `status: 'accepted'` सँगै एउटै लेखाइमा
    // sequentially await हुन्थ्यो — accept नै GPS fix नआएसम्म/cap नटुटेसम्म
    // रोकिन्थ्यो (१५-२०s सम्म देखिने ढिलाइको साँचो जड)। अब accept फोन
    // नम्बर (छिटो Firestore पढाइ) मात्रमा भर पर्छ; स्थान पछि (claim सफल
    // भइसकेपछि) छुट्टै non-blocking follow-up update मार्फत थपिन्छ।
    final phone = await myPhoneNumber(uid);
    await claimJobForWorker(
      docId: docId,
      workerUid: uid,
      updateFields: {
        'status': 'accepted',
        'finalPrice': data['proposedPrice'],
        'acceptedAt': FieldValue.serverTimestamp(),
        'workerPhone': phone,
      },
    );
    unawaited(workerLocationForWrite(uid).then((loc) {
      if (loc.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('serviceRequests')
            .doc(docId)
            .update(loc);
      }
    }).catchError((_) {}));
    messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));
  } catch (e) {
    if (!context.mounted) return;
    // ignore: use_build_context_synchronously
    messenger.showSnackBar(offerErrorSnackBar(context, e));
  }
}

/// Direct Offer मा नयाँ मूल्य प्रस्ताव फिर्ता पठाउने (employer को पुष्टि चाहिने)।
Future<void> counterDirectOffer(
    BuildContext context, String docId, Map<String, dynamic> data,
    {String? myService}) async {
  if (!await workerSkillMatchesJob(data, workerService: myService)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.notAuthorizedForJobCategory)));
    return;
  }
  final suggested = (data['proposedPrice'] as num?)?.toInt() ?? 500;
  final controller = TextEditingController(text: suggested.toString());
  if (!context.mounted) return;
  // Dead Send/Cancel Fix — यो dialog खोल्ने caller प्रायः job-feed कार्डको
  // context हो, जुन त्यही tap मा चलेको `onAction()` (Auto-Dismiss — कार्ड
  // list बाट तुरुन्तै हराउने) ले dialog खुल्नेबित्तिकै disposed हुन्छ।
  // dialog आफैं खुल्छ (उही synchronous call stack मै हुन्छ, disposal अझै
  // process नभएको), तर प्रयोगकर्ताले पछि (मूल्य टाइप गरेर) Send/Cancel
  // थिच्दा सम्म त्यो पुरानो context साँच्चै unmounted भइसक्छ — त्यहीँको
  // `if (!context.mounted) return;` ले चुपचाप केही नगरी फर्किन्थ्यो, Send/
  // Cancel दुवै "dead/frozen" देखिने गुनासोको साँचो जड यही थियो। nearby_
  // common.dart::_send() कै उस्तै fix — context होइन, सधैं mounted रहने
  // NavigatorState/ScaffoldMessengerState नै dialog खोल्नुअघि नै समातेर
  // राख्ने (ती State object आफैं भने त्यो disposed card मा भर पर्दैनन्)।
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  await showKmDialog(
    context: context,
    title: S.offerPrice,
    icon: Icons.local_offer_rounded,
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
                const SnackBar(content: Text('नयाँ मूल्य ग्राहकलाई पठाइयो।')));
          } catch (e) {
            messenger
                .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
          }
        },
      ),
    ],
  );
}

/// Direct Offer लाई अस्वीकार गर्ने — `declineBroadcastJob` कै `rejectedBy`
/// array (धेरै worker मध्ये कसैले हेरेन भन्ने अर्थ) भन्दा फरक: यहाँ सिधै
/// `status: 'declined'` नै लेख्ने (एउटै worker लाई addressed भएकोले,
/// employer ले आफ्नो RequestTrackingScreen मा तुरुन्तै थाहा पाओस्)।
Future<void> declineDirectOffer(String docId) async {
  try {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .update({
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
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
  // Self-Ride Prevention — आफैंले पोस्ट गरेको राइड अनुरोधमा आफैं driver भएर
  // प्रस्ताव पठाउन नपाओस्।
  if ((data['employerUid'] ?? '').toString() == uid) {
    messenger.showSnackBar(SnackBar(content: Text(S.cannotAcceptOwnRequest)));
    return;
  }
  try {
    // Instant-Response Fix — पहिले यी ४ वटा स्वतन्त्र (एउटाले अर्कोको
    // नतिजामा भर नपर्ने) पढाइ (नाम, फोन, गाडी/रेटिङ, GPS स्थान) एक-एक
    // गरी क्रमैसँग (sequential) कुर्थे — हरेकको आफ्नै नेटवर्क round-trip
    // (+GPS fix, बिस्तारै हुन सक्ने) जोडिँदा Accept/Offer थिचेपछि साँच्चै
    // लेखिनुअघि नै धेरै सेकेन्ड "केही नभएको जस्तो" देखिन्थ्यो — ठ्याक्कै
    // "Accept बटन instant/तुरुन्तै प्रतिक्रिया नदिने" गुनासोको ठूलो हिस्सा।
    // अब सबै समानान्तर (concurrent) — कुल समय सबैभन्दा ढिलो एउटा
    // operation बराबर मात्र हुन्छ, जम्मा homerof होइन।
    Future<DocumentSnapshot<Map<String, dynamic>>?> fetchUserDoc() async {
      try {
        return await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
      } catch (_) {
        return null;
      }
    }

    final (name, phone, userSnap, loc) = await (
      myWorkerName(uid),
      myPhoneNumber(uid),
      fetchUserDoc(),
      // प्रस्ताव पठाउने ठ्याक्कै क्षणको driver-स्थान — passenger को खोजी
      // स्क्रिनमा नक्सामा देखाउन (worker प्रस्ताव पठाउनेबित्तिकै कहाँ थियो
      // भन्ने एउटा स्थिर snapshot; लगातार लाइभ movement होइन — त्यो चाहिँदा
      // worker-तर्फ background GPS stream चाहिन्छ, अझै छैन)।
      workerLocationForWrite(uid),
    ).wait;

    double rating = 0;
    int completedRides = 0;
    String vehicleDetails = '';
    String vehicleMake = '';
    String vehicleModel = '';
    String vehiclePlate = '';
    final u = userSnap;
    vehicleDetails = (u?.data()?['vehicleDetails'] ?? '').toString();
    vehicleMake = (u?.data()?['vehicleMake'] ?? '').toString();
    vehicleModel = (u?.data()?['vehicleModel'] ?? '').toString();
    vehiclePlate = (u?.data()?['vehiclePlate'] ?? '').toString();
    final sum = (u?.data()?['ratingSum'] as num?) ?? 0;
    final count = (u?.data()?['ratingCount'] as num?) ?? 0;
    if (count > 0) rating = sum / count;
    completedRides = ((u?.data()?['completedRidesCount'] as num?) ?? 0).toInt();
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
    // Real-Time Notification Reliability — passenger ले यो क्षण साँच्चै
    // tracking screen हेरिरहेको नहुन सक्छ (अर्को app मा, वा फोन बन्द)।
    // Firestore live listener ले त्यो बेला केही देखाउँदैन — यहीँ real FCM
    // push (functions/index.js कै generic `notifications` relay मार्फत)
    // पठाइन्छ ताकि driver को नयाँ प्रस्ताव कहिल्यै "हराउँदैन"।
    final employerUid = (data['employerUid'] ?? '').toString();
    if (employerUid.isNotEmpty) {
      unawaited(createNotificationForUser(
        employerUid,
        S.newRideOfferNotifTitle,
        S.newRideOfferNotifBody(name, price),
        data: {'requestId': docId, 'type': 'new_ride_offer'},
      ));
    }
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
/// [firestore] — testability का लागि मात्र (माथिकै `claimJobForWorker`
/// doc-comment हेर्नुहोस्); नदिए production कै `FirebaseFirestore.instance`।
Future<void> acceptRideOffer(BuildContext context, String docId, String offerId,
        Map<String, dynamic> offer,
        {FirebaseFirestore? firestore}) =>
    _onceAt(
        'acceptOffer:$docId',
        () => _acceptRideOfferImpl(
              context,
              docId,
              offerId,
              offer,
              firestore: firestore,
            ));

Future<void> _acceptRideOfferImpl(BuildContext context, String docId,
    String offerId, Map<String, dynamic> offer,
    {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final messenger = ScaffoldMessenger.of(context);
  final ref = db.collection('serviceRequests').doc(docId);
  final workerUid = (offer['workerUid'] ?? '').toString();
  Map<String, dynamic>? finalData;

  try {
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final status = (data?['status'] ?? '').toString();
      if (data == null ||
          (status != 'broadcasting' && status != 'pending_worker')) {
        throw StateError('stale_offer');
      }
      final userRef = db.collection('users').doc(workerUid);
      final userSnap = await tx.get(userRef);
      final existingActiveId =
          (userSnap.data()?['activeJobId'] ?? '').toString();
      if (existingActiveId.isNotEmpty && existingActiveId != docId) {
        final otherSnap = await tx
            .get(db.collection('serviceRequests').doc(existingActiveId));
        final otherStatus = (otherSnap.data()?['status'] ?? '').toString();
        if (kActiveJobStatuses.contains(otherStatus)) {
          throw const WorkerBusyException();
        }
      }
      consumeOrderQuotaInTransaction(tx, userRef, userSnap.data());
      final price =
          (offer['offerPrice'] as num?) ?? (data['proposedPrice'] as num?) ?? 0;
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
        // Vehicle Details Persistence — `offer` (rideOffers/{uid}, submitRideOffer
        // ले लेखेको) मा यी पहिल्यै छन्, तर पहिले यहाँ parent serviceRequests
        // doc मा कहिल्यै कपी हुँदैनथे — accept भएपछि passenger को live-
        // tracking screen (request_tracking_screen.dart::_ProviderTrackCard,
        // जसले parent doc कै field पढ्छ, offer doc होइन) मा गाडीको
        // नम्बर प्लेट/मोडेल कहिल्यै नदेखिने गुनासोको साँचो जड यही थियो।
        'vehicleMake': offer['vehicleMake'],
        'vehicleModel': offer['vehicleModel'],
        'vehiclePlate': offer['vehiclePlate'],
        'vehicleDetails': offer['vehicleDetails'],
      };
      tx.update(ref, update);
      if (workerUid.isNotEmpty) {
        tx.set(userRef, {'activeJobId': docId}, SetOptions(merge: true));
      }
      tx.update(
          ref.collection('rideOffers').doc(offerId), {'status': 'accepted'});
      finalData = {...data, ...update};
    });
  } catch (e) {
    // Silent-Failure Fix — माथि `acceptBroadcastJob` कै उस्तै doc-comment
    // हेर्नुहोस्: `messenger` async gap भन्दा अघि नै capture भएकोले, offer
    // card (`context`) त्यतिञ्जेल unmounted भए पनि यो त्रुटि-सन्देश सुरक्षित
    // देखाउन मिल्छ — चुपचाप निलिने होइन।
    // ignore: use_build_context_synchronously
    messenger.showSnackBar(offerErrorSnackBar(context, e));
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

/// Ride Direct-Accept — driver ले passenger कै सूचीबद्ध मूल्यमै "Accept"
/// थिच्दा (custom counter होइन), `claimJobForWorker`/`acceptBroadcastJob`
/// कै उस्तै ढाँचामा तुरुन्तै/सिधै राइड confirm हुने — passenger को छुट्टै
/// अनुमोदन कहिल्यै चाहिँदैन (पहिले यो पनि `submitRideOffer` मार्फत एउटा
/// "प्रस्ताव" मात्र बन्थ्यो, जुन passenger ले अरू driver-प्रस्तावसँगै छानेर
/// मात्र confirm हुन्थ्यो — त्यही नै "Accept थिचेपछि पनि passenger को
/// पुष्टि किन चाहियो" गुनासोको जड थियो)। Custom मूल्य ("Offer Price") भने
/// अझै पहिलेकै ढाँचामा — passenger ले नै छान्नुपर्छ, किनभने त्यो मूल्य
/// passenger ले आफैं तोकेको होइन।
///
/// एकैचोटि धेरै driver ले "Accept" थिचे पनि — पहिलो जसको transaction
/// पहिले पुग्छ त्यसैले मात्र पाउँछ (status अझै 'broadcasting'/
/// 'pending_worker' भएमा मात्र)। पछिका सबैले [S.offerNoLongerAvailable]
/// देख्छन् — ठ्याक्कै `claimJobForWorker` कै broadcast-job race-safety।
Future<void> acceptRideAtListedPrice(
        BuildContext context, String docId, Map<String, dynamic> data,
        {FirebaseFirestore? firestore, FirebaseAuth? auth}) =>
    _onceAt(
        'acceptOffer:$docId',
        () => _acceptRideAtListedPriceImpl(context, docId, data,
            firestore: firestore, auth: auth));

Future<void> _acceptRideAtListedPriceImpl(
    BuildContext context, String docId, Map<String, dynamic> data,
    {FirebaseFirestore? firestore, FirebaseAuth? auth}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final messenger = ScaffoldMessenger.of(context);
  final uid = (auth ?? FirebaseAuth.instance).currentUser?.uid;
  if (uid == null) return;
  final ref = db.collection('serviceRequests').doc(docId);

  // Instant Accept — Optimistic/Decoupled Location Fix — पहिले यहाँ
  // `workerLocationForWrite(uid)` (live GPS कोसिस, भित्री ~12s cap) पनि यही
  // सुरुको parallel-read block मै थियो, र त्यसको नतिजा (`...loc`) तलको
  // transaction कै एउटै लेखाइ (`status: 'accepted'` सहित) भित्र spread
  // हुन्थ्यो — अर्थात् दुवै पक्षले पर्खिरहेको "accepted" स्थिति-परिवर्तन नै
  // GPS fix आउने/cap नटुटेसम्म (गरी १५-२०s सम्म) रोकिन्थ्यो, ठ्याक्कै
  // "Accept थिचेपछि राइड सुरु हुन धेरै ढिला हुने" गुनासोको साँचो जड। अब
  // status flip गर्ने transaction (तल) केवल छिटो Firestore पढाइहरू (नाम/
  // फोन/गाडी) मा मात्र भर पर्छ — GPS कहिल्यै होइन; स्थान पछि (transaction
  // सफल भइसकेपछि, तल) छुट्टै non-blocking follow-up update मार्फत थपिन्छ।
  final (name, phone, vehicleSnap) = await (
    myWorkerName(uid, auth: auth, firestore: db),
    myPhoneNumber(uid, auth: auth, firestore: db),
    db.collection('users').doc(uid).get(),
  ).wait;
  // Vehicle Details Persistence — _acceptRideOfferImpl कै उस्तै जड, यहाँ
  // (direct-accept बाटो, कुनै rideOffers doc नहुने) driver कै आफ्नै profile
  // बाटै सिधै पढेर parent doc मा लेखिन्छ, नत्र accept भएपछि passenger को
  // live-tracking screen मा गाडीको विवरण कहिल्यै नदेखिने।
  final vehicleData = vehicleSnap.data();
  final vehicleMake = (vehicleData?['vehicleMake'] ?? '').toString();
  final vehicleModel = (vehicleData?['vehicleModel'] ?? '').toString();
  final vehiclePlate = (vehicleData?['vehiclePlate'] ?? '').toString();
  final vehicleDetails = (vehicleData?['vehicleDetails'] ?? '').toString();

  try {
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final jobData = snap.data();
      final status = (jobData?['status'] ?? '').toString();
      if (jobData == null ||
          (status != 'broadcasting' && status != 'pending_worker')) {
        throw StateError('stale_offer');
      }
      final employerUid = (jobData['employerUid'] ?? '').toString();
      if (employerUid.isNotEmpty && employerUid == uid) {
        throw const SelfBookingException();
      }
      final userRef = db.collection('users').doc(uid);
      final userSnap = await tx.get(userRef);
      final existingActiveId =
          (userSnap.data()?['activeJobId'] ?? '').toString();
      if (existingActiveId.isNotEmpty && existingActiveId != docId) {
        final otherSnap = await tx
            .get(db.collection('serviceRequests').doc(existingActiveId));
        final otherStatus = (otherSnap.data()?['status'] ?? '').toString();
        if (kActiveJobStatuses.contains(otherStatus)) {
          throw const WorkerBusyException();
        }
      }
      consumeOrderQuotaInTransaction(tx, userRef, userSnap.data());
      final price = (jobData['proposedPrice'] as num?) ?? 0;
      tx.update(ref, {
        'status': 'accepted',
        'finalPrice': price,
        'agreedAmount': price,
        'acceptedAt': FieldValue.serverTimestamp(),
        'workerUid': uid,
        'workerName': name,
        'workerPhone': phone,
        'vehicleMake': vehicleMake,
        'vehicleModel': vehicleModel,
        'vehiclePlate': vehiclePlate,
        'vehicleDetails': vehicleDetails,
      });
      tx.set(userRef, {'activeJobId': docId}, SetOptions(merge: true));
    });
  } catch (e) {
    // Silent-Failure Fix — माथिकै `acceptBroadcastJob`/`_acceptRideOfferImpl`
    // doc-comment हेर्नुहोस्: offer card Accept थिचेकै क्षण हटिसक्ने भएकोले
    // (`onAction()`), यो त्रुटि सामान्यतया card unmounted भइसकेपछि नै आउँछ —
    // `messenger` (async gap भन्दा अघि capture भएको, card सँग बाँधिएको
    // होइन) प्रयोग गरेर सधैँ सुरक्षित देखाउने, चुपचाप निलिने होइन (नत्र
    // "Accept थिचेपछि केही भएन/अड्कियो" जस्तो देखिन्छ, जबकि वास्तवमा
    // accept असफल भएको हो)।
    // ignore: use_build_context_synchronously
    messenger.showSnackBar(offerErrorSnackBar(context, e));
    return;
  }

  // Fast-Follow Location — transaction (माथि) सफल भइसकेपछि मात्र, GPS
  // पर्खेर राइड स्वीकृति नै नरोकियोस् भनेर। यो असफल भए पनि राइड पहिल्यै
  // accepted छँदैछ — चुपचाप best-effort (JobRouteScreen खोलेपछि उसैले पनि
  // आफ्नै लाइभ स्थान पठाउँछ, त्यसैले यहाँ नपुगे पनि लामो समय खाली रहँदैन)।
  unawaited(workerLocationForWrite(uid).then((loc) {
    if (loc.isNotEmpty) ref.update(loc);
  }).catchError((_) {}));

  if (!context.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(S.jobAccepted)));
  // MainContainer कै active-job watcher ले यो status बदलिएको देखेर आफैं
  // route screen खोल्छ — passenger तर्फ पनि उसकै live tracking stream ले
  // सिधै 'accepted' UI देखाउँछ, छुट्टै push notification नचाहिने
  // (acceptBroadcastJob कै उस्तै — passenger सामान्यतया त्यही screen हेरिरहेकै हुन्छ)।

  // बाँकी कुनै custom counter-offer (अरू driver ले पहिल्यै पठाएको भए) अब
  // सान्दर्भिक छैन — best-effort decline (transaction भन्दा बाहिर)।
  try {
    final others = await ref
        .collection('rideOffers')
        .where('status', isEqualTo: 'pending')
        .get();
    for (final d in others.docs) {
      d.reference.update({'status': 'declined'});
    }
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
    BuildContext context, String docId, String offerId, num currentPrice,
    {required String workerUid}) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController(text: currentPrice.toString());
  // Dead Send/Cancel Fix — job_feed_screen.dart::_openOfferDialog कै उस्तै
  // साँचो fix — यो बाहिरी context हो, live rideOffers list ले यो offer
  // card नै हटाइदिए (driver ले फिर्ता लियो, वा ride अन्तै भइसक्यो) dialog
  // खुलिरहेकै बेला unmounted हुन सक्छ — पहिले `context.mounted` मात्र
  // जाँचिँदा Send/Cancel दुवै त्यो race मा चुपचाप "dead/frozen" देखिन्थे।
  // context होइन, सधैं mounted रहने NavigatorState नै dialog खोल्नुअघि नै
  // समातेर राख्ने।
  final navigator = Navigator.of(context, rootNavigator: true);
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
          if (!navigator.mounted) return;
          navigator.pop();
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
            if (workerUid.isNotEmpty) {
              unawaited(createNotificationForUser(
                workerUid,
                S.newCounterOfferNotifTitle,
                S.newCounterOfferNotifBody(newPrice),
                data: {'requestId': docId, 'type': 'passenger_countered'},
              ));
            }
          } catch (e) {
            // पहिले यहाँ चुपचाप (`catch (_) {}`) — `driverCounterOffer` कै
            // उस्तै जड (लेखाइ असफल भए passenger लाई कुनै संकेत नै नदेखिने,
            // अनि driver ले counter-offer कहिल्यै नपाउने)। अब स्पष्ट त्रुटि।
            // `messenger` आफैं सधैं mounted रहने State object हो — context
            // जाँच्नु पर्दैन।
            messenger
                .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
          }
        },
      ),
    ],
  );
}

/// driver ले passenger कै counter मूल्य स्वीकार्दा — यो नै अन्तिम/साँचो
/// acceptance हो। पहिले यहाँ offer doc मात्र 'pending' मा फर्काइन्थ्यो
/// (passenger ले फेरि आफैं Accept थिच्नुपर्ने "mutual consent" चरण) —
/// त्यसैले driver ले "Accept" थिचेपछि राइड सिधै सुरु नभई counter-offer
/// नै फेरि passenger तिर फर्केको/bounce भएको जस्तो देखिन्थ्यो। अब
/// `_acceptRideOfferImpl` कै उस्तै पूरा transaction — parent
/// `serviceRequests` doc सिधै 'accepted' मा जान्छ, driver ले थप कुनै
/// पुष्टि पर्खनुपर्दैन।
Future<void> driverAcceptPassengerCounter(
    BuildContext context, String docId, String offerId, num newPrice,
    {required String employerUid}) async {
  final messenger = ScaffoldMessenger.of(context);
  final db = FirebaseFirestore.instance;
  final ref = db.collection('serviceRequests').doc(docId);
  final offerRef = ref.collection('rideOffers').doc(offerId);
  try {
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final status = (data?['status'] ?? '').toString();
      if (data == null ||
          (status != 'broadcasting' && status != 'pending_worker')) {
        throw StateError('stale_offer');
      }
      final offerSnap = await tx.get(offerRef);
      final offer = offerSnap.data() ?? const <String, dynamic>{};
      final workerUid = (offer['workerUid'] ?? offerId).toString();
      final userRef = db.collection('users').doc(workerUid);
      final userSnap = await tx.get(userRef);
      final existingActiveId =
          (userSnap.data()?['activeJobId'] ?? '').toString();
      if (existingActiveId.isNotEmpty && existingActiveId != docId) {
        final otherSnap = await tx
            .get(db.collection('serviceRequests').doc(existingActiveId));
        final otherStatus = (otherSnap.data()?['status'] ?? '').toString();
        if (kActiveJobStatuses.contains(otherStatus)) {
          throw const WorkerBusyException();
        }
      }
      consumeOrderQuotaInTransaction(tx, userRef, userSnap.data());
      tx.update(ref, {
        'status': 'accepted',
        'finalPrice': newPrice,
        'agreedAmount': newPrice,
        'acceptedAt': FieldValue.serverTimestamp(),
        'workerUid': workerUid,
        'workerName': offer['workerName'],
        'workerPhone': offer['workerPhone'],
        'vehicleMake': offer['vehicleMake'],
        'vehicleModel': offer['vehicleModel'],
        'vehiclePlate': offer['vehiclePlate'],
        'vehicleDetails': offer['vehicleDetails'],
      });
      tx.set(userRef, {'activeJobId': docId}, SetOptions(merge: true));
      // Clear Negotiation State — offer doc आफैं पनि 'accepted' मा, अब
      // कुनै थप counter-offer payload नचलोस् भनेर `passengerCounterPrice`
      // हटाइन्छ।
      tx.update(offerRef, {
        'status': 'accepted',
        'offerPrice': newPrice,
        'passengerCounterPrice': FieldValue.delete(),
      });
    });
    // बाँकी कुनै अरू pending प्रस्ताव अब सान्दर्भिक छैन — transaction भन्दा
    // बाहिर, best-effort decline (`_acceptRideOfferImpl` कै उस्तै ढाँचा)।
    try {
      final others =
          await ref.collection('rideOffers').where('status', whereIn: [
        'pending',
        'passenger_countered'
      ]).get();
      for (final d in others.docs) {
        if (d.id == offerId) continue;
        d.reference.update({'status': 'declined'});
      }
    } catch (_) {}
    if (employerUid.isNotEmpty) {
      unawaited(createNotificationForUser(
        employerUid,
        S.driverAcceptedCounterNotifTitle,
        S.driverAcceptedCounterNotifBody,
        data: {'requestId': docId, 'type': 'driver_accepted_counter'},
      ));
    }
  } catch (e) {
    // पहिले चुपचाप — लेखाइ असफल भए driver लाई केही संकेत नै नदेखिने, र
    // passenger ले कहिल्यै अपडेट नपाउने गुनासोको सम्भाव्य जड।
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
  }
}

Future<void> driverDeclinePassengerCounter(
    BuildContext context, String docId, String offerId,
    {required String employerUid}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(docId)
        .collection('rideOffers')
        .doc(offerId)
        .update({'status': 'declined'});
    if (employerUid.isNotEmpty) {
      unawaited(createNotificationForUser(
        employerUid,
        S.driverDeclinedCounterNotifTitle,
        S.driverDeclinedCounterNotifBody,
        data: {'requestId': docId, 'type': 'driver_declined_counter'},
      ));
    }
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
  }
}

/// driver ले passenger-को counter मूल्य स्वीकार्ने वा अस्वीकार गर्नुको सट्टा
/// आफ्नै अर्को (तेस्रो) मूल्य फिर्ता पठाउन — बाइ-डाइरेक्शनल बिडिङ यहीँबाट
/// धेरै round सम्म चलिरहन सक्छ (offer फेरि 'pending' मा फर्कन्छ, passenger
/// ले फेरि Accept/Decline/Counter गर्न पाउँछ — `negotiateRideOffer` कै loop)।
Future<void> driverCounterOffer(
    BuildContext context, String docId, String offerId, num currentCounterPrice,
    {required String employerUid}) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller =
      TextEditingController(text: currentCounterPrice.toString());
  // Dead Send/Cancel Fix — job_feed_screen.dart::_openOfferDialog कै उस्तै
  // साँचो fix — बाहिरी context, live offer card dialog खुलिरहेकै बेला
  // unmounted हुन सक्ने। context होइन, सधैं mounted रहने NavigatorState नै
  // dialog खोल्नुअघि नै समातेर राख्ने।
  final navigator = Navigator.of(context, rootNavigator: true);
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
          if (!navigator.mounted) return;
          navigator.pop();
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
            if (employerUid.isNotEmpty) {
              unawaited(createNotificationForUser(
                employerUid,
                S.newCounterOfferNotifTitle,
                S.newCounterOfferNotifBody(newPrice),
                data: {'requestId': docId, 'type': 'driver_countered'},
              ));
            }
          } catch (e) {
            // पहिले यहाँ चुपचाप (`catch (_) {}`) — लेखाइ नै असफल भए
            // (जस्तै stale/हटिसकेको offer doc) driver लाई कुनै संकेत नै
            // नदेखिने, र passenger ले नयाँ मूल्य कहिल्यै नपाउने ("counter-
            // offer पठाएपछि passenger मा नदेखिने" गुनासोको सम्भाव्य जड)।
            // अब कम्तिमा स्पष्ट त्रुटि देखिने — `messenger` सधैं mounted
            // रहने State object हो, context जाँच्नु पर्दैन।
            messenger
                .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
          }
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
  // [firestore] — testability का लागि मात्र (माथिकै `claimJobForWorker`
  // doc-comment हेर्नुहोस्); नदिए production कै `FirebaseFirestore.instance`।
  FirebaseFirestore? firestore,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  if (reason != null && reason.trim().isNotEmpty) {
    unawaited(() async {
      try {
        await db.collection('cancellations').add({
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
  // महत्वपूर्ण भाग — यो असफल भए (जस्तै permission-denied/network) caller
  // लाई थाहा नै नपाई चुपचाप बेवास्ता हुनु हुँदैन (पहिले यहाँ `catch (_) {}`
  // थियो — त्यसैले असफल भए पनि booking Firestore मा उस्तै-को-उस्तै
  // रहिरहन्थ्यो, तर caller ले "cancel भइसक्यो" भनेर screen pop गर्दिन्थ्यो/
  // केही संकेत नै नदेखाउँथ्यो — counter-offer मा भेटिएकै उस्तै जड,
  // "Cancel बटन थिचेर पनि केही नहुने" गुनासोको सम्भाव्य कारण)। अब यहाँ
  // throw हुन दिइन्छ, caller (request_tracking_screen.dart::_cancel,
  // widgets/active_job_bar.dart::_confirmCancel) ले स्पष्ट त्रुटि देखाउँछ।
  // यहाँ पहिले कुनै `.timeout()` नै थिएन — नेटवर्क साँच्चै खराब भए यो
  // Firestore SDK कै आन्तरिक retry मा अनन्तकालसम्म (60s भन्दा बढी समेत)
  // अडिन सक्थ्यो, "Cancel गर्दा धेरै ढिलो हुने" गुनासोको अर्को सम्भावित
  // जड। dispatch (माथि `retryTransient`) सँगै मिल्दो 10s bound।
  if (reason != null && reason.trim().isNotEmpty) {
    // अर्को पक्षलाई कारण पुर्‍याउने — booking doc मेटिएपछि उसले कारण कहीँबाट
    // पढ्न नसक्ने भएकाले मेटिनु अघि नै `cancelNotices/{docId}` मा राखिन्छ।
    // best-effort: असफल भए पनि cancel आफैं रोकिँदैन।
    try {
      final booking = await webSafeTimeout(
          db.collection('serviceRequests').doc(docId).get(),
          const Duration(seconds: 5));
      final b = booking.data();
      final targetUid =
          (b?[cancelledByWorker ? 'employerUid' : 'workerUid'] ?? '')
              .toString();
      if (targetUid.isNotEmpty) {
        await webSafeTimeout(
            db.collection('cancelNotices').doc(docId).set({
              'targetUid': targetUid,
              'reason': reason.trim(),
              'cancelledByWorker': cancelledByWorker,
              'createdAt': FieldValue.serverTimestamp(),
            }),
            const Duration(seconds: 5));
      }
    } catch (_) {}
  }
  final msgs = await webSafeTimeout(
      db.collection('chats').doc(docId).collection('messages').get(),
      const Duration(seconds: 10));
  final batch = db.batch();
  for (final m in msgs.docs) {
    batch.delete(m.reference);
  }
  batch.delete(db.collection('chats').doc(docId));
  batch.delete(db.collection('serviceRequests').doc(docId));
  await webSafeTimeout(batch.commit(), const Duration(seconds: 10));
  // गैर-महत्वपूर्ण सफाइ — serviceRequests माथिकै batch मा नै मेटिसकेको
  // भएकोले (cancel आफैं भइसकेको), यहाँ असफल भए पनि silent catch नै ठीक।
  try {
    await db.collection('calls').doc(docId).delete();
  } catch (_) {}
  unawaited(_deleteChatMedia(docId));
  if (workerUid != null && workerUid.isNotEmpty) {
    unawaited(releaseWorkerActiveJob(workerUid, docId));
    if (cancelledByWorker) {
      unawaited(recordWorkerCancellation(workerUid));
    }
  }
}

/// अर्को पक्षले cancel गर्दा छानेको कारण (`deleteCancelledBooking` ले राखेको)
/// पढ्छ र एकपटक देखाइसकेपछि नदोहोरियोस् भनेर मेट्छ। कारण नभए null।
Future<String?> takeCancelNoticeReason(String docId) =>
    _cancelNoticeCache.putIfAbsent(docId, () => _readCancelNotice(docId));

// एउटै cancel लाई एकै समय दुई screen (route screen + app-shell) ले सुन्छन्;
// पहिलोले मेटिदिँदा दोस्रोले कारण नगुमाओस् भनेर नतिजा साझा राखिन्छ।
final _cancelNoticeCache = <String, Future<String?>>{};

Future<String?> _readCancelNotice(String docId) async {
  try {
    final ref = FirebaseFirestore.instance.collection('cancelNotices').doc(docId);
    final snap = await ref.get();
    final reason = (snap.data()?['reason'] ?? '').toString().trim();
    if (snap.exists) unawaited(ref.delete().catchError((_) {}));
    return reason.isEmpty ? null : reason;
  } catch (_) {
    return null;
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

/// केवल क्षणिक (नेटवर्क/सर्भर-साइड अस्थायी) त्रुटिमा मात्र true — यिनैमा
/// मात्र retry गर्नु सान्दर्भिक छ। permission-denied/invalid-argument
/// जस्ता स्थायी त्रुटिमा दोहोर्‍याउँदा केही फरक पर्दैन, केवल प्रयोगकर्ताले
/// त्रुटि देख्न थप पर्खनुपर्ने मात्र हुन्छ।
bool isTransientDispatchError(Object e) {
  if (e is TimeoutException) return true;
  if (e is FirebaseException) {
    const transientCodes = {
      'unavailable',
      'deadline-exceeded',
      'aborted',
      'internal',
      'resource-exhausted',
      'cancelled',
      'unknown',
    };
    return transientCodes.contains(e.code);
  }
  return false;
}

/// [op] लाई चलाउने — नेटवर्क क्षणिक अवरोध (timeout/unavailable/aborted) भए
/// बढीमा [maxAttempts] पटकसम्म, बढ्दो delay (backoff) सहित सुरक्षित रूपमा
/// दोहोर्‍याउँछ। स्थायी त्रुटि (जस्तै permission-denied) भए तुरुन्तै
/// rethrow, बेकारमा पर्खिरहनु पर्दैन। [onAttemptFailed], दिइएमा, हरेक असफल
/// प्रयासपछि (अन्तिम प्रयास सहित, rethrow गर्नुअघि) बोलाइन्छ — caller
/// आफैंले टर्मिनल/log मा ट्रेस गर्न। [op] आफैं idempotent हुनु caller कै
/// जिम्मा हो — Firestore मा नयाँ doc बनाउने लेखाइका लागि यसको मतलब `.add()`
/// (हरेक पटक नयाँ auto-ID, दोहोरिँदा duplicate doc बन्ने जोखिम) होइन, बरु
/// client-side पहिले नै बनेको स्थिर doc ID मा `.set()` (setDocWithRetry
/// तल हेर्नुहोस्) — पहिलो प्रयासको लेखाइ साँच्चै सर्भरमा पुगिसकेको तर
/// acknowledgment मात्र client सम्म नपुगेको (timeout) अवस्थामा पनि
/// दोहोरिँदा त्यही उस्तै doc फेरि लेखिन्छ, कहिल्यै duplicate बन्दैन।
Future<T> retryTransient<T>(
  Future<T> Function() op, {
  int maxAttempts = 3,
  // 20s थियो — 3 प्रयास × 20s = बढीमा ~60s सम्म पर्खिरहनु पर्ने (ठ्याक्कै
  // "1 मिनेटसम्म ढिलो" गुनासोको जड, Chrome debug log मा नै
  // `TimeoutException after 0:00:20.000000` भेटिएर पुष्टि भएको)। 10s मा
  // झारेर बढीमा ~30s मा झारियो।
  Duration timeout = const Duration(seconds: 10),
  Duration Function(int attempt)? backoff,
  void Function(int attempt, int maxAttempts, Object error, bool transient)?
      onAttemptFailed,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await webSafeTimeout(op(), timeout);
    } catch (e) {
      final isLastAttempt = attempt == maxAttempts;
      final transient = isTransientDispatchError(e);
      onAttemptFailed?.call(attempt, maxAttempts, e, transient);
      if (isLastAttempt || !transient) rethrow;
      await Future.delayed(
          backoff?.call(attempt) ?? Duration(milliseconds: 600 * attempt));
    }
  }
  throw StateError('unreachable');
}

/// [ref] (पहिले नै client-side बनेको, कुनै लेखाइ नभएको doc ID — `collection(..)
/// .doc()` बाट, `.add()` होइन) मा [data] सुरक्षित रूपमा दोहोर्‍याउँदै लेख्ने
/// — [retryTransient] कै Firestore-विशिष्ट सुविधा-wrapper, doc-comment
/// त्यहीँ हेर्नुहोस्।
Future<void> setDocWithRetry(
  DocumentReference<Map<String, dynamic>> ref,
  Map<String, dynamic> data, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 10),
  Duration Function(int attempt)? backoff,
  void Function(int attempt, int maxAttempts, Object error, bool transient)?
      onAttemptFailed,
}) =>
    retryTransient(
      () => ref.set(data),
      maxAttempts: maxAttempts,
      timeout: timeout,
      backoff: backoff,
      onAttemptFailed: onAttemptFailed,
    );

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
/// [firestore] — testability का लागि मात्र (माथिकै `claimJobForWorker`
/// doc-comment हेर्नुहोस्); नदिए production कै `FirebaseFirestore.instance`।
Future<void> acceptWorkerCounterOffer(BuildContext context, String docId,
        {FirebaseFirestore? firestore}) =>
    _onceAt(
        'acceptCounter:$docId',
        () => _acceptWorkerCounterOfferImpl(context, docId,
            firestore: firestore));

Future<void> _acceptWorkerCounterOfferImpl(BuildContext context, String docId,
    {FirebaseFirestore? firestore}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final messenger = ScaffoldMessenger.of(context);
  final ref = db.collection('serviceRequests').doc(docId);
  Map<String, dynamic>? finalData;

  try {
    await db.runTransaction((tx) async {
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
      final userRef = db.collection('users').doc(workerUid);
      final userSnap = await tx.get(userRef);
      final existingActiveId =
          (userSnap.data()?['activeJobId'] ?? '').toString();
      if (existingActiveId.isNotEmpty && existingActiveId != docId) {
        final otherSnap = await tx
            .get(db.collection('serviceRequests').doc(existingActiveId));
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
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
        offerErrorSnackBar(context, e, staleOfferMessage: S.staleOfferError));
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
