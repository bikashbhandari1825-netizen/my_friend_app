// services/pending_media_queue.dart
//
// फोटो/भिडियो/भ्वाइस पठाउँदा (compress+upload+Firestore-लेखन, र
// `ChatMediaService.withRetry` भित्रकै तत्काल retry पनि) असफल भइहाले —
// पहिले प्रयोगकर्ताले आफैं SnackBar कै "फेरि प्रयास" थिच्नुपर्थ्यो, र त्यो
// पनि यही chat screen खुलै रहेसम्म मात्र सम्भव थियो (screen बन्द गरे bytes
// नै हराउँथ्यो, फेरि chat खोलेर फोटो नयाँ छान्नुपर्ने)। अब यहाँ disk मा नै
// (bytes + metadata, JSON sidecar) राखिन्छ — chat बन्द गरे, app नै
// बन्द/क्र्यास भएर फेरि खोलिए पनि — नेटवर्क फर्कनेबित्तिकै आफैं पछाडि
// (background) पठाउने प्रयास जारी रहन्छ, कुनै chat फेरि खोल्नु पर्दैन।
//
// Web मा file-system नै नभएकोले (bytes डिस्कमा राख्न नमिल्ने) यो queue
// mobile/desktop मात्र — Web मा पहिलेकै जस्तै SnackBar कै म्यानुअल "फेरि
// प्रयास" ले सिधै फेरि पठाउने प्रयास गर्छ (chat_screen.dart हेर्नुहोस्)।
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';

import '../app_globals.dart' show isOffline;
import 'chat_media_service.dart';

class _QueuedMedia {
  final String id;
  final String requestId;
  final String senderUid;
  final String type; // image | video | audio
  final String ext;
  final String previewText;
  int attempts;

  _QueuedMedia({
    required this.id,
    required this.requestId,
    required this.senderUid,
    required this.type,
    required this.ext,
    required this.previewText,
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'requestId': requestId,
        'senderUid': senderUid,
        'type': type,
        'ext': ext,
        'previewText': previewText,
        'attempts': attempts,
      };

  static _QueuedMedia fromJson(Map<String, dynamic> j) => _QueuedMedia(
        id: j['id'] as String,
        requestId: j['requestId'] as String,
        senderUid: j['senderUid'] as String,
        type: j['type'] as String,
        ext: (j['ext'] ?? '') as String,
        previewText: (j['previewText'] ?? '') as String,
        attempts: (j['attempts'] ?? 0) as int,
      );
}

class PendingMediaQueue {
  PendingMediaQueue._();

  static bool get _supported => !kIsWeb;

  static final _items = <_QueuedMedia>[];
  static Timer? _timer;
  static bool _draining = false;
  static bool _started = false;
  static Directory? _dir;

  // धेरैचोटि (लगातार ~१ घण्टा, हरेक २० सेकेन्डमा एकचोटि गन्दा) लगातार
  // असफल भइरहे (जस्तै त्यो booking नै मेटिएको/participant होइन जस्तो
  // वास्तविक — नरहने — कारण) — सधैँभरि disk मा थुपार्नुको साटो त्यागी हटाउने।
  static const int _maxAttempts = 200;

  static Future<Directory> _queueDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/pending_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  static Future<File> _bytesFile(String id) async =>
      File('${(await _queueDir()).path}/$id.bin');
  static Future<File> _metaFile(String id) async =>
      File('${(await _queueDir()).path}/$id.json');

  /// App startup मा एकपटक (main.dart) — अघिल्लो session (app बन्द/क्र्यास)
  /// बाट बाँकी रहेका item हरू फेरि load गरेर retry loop सुरु गर्ने।
  static Future<void> init() async {
    if (!_supported || _started) return;
    _started = true;
    try {
      final dir = await _queueDir();
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.json')) {
          try {
            final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
            _items.add(_QueuedMedia.fromJson(j));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('PENDING_MEDIA_INIT_FAILED error=$e');
    }
    // नेटवर्क फर्कनेबित्तिकै (ConnectivityService कै `isOffline` — नयाँ
    // package नचाहिने) तुरुन्तै एकपटक प्रयास, timer कै अर्को cycle
    // (बढीमा २० सेकेन्ड) नपर्खी।
    isOffline.addListener(_onConnectivityChanged);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _drain());
    if (_items.isNotEmpty) unawaited(_drain());
  }

