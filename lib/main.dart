// main.dart
// एपको entry point मात्र। असली widget हरू आ-आफ्नै फाइलमा सारिएका छन् र तल
// `export` गरिएका छन्, ताकि `import 'main.dart';` गर्ने पुराना फाइलहरू नबिग्रियोस्।
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding, runApp;

import 'app.dart';
import 'firebase_options.dart';

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
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const KaamMitraApp());
}
