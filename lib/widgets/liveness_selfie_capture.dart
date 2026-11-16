// widgets/liveness_selfie_capture.dart
// Face Liveness Scanning — KYC selfie अब स्थिर single photo (पुरानो
// `ImagePicker().pickImage(source: camera)`) होइन, बरु live front-camera
// view मा छोटो चुनौती (सिधा हेर्नुहोस् → झिम्क्याउनुहोस् → टाउको घुमाउनुहोस्)
// पूरा गरेपछि मात्र क्याप्चर हुन्छ — on-device ML Kit Face Detection ले नै
// (कुनै तस्बिर/डेटा नेटवर्कमा नजाने)।
//
// Heuristic, Not True Depth-3D — यो स्थिर 2D फोटो (printed photo+eye-holes,
// दोस्रो स्क्रिनमा video replay) बाट पूर्ण सुरक्षित होइन — iPhone Face ID
// जस्तो depth-sensing hardware अधिकांश Android फोनमा छैन, र त्यसको लागि
// cross-platform standard API पनि अस्तित्वमा छैन। यो केवल सामान्य/casual
// fraud (सिधै गैलरीबाट पुरानो फोटो) रोक्ने on-device heuristic हो — जानाजान
// स्वीकारिएको सीमा, नयाँ commercial liveness-vendor भन्दा फरक ट्रेडअफ।
//
// Still-Capture Polling (Not Raw YUV Stream) — frame-by-frame raw
// `CameraImage` (YUV_420_888/NV21/BGRA8888) लाई हातैले `InputImage.fromBytes`
// मा बदल्ने काम plane-format अनुसार धेरै सूक्ष्म/गल्ती हुन सहज हुन्छ, र
// डिभाइसमै नजाँची त्यस्तो कोड ठीक छ भनेर पक्का गर्न सकिँदैन। बरु हरेक ~600ms
// मा `controller.takePicture()` (साँचो JPEG फाइल, `InputImage.fromFilePath`
// ले नै सिधै decode गर्छ — format-conversion नै चाहिँदैन) बाट हेर्छ — live
// preview (`CameraPreview`) भने यसबाट अप्रभावित, निरन्तर नै देखिन्छ। मानव-
// गतिको चुनौती (झिम्काउने/घुमाउने) का लागि ६००ms sampling प्रशस्त हो।
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/ocr_match_service.dart';
import '../theme/app_theme.dart';

// DEBUG-ONLY MOCK SELFIE — साँचो क्यामेरा/ML Kit कहिल्यै नचलाई तुरुन्तै एउटा
// निश्चित १×१ JPEG फर्काउने। `kDebugMode` (debug build मा मात्र `true`) ले
// यसलाई प्रयोग गर्ने एकमात्र ठाउँ (`_DebugMockButton`/`_mockCapture` तल)
// double-guard गर्छ — release/profile build मा यो बटन नै कहिल्यै देखिँदैन।
const String _debugMockJpegBase64 =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=';

/// Pushes a fullscreen live-camera liveness challenge. Returns the captured
/// JPEG bytes on success, or `null` if the user cancels — same nullable
/// `Uint8List` contract as `ImagePicker().pickImage()`, so this is a drop-in
/// replacement at each KYC flow's existing selfie-capture call site.
Future<Uint8List?> captureLivenessSelfie(BuildContext context) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => const LivenessSelfieCapture(),
      fullscreenDialog: true,
    ),
  );
}

enum _Stage { starting, lookStraight, blink, turnHead, capturing, error }

class LivenessSelfieCapture extends StatefulWidget {
  const LivenessSelfieCapture({super.key});

  @override
  State<LivenessSelfieCapture> createState() => _LivenessSelfieCaptureState();
}

