// screens/chat_screen.dart
// Messenger-style एक-to-एक chat — Instagram gradient bubbles/header/send button,
// theme-aware input (dark mode मा पनि text देखिने)। Text + Photo + Voice।
// पठाउँदा serviceRequests/{requestId} मा lastMessage/lastMessageAt पनि लेखिन्छ
// (Messages list तुरुन्तै अपडेट होस्)।
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, PlatformException;
import 'package:image_picker/image_picker.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../services/chat_media_service.dart';
import '../services/pending_media_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/futuristic_ui.dart';
import '../widgets/glass_ui.dart';
import '../widgets/online_badge.dart';
import '../widgets/spring_tap.dart';
import '../widgets/voice_recorder_bar.dart';
import 'call_screen.dart';
import 'image_preview_screen.dart';
import 'job_actions.dart' show kActiveJobStatuses;
import 'video_preview_screen.dart';

class ChatScreen extends StatefulWidget {
  final String requestId;

  /// अर्को व्यक्तिको देखाउने नाम।
  final String workerName;

  /// caller लाई पहिल्यै थाहा भएको request status (दिए) — पहिलो Firestore
  /// snapshot नआएसम्म call बटन/input bar झिम्किएर लुकेर फेरि नदेखियोस्
  /// (flash) भनेर। caller ले नदिए (null) पहिलो snapshot नआएसम्म सुरक्षित
  /// default (locked) मानिन्छ।
  final String? initialStatus;

  /// `requestId` कुन collection भित्रको doc हो (live status watch गर्न,
  /// अर्को पक्षको uid नलेटे पत्ता लगाउन, र lastMessage stamp गर्न) —
  /// Ride/service job हरूका लागि default `serviceRequests`; Hotel booking
  /// communication (hotel_booking_pass_screen.dart/
  /// hotel_partner_dashboard_screen.dart) ले `hotel_bookings` दिन्छ।
  final String statusCollection;

  /// caller लाई पहिल्यै थाहा भएको अर्को पक्षको uid (दिए) — दिएमा
  /// `statusCollection` बाट uid लुकअप गर्दै जानु पर्दैन (hotel booking docs
  /// मा `employerUid`/`workerUid` field हुँदैनन्, त्यसैले hotel काल hरूले
  /// यो सधैं दिनुपर्छ — guest तर्फबाट `hotel.ownerId`, partner तर्फबाट
  /// `booking.userId`)।
  final String? otherUid;

  /// कुन status मान हरूमा chat/call unlocked मानिने — ride/service job
  /// हरूका लागि default `kActiveJobStatuses`; hotel booking ले
  /// `kActiveHotelBookingStatuses` दिन्छ।
  final Set<String> unlockedStatuses;

  /// null = केही गर्दैन (सामान्य chat); false = खुल्नेबित्तिकै voice call;
  /// true = video call। Salon विवरण पेजको "Call"/"Video" बटनले प्रयोग गर्छ।
  final bool? autoStartCallVideo;

  const ChatScreen({
    super.key,
    required this.requestId,
    required this.workerName,
    this.initialStatus,
    this.statusCollection = 'serviceRequests',
    this.otherUid,
    this.unlockedStatuses = kActiveJobStatuses,
    this.autoStartCallVideo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _recordingVoice = false;
  bool _canSend = false;
  // Communication Never Locks — booking/job status जे भए पनि (completed/
  // cancelled/declined/pending समेत) Call/Video/Chat सधैं खुला। पहिले
  // `_requestStatus`/`widget.unlockedStatuses` अनुसार मात्र (accepted/
  // confirmed/in_progress) सक्रिय हुन्थ्यो — काम/booking completed भएपछि
  // "This job is completed. Chat & calls are closed" देखिने र Call/Video
  // बटन नै हराउने गुनासोको जड। `_requestStatus` अझै live-track हुन्छ
  // (भविष्यमा अन्य display-मात्र प्रयोजनका लागि), तर अब communication
  // gate गर्दैन।
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  late String? _requestStatus = widget.initialStatus;
  bool get _chatActive => true;
  // कल बटन थिचेपछि CallScreen तुरुन्तै (उही frame मा) push हुन्छ — कुनै
  // network round-trip पर्खिनु पर्दैन, त्यसैले छुट्टै "busy" spinner
  // चाहिँदैन। `_inCall` ले मात्र double-tap (दुइटा CallScreen एकैचोटि
  // push हुनबाट) रोक्छ — SpringTap कै press animation ले tactile
  // feedback दिन्छ।
  bool _inCall = false;
  String _myName = '';
  String? _lastMarkedReadDocId;
  String _otherUid = '';
  // फोटो/भिडियो/भ्वाइस Firebase Storage मा अपलोड हुँदाको छोटो समय —
  // पहिले base64 सिधै Firestore मा लेख्दा झट्ट हुन्थ्यो, अब उपलोड (नेटवर्क
  // round-trip) लाग्ने भएकोले प्रयोगकर्तालाई प्रस्ट "पठाउँदै..." संकेत चाहियो।
  bool _sendingMedia = false;

  // `_jumpToBottom()` पहिले messages-list का हरेक rebuild मा (नयाँ सन्देश
  // आउँदा मात्र होइन, अर्को पक्षको "seen"/readBy अपडेट हुँदा पनि — किनकि
  // त्यो पनि यही StreamBuilder भित्रै फेरि चलाउँछ) दोहोरिँदै चल्थ्यो — पहिल्यै
  // तल पुगिसकेको list लाई फेरि-फेरि उही scroll-animation दिँदा प्रस्ट देखिने
  // jitter/flicker हुन्थ्यो। अब पछिल्लो सन्देशको id पहिले नै जम्प गरिसकेको
  // भन्दा फरक भए मात्र (साँच्चै नयाँ/मेटिएको सन्देश) जम्प गर्ने।
  String? _lastJumpedDocId;

  DocumentReference<Map<String, dynamic>> get _chatDoc =>
      FirebaseFirestore.instance.collection('chats').doc(widget.requestId);

  CollectionReference<Map<String, dynamic>> get _messages =>
      _chatDoc.collection('messages');

  // यी दुवै Stream एकपटक मात्र (initState मै) बनाइन्छ — `messages_screen.dart`
  // कै उस्तै कारण: `_chatDoc.snapshots()`/`_messages....snapshots()` लाई
  // सिधै build() भित्रै (हरेक पटक नयाँ Stream instance दिने गरी) बोलाए,
  // ChatScreen को जुनसुकै अरू setState (टाइप गर्दा `_canSend`, फोटो/भिडियो
  // पठाउँदा `_sendingMedia`, आदि) ले पनि StreamBuilder लाई "stream नै बदलियो"
  // भन्ठान्न लगाउँथ्यो (Stream मा साधारण `==` object-identity तुलना हुन्छ) —
  // त्यसैले पुरानो/पहिल्यै-लोड भएको data देखाइरहेको बीचैमा एकैछिनको लागि
  // फेरि "waiting" state (spinner) मा फर्केर देखिने, ठ्याक्कै "chat/media
  // फ्लिकर हुन्छ" गुनासोको साँचो जड। अब build() ले यिनै स्थिर field मात्र
  // पढ्छ, नयाँ Stream कहिल्यै दोहोरिँदैन।
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatDocStream =
      _chatDoc.snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream =
      _messages.orderBy('createdAt', descending: false).limitToLast(50).snapshots();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final can = _controller.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    _loadMyName().then((_) {
      final autoVideo = widget.autoStartCallVideo;
      if (autoVideo != null && mounted) _startCall(video: autoVideo);
    });
    _markRead();
    _otherPartyUid().then((uid) {
      if (mounted && uid != null) setState(() => _otherUid = uid);
    });
    _statusSub = FirebaseFirestore.instance
        .collection(widget.statusCollection)
        .doc(widget.requestId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      // `serviceRequests/{requestId}` मा status बाहेक अरू जुनसुकै field
      // बदलिँदा पनि (live worker-location अपडेट, हरेक सन्देशपछिको
      // lastMessage/lastMessageAt stamp, आदि — यी सबैले यही doc लाई नै
      // touch गर्छन्) यो listener फायर हुन्छ। status साँच्चै नबदलिए setState
      // नै नगर्ने — नत्र हरेक त्यस्तो असम्बन्धित लेखाइले पनि पूरै ChatScreen
      // (AppBar कै कल बटन सहित) व्यर्थै फेरि rebuild गर्थ्यो, जुन "कल
      // सकिएपछि/मिडिया पठाएपछि आइकन बटन झिम्किन्छ" गुनासोको अर्को (यही
      // फाइलभित्रकै) जड थियो।
      final status = (snap.data()?['status'])?.toString();
      if (status != _requestStatus) setState(() => _requestStatus = status);
    });
  }

