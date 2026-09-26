// services/chat_media_service.dart
//
// Chat भित्रको फोटो/भिडियो/भ्वाइस — पहिले Firestore document भित्रै
// base64 गरेर सिधै embed हुन्थ्यो (हरेक message = ठूलो blob, हरेक
// snapshot listener ले फेरि-फेरि पूरै डाउनलोड गर्ने, Firestore को 1MB
// per-doc limit नजिकै पुग्ने जोखिम, र कुनै CDN caching नहुने) — अब
// `document_service.dart` कै उस्तै ढाँचामा Firebase Storage मा अपलोड
// गरेर सानो download URL मात्र Firestore मा राखिन्छ। फाइदा:
//   - हरेक chat message document सानो (केही सय byte) रहन्छ — धेरै
//     प्रयोगकर्ता एकैचोटि chat खोल्दा पनि Firestore read cost/bandwidth
//     थोरै।
//   - `cached_network_image`/Storage को CDN ले पहिलोपटक मात्र वास्तविक
//     डाउनलोड गर्छ, त्यसपछि local cache बाटै — बारम्बार खोल्दा तुरुन्तै।
//   - फोटो पठाउनुअघि नै (client-side) compress हुन्छ — ठूलो original
//     भन्दा धेरै सानो upload।
//
// Folder structure: chats/{requestId}/media/{messageId}.{ext}
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../l10n/strings.dart';
import 'document_service.dart' show DocumentService;

class ChatMediaService {
  ChatMediaService._();

