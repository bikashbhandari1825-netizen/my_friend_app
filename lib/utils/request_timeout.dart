// utils/request_timeout.dart
//
// खुला (broadcasting) राइड/काम अनुरोधको म्याद — कसैले स्वीकार नगरे अनिश्चित
// कालसम्म खुला नरहोस्। तीन तह:
//   १. यात्रीको स्क्रिनमा ५ मिनेटको गणना; सकिएपछि "भाडा बढाउनुहोस् / पर्खिरहनुहोस्
//      / रद्द" को छनोट।
//   २. Driver को सूचीमा १० मिनेटभन्दा पुरानो अनुरोध नदेखाउने।
//   ३. सर्भरमा (`expireStaleRequests` function) १० मिनेटभन्दा पुराना खुला
//      अनुरोध `no_provider` बनाउने — एप बन्द भएको यात्रीको अनुरोध पनि सफा हुन्छ।
import 'package:cloud_firestore/cloud_firestore.dart';

/// यात्रीले पर्खने समय (सेकेन्ड) — सकिएपछि छनोट सोधिन्छ।
const int kRequestTimeoutSec = 300;

/// "पर्खिरहनुहोस्" थिचेपछि थपिने समय (सेकेन्ड)।
const int kRequestExtendSec = 180;

/// यसभन्दा पुरानो खुला अनुरोध driver लाई नदेखाउने (सर्भरले पनि यही सीमामा
/// `no_provider` बनाउँछ — functions/requestExpiry.js मा उही मान राख्नुहोस्)।
const int kRequestStaleSec = 600;

/// अनुरोध "सक्रिय भएको" पछिल्लो समय — सिर्जना वा पछिल्लो भाडा-वृद्धि
/// (`fareRaisedAt`) मध्ये पछिल्लो। timestamp अझै सर्भरले नलेखेको (null) भए
/// null फर्काउँछ — ताजा मानिन्छ।
DateTime? requestActiveSince(Map<String, dynamic> data) {
  DateTime? best;
  for (final k in const ['createdAt', 'fareRaisedAt']) {
    final v = data[k];
    if (v is Timestamp) {
      final d = v.toDate();
      if (best == null || d.isAfter(best)) best = d;
    }
  }
  return best;
}

/// खुला अनुरोध driver लाई देखाउन धेरै पुरानो भयो कि।
bool isRequestStale(Map<String, dynamic> data) {
  final since = requestActiveSince(data);
  if (since == null) return false;
  return DateTime.now().difference(since).inSeconds > kRequestStaleSec;
}