  /// यो chat अहिले खुलेको छ भनेर आफ्नो "पढेको समय" बचत गर्ने — Messenger
  /// जस्तै अर्को पक्षले पठाएको पछिल्लो सन्देश मुनि "Seen" देखिन यही चाहिन्छ।
  Future<void> _markRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _chatDoc.set({
        'readBy': {uid: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _loadMyName() async {
    final me = FirebaseAuth.instance.currentUser;
    var name = me?.displayName ?? '';
    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(me?.uid)
          .get();
      final n = (u.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) name = n;
    } catch (_) {}
    if (mounted) setState(() => _myName = name.isEmpty ? 'सहयात्री' : name);
  }

  /// अर्को पक्षको uid — `serviceRequests/{requestId}` बाट। Notification
  /// पठाउन (call सुरु हुनेबित्तिकै backgrounded भए पनि थाहा पाओस्) चाहिन्छ;
  /// आउँदो-कल पत्ता लगाउने काम अब यहाँ होइन, MainContainer कै साझा
  /// (tab-independent) watcher ले गर्छ — त्यसैले यो screen खुला नभए पनि
  /// अर्को tab/screen मा भए पनि कल आएको देखिन्छ।
  Future<String?> _otherPartyUid() async {
    if (widget.otherUid != null) return widget.otherUid;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.statusCollection)
          .doc(widget.requestId)
          .get();
      final data = doc.data();
      if (data == null) return null;
      final me = FirebaseAuth.instance.currentUser?.uid;
      final employerUid = (data['employerUid'] ?? '').toString();
      final workerUid = (data['workerUid'] ?? '').toString();
      if (me == employerUid) return workerUid.isEmpty ? null : workerUid;
      if (me == workerUid) return employerUid.isEmpty ? null : employerUid;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Touch हुनेबित्तिकै तुरुन्तै CallScreen खुल्छ — कुनै Firestore
  /// round-trip (stale-signal reset, अर्को पक्षको uid लुकअप) लाई अब यहाँ
  /// await गरिँदैन। पहिले यी दुवै await हुँदा बटन थिचेदेखि screen देखिनेसम्म
  /// नेटवर्क जति ढिलो भयो त्यति नै ढिलो हुन्थ्यो — अब ती background मा सर्छन्:
  /// stale-signal reset अब `CallSession.start()` भित्रै (CallScreen
  /// पहिल्यै push भइसकेपछि) हुन्छ, र notification पठाउने काम fire-and-forget।
  Future<void> _startCall({required bool video}) async {
    if (_inCall) return;
    unawaited(_notifyOtherPartyOfCall(video));
    final durationSeconds = await _openCall(video: video, isCaller: true);
    _stampLast(video ? '📹 ${S.videoCall}' : '📞 ${S.voiceCall}');
    _messages.add({
      'senderUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      'type': 'call',
      'mode': video ? 'video' : 'audio',
      'createdAt': FieldValue.serverTimestamp(),
      // साँच्चै जोडिएकोमा मात्र > 0 (CallScreen/CallSession हेर्नुहोस्) —
      // नउठाइएको/decline भएको कलमा 0, chat bubble ले त्यसबेला अवधि नै
      // नदेखाउने।
      'durationSeconds': durationSeconds,
    });
  }

  /// अर्को पक्ष अहिले app मै नभए/backgrounded भए पनि थाहा पाओस् भनेर —
  /// real-time signaling त `calls/{requestId}` doc ले नै गर्छ, यो त
  /// additional push/in-app alert मात्र हो, कल screen खोल्नुलाई कहिल्यै
  /// block गर्नु हुँदैन।
  Future<void> _notifyOtherPartyOfCall(bool video) async {
    final otherUid = await _otherPartyUid();
    if (otherUid != null) {
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      createNotificationForUser(
        otherUid,
        S.incomingCallTitle,
        '$_myName  ·  ${video ? S.videoCall : S.voiceCall}',
        data: {
          'requestId': widget.requestId,
          'type': 'incoming_call',
          'mode': video ? 'video' : 'audio',
          // Backgrounded/बन्द एपमा push notification ट्याप गर्दा सिधै साँचो
          // full-screen incoming-call UI मा जान (map मा होइन) यी दुवै
          // चाहिन्छ — Cloud Function ले पनि यी forward गर्नुपर्छ (तल
          // functions/index.js हेर्नुहोस्)।
          'callerName': _myName,
          'callerUid': myUid,
        },
      );
    }
  }

  /// Call ended भएपछि साँचो अवधि (सेकेन्डमा, `CallScreen`/`CallSession` कै
  /// live timer मै track भएको) फर्काउँछ — कल message doc मा `durationSeconds`
  /// राख्न। कहिल्यै नजोडिएको (screen dismiss/error) भए 0।
  Future<int> _openCall({required bool video, required bool isCaller}) async {
    _inCall = true;
    final durationSeconds = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          requestId: widget.requestId,
          otherName: widget.workerName,
          myName: _myName,
          video: video,
          isCaller: isCaller,
          otherUid: _otherUid,
        ),
      ),
    );
    _inCall = false;
    return durationSeconds ?? 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _statusSub?.cancel();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _stampLast(String preview) async {
    try {
      await FirebaseFirestore.instance
          .collection(widget.statusCollection)
          .doc(widget.requestId)
          .set({
        'lastMessage': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // Firestore को एउटै field मा व्यावहारिक रूपमा यति ठूलो text कहिल्यै
  // पठाइनु पर्दैन (doc कै १MiB सीमा भन्दा धेरै तल) — कुनै गल्तिले (जस्तै
  // ठूलो टेक्स्ट paste) यति नाघे client-side मै रोक्ने, सर्भरसम्म
  // नपठाई। यसले नै "invalid-argument" जस्ता अस्पष्ट Firestore त्रुटि
  // आउनुअघि नै प्रस्ट सन्देश दिन्छ।
  static const int _maxTextLength = 4000;

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (text.length > _maxTextLength) {
      _snack(S.messageTooLong);
      return;
    }
    // Messenger-जस्तै तुरुन्तै feel दिन input एकैचोटि खाली (Firestore को
    // आफ्नै offline-cache ले सन्देश bubble पनि लगत्तै देखाउँछ, server ack
    // को पर्खाइ पर्दैन) — तर पुरानो बग (सन्देश हराउने) नदोहोरियोस् भनेर
    // असफल भएमा `catch` ले उही पाठ फिर्ता ल्याइदिन्छ, डेटा कहिल्यै हराउँदैन।
    _controller.clear();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _messages.add({
        'senderUid': uid,
        'type': 'text',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      unawaited(_stampLast(text));
    } catch (e) {
      if (mounted) _controller.text = text;
      _snack('${S.errorWord}: $e');
    }
  }

  Future<void> _sendImage(Uint8List bytes) async {
    // SnackBar कै "फेरि प्रयास" ले (Web मा) यो सिधै फेरि बोलाउँछ — त्यो
    // बेलासम्म प्रयोगकर्ता यो chat छाडेर अर्कै screen गइसकेको (यो State
    // पहिल्यै disposed भइसकेको) भए यहीँको पहिलो `setState` ले नै तुरुन्तै
    // "setState() called after dispose()" क्र्यास दिन्थ्यो — यो गुनासोको
    // साँचो जड device लगमा नै (live testing मा) समातिएको थियो।
    if (!mounted) return;
    setState(() => _sendingMedia = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    const preview = '📷 ';
    try {
      final url = await ChatMediaService.uploadChatImage(
        requestId: widget.requestId,
        bytes: bytes,
      );
      await ChatMediaService.sendMediaMessage(
        requestId: widget.requestId,
        senderUid: uid,
        type: 'image',
        url: url,
        preview: '$preview${S.photo}',
      );
    } catch (e) {
      // `withRetry` भित्रकै तत्काल प्रयास पनि सकिएपछि — mobile/desktop मा
      // यहीँबाट (chat बन्द भए/app नै बन्द भए पनि) background मा आफैं फेरि
      // प्रयास जारी रहने गरी थन्क्याउने; Web मा queue समर्थित नभएकोले
      // (`PendingMediaQueue.enqueue` त्यहाँ no-op) SnackBar कै "फेरि
      // प्रयास" ले सिधै फेरि पठाउँछ।
      unawaited(PendingMediaQueue.enqueue(
        requestId: widget.requestId,
        senderUid: uid,
        type: 'image',
        bytes: bytes,
        previewText: '$preview${S.photo}',
      ));
      _snack(ChatMediaService.friendlyUploadError(e),
          onRetry: kIsWeb
              ? () => _sendImage(bytes)
              : PendingMediaQueue.drainNow);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  /// भिडियो — pick/record गर्दा नै अवधि सीमित (Send-अघि आकार पनि दोहोर्‍याएर
  /// जाँचिन्छ, `ChatMediaService.uploadChatVideo` भित्र)। Preview मा Send
  /// थिचेपछि मात्र साँच्चै अपलोड।
  Future<void> _sendVideo(Uint8List bytes, String ext) async {
    if (!mounted) return; // _sendImage कै उस्तै — माथिको टिप्पणी हेर्नुहोस्।
    setState(() => _sendingMedia = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    const preview = '🎥 ';
    try {
      final url = await ChatMediaService.uploadChatVideo(
        requestId: widget.requestId,
        bytes: bytes,
        ext: ext,
      );
      await ChatMediaService.sendMediaMessage(
        requestId: widget.requestId,
        senderUid: uid,
        type: 'video',
        url: url,
        preview: '$preview${S.video}',
      );
    } on VideoTooLargeException {
      _snack(S.videoTooLarge);
    } catch (e) {
      unawaited(PendingMediaQueue.enqueue(
        requestId: widget.requestId,
        senderUid: uid,
        type: 'video',
        bytes: bytes,
        ext: ext,
        previewText: '$preview${S.video}',
      ));
      _snack(ChatMediaService.friendlyUploadError(e),
          onRetry: kIsWeb
              ? () => _sendVideo(bytes, ext)
              : PendingMediaQueue.drainNow);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  /// Camera/gallery बाट छानेको तस्बिर — सिधै नपठाई पहिले preview देखाउने,
  /// "Send" थिचेपछि मात्र साँच्चै अपलोड हुने।
  Future<void> _previewThenSend(Uint8List bytes) async {
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImagePreviewScreen(bytes: bytes),
      ),
    );
    if (confirmed == true) await _sendImage(bytes);
  }

  /// Camera/gallery/video-picker बाट आएको OS-level त्रुटि — Android/iOS ले
  /// क्यामेरा/फोटो अनुमति नदिँदा `PlatformException` (code जस्तै
  /// `camera_access_denied`/`photo_access_denied`) throw गर्छ, जुन raw
  /// रूपमा देखाउँदा प्रयोगकर्तालाई किन/के गर्ने केही थाहा हुँदैन। यस्तो
  /// अवस्थामा मात्र स्पष्ट "Settings मा गएर अनुमति दिनुहोस्" सन्देश, बाँकी
  /// (rare/unexpected) त्रुटिमा साधारण fallback।
  void _snackPickError(Object e) {
    if (e is PlatformException &&
        (e.code == 'camera_access_denied' ||
            e.code == 'photo_access_denied')) {
      _snack(S.mediaPermissionNeeded);
      return;
    }
    _snack('${S.errorWord}: $e');
  }

  Future<void> _pickCamera() async {
    try {
      final XFile? p = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 85);
      if (p != null) await _previewThenSend(await p.readAsBytes());
    } catch (e) {
      _snackPickError(e);
    }
  }

  Future<void> _pickGallery() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null) await _previewThenSend(await file.readAsBytes());
    } catch (e) {
      _snackPickError(e);
    }
  }

  /// भिडियो — preview गरेर मात्र (Send थिचेपछि) साँच्चै upload/पठाउने।
  Future<void> _previewVideoThenSend(Uint8List bytes, String ext) async {
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoPreviewScreen(bytes: bytes),
      ),
    );
    if (confirmed == true) await _sendVideo(bytes, ext);
  }

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    return i == -1 ? 'mp4' : path.substring(i + 1).toLowerCase();
  }

  Future<void> _recordVideoCamera() async {
    try {
      final XFile? v = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        maxDuration: ChatMediaService.kMaxVideoDuration,
      );
      if (v != null) {
        await _previewVideoThenSend(await v.readAsBytes(), _extOf(v.path));
      }
    } catch (e) {
      _snackPickError(e);
    }
  }

