// services/upload_validation.dart
//
// फाइल upload गर्नुअघि सुरक्षा जाँच: साइज, extension allowlist, र magic-byte
// (file signature) जाँच — picker ले भनेको MIME मा भर नपरी बाइटहरूबाटै प्रकार पत्ता।
import 'dart:typed_data';

import '../l10n/strings.dart';

enum UploadError { empty, tooLarge, badExtension, contentMismatch }

class UploadValidation {
  UploadValidation._();

  /// अधिकतम साइज — ५ MB।
  static const int maxBytes = 5 * 1024 * 1024;

  /// स्वीकार्य extension हरू (lowercase, थेगो बिना)।
  static const Set<String> allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  };

  /// फाइल ठीक छ भने `null`; नत्र कारण।
  static UploadError? validate(Uint8List? bytes, String originalName) {
    if (bytes == null || bytes.isEmpty) return UploadError.empty;
    if (bytes.length > maxBytes) return UploadError.tooLarge;

    final ext = _rawExt(originalName);
    if (!allowedExtensions.contains(ext)) return UploadError.badExtension;

    final sniffed = sniffMime(bytes);
    if (sniffed.isEmpty) return UploadError.contentMismatch;

    // sniff गरेको प्रकार claim गरेको extension सँग मिल्नुपर्छ।
    final extIsPdf = ext == 'pdf';
    final sniffIsPdf = sniffed == 'application/pdf';
    if (extIsPdf != sniffIsPdf) return UploadError.contentMismatch;

    return null;
  }

  /// Allowlist भित्रको सफा extension; नमिले `jpg`।
  static String safeExtension(String originalName) {
    final ext = _rawExt(originalName);
    return allowedExtensions.contains(ext) ? ext : 'jpg';
  }

  /// फाइल signature (magic bytes) बाट MIME; नचिनिए खाली string।
  static String sniffMime(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && // R
        b[1] == 0x49 && // I
        b[2] == 0x46 && // F
        b[3] == 0x46 && // F
        b[8] == 0x57 && // W
        b[9] == 0x45 && // E
        b[10] == 0x42 && // B
        b[11] == 0x50) {
      return 'image/webp';
    }
    if (b.length >= 5 &&
        b[0] == 0x25 && // %
        b[1] == 0x50 && // P
        b[2] == 0x44 && // D
        b[3] == 0x46 && // F
        b[4] == 0x2D) {
      return 'application/pdf';
    }
    return '';
  }

  static String messageFor(UploadError e) {
    switch (e) {
      case UploadError.empty:
        return S.fileEmptyOrCorrupt;
      case UploadError.tooLarge:
        return S.fileTooLarge;
      case UploadError.badExtension:
        return S.fileTypeNotAllowed;
      case UploadError.contentMismatch:
        return S.fileContentMismatch;
    }
  }

  static String _rawExt(String name) {
    final clean = name.split('?').first.split('#').first;
    final i = clean.lastIndexOf('.');
    if (i == -1 || i == clean.length - 1) return '';
    return clean.substring(i + 1).toLowerCase().trim();
  }
}
