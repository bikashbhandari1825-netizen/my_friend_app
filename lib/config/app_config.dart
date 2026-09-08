// config/app_config.dart
// App owner ले बदल्न सक्ने setting हरू (Firestore `config` collection मा)।
import 'package:cloud_firestore/cloud_firestore.dart';

/// Contact Support नम्बर — Firestore: config/support { phone: "..." }
class SupportConfig {
  SupportConfig._();

  static final _doc =
      FirebaseFirestore.instance.collection('config').doc('support');

  /// Live support नम्बर (सेट नभए null/खाली)।
  static Stream<String> phoneStream() => _doc.snapshots().map((s) {
        final data = s.data();
        return (data?['phone'] ?? '').toString().trim();
      });

  static Future<String> phoneOnce() async {
    final s = await _doc.get();
    return (s.data()?['phone'] ?? '').toString().trim();
  }

  /// Admin ले नम्बर सेट/अपडेट गर्ने।
  static Future<void> setPhone(String phone) => _doc.set(
        {'phone': phone.trim(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
}