  Future<void> _pickVideoGallery() async {
    try {
      final XFile? v = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: ChatMediaService.kMaxVideoDuration,
      );
      if (v != null) {
        await _previewVideoThenSend(await v.readAsBytes(), _extOf(v.path));
      }
    } catch (e) {
      _snackPickError(e);
    }
  }

  /// क्यामेरा (mobile/desktop मात्र) वा gallery — छोटो choice sheet।
  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.kmSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ChatMediaService.videoRecordingSupported)
                ListTile(
                  leading: const Icon(Icons.videocam_rounded,
                      color: AppColors.kmTealBlue),
                  title: Text(S.recordVideo,
                      style: const TextStyle(color: AppColors.kmText)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _recordVideoCamera();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.video_library_rounded,
                    color: AppColors.kmPink),
                title: Text(S.chooseFromGallery,
                    style: const TextStyle(color: AppColors.kmText)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickVideoGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Voice-note recorder bar (widgets/voice_recorder_bar.dart) ले नै रेकर्ड
  /// + waveform + preview सबै सम्हाल्छ — यहाँ त प्रयोगकर्ताले Send थिचेपछि
  /// आएको bytes मात्र साँच्चै Firestore मा लेख्ने।
  Future<void> _sendVoiceBytes(
      Uint8List bytes, String ext, int durationSeconds) async {
    if (!mounted) return; // _sendImage कै उस्तै — माथिको टिप्पणी हेर्नुहोस्।
    setState(() {
      _recordingVoice = false;
      _sendingMedia = true;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    const preview = '🎤 ';
    try {
      final url = await ChatMediaService.uploadChatVoice(
        requestId: widget.requestId,
        bytes: bytes,
        ext: ext,
      );
      await ChatMediaService.sendMediaMessage(
        requestId: widget.requestId,
        senderUid: uid,
        type: 'audio',
        url: url,
        preview: '$preview${S.voiceMessage}',
        extraFields: {'durationSeconds': durationSeconds},
      );
    } catch (e) {
      unawaited(PendingMediaQueue.enqueue(
        requestId: widget.requestId,
        senderUid: uid,
        type: 'audio',
        bytes: bytes,
        ext: ext,
        previewText: '$preview${S.voiceMessage}',
        durationSeconds: durationSeconds,
      ));
      _snack(ChatMediaService.friendlyUploadError(e),
          onRetry: kIsWeb
              ? () => _sendVoiceBytes(bytes, ext, durationSeconds)
              : PendingMediaQueue.drainNow);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  /// [onRetry] दिए (media पठाउन असफल भएको खण्डमा) — SnackBar मै "फेरि
  /// प्रयास" बटन देखिन्छ, प्रयोगकर्ताले chat पूरै फेरि खोल्नु नपरोस् भनेर।
  void _snack(String m, {VoidCallback? onRetry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      action: onRetry == null
          ? null
          : SnackBarAction(label: S.retryWord, onPressed: onRetry),
    ));
  }

  String _time(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = FirebaseAuth.instance.currentUser?.uid;
    final initial = widget.workerName.trim().isEmpty
        ? '?'
        : widget.workerName.trim()[0].toUpperCase();

    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.kmText,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              border: Border(
                  bottom: BorderSide(
                      color: kNeonTeal.withValues(alpha: 0.18))),
            ),
          ),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const SweepGradient(
                    colors: [kNeonTeal, kNeonViolet, kNeonPink, kNeonTeal]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: kNeonViolet.withValues(alpha: 0.45),
                      blurRadius: 12),
                ],
              ),
              child: Container(
                width: 35,
                height: 35,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: Color(0xFF05050A), shape: BoxShape.circle),
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.workerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  _otherUid.isEmpty
                      ? Text(S.activeRecently,
                          style: const TextStyle(
                              color: AppColors.kmMuted, fontSize: 11))
                      : OnlineBadge(uid: _otherUid, onDark: true, neon: true),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Pre-Acceptance/Post-Completion Security — request active
          // (accepted/confirmed/in_progress) नभएसम्म कल बटन नै नदेखिने।
          if (_chatActive) ...[
            _CallBtn(
              key: const ValueKey('audioCallBtn'),
              icon: Icons.call_rounded,
              onTap: () => _startCall(video: false),
            ),
            _CallBtn(
              key: const ValueKey('videoCallBtn'),
              icon: Icons.videocam_rounded,
              onTap: () => _startCall(video: true),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      body: Column(
        children: [
          SizedBox(
              height: MediaQuery.of(context).padding.top + kToolbarHeight),
          Expanded(
            // Read-receipt tick मार्क हरूका लागि chat-level `readBy` एकपटक
            // मात्र (सबै सन्देशले साझा गर्ने) — हरेक सन्देश-bubble ले आफ्नै
            // छुट्टै StreamBuilder राख्दा (पहिले `_SeenLabel` जस्तै) message
            // जति भयो त्यति नै Firestore listener खुल्थ्यो, जुन एउटै doc
            // दोहोर्‍याएर सुन्नु मात्र होइन, थुप्रै सन्देश भएको लामो chat मा
            // वास्तविक jank/lag पनि दिन्थ्यो।
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _chatDocStream,
              builder: (context, chatSnap) {
                final readBy =
                    chatSnap.data?.data()?['readBy'] as Map<String, dynamic>?;
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  // `limitToLast` — नत्र लामो chat मा हरेक snapshot (नयाँ
                  // सन्देश वा कुनै readBy अपडेट) ले सुरुदेखिकै सबै सन्देश
                  // पुनः-fetch/diff गर्थ्यो, जति लामो chat त्यति नै भारी
                  // (120fps स्मूथनेसमा सिधै असर)।
                  stream: _messagesStream,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.forum_rounded,
                                size: 54, color: AppColors.kmMuted),
                            const SizedBox(height: 10),
                            Text(S.startTheConversation,
                                style: const TextStyle(
                                    color: AppColors.kmMuted)),
                          ],
                        ),
                      );
                    }
                    if (docs.last.id != _lastJumpedDocId) {
                      _lastJumpedDocId = docs.last.id;
                      _jumpToBottom();
                    }
                    // अर्को पक्षले नयाँ सन्देश पठायो र म यो chat हेर्दै नै छु भने
                    // तुरुन्तै "पढेको" म्हार्क गर्ने — Messenger जस्तै live "Seen"।
                    final lastDoc = docs.last;
                    if (lastDoc.id != _lastMarkedReadDocId &&
                        lastDoc.data()['senderUid'] != me) {
                      _lastMarkedReadDocId = lastDoc.id;
                      _markRead();
                    }
                    // अर्को पक्षको uid — सन्देश इतिहासबाटै (सबभन्दा पछिल्लो
                    // "मैले नपठाएको" सन्देशको sender) निकालिन्छ, अलग Firestore
                    // पढाइ नचाहिने गरी।
                    final otherUid = docs
                        .map((d) => (d.data()['senderUid'] ?? '').toString())
                        .lastWhere((u) => u.isNotEmpty && u != me,
                            orElse: () => '');

                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i].data();
                        final id = docs[i].id;
                        final isMe = data['senderUid'] == me;
                        final type = (data['type'] ?? 'text').toString();
                        final isLast = i == docs.length - 1;
                        // लगातार एउटै व्यक्तिका सन्देश Messenger-शैलीमा नजिक-नजिक
                        // देखिने — समूहको पछिल्लोमा मात्र समय देखाउने।
                        final isLastOfGroup = isLast ||
                            docs[i + 1].data()['senderUid'] !=
                                data['senderUid'];
                        final isFirstOfGroup = i == 0 ||
                            docs[i - 1].data()['senderUid'] !=
                                data['senderUid'];
                        // मैले पठाएको सन्देश अर्को पक्षले हेरिसक्यो/सक्यो — उसको
                        // `readBy` timestamp यो सन्देश लेखिएको बेलाभन्दा अघि
                        // नभए (यही वा पछिको भए) मात्र "seen" (double tick)।
                        final createdAt = data['createdAt'];
                        final otherReadAt = readBy?[otherUid];
                        final seen = isMe &&
                            createdAt is Timestamp &&
                            otherReadAt is Timestamp &&
                            !otherReadAt.toDate().isBefore(createdAt.toDate());

                        // हरेक bubble आफ्नै छुट्टै repaint layer — नत्र
                        // सूचीमा एउटा मात्र item बदलिँदा (नयाँ सन्देश थपिँदा,
                        // वा readBy tick अपडेट हुँदा) पूरै ListView कै सबै
                        // bubble फेरि repaint हुन्थ्यो, लामो chat मा jank।
                        return RepaintBoundary(
                          key: ValueKey('rb_$id'),
                          child: Dismissible(
                          key: Key(id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: AppColors.kmRose),
                          ),
                          confirmDismiss: (_) => _confirmDelete(),
                          onDismissed: (_) => _messages.doc(id).delete(),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: _MessageEntrance(
                                  key: ValueKey(id),
                                  child: _Bubble(
                                    isMe: isMe,
                                    showTail: isLastOfGroup,
                                    topMargin: isFirstOfGroup ? 8 : 2,
                                    time: isLastOfGroup
                                        ? _time(data['createdAt'])
                                        : null,
                                    seen: isMe && isLastOfGroup ? seen : null,
                                    child: _content(type, data, isMe, theme),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          _chatActive ? _inputBar(theme) : _lockedBanner(theme),
        ],
      ),
      ),
    );
  }

  /// Request active नरहेको बेला (Accept हुनुअघि, वा काम completed
  /// भइसकेपछि) इनपुट/कल दुवैको सट्टा देखिने read-only सूचना पट्टी — दुई फरक
  /// कारणका लागि दुई फरक सन्देश। स्वीकृति भएकै क्षणदेखि चैट सधैँ सक्रिय हुने
  /// भएकोले यो banner ती दुई अवस्थामा मात्र देखिन्छ।
  Widget _lockedBanner(ThemeData theme) {
    final completed = _requestStatus == 'completed';
    final caption =
        completed ? S.chatLockedCompleted : S.contactLockedCaption;
    return ClipRect(
      child: glassBackdrop(sigma: 20, child: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: AppColors.kmSurface.withValues(alpha: 0.75),
            border: Border(top: BorderSide(color: AppColors.kmGlassBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppColors.kmMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  caption,
                  style:
                      const TextStyle(fontSize: 12.5, color: AppColors.kmMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
      String type, Map<String, dynamic> data, bool isMe, ThemeData theme) {
    if (type == 'call') {
      final video = (data['mode'] ?? 'audio').toString() == 'video';
      final fg = isMe ? AppColors.kmInk : AppColors.kmText;
      // कल साँच्चै जोडिएकोमा मात्र (`CallSession` ले जोडिएपछि मात्र नाप्ने
      // भएकोले) — नत्र नउठाइएको/decline भएको कलमा पनि "0:00" जस्तो अर्थहीन
      // संख्या देखिन्थ्यो।
      final durationSeconds = (data['durationSeconds'] as num?)?.toInt() ?? 0;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(video ? Icons.videocam_rounded : Icons.call_rounded,
              size: 17, color: fg),
          const SizedBox(width: 6),
          Text(video ? S.videoCall : S.voiceCall,
              style: TextStyle(fontSize: 13, color: fg)),
          if (durationSeconds > 0) ...[
            Text(' · ', style: TextStyle(fontSize: 13, color: fg)),
            Text(formatDuration(durationSeconds),
                style: TextStyle(
                    fontSize: 13,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ],
      );
    }
    if (type == 'image') {
      // नयाँ म्यासेज Storage URL (हल्का) मा; base64 त पुरानो message
      // history कै backward-compat fallback (नयाँ कहिल्यै यसरी लेखिँदैन)।
      final url = (data['imageUrl'] ?? '').toString();
      if (url.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _ChatImage(url: url),
        );
      }
      if (data['imageBase64'] != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(base64Decode(data['imageBase64']),
              width: 200, fit: BoxFit.cover),
        );
      }
    }
    if (type == 'video') {
      final url = (data['videoUrl'] ?? '').toString();
      if (url.isEmpty) return const SizedBox.shrink();
      return SpringTap(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => VideoPreviewScreen(url: url),
          ),
        ),
        pressedScale: 0.97,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 200,
            height: 140,
            color: Colors.black87,
            child: const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 44),
            ),
          ),
        ),
      );
    }
    if (type == 'audio') {
      final durationSeconds = (data['durationSeconds'] as num?)?.toInt() ?? 0;
      final url = (data['audioUrl'] ?? '').toString();
      if (url.isNotEmpty) {
        return _VoiceBubble(
            audioUrl: url, isMe: isMe, durationSeconds: durationSeconds);
      }
      if (data['audioBase64'] != null) {
        return _VoiceBubble(
            audioBytes: base64Decode(data['audioBase64']),
            isMe: isMe,
            durationSeconds: durationSeconds);
      }
    }
    return Text(
      (data['text'] ?? '').toString(),
      style: TextStyle(
        fontSize: 14.5,
        height: 1.3,
        color: isMe ? AppColors.kmInk : AppColors.kmText,
      ),
    );
  }

  Future<bool?> _confirmDelete() => showKmDialog<bool>(
        context: context,
        title: S.delete,
        icon: Icons.delete_outline_rounded,
        iconBg: const LinearGradient(
            colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
        actions: [
          KmDialogAction(
            label: S.cancel,
            onPressed: () => Navigator.pop(context, false),
          ),
          KmDialogAction(
            label: S.delete,
            destructive: true,
            filled: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );

  Widget _inputBar(ThemeData theme) {
    if (_recordingVoice) {
      return ClipRect(
        child: glassBackdrop(sigma: 20, child: Container(
            padding: EdgeInsets.fromLTRB(
                8, 6, 8, 6 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: AppColors.kmSurface.withValues(alpha: 0.75),
              border: Border(top: BorderSide(color: AppColors.kmGlassBorder)),
            ),
            child: VoiceRecorderBar(
              onSend: _sendVoiceBytes,
              onCancel: () => setState(() => _recordingVoice = false),
            ),
          ),
        ),
      );
    }
    if (_sendingMedia) {
      return ClipRect(
        child: glassBackdrop(sigma: 20, child: Container(
            height: 52,
            padding: EdgeInsets.fromLTRB(
                16, 6, 16, 6 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: AppColors.kmSurface.withValues(alpha: 0.75),
              border: Border(top: BorderSide(color: AppColors.kmGlassBorder)),
            ),
            child: Row(
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.kmOrange)),
                const SizedBox(width: 12),
                Text(S.sendingMedia,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.kmMuted)),
              ],
            ),
          ),
        ),
      );
    }
    // तैरिरहेको ग्लास क्याप्सुल (OLED कालो माथि) — logic अपरिवर्तित।
    return Padding(
      padding: EdgeInsets.fromLTRB(
          10, 4, 10, 10 + MediaQuery.of(context).padding.bottom),
      child: GlassCapsule(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CapsuleIcon(
                icon: Icons.camera_alt_rounded,
                color: kNeonTeal,
                onTap: _pickCamera),
            CapsuleIcon(
                icon: Icons.image_rounded,
                color: kNeonPink,
                onTap: _pickGallery),
            CapsuleIcon(
                icon: Icons.videocam_rounded,
                color: kNeonBlue,
                onTap: _showVideoSourceSheet),
            CapsuleIcon(
                icon: Icons.mic_rounded,
                color: kNeonViolet,
                onTap: () => setState(() => _recordingVoice = true)),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                cursorColor: kNeonTeal,
                decoration: InputDecoration(
                  hintText: S.typeMessage,
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 10),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedScale(
              scale: _canSend ? 1.0 : 0.92,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: SpringTap(
                onTap: _canSend
                    ? () {
                        HapticFeedback.lightImpact();
                        _sendText();
                      }
                    : null,
                pressedScale: 0.82,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: _canSend
                        ? const LinearGradient(
                            colors: [kNeonTeal, kNeonViolet],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight)
                        : null,
                    color:
                        _canSend ? null : Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    boxShadow: _canSend
                        ? [
                            BoxShadow(
                                color: kNeonTeal.withValues(alpha: 0.55),
                                blurRadius: 16,
                                spreadRadius: 1),
                          ]
                        : null,
                  ),
                  child: Icon(Icons.send_rounded,
                      size: 20,
                      color: _canSend ? Colors.black : AppColors.kmMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AppBar को गोलो कल बटन — सेतो circle + violet icon (high contrast on
/// gradient)। थिच्नेबित्तिकै CallScreen instant push हुने भएकोले (कुनै
/// network-bound "busy" पर्खाइ छैन) spinner चाहिँदैन — SpringTap कै
/// press-down/bounce ले नै तुरुन्तै tactile feedback दिन्छ।
class _CallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CallBtn({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SpringTap(
        onTap: onTap,
        pressedScale: 0.82,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: AppColors.kmPurpleDeep),
        ),
      ),
    );
  }
}

/// नयाँ सन्देश आउनेबित्तिकै एकपटक मात्र (fade + थोरै माथिबाट स्लाइड) —
/// `TweenAnimationBuilder(tween: Tween(...))` अघि यहाँ प्रयोग हुन्थ्यो, तर
/// त्यसले हरेक build मा नयाँ `Tween` instance बनाउँदा (`begin`/`end` उस्तै
/// भए पनि, reference फरक भएकोले) TweenAnimationBuilder ले "tween बदलियो"
/// ठानेर animation शुरुबाटै (`value = 0`) फेरि चलाउँथ्यो। यो chat screen
/// को दुई-तहको `StreamBuilder` (messages + readBy) ले धेरै (हरेक नयाँ
/// सन्देश, हरेक "seen" mark, हरेक अर्को पक्षको readBy अपडेट) पटक पूरै
/// `ListView` rebuild गर्छ — त्यसैले पहिल्यै देखिसकेका सबै bubble
/// (फोटो/भ्वाइस-नोट सहित) पनि हरेकपटक फेरि फेड-इन हुँदै "फ्लिकर/ग्लिच"
/// जस्तो देखिन्थ्यो, जुन विशेष गरी image/audio bubble मा प्रस्ट देखिन्थ्यो।
/// अब आफ्नै `AnimationController` (`initState` मा एकपटक मात्र `forward()`)
/// प्रयोग गरिन्छ — parent जति पटक rebuild भए पनि (यही `ValueKey(id)` ले
/// element/State जोगिने भएकोले) `initState` दोहोरिँदैन, त्यसैले एकपटक
/// देखिसकेको सन्देश फेरि कहिल्यै फेड-इन हुँदैन।
class _MessageEntrance extends StatefulWidget {
  final Widget child;
  const _MessageEntrance({required super.key, required this.child});

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  late final Animation<double> _curved =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curved.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curved.value) * 8),
          child: child,
        ),
      ),
    );
  }
}