  static void _onConnectivityChanged() {
    if (!isOffline.value) unawaited(_drain());
  }

  /// Test/hot-restart मा मात्र चाहिने — सामान्य app lifetime भरि यो
  /// service सधैँ चलिरहन्छ, कहिल्यै stop गर्नुपर्दैन।
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Upload/message-लेखन दुवैको (`ChatMediaService.withRetry` भित्री
  /// तत्काल प्रयासहरू) पनि असफल भएपछि मात्र — यहाँ थपेपछि प्रयोगकर्ताले
  /// केही नगरे पनि (chat बन्द गरे पनि) नेटवर्क फर्कनेबित्तिकै आफैं पठाउने
  /// प्रयास जारी रहन्छ।
  static Future<void> enqueue({
    required String requestId,
    required String senderUid,
    required String type,
    required Uint8List bytes,
    String ext = '',
    required String previewText,
  }) async {
    if (!_supported) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await (await _bytesFile(id)).writeAsBytes(bytes);
      final item = _QueuedMedia(
        id: id,
        requestId: requestId,
        senderUid: senderUid,
        type: type,
        ext: ext,
        previewText: previewText,
      );
      await (await _metaFile(id)).writeAsString(jsonEncode(item.toJson()));
      _items.add(item);
      unawaited(_drain());
    } catch (e) {
      debugPrint('PENDING_MEDIA_ENQUEUE_FAILED error=$e');
    }
  }

  /// SnackBar कै "फेरि प्रयास" बटनले — पूरै नयाँ स्वतन्त्र upload नभई, यही
  /// queue लाई तुरुन्तै एकपटक (timer कै २० सेकेन्ड नपर्खी) चलाउने — दुई
  /// ठाउँबाट (यो बटन + पछिको स्वतः timer/connectivity) एउटै फोटो दोहोरिएर
  /// नपठियोस् भनेर सधैँ यही एउटै queued item माथि नै काम गर्छ।
  static Future<void> drainNow() => _drain();

  static Future<void> _drain() async {
    if (!_supported || _draining || _items.isEmpty) return;
    _draining = true;
    try {
      // list कै snapshot माथि — भित्रैबाट remove हुँदा concurrent-modification नहोस्।
      for (final item in List<_QueuedMedia>.from(_items)) {
        try {
          final bytes = await (await _bytesFile(item.id)).readAsBytes();
          final url = switch (item.type) {
            'image' => await ChatMediaService.uploadChatImage(
                requestId: item.requestId, bytes: bytes),
            'video' => await ChatMediaService.uploadChatVideo(
                requestId: item.requestId, bytes: bytes, ext: item.ext),
            _ => await ChatMediaService.uploadChatVoice(
                requestId: item.requestId, bytes: bytes, ext: item.ext),
          };
          await ChatMediaService.sendMediaMessage(
            requestId: item.requestId,
            senderUid: item.senderUid,
            type: item.type,
            url: url,
            preview: item.previewText,
          );
          await _remove(item);
        } catch (e) {
          item.attempts++;
          debugPrint(
              'PENDING_MEDIA_RETRY_FAILED id=${item.id} attempts=${item.attempts} error=$e');
          if (item.attempts > _maxAttempts) {
            await _remove(item);
          } else {
            try {
              await (await _metaFile(item.id))
                  .writeAsString(jsonEncode(item.toJson()));
            } catch (_) {}
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  static Future<void> _remove(_QueuedMedia item) async {
    _items.removeWhere((e) => e.id == item.id);
    try {
      await (await _bytesFile(item.id)).delete();
    } catch (_) {}
    try {
      await (await _metaFile(item.id)).delete();
    } catch (_) {}
  }
}
