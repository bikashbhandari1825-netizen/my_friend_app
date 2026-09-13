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
//  'ne' = नेपाली (default), 'en' = English.
// Settings मा touch गर्दा तुरुन्तै पूरै app को भाषा बदलिन्छ (app.dart मा
// MaterialApp यसैको ValueListenableBuilder भित्र छ)।
ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('ne'));

// एप भित्रको notification देखाउने/नदेखाउने (Settings को toggle — session भरि)।
ValueNotifier<bool> notificationsEnabled = ValueNotifier(true);

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
  await FirebaseFirestore.instance.collection('notifications').add({
    'uid': uid,
    'title': title,
    'body': body,
    'read': false,
    'createdAt': FieldValue.serverTimestamp(),
    ...?data,
  });
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
