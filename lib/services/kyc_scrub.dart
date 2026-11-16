// services/kyc_scrub.dart
//
// एक-पटकको admin सफाइ — पहिले दर्ता भएका कामदार/होटलका KYC कागजातको
// token-URL (जसले सबै लग इन युजरलाई कागजात खोल्न दिन्थ्यो) लाई Storage path मा
// बदल्छ, र `registeredWorkers` (सबैले पढ्ने सूची) बाट कागजात-लिङ्क पूरै हटाउँछ।
// सेल्फी (अवतार) र certificateUrls (पोर्टफोलियो) छोइँदैन।
//
// नोट: यसले Firestore मा भएका लिङ्क मात्र हटाउँछ। कसैले पहिल्यै प्रतिलिपि
// गरेको पुरानो URL को token Firebase Console → Storage → फाइल → "Access
// token" बाट revoke गरेपछि मात्र निष्क्रिय हुन्छ।
import 'package:cloud_firestore/cloud_firestore.dart';

import 'kyc_url.dart';

const _kycFields = [
  'citizenshipFrontUrl',
  'citizenshipBackUrl',
  'licenseUrl',
  'documentUrl',
  'drivingLicenseUrl',
  'vehicleRegistrationUrl',
  'vehicleInsuranceUrl',
  'routePermitUrl',
];

class KycScrubResult {
  final int converted;
  final int removed;
  final int failed;
  const KycScrubResult(this.converted, this.removed, this.failed);
}

Future<KycScrubResult> scrubKycLinks() async {
  final db = FirebaseFirestore.instance;
  var converted = 0, removed = 0, failed = 0;

  Future<void> sweep(
    String collection,
    Map<String, dynamic>? Function(Map<String, dynamic> d) plan,
    void Function(Map<String, dynamic> update) count,
  ) async {
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      var q = db
          .collection(collection)
          .orderBy(FieldPath.documentId)
          .limit(300);
      if (last != null) q = q.startAfterDocument(last);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      var batch = db.batch();
      var ops = 0;
      for (final d in snap.docs) {
        final update = plan(d.data());
        if (update == null || update.isEmpty) continue;
        batch.update(d.reference, update);
        count(update);
        if (++ops >= 400) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      last = snap.docs.last;
      if (snap.docs.length < 300) break;
    }
  }

  // users / providers / pendingWorkers — http URL → Storage path।
  for (final c in ['users', 'providers', 'pendingWorkers']) {
    await sweep(c, (d) {
      final u = <String, dynamic>{};
      for (final f in _kycFields) {
        final v = (d[f] ?? '').toString();
        if (!v.startsWith('http')) continue;
        final path = kycPathFromUrl(v);
        if (path == null) {
          failed++;
        } else {
          u[f] = path;
        }
      }
      return u;
    }, (u) => converted += u.length);
  }

  // hotels — documentUrls सूची।
  await sweep('hotels', (d) {
    final list = d['documentUrls'];
    if (list is! List || !list.any((e) => e.toString().startsWith('http'))) {
      return null;
    }
    final out = <String>[];
    for (final e in list) {
      final v = e.toString();
      if (!v.startsWith('http')) {
        out.add(v);
        continue;
      }
      final p = kycPathFromUrl(v);
      if (p == null) {
        failed++;
        out.add(v);
      } else {
        out.add(p);
      }
    }
    return {'documentUrls': out};
  }, (_) => converted++);

  // registeredWorkers (सबैले पढ्ने) — कागजात-लिङ्क पूरै हटाउने।
  await sweep('registeredWorkers', (d) {
    final u = <String, dynamic>{};
    for (final f in _kycFields) {
      if (d.containsKey(f)) u[f] = FieldValue.delete();
    }
    return u;
  }, (u) => removed += u.length);

  return KycScrubResult(converted, removed, failed);
}