/// Chat भित्रको फोटो bubble — mobile/desktop (native) मा `CachedNetworkImage`
/// (disk-cache फाइदाजनक), तर Flutter Web मा त्यसको मुनिको `flutter_cache_manager`
/// disk cache layer कै वास्तविक filesystem नभएकोले लामो समयदेखि अविश्वसनीय
/// छ (कहिलेकाहीं सफलतापूर्वक अपलोड भइसकेको फोटो पनि broken-image icon सहित
/// देखिने/नदेखिने) — ठ्याक्कै "worker को स्क्रिनमा फोटो देखिँदैन" गुनासो
/// यही थियो। Web मा त्यो cache layer नै नचली Flutter को आफ्नै (व्यापक रूपमा
/// भरपर्दो) `Image.network` प्रयोग गर्ने — cache-control header (upload गर्दा
/// नै सेट गरिएको, `chat_media_service.dart` हेर्नुहोस्) ब्राउजरको आफ्नै HTTP
/// cache ले यसै पनि सम्हाल्छ, अलग plugin-level cache चाहिँदैन।
class _ChatImage extends StatelessWidget {
  final String url;
  const _ChatImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        url,
        key: ValueKey(url),
        width: 200,
        fit: BoxFit.cover,
        // `gaplessPlayback` नभए ListView item recycle/parent rebuild
        // हुनेबित्तिकै यो widget को ImageStream फेरि resolve हुन्छ — त्यो
        // क्षणभर (पुरानो frame मेटिएर नयाँ नआउँदासम्म) खाली/झिप्किएको
        // देखिन्छ, ठ्याक्कै "फोटो लोड हुँदा झिपिक-झिपिक" गुनासोको कारण।
        gaplessPlayback: true,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: 200,
                height: 150,
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.2)),
              ),
        errorBuilder: (_, error, ___) {
          // TEMP DIAGNOSTIC — यो चाहिँ स्थायी हुनु हुँदैन, तर अहिले साँच्चै
          // कारण के हो (network, decode, वा अर्कै) पत्ता लगाउन आवश्यक।
          debugPrint('CHAT_IMG_LOAD_FAILED url=$url error=$error');
          return const SizedBox(
            width: 200,
            height: 150,
            child: Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
          );
        },
      );
    }
    return CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      width: 200,
      fit: BoxFit.cover,
      // default cross-fade (~500ms) ले rebuild हुनेबित्तिकै (जस्तै readBy
      // अपडेट हुँदा) पहिल्यै-लोड भइसकेको फोटो पनि देखिने-गरी-फेरि-fade हुन्छ
      // — त्यही "झिपिक-झिपिक" प्रभाव। शून्य राख्दा already-cached फोटो
      // तुरुन्तै/स्थिर देखिन्छ, Messenger जस्तै।
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox(
        width: 200,
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      ),
      errorWidget: (_, __, error) {
        debugPrint('CHAT_IMG_LOAD_FAILED url=$url error=$error');
        return const SizedBox(
          width: 200,
          height: 150,
          child: Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool isMe;
  // null = यो समूहको अन्तिम सन्देश होइन — Messenger जस्तै लगातार सन्देशमा
  // समय हरेकमा नदेखाई अन्तिममा मात्र देखाउने।
  final String? time;
  // समूहको अन्तिम सन्देशमा मात्र "tail" कुनो (bottom corner) देखिने; बीचका
  // सन्देश दुवैतिर उस्तै गोलो हुन्छन् (Messenger/WhatsApp कै परिचित ढाँचा)।
  final bool showTail;
  final double topMargin;
  final Widget child;
  // WhatsApp/Messenger-शैली read receipt — मैले पठाएको (isMe) सन्देशमा मात्र
  // अर्थपूर्ण: null = लागू हुँदैन (अर्को पक्षको सन्देश), false = पठाइयो तर
  // अझै नहेरिएको (एउटा ✓), true = अर्को पक्षले हेरिसक्यो (डबल ✓, highlight
  // रङमा)।
  final bool? seen;
  const _Bubble({
    required this.isMe,
    required this.time,
    required this.child,
    this.showTail = true,
    this.topMargin = 8,
    this.seen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: topMargin, bottom: 1),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: BoxDecoration(
        gradient: isMe ? AppColors.kmCtaGradient : null,
        color: isMe ? null : Colors.white.withValues(alpha: 0.08),
        border: isMe
            ? null
            : Border.all(color: AppColors.kmGlassBorder),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe || !showTail ? 18 : 4),
          bottomRight: Radius.circular(!isMe || !showTail ? 18 : 4),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          child,
          if (time != null) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time!,
                    style: TextStyle(
                        fontSize: 9.5,
                        color: isMe
                            ? AppColors.kmInk.withValues(alpha: 0.65)
                            : AppColors.kmMuted)),
                if (seen != null) ...[
                  const SizedBox(width: 3),
                  Icon(
                    seen! ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 13,
                    color: seen!
                        ? AppColors.kmTealBlue
                        : AppColors.kmInk.withValues(alpha: 0.65),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  /// नयाँ म्यासेजका लागि — Storage बाट सिधै streamed play (पूरै फाइल
  /// पहिले memory मा डाउनलोड गर्नु पर्दैन, tap गर्नेबित्तिकै तुरुन्तै सुरु)।
  final String? audioUrl;

  /// पुरानो base64 message (backward-compat fallback) का लागि मात्र।
  final Uint8List? audioBytes;
  final bool isMe;

  /// रेकर्डिङ बेलै नाप्ता (सेकेन्डमा) — यही message देखिनेबित्तिकै तुरुन्तै
  /// देखाउन (audio फाइल load हुनुपर्दैन, playback सुरु नभई पनि देखिन्छ)।
  /// पुरानो (यो field आउनुअघिको) सन्देशमा 0 — त्यसबेला साधारण "Voice
  /// message" लेबल नै देखिन्छ।
  final int durationSeconds;

  const _VoiceBubble({
    this.audioUrl,
    this.audioBytes,
    required this.isMe,
    this.durationSeconds = 0,
  }) : assert(audioUrl != null || audioBytes != null);

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else if (widget.audioUrl != null) {
      await _player.play(UrlSource(widget.audioUrl!));
    } else {
      await _player.play(BytesSource(widget.audioBytes!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? AppColors.kmInk : AppColors.kmText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Icon(
              _playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: fg,
              size: 30),
        ),
        const SizedBox(width: 8),
        Icon(Icons.graphic_eq_rounded, color: fg.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Text(
          widget.durationSeconds > 0
              ? formatDuration(widget.durationSeconds)
              : S.voiceMessage,
          style: TextStyle(
              fontSize: 12.5,
              color: fg,
              fontFeatures: widget.durationSeconds > 0
                  ? const [FontFeature.tabularFigures()]
                  : null),
        ),
      ],
    );
  }
}
