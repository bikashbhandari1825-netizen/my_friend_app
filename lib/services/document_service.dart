// services/document_service.dart
//
// प्रदायकको कागजात Firebase Storage मा राख्ने र URL फर्काउने।
// फोल्डर स्ट्रक्चर: documents/{uid}/<type>.<ext>   (जस्तै: documents/abc123/license.jpg)
//
// सुरक्षा: upload अघि साइज/extension/magic-byte जाँच (UploadValidation),
// filename allowlist बाटै बनाइन्छ (user-supplied नाम प्रयोग हुँदैन), र
// contentType बाइट-signature बाट सेट हुन्छ।
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'upload_validation.dart';

class DocumentService {
  DocumentService._();

  /// Storage मा document upload गरेर download URL फर्काउँछ।
  /// [type] = 'license', 'selfie', 'certificate' आदि (allowlist)।
  /// फाइल अमान्य भए [FormatException] फ्याँक्छ (message देखाउन मिल्ने)।
  static Future<String> uploadDocument({
    required String uid,
    required Uint8List bytes,
    required String originalName,
    String type = 'document',
  }) async {
    final err = UploadValidation.validate(bytes, originalName);
    if (err != null) {
      throw FormatException(UploadValidation.messageFor(err));
    }

    final safeType = _safeType(type);
    final ext = UploadValidation.safeExtension(originalName);
    final path = 'documents/$uid/$safeType.$ext';
    final ref = FirebaseStorage.instance.ref(path);

    final sniffed = UploadValidation.sniffMime(bytes);
    final contentType = sniffed.isNotEmpty ? sniffed : _contentType(ext);

    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        cacheControl: 'private, max-age=0',
      ),
    );
    return ref.getDownloadURL();
  }

  /// [type] लाई सुरक्षित segment मा — allowlist (+ ऐच्छिक `_N` suffix), नत्र 'document'।
  ///  citizenship_front, citizenship_back, selfie, certificate_1, certificate_2 ...
  static final RegExp _typeOk = RegExp(
      r'^(license|selfie|certificate|citizenship_front|citizenship_back|document|id)(_[0-9]+)?$');

  static String _safeType(String type) {
    final t = type.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return _typeOk.hasMatch(t) ? t : 'document';
  }

  static String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  /// कामको पोर्टफोलियो तस्बिर upload → download URL।
  /// path: portfolio/{uid}/{millis}.{ext}
  static Future<String> uploadPortfolioPhoto({
    required String uid,
    required Uint8List bytes,
    required String originalName,
  }) async {
    final err = UploadValidation.validate(bytes, originalName);
    if (err != null) {
      throw FormatException(UploadValidation.messageFor(err));
    }
    final ext = UploadValidation.safeExtension(originalName);
    final id = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref('portfolio/$uid/$id.$ext');
    final sniffed = UploadValidation.sniffMime(bytes);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: sniffed.isNotEmpty ? sniffed : _contentType(ext),
      ),
    );
    return ref.getDownloadURL();
  }

  /// upload असफल हुँदाको कारण छोटो code मा — Firestore मा राख्न / message देखाउन।
  ///  'storage-not-setup' | 'permission-denied' | 'network' | 'invalid-file' | 'error'
  static String describeUploadError(Object e) {
    if (e is FormatException) return 'invalid-file';
    if (e is TimeoutException) return 'network';
    if (e is FirebaseException) {
      switch (e.code) {
        case 'object-not-found':
        case 'bucket-not-found':
        case 'project-not-found':
        case 'unknown':
          return 'storage-not-setup';
        case 'unauthorized':
        case 'permission-denied':
          return 'permission-denied';
        case 'retry-limit-exceeded':
        case 'canceled':
        case 'app-deleted':
          return 'network';
        default:
          return e.code;
      }
    }
    return 'error';
  }

  /// पहिले upload नभएका KYC कागजात (नागरिकता अगाडि/पछाडि + अनुहार) फेरि उठाएर
  /// Storage मा राख्छ र तीनवटै doc (users / providers / pendingWorkers) update गर्छ।
  /// सफल भए `null`, नत्र [describeUploadError] बाटको कारण फर्काउँछ।
  static Future<String?> resyncDocuments({
    required String uid,
    required Uint8List citFrontBytes,
    required String citFrontName,
    required Uint8List citBackBytes,
    required String citBackName,
    required Uint8List selfieBytes,
  }) async {
    String frontUrl;
    String backUrl;
    String selfieUrl;
    try {
      frontUrl = await uploadDocument(
        uid: uid,
        bytes: citFrontBytes,
        originalName: citFrontName,
        type: 'citizenship_front',
      ).timeout(const Duration(seconds: 30));
      backUrl = await uploadDocument(
        uid: uid,
        bytes: citBackBytes,
        originalName: citBackName,
        type: 'citizenship_back',
      ).timeout(const Duration(seconds: 30));
      selfieUrl = await uploadDocument(
        uid: uid,
        bytes: selfieBytes,
        originalName: 'selfie.jpg',
        type: 'selfie',
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      return describeUploadError(e);
    }

    final db = FirebaseFirestore.instance;
    final fields = {
      'citizenshipFrontUrl': frontUrl,
      'citizenshipBackUrl': backUrl,
      'selfieUrl': selfieUrl,
      'licenseUrl': frontUrl, // पुरानो field सँग compat
      'documentUrl': frontUrl,
    };
    await db.collection('users').doc(uid).set({
      ...fields,
      'documentsPending': false,
      'documentsError': FieldValue.delete(),
      'documentsSyncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await db
        .collection('providers')
        .doc(uid)
        .set(fields, SetOptions(merge: true));

    try {
      final pend = await db
          .collection('pendingWorkers')
          .where('uid', isEqualTo: uid)
          .get();
      for (final d in pend.docs) {
        await d.reference.update({...fields, 'documentsPending': false});
      }
    } catch (_) {}

    return null;
  }

  static bool isImageUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('.png') ||
        u.contains('.jpg') ||
        u.contains('.jpeg') ||
        u.contains('.webp') ||
        u.contains('license.') ||
        u.contains('selfie.') ||
        u.contains('document.') ||
        u.contains('certificate.');
  }
}
