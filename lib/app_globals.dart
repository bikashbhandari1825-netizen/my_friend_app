// app_globals.dart
// एपभरि साझा हुने ग्लोबल State र Helper फंक्सनहरू।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart'
    show GlobalKey, Locale, NavigatorState, ThemeMode, ValueNotifier;

// MaterialApp(navigatorKey: rootNavigatorKey) — notification tap ले app लाई
// background/terminated बाट ब्युँझाउँदा कुनै widget को आफ्नै BuildContext
// उपलब्ध हुँदैन; यही global key बाट मात्र route push गर्न मिल्छ।
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// एपको Theme (Light/Dark/System) नियन्त्रण गर्ने ग्लोबल भेरिएबल।
// inDrive जस्तै default dark; Settings बाट प्रयोगकर्ताले बदल्न सक्छ।
ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// एपको भाषा नियन्त्रण गर्ने ग्लोबल भेरिएबल।
//  'en' = English (default — पहिलोपटक खोल्दा, prefs.dart मा कुनै बचत
//  नभएसम्म), 'ne' = नेपाली।
// Settings मा touch गर्दा तुरुन्तै पूरै app को भाषा बदलिन्छ (app.dart मा
// MaterialApp यसैको ValueListenableBuilder भित्र छ), र त्यो छनोट
// prefs.dart ले बचत गरेर भविष्यका सबै launch मा यही डिफल्टभन्दा
// प्राथमिकता पाउँछ।
ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en'));

// एप भित्रको notification देखाउने/नदेखाउने (Settings को toggle — session भरि)।
ValueNotifier<bool> notificationsEnabled = ValueNotifier(true);

// Biometric/Passkey protection — auth/passkey_setup_page.dart (OTP पछिको
// ऐच्छिक step) र Settings को toggle दुवैले यही एउटै global state साझा
// गर्छन् (prefs.dart ले kPasskeyEnabledPrefKey कुञ्जीमै persist गर्छ), ताकि
// जहाँबाट बदले पनि अर्को ठाउँमा तुरुन्तै सिंक देखियोस्। डिफल्ट false —
// कहिल्यै जबरजस्ती होइन, प्रयोगकर्ताले आफैं enable गरेपछि मात्र।
ValueNotifier<bool> biometricEnabled = ValueNotifier(false);

// Firestore सर्भरसँग हाल पहुँच छ/छैन — `services/connectivity_service.dart`
// ले नियमित रूपमा ताजा गर्छ। `services/pending_media_queue.dart` ले यो
// फेरि `true`->`false` हुनेबित्तिकै (नेटवर्क फर्कनेबित्तिकै) पर्खिरहेका
// अपलोड/सन्देश पठाउन सुरु गर्छ। (पहिले यहाँ यो true हुँदा सबै स्क्रिनमाथि
// एउटा "अफलाइन" UI ब्यानर पनि देखिन्थ्यो — प्रयोगकर्तालाई भ्रमित/अनावश्यक
// लागेकोले हटाइयो; यो flag भने अझै माथिको queue-retry प्रयोजनका लागि
// चाहिन्छ।)
ValueNotifier<bool> isOffline = ValueNotifier(false);

