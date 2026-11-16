// services/connectivity_service.dart
//
// Firestore सर्भरसँग साँच्चै पहुँच छ कि भनेर नियमित रूपमा जाँच्ने — कुनै नयाँ
// package (connectivity_plus आदि) थपिनु पर्दैन, हाल भइरहेकै `config/appUpdate`
// doc (सार्वजनिक-पढ्न मिल्ने, पहिल्यै app startup मा एकपटक पढिने) लाई नै
// जबरजस्ती SERVER बाट (cache बाइपास गरेर) पढ्ने प्रयास गर्छ। सफल भए
// अनलाइन, timeout/असफल भए अफलाइन — नतिजा `app_globals.dart::isOffline` मा।
//
// किन यो एक्लै पर्याप्त छैन भन्ने होइन, बरु किन आवश्यक छ: Firestore को
// `.snapshots()` ले offline हुँदा पनि cache बाटै चुपचाप चलिरहन्छ (persistence
// पहिल्यै सक्रिय) — त्यसैले "म अफलाइन छु" भन्ने कुरा प्रयोगकर्ताले आफैं
// कहिल्यै थाहा पाउँदैनन्, जबसम्म कुनै एक्सन (message पठाउने, काम accept
// गर्ने, call सुरु गर्ने) असफल नभई। यो सेवा ले त्यो स्थिति *अगावै* नै प्रस्ट
// पारिदिन्छ।
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_globals.dart';
import '../screens/job_actions.dart' show webSafeTimeout;

class ConnectivityService {
  ConnectivityService._();

  static Timer? _timer;
  static bool _checking = false;

  static void start() {
    _timer?.cancel();
    unawaited(_check());
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _check());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _check() async {
    // पहिलेको जाँच अझै सकिएको छैन भने (धेरै ढिलो नेटवर्कमा दोहोरिन नदिन)
    // दोस्रोपटक सुरु नगर्ने।
    if (_checking) return;
    _checking = true;
    try {
      await webSafeTimeout(
          FirebaseFirestore.instance
              .collection('config')
              .doc('appUpdate')
              .get(const GetOptions(source: Source.server)),
          const Duration(seconds: 8));
      isOffline.value = false;
    } catch (_) {
      isOffline.value = true;
    } finally {
      _checking = false;
    }
  }
}
