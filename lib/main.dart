// main.dart
// एपको entry point मात्र। असली widget हरू आ-आफ्नै फाइलमा सारिएका छन् र तल
// `export` गरिएका छन्, ताकि `import 'main.dart';` गर्ने पुराना फाइलहरू नबिग्रियोस्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:flutter/material.dart';

import 'app.dart';
import 'app_globals.dart';
import 'firebase_options.dart';
import 'prefs.dart';
import 'services/app_update_service.dart';
import 'services/push_notification_service.dart';

// साझा State/Helper र सबै स्क्रिन — पुराना relative import सँग compatibility को लागि
export 'app.dart' show KaamMitraApp;
export 'app_globals.dart';
// पहिले main.dart मा रहेको तर प्रयोगमा नआएको widget — पुरानो test सँग compatibility को लागि मात्र
export 'legacy/unused_widgets.dart' show MyApp;
export 'screens/bookings_screen.dart';
export 'screens/chat_screen.dart';
export 'screens/help_support_screen.dart';
export 'screens/home_screen.dart';
export 'screens/main_container.dart';
export 'screens/messages_screen.dart';
export 'screens/my_reviews_screen.dart';
export 'screens/notification_screen.dart';
export 'screens/owner_dashboard_screen.dart';
export 'screens/payment_methods_screen.dart';
export 'screens/profile_screen.dart';
export 'screens/saved_workers_screen.dart';
export 'screens/worker_list_screen.dart';
export 'screens/worker_profile_screen.dart';
export 'screens/worker_register_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // कुनै अघिल्लो session/hot-restart बाट बाँकी रहन सक्ने stale guard — यो
  // भएको भरमा MainContainer कै active-job watcher ले route screen auto-open
  // गर्न सधैँका लागि रोकिन सक्थ्यो (त्यो id सँग कहिल्यै नमिल्ने भइदिए पनि)।
  visibleRouteScreenRequestId = null;

  // कुनै पनि widget build त्रुटि आउँदा कालो/खाली स्क्रिनको सट्टा सधैँ देख्न
  // मिल्ने सन्देश देखियोस् — विशेष गरी framework-level assertion (जस्तै
  // duplicate GlobalKey, वा कुनै dialog/popup भित्रको layout त्रुटि) ले
  // Android release/profile रेन्डरिङमा प्रायः केही नदेखाई कालो छोड्छ, जुन
  // debug गर्न असम्भव हुन्छ। debug मा पूरा स्ट्याक ट्रेस (रातो पृष्ठभूमि);
  // release मा प्रयोगकर्तालाई internal स्ट्याक ट्रेस नदेखियोस् भनेर छोटो,
  // सामान्य सन्देश मात्र — तर दुवैमा कम्तिमा केही त देखिन्छ, खाली/कालो
  // होइन।
  ErrorWidget.builder = (FlutterErrorDetails details) => Scaffold(
        backgroundColor: Colors.red.shade900,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              kReleaseMode
                  ? 'Something went wrong displaying this screen.'
                  : details.exceptionAsString(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );

  // Flutter framework-level (widget build) त्रुटि — पहिल्यै माथिको
  // `ErrorWidget.builder` ले render गर्छ, यहाँ थप debug-console log मात्र।
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  // Widget build बाहिर (जस्तै कुनै async callback भित्र) uncaught भएको जुनसुकै
  // error — यसले नरोकी, log मात्र गरेर app लाई जिउँदै राख्छ (नत्र कहिलेकाहीं
  // पूरै isolate/render pipeline नै अड्किएर कालो स्क्रिन दिन्थ्यो)।
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // background/terminated state मा FCM message आउँदा चलाउने handler — Firebase
  // ले यसलाई एउटा छुट्टै isolate मा चलाउने भएकोले `runApp` भन्दा अघि, र
  // top-level function नै (class भित्र होइन) दर्ता गर्नुपर्छ।
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  PushNotificationService.init();

  // Offline-first: हरेक query पहिले local cache बाट instant देखिन्छ, अनि network
  // बाट background मा sync हुन्छ — screen खोल्दा spinner देखिँदैन, tap-हरू छिटो।
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {
    // multi-tab web मा दोस्रो tab ले persistence नपाउन सक्छ — app अझै चल्छ।
  }

  await Prefs.load(); // save गरेको theme/भाषा/notification setting फेरि लोड
  runApp(const KaamMitraApp());

  // App startup मा एकपटक — auto-update जाँच्ने। Login भए/नभए दुवै अवस्थामा
  // चल्छ (Firestore `config/*` सार्वजनिक-पढ्न मिल्ने), ताकि tester ले login
  // गर्नुअघि नै नयाँ APK उपलब्ध छ भन्ने थाहा पाओस्।
  //
  // पहिलो frame पछि तुरुन्तै (postFrameCallback मात्र) नबोलाउने — `app.dart`
  // कै auth/role StreamBuilder cascade (login state → role → verification
  // status → आखिरमा MainContainer) यही समयमा लगातार छिटो-छिटो rebuild भइरहेको
  // हुन्छ; त्यही अस्थिर अवधिमा dialog देखाउँदा त्यो transition सँग collide
  // भएर "app खोल्नेबित्तिकै कालो/खाली स्क्रिन" देखिने गुनासोको मूल कारण
  // देखिएको थियो। यहाँ केही सेकेन्ड पर्खेर (route/UI settle भइसकेपछि) मात्र,
  // र त्यतिबेलाको ताजा context लिएर।
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(seconds: 2), () {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) AppUpdateService.checkForUpdate(ctx);
    });
  });
}
