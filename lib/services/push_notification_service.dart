// services/push_notification_service.dart
// Firebase Cloud Messaging (worker/employer लाई काम-अपडेट पुर्‍याउने) — token
// capture/refresh, permission request (Android 13+ POST_NOTIFICATIONS सहित),
// foreground मा आफैं local notification देखाउने (Android ले FCM
// `notification` payload लाई app खुला हुँदा आफैं देखाउँदैन), र
// tap/deep-link तीनवटै अवस्थामा (foreground, background, terminated)।
//
// नोट: यो फाइलले client-side receiving/display/token-management मात्र
// गर्छ। वास्तविक push *पठाउन* भने server-side (Cloud Function वा equivalent,
// जसले FCM Admin SDK बाट `admin.messaging().send()` गर्छ) चाहिन्छ — client
// बाट सिधै FCM server key प्रयोग गरेर पठाउनु insecure हुन्छ, त्यसैले यहाँ
// त्यसो गरिएको छैन। सम्बन्धित Cloud Function `functions/index.js` मा तयार
// छ, तर deploy गर्ने/नगर्ने निर्णय project owner कै हो (Firebase Blaze plan
// चाहिन्छ)।
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_globals.dart';
import '../screens/job_actions.dart';
import '../widgets/job_alert_sound.dart';

const String kJobUpdatesChannelId = 'kaammitra_job_updates';

final FlutterLocalNotificationsPlugin _localNotifs =
    FlutterLocalNotificationsPlugin();

/// Firebase ले background isolate मा चलाउने entry point — top-level (कुनै
/// class भित्र होइन) हुनैपर्छ, र `main()` मा runApp() भन्दा अघि नै
/// `FirebaseMessaging.onBackgroundMessage()` मार्फत दर्ता गर्नुपर्छ।
/// Android/iOS ले notification payload भएको message लाई यो नचली नै आफैं
/// system tray मा देखाउँछ — यो handler मुख्यतया data-only message वा भविष्यको
/// थप प्रोसेसिङका लागि।
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._();
  static bool _initialized = false;

  /// `main()` बाट Firebase.initializeApp() पछि एकपटक मात्र बोलाउने।
  static Future<void> init() async {
    if (_initialized || kIsWeb) return; // web मा हाल FCM setup छैन (scope बाहिर)
    _initialized = true;

    await _initLocalNotifications();

    final messaging = FirebaseMessaging.instance;
    // Android 13+ (POST_NOTIFICATIONS) + iOS अनुमति — दुवै यही एउटा call ले।
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // login/logout/account-switch हुनेबित्तिकै token फेरि save (यो app मा
    // testing को लागि धेरै account switch हुन्छ — हरेकपटक सही uid मा token
    // जाओस्)।
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _saveTokenForCurrentUser();
    });
    if (FirebaseAuth.instance.currentUser != null) {
      await _saveTokenForCurrentUser();
    }
    // OS/Google ले token आफैं बदल्दा (rotation) पनि तुरुन्तै अद्यावधिक।
    messaging.onTokenRefresh.listen((_) => _saveTokenForCurrentUser());

    // ── Foreground: OS ले आफैं notification देखाउँदैन — आफैं देखाउने + ting ──
    FirebaseMessaging.onMessage.listen((message) {
      playCounterOfferAlert();
      _showLocalNotification(message);
    });

    // ── Background (app minimized, notification बाट tap गरेर फर्कियो) ──
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // ── Terminated (notification तापेरै app पहिलोपटक खुल्यो) ──
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      await _handleMessageTap(initialMessage);
    }
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifs.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final requestId = response.payload;
        if (requestId != null && requestId.isNotEmpty) {
          navigateToAcceptedJob(requestId);
        }
      },
    );
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        kJobUpdatesChannelId,
        'Job updates',
        description: 'Offer accepted, counter-offers, and job status changes',
        importance: Importance.high,
      );
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notif = message.notification;
    final title = notif?.title ?? message.data['title'] ?? '';
    final body = notif?.body ?? message.data['body'] ?? '';
    if (title.isEmpty && body.isEmpty) return;
    await _localNotifs.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kJobUpdatesChannelId,
          'Job updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data['requestId'] as String?,
    );
  }

  static Future<void> _handleMessageTap(RemoteMessage message) async {
    final requestId = message.data['requestId'] as String?;
    if (requestId != null && requestId.isNotEmpty) {
      await navigateToAcceptedJob(requestId);
    }
  }

  static Future<void> _saveTokenForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': token, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // token/permission असफल भए पनि app चलिरहोस् — in-app notification
      // (Firestore doc) जहिल्यै काम गर्छ, push यसैमा depend गर्दैन।
    }
  }
}

/// Notification tap (push वा local दुवै) बाट सिधै accepted job को live-route
/// screen मा पुर्‍याउने — `job_actions.dart` कै `openJobRoute()` नै प्रयोग
/// गर्छ ताकि accept-पछिको सामान्य flow सँग ठ्याक्कै उस्तै व्यवहार होस्।
Future<void> navigateToAcceptedJob(String requestId) async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('serviceRequests')
        .doc(requestId)
        .get();
    final data = doc.data();
    if (data == null || !ctx.mounted) return;
    openJobRoute(ctx, requestId, data);
  } catch (_) {}
}
