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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../l10n/strings.dart';
import 'document_service.dart' show DocumentService;

class ChatMediaService {
  ChatMediaService._();

  /// क्षणिक (transient) Storage/Firestore त्रुटि कोड — retry ले साँच्चै
  /// मद्दत गर्न सक्छ, नत्र सधैँ फेरि खोल्नुपर्ने बन्थ्यो।
  static const _transientRetryCodes = {
    'retry-limit-exceeded',
    'canceled',
    'unknown',
    'deadline-exceeded',
    'unavailable',
    'aborted',
    'internal',
  };

  /// Upload अपलोड र त्यसपछिको Firestore message-लेखन दुवैले साझा गर्ने
  /// retry wrapper — पहिले कुनै पनि Storage/network हिचकिचाहट भएमा सिधै
  /// "पठाउन सकिएन — यो chat फेरि खोलेर प्रयास गर्नुहोस्" त्रुटि देखिन्थ्यो,
  /// अनि chat फेरि खोल्दा (Firebase Auth/Storage को SDK ले भित्रभित्रै आफ्नो
  /// ID token फेरि सिंक गर्ने मौका पाउने भएकोले) प्रायः सफलै हुन्थ्यो — जुन
  /// देखाउँछ समस्या प्रायः वास्तविक अनुमति समस्या थिएन, ID token अझै पूर्ण
  /// रूपमा propagate नभएको क्षणिक race थियो (विशेष गरी भर्खरै sign-in भएपछि
  /// वा app resume भएपछि chat तुरुन्तै खोलेर पहिलो फोटो पठाउँदा)। अब:
  ///  (१) `permission-denied`/`unauthorized` आएमा — ID token जबरजस्ती
  ///      refresh गरेर (`getIdToken(true)`) एकपटक फेरि प्रयास,
  ///  (२) क्षणिक network/server त्रुटिमा — छोटो backoff सहित थप पटकसम्म,
  ///  (३) अरू (invalid-file, storage-not-setup, वास्तविक participant होइन)
  ///      मा — retry ले सहयोग नगर्ने भएकोले सिधै असफल, ताकि प्रयोगकर्ताले
  ///      स्पष्ट सन्देश तुरुन्तै देख्न पाओस्।
  /// हरेक असफल प्रयास `debugPrint` मार्फत raw error/code सहित लेखिन्छ —
  /// अझै असफल भए `flutter logs`/डिभाइस logcat बाट साँचो कारण छुट्टै भेट्टाउन।
  static Future<T> withRetry<T>(Future<T> Function() attempt,
      {String debugLabel = 'media'}) async {
    Object lastError = StateError('unreachable');
    for (var i = 0; i < 3; i++) {
      try {
        return await attempt();
      } catch (e) {
        lastError = e;
        final code = e is FirebaseException ? e.code : null;
        debugPrint(
            'CHAT_MEDIA_RETRY label=$debugLabel attempt=$i code=$code error=$e');
        if (i == 0 && (code == 'unauthorized' || code == 'permission-denied')) {
          try {
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
          } catch (_) {}
          continue;
        }
        if (code != null && _transientRetryCodes.contains(code) && i < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw lastError;
  }

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
  }) {
    return withRetry(() async {
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
    }, debugLabel: 'upload $path');
  }

  /// Media अपलोड भइसकेपछि — Firestore मा chat message लेख्ने + booking
  /// doc कै lastMessage/lastMessageAt/lastSenderUid stamp गर्ने, दुवै एकै
  /// ठाउँमा — तुरुन्तै पठाउने बेला (`chat_screen.dart`) र पछि background
  /// मा retry हुँदा (`pending_media_queue.dart`) दुवैले उही बाटो प्रयोग
  /// गरून् भनेर (logic दोहोरिनु हुँदैन)।
  static Future<void> sendMediaMessage({
    required String requestId,
    required String senderUid,
    required String type, // 'image' | 'video' | 'audio'
    required String url,
    required String preview,
    // भ्वाइस-नोटको लम्बाइ (सेकन्डमा) जस्ता थप field — bubble मा तुरुन्तै
    // (कुनै audio metadata load नगरी नै, त्यसैले flicker/lag बिना) देखाउन।
    Map<String, dynamic>? extraFields,
  }) async {
    final field = switch (type) {
      'image' => 'imageUrl',
      'video' => 'videoUrl',
      _ => 'audioUrl',
    };
    final messages = FirebaseFirestore.instance
        .collection('chats')
        .doc(requestId)
        .collection('messages');
    await withRetry(
      () => messages.add({
        'senderUid': senderUid,
        'type': type,
        field: url,
        'createdAt': FieldValue.serverTimestamp(),
        ...?extraFields,
      }),
      debugLabel: 'message $type',
    );
    try {
      await FirebaseFirestore.instance
          .collection('serviceRequests')
          .doc(requestId)
          .set({
        'lastMessage': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderUid': senderUid,
      }, SetOptions(merge: true));
    } catch (_) {}
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
