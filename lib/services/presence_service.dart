// services/presence_service.dart
// हल्का "online/last seen" heartbeat — कुनै अतिरिक्त Firebase product (जस्तै
// Realtime Database) बिना, सिधै Firestore कै `users/{uid}.lastActive` field
// प्रयोग गरेर। App खुला/foreground मा हुँदा हरेक ~२५s मा यो timestamp ताजा
// राखिन्छ; app background/बन्द भएपछि Dart isolate नै रोकिने (वा kill हुने)
// भएकोले यो timer आफैं बन्द हुन्छ — त्यसैले "lastActive भर्खरैको हो कि होइन"
// जाँचेर अर्को पक्ष अहिले साँच्चै एपमा सक्रिय छ कि छैन भन्ने अनुमान लगाउन
// सकिन्छ (WhatsApp/Messenger कै "Online"/"Active X min ago" जस्तै भरपर्दो,
// तर हल्का, हेयुरिस्टिक)।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// यो भन्दा भित्र `lastActive` भेटिए मात्र "Online" मानिन्छ।
const Duration kOnlineFreshWindow = Duration(seconds: 45);

class PresenceService {
  PresenceService._();

  static Timer? _heartbeat;
  static StreamSubscription<User?>? _authSub;

  /// एपको root shell (MainContainer) को initState बाट एकपटक मात्र — signed-in
  /// रहँदासम्म आफैं heartbeat चलाउँछ, sign-out भएमा आफैं रोकिन्छ।
  static void start() {
    if (_authSub != null) return; // पहिल्यै सुरु भइसकेको
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _heartbeat?.cancel();
      _heartbeat = null;
      if (user == null) return;
      _beat(user.uid);
      _heartbeat =
          Timer.periodic(const Duration(seconds: 25), (_) => _beat(user.uid));
    });
  }

  static Future<void> _beat(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'lastActive': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Presence मात्र UX polish हो — नेटवर्क अफ भए पनि एप सामान्य चलिरहन्छ।
    }
  }

  static void stop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _authSub?.cancel();
    _authSub = null;
  }
}
