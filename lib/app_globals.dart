// app_globals.dart
// एपभरि साझा हुने ग्लोबल State र Helper फंक्सनहरू।
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show Locale, ThemeMode, ValueNotifier;

// एपको Theme (Light/Dark/System) नियन्त्रण गर्ने ग्लोबल भेरिएबल।
// inDrive जस्तै default dark; Settings बाट प्रयोगकर्ताले बदल्न सक्छ।
ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// एपको भाषा नियन्त्रण गर्ने ग्लोबल भेरिएबल।
//  'ne' = नेपाली (default), 'en' = English.
// Settings मा touch गर्दा तुरुन्तै पूरै app को भाषा बदलिन्छ (app.dart मा
// MaterialApp यसैको ValueListenableBuilder भित्र छ)।
ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('ne'));

// Profile Photo अस्थायी रूपमा राख्ने (Session भरि मात्र, Firebase Storage आउँदासम्म)
Uint8List? sessionProfilePhoto;

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
