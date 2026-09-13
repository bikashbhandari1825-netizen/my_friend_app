// main.dart
// एपको entry point मात्र। असली widget हरू आ-आफ्नै फाइलमा सारिएका छन् र तल
// `export` गरिएका छन्, ताकि `import 'main.dart';` गर्ने पुराना फाइलहरू नबिग्रियोस्।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'app.dart';
import 'app_globals.dart';
import 'firebase_options.dart';
import 'prefs.dart';
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

  // कुनै पनि widget build त्रुटि आउँदा (debug मा) कालो/खाली स्क्रिनको सट्टा
  // सधैँ देख्न मिल्ने रातो सन्देश देखियोस् — विशेष गरी framework-level
  // assertion (जस्तै duplicate GlobalKey) ले Android release/profile
  // रेन्डरिङमा प्रायः केही नदेखाई कालो छोड्छ, जुन debug गर्न असम्भव हुन्छ।
  // Release build मा भने प्रयोगकर्तालाई internal stack trace नदेखियोस् भनेर
  // Flutter को default grey "something went wrong" नै राखिएको छ।
  if (!kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) => Scaffold(
          backgroundColor: Colors.red.shade900,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                details.exceptionAsString(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
  }
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
}