  /// फोटो — पठाउनुअघि नै resize+re-encode (लामो छेउ बढीमा १२८०px, JPEG
  /// गुणस्तर ~७०) — मोबाइल data/Storage bandwidth दुवैमा ठूलो बचत, र
  /// साना स्क्रिनमा देखिने chat bubble का लागि full-resolution चाहिँदैन।
  /// Compress असफल भए (दुर्लभ, unsupported format) मूल bytes नै अपलोड
  /// हुन्छ — पठाउन नमिल्नुभन्दा अलि ठूलो भए पनि पठिनु राम्रो।
  static Future<Uint8List> compressImage(Uint8List bytes) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 70,
        format: CompressFormat.jpeg,
      );
      // कहिलेकाहीं compress गरेको ठूलै फाइल (already-small image) — त्यसबेला
      // मूल नै राख्ने, compress ले साइज बढाउनु हुँदैन।
      return out.length < bytes.length ? out : bytes;
    } catch (_) {
      return bytes;
    }
  }

  static Future<String> _upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        // chat media निजी कुराकानीको हिस्सा हो — public/लामो cache होइन।
        cacheControl: 'private, max-age=3600',
      ),
    );
    return ref.getDownloadURL();
  }

  /// फोटो — compress गरेर अपलोड, JPEG मै (सबैभन्दा साना/व्यापक रूपमा
  /// समर्थित) — download URL फर्काउँछ।
  static Future<String> uploadChatImage({
    required String requestId,
    required Uint8List bytes,
  }) async {
    final compressed = await compressImage(bytes);
    final id = DateTime.now().millisecondsSinceEpoch;
    return _upload(
      path: 'chats/$requestId/media/$id.jpg',
      bytes: compressed,
      contentType: 'image/jpeg',
    );
  }

  /// भ्वाइस-नोट — `record` package ले mobile/desktop मा AAC-LC (.m4a) मा
  /// दिन्छ, तर Web मा Chrome/Edge/Firefox को `MediaRecorder` ले AAC नै
  /// समर्थन नगर्ने भएकोले `voice_recorder_bar.dart` त्यहाँ Opus (.webm) मा
  /// रेकर्ड गर्छ — container फरक भएकोले [ext]/content-type पनि सोही अनुसार,
  /// caller (chat_screen.dart) बाट स्पष्ट रूपमा आउनुपर्छ (हार्डकोड गरे
  /// गलत content-type सहित अपलोड हुन्छ र playback असफल हुन्छ)। audio codec
  /// अगाडि नै साँघुरो bitrate मा रेकर्ड भएकोले थप compress गर्नुपर्ने ठूलो
  /// फाइदा हुँदैन, container ज्यूँकात्यूँ अपलोड।
  static Future<String> uploadChatVoice({
    required String requestId,
    required Uint8List bytes,
    String ext = 'm4a',
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch;
    final contentType = switch (ext) {
      'webm' => 'audio/webm',
      'ogg' => 'audio/ogg',
      _ => 'audio/mp4',
    };
    return _upload(
      path: 'chats/$requestId/media/$id.$ext',
      bytes: bytes,
      contentType: contentType,
    );
  }

  /// भिडियो — क्लाइन्ट-साइड re-encode/compress (video codec) Flutter मा
  /// भरपर्दो cross-platform (विशेष गरी Web मा) उपलब्ध नभएकोले, यहाँ
  /// त्यसको साटो [maxVideoBytes] भन्दा ठूलो भिडियो सिधै अस्वीकार गरिन्छ
  /// (caller ले पिक्/रेकर्ड गर्दा नै [kMaxVideoDuration] ले अवधि पनि
  /// सीमित गरिसकेको हुन्छ) — यसैले अत्यधिक ठूलो अपलोडले सर्भर/Storage
  /// bandwidth नखाओस्। यो नै धेरै (हजारौं) प्रयोगकर्ता एकैचोटि chat
  /// चलाउँदा पनि हल्का रहने व्यावहारिक उपाय हो।
  static const int maxVideoBytes = 25 * 1024 * 1024; // 25 MB
  static const Duration kMaxVideoDuration = Duration(seconds: 60);

  static Future<String> uploadChatVideo({
    required String requestId,
    required Uint8List bytes,
    required String ext,
  }) async {
    if (bytes.length > maxVideoBytes) {
      throw const VideoTooLargeException();
    }
    final id = DateTime.now().millisecondsSinceEpoch;
    final safeExt = (ext == 'mov' || ext == 'webm') ? ext : 'mp4';
    return _upload(
      path: 'chats/$requestId/media/$id.$safeExt',
      bytes: bytes,
      contentType: safeExt == 'webm'
          ? 'video/webm'
          : (safeExt == 'mov' ? 'video/quicktime' : 'video/mp4'),
    );
  }

  /// Web मा भिडियो रेकर्डिङ (क्यामेराबाट सिधै) व्यापक रूपमा भरपर्दो छैन —
  /// UI ले यो जाँचेर "gallery बाट मात्र" देखाउन सक्छ।
  static bool get videoRecordingSupported => !kIsWeb;

  /// upload असफल हुँदाको कारण — document_service.dart कै उस्तै वर्गीकरण
  /// पुनः-प्रयोग (त्यही Storage/network error handling सधैँभरि एउटै ठाउँ)।
  static String describeUploadError(Object e) =>
      DocumentService.describeUploadError(e);

  /// [describeUploadError] कै code (जस्तै "permission-denied") सिधै
  /// प्रयोगकर्तालाई नदेखाई — यसको सट्टा कारण-अनुसार प्रस्ट, कारबाही-योग्य
  /// (actionable) सन्देश। "permission-denied" यहाँ प्रायः यो chat अघिल्लोपल्ट
  /// खोलेपछि त्यसको access अद्यावधिक भएको (जस्तै काम अर्को स्थितिमा गइसकेको)
  /// बेला देखिन्छ — "फेरि प्रयास गर्नुहोस्" भन्दा "यो chat फेरि खोल्नुहोस्"
  /// बढी उपयोगी हुन्छ।
  static String friendlyUploadError(Object e) {
    switch (describeUploadError(e)) {
      case 'permission-denied':
        return S.uploadErrorPermission;
      case 'network':
        return S.uploadErrorNetwork;
      case 'storage-not-setup':
        return S.uploadErrorStorageNotSetup;
      default:
        return S.uploadErrorGeneric;
    }
  }
}

class VideoTooLargeException implements Exception {
  const VideoTooLargeException();
}
