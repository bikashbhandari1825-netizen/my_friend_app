// services/document_service.dart
//
// प्रदायकको कागजात Firebase Storage मा राख्ने र URL फर्काउने।
// फोल्डर स्ट्रक्चर: documents/{uid}/<type>.<ext>   (जस्तै: documents/abc123/license.jpg)
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class DocumentService {
  DocumentService._();

  /// Storage मा document upload गरेर download URL फर्काउँछ।
  /// [type] = 'license', 'certificate' आदि। [originalName] बाट extension लिइन्छ।
  static Future<String> uploadDocument({
    required String uid,
    required Uint8List bytes,
    required String originalName,
    String type = 'document',
  }) async {
    final ext = _extOf(originalName);
    final path = 'documents/$uid/$type.$ext';
    final ref = FirebaseStorage.instance.ref(path);

    final metadata = SettableMetadata(contentType: _contentType(ext));
    await ref.putData(bytes, metadata);
    return ref.getDownloadURL();
  }

  static String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i == -1 || i == name.length - 1) return 'jpg';
    return name.substring(i + 1).toLowerCase();
  }

  static String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  static bool isImageUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('.png') ||
        u.contains('.jpg') ||
        u.contains('.jpeg') ||
        u.contains('license.') ||
        u.contains('document.') ||
        u.contains('certificate.');
  }
}