/// कल/भ्वाइस-नोट दुवैको लम्बाइ देखाउन साझा — m:ss (घण्टौं लामो कल भए
/// h:mm:ss)। `call_screen.dart` (live timer) र `chat_screen.dart` (call/
/// voice bubble) दुवैले उही ढाँचा प्रयोग गरून् भनेर एउटै ठाउँमा।
String formatDuration(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

// Profile Photo अस्थायी रूपमा राख्ने (Session भरि मात्र, Firebase Storage आउँदासम्म)
Uint8List? sessionProfilePhoto;

// Test login को phone (Anonymous auth सँग phone number जोड्न) — logout मा null।
String? activeTestPhone;

// अहिले स्क्रिनमा नै देखिरहेको route-map (JobRouteScreen/RequestTrackingScreen)
// को requestId — त्यो screen आफैंले initState/dispose मा सेट/खाली गर्छ।
// MainContainer कै active-job watcher ले auto-navigate गर्नुअघि यो जाँच्छ,
// ताकि उपयोगकर्ता पहिल्यै त्यही काम को route screen मा हुँदा (जस्तै आफैं
// त्यहीँबाटै counter-offer accept गर्दा) उही screen दोहोरिएर नखुलियोस्।
String? visibleRouteScreenRequestId;

// Worker/Driver Dashboard (job_feed_screen.dart कै JobsMapLayer — "Open jobs
// near you") MainContainer को IndexedStack भित्रको tab होइन, बरु
// profile_screen.dart बाट Navigator.push गरिएको छुट्टै full-screen route हो
// (आफ्नै live map/AppBar/drawer चाहिने भएकोले)। त्यसैले त्यहाँ MainContainer
// कै साझा bottom nav bar कहिल्यै देखिँदैनथ्यो — worker/driver त्यो screen
// भित्र पसेपछि Home/Bookings/Messages/Profile कुनैमा पनि एक ट्याप तान फर्कन
// नपाई "अड्किएको" (केवल Android back बटन, जसले drawer भएकोले पहिले hamburger
// अनि पछि पूरै app नै बन्द गरिदिन्थ्यो) जस्तो हुन्थ्यो।
//
// अब त्यो screen ले आफ्नै (देखिनमा उस्तै) bottom nav bar देखाउँछ — त्यहाँको
// कुनै पनि ट्याप यही notifier मा चाहिएको tab index राखेर MainContainer सम्म
// (Navigator.popUntil((r) => r.isFirst) ले) फर्कन्छ, र MainContainer ले
// आफ्नो `_currentIndex` यही अनुसार तुरुन्तै अद्यावधिक गर्छ — त्यसैले "Home"
// ट्याप गर्दा role जे भए पनि सधैँ मुख्य Super-App Home Screen मै पुगिन्छ।
final ValueNotifier<int> requestedMainTabIndex = ValueNotifier<int>(0);

// अहिले स्क्रिनमा नै देखिरहेको `CallScreen` (ringing/awaiting-accept वा
// जोडिएको, दुवै) को requestId — `CallScreen` आफैंले initState/dispose मा
// सेट/खाली गर्छ। MainContainer को Firestore-driven incoming-call watcher र
// push-notification tap दुवै बाटोले (एउटै कल दुई ठाउँबाट लगभग एकैसाथ पत्ता
// लाग्न सक्छ — foreground Firestore listener + backgrounded बेला ट्याप
// गरिएको FCM notification) यही जाँचेर उही requestId कै लागि दोहोरो
// CallScreen push नहोस् भनेर।
String? activeCallRequestId;

// जुन uid लाई approval-celebration देखाइसकियो (फेरि नदेखाउन) — logout मा clear।
final Set<String> celebrationShownFor = {};

// जुनसुकै ठाउँबाट Notification बनाउन प्रयोग हुने साझा फंक्सन
Future<void> createNotification(String title, String body) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance.collection('notifications').add({
    'uid': uid,
    'title': title,
    'body': body,
    'read': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// अर्को (अहिले login नभएको) प्रयोगकर्तालाई in-app notification पठाउने —
/// जस्तै employer ले accept गरेपछि worker लाई। `createNotification` (आफैलाई)
/// भन्दा फरक — यहाँ uid caller बाहेकको हुन सक्छ, त्यसैले `data` मा
/// deep-link/context राख्न सकिन्छ (जस्तै `requestId`)।
Future<void> createNotificationForUser(
  String uid,
  String title,
  String body, {
  Map<String, dynamic>? data,
}) async {
  // यो सधैँ best-effort side-effect मात्र हो (मूल काम — offer/accept/
  // counter आदि — यसमा कहिल्यै निर्भर हुँदैन); धेरैजसो caller ले
  // `unawaited(...)` गरी बोलाउँछन्, त्यसैले यहाँ नसमातिए कुनै पनि असफलता
  // (permission/network) uncaught async exception भएर UI मा "Future
  // error" flash हुन्थ्यो — मूल action (जस्तै "प्रस्ताव पठाइयो" भन्ने
  // सफल SnackBar) पहिल्यै देखिसकेपछि पनि।
  try {
    await FirebaseFirestore.instance.collection('notifications').add({
      'uid': uid,
      'title': title,
      'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...?data,
    });
  } catch (_) {}
}

Future<void> createAdminNotification(String title, String body) async {
  await FirebaseFirestore.instance.collection('adminNotifications').add({
    'title': title,
    'body': body,
    'read': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

// सबै स्वीकृत (Approved) कामदारहरूको डाटा रहने ग्लोबल लिस्ट
List<Map<String, String>> registeredWorkers = [
  {
    'name': 'Ram Thapa',
    'service': 'Plumber',
    'rating': '4.8',
    'reviews': '127',
    'experience': '7 years',
    'distance': '1.2 km away',
    'price': 'Rs. 500',
    'location': 'Kathmandu, Nepal',
    'document': 'Plumber_Cert.pdf',
  },
  {
    'name': 'Hari Gurung',
    'service': 'Electrician',
    'rating': '4.6',
    'reviews': '98',
    'experience': '5 years',
    'distance': '2.1 km away',
    'price': 'Rs. 450',
    'location': 'Jhapa, Nepal',
    'document': 'Electrician_License.pdf',
  },
];

// नयाँ रजिस्टर भएका तर एडमिनबाट स्वीकृति लिन बाँकी (Pending) कामदारहरूको लिस्ट
List<Map<String, String>> pendingWorkers = [];

// सेवा अनुरोधहरू (Service Requests) राख्ने ग्लोबल लिस्ट
List<Map<String, String>> serviceRequests = [
  {
    'workerName': 'Ram Thapa',
    'service': 'Plumber',
    'userName': 'Rajesh Nepal',
    'details': 'Kitchen pipe leakage repair',
    'status': 'Confirmed', // Pending वा Confirmed
    'date': '25 May, 2024 - 10:00 AM',
  }
];