class _LivenessSelfieCaptureState extends State<LivenessSelfieCapture> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  _Stage _stage = _Stage.starting;
  String? _error;
  bool _busy = false;

  // Blink debounce — एक पटक मात्रको noisy frame ले गलत-सकारात्मक नदेओस्
  // भनेर लगातार कम्तिमा २ पटक eyes-closed भेटिएपछि मात्र "झिम्क्यायो" मान्ने।
  int _closedStreak = 0;
  bool _sawClosedEyes = false;

  static const _eyesOpenThreshold = 0.6;
  static const _eyesClosedThreshold = 0.3;
  static const _headTurnThresholdDeg = 15.0;
  static const _headStraightThresholdDeg = 10.0;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _stage == _Stage.capturing) return;
      setState(() {
        _error = "Couldn't complete the check in time. Please try again.";
        _stage = _Stage.error;
      });
      _pollTimer?.cancel();
    });
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );
      setState(() {
        _controller = controller;
        _stage = _Stage.lookStraight;
      });
      _pollTimer = Timer.periodic(
          const Duration(milliseconds: 600), (_) => _pollOnce());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera unavailable: $e';
        _stage = _Stage.error;
      });
    }
  }

  Future<void> _pollOnce() async {
    final controller = _controller;
    final detector = _faceDetector;
    if (controller == null ||
        detector == null ||
        _busy ||
        _stage == _Stage.capturing ||
        _stage == _Stage.error) {
      return;
    }
    _busy = true;
    XFile? shot;
    try {
      shot = await controller.takePicture();
      final faces =
          await detector.processImage(InputImage.fromFilePath(shot.path));
      if (!mounted) return;
      if (faces.isEmpty) {
        _busy = false;
        return;
      }
      final face = faces.first;
      await _advance(face);
    } catch (_) {
      // क्षणिक त्रुटि (frame drop/timeout) — पूरै challenge नरोकी अर्को
      // poll-tick मा फेरि कोसिस हुन्छ।
    } finally {
      if (shot != null) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
      _busy = false;
    }
  }

  Future<void> _advance(Face face) async {
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    final yaw = face.headEulerAngleY;

    switch (_stage) {
      case _Stage.lookStraight:
        if (yaw != null && yaw.abs() < _headStraightThresholdDeg) {
          setState(() => _stage = _Stage.blink);
        }
        return;

      case _Stage.blink:
        if (leftOpen == null || rightOpen == null) return;
        final bothClosed =
            leftOpen < _eyesClosedThreshold && rightOpen < _eyesClosedThreshold;
        final bothOpen =
            leftOpen > _eyesOpenThreshold && rightOpen > _eyesOpenThreshold;
        if (bothClosed) {
          _closedStreak++;
          if (_closedStreak >= 1) _sawClosedEyes = true;
        } else {
          _closedStreak = 0;
        }
        if (_sawClosedEyes && bothOpen) {
          setState(() => _stage = _Stage.turnHead);
        }
        return;

      case _Stage.turnHead:
        if (yaw == null) return;
        if (yaw.abs() > _headTurnThresholdDeg) {
          // टाउको पुगेको पुष्टि भयो — सीधा फर्कनेबित्तिकै क्याप्चर गर्ने।
          _headTurnConfirmed = true;
          return;
        }
        if (_headTurnConfirmed && yaw.abs() < _headStraightThresholdDeg) {
          await _capture();
        }
        return;

      case _Stage.starting:
      case _Stage.capturing:
      case _Stage.error:
        return;
    }
  }

  bool _headTurnConfirmed = false;

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _stage = _Stage.capturing);
    _pollTimer?.cancel();
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      try {
        await File(file.path).delete();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not capture photo: $e';
        _stage = _Stage.error;
      });
    }
  }

  /// DEBUG-ONLY — साँचो क्यामेरा/liveness/OCR बिना नै KYC flow अगाडि बढाउन।
  /// Caller (बटन, तलको `build()`) आफैं `kDebugMode` ले wrap गरिएको हुन्छ —
  /// release build मा यो method कहिल्यै बोलाइँदैन। यहीं OCR gate पनि
  /// auto-pass गरिदिन्छ (एउटै बटनले दुवै — liveness + OCR — छोप्ने, ताकि
  /// कागजातको साँचो फोटो नभए पनि पूरा registration flow test गर्न सकियोस्)।
  void _mockCapture() {
    OcrMatchService.debugAutoPassEnabled = true;
    Navigator.of(context).pop<Uint8List>(base64Decode(_debugMockJpegBase64));
  }

  String get _instruction => switch (_stage) {
        _Stage.starting => 'Starting camera…',
        _Stage.lookStraight => 'Look straight at the camera',
        _Stage.blink => 'Blink naturally',
        _Stage.turnHead => 'Slowly turn your head, then look straight again',
        _Stage.capturing => 'Capturing…',
        _Stage.error => _error ?? 'Something went wrong',
      };

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _faceDetector?.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: AppColors.kmVoid,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipOval(
                    child: Transform.scale(
                      // Front-camera mirror — प्रयोगकर्ताले ऐनामा हेरेजस्तै
                      // आफैंलाई देख्नुपर्छ, नत्र "उल्टो" देखिन्छ।
                      scaleX: -1,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              )
            else if (_stage != _Stage.error)
              const Center(
                  child: CircularProgressIndicator(color: AppColors.kmOrange)),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.kmText),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // DEBUG-ONLY MOCK PASS — साँचो भौतिक ID/license कागजात वा लामो
            // blink/head-turn challenge बिना नै registration flow test
            // गर्न। `kDebugMode` false भएको जुनसुकै build (profile/release
            // सहित) मा यो सिंगो subtree नै कहिल्यै build हुँदैन।
            if (kDebugMode)
              Positioned(
                top: 12,
                right: 12,
                child: ElevatedButton.icon(
                  onPressed: _mockCapture,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.bug_report_rounded, size: 18),
                  label: const Text('Mock Pass (Debug)'),
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.kmSurface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.kmText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_stage == _Stage.error) ...[
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _stage = _Stage.starting;
                          _closedStreak = 0;
                          _sawClosedEyes = false;
                          _headTurnConfirmed = false;
                        });
                        _pollTimer?.cancel();
                        _timeoutTimer?.cancel();
                        _timeoutTimer = Timer(const Duration(seconds: 30), () {
                          if (!mounted || _stage == _Stage.capturing) return;
                          setState(() {
                            _error = "Couldn't complete the check in time.";
                            _stage = _Stage.error;
                          });
                        });
                        if (_controller != null) {
                          setState(() => _stage = _Stage.lookStraight);
                          _pollTimer = Timer.periodic(
                              const Duration(milliseconds: 600),
                              (_) => _pollOnce());
                        } else {
                          _setup();
                        }
                      },
                      child: const Text('Try Again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
