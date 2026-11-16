// dead_reckoning.dart
// GPS-Anchored Gyroscope Heading Fusion — GPS fix हरू बीचको खाली ठाउँमा पनि
// बाइकको फर्किने दिशा (bearing) लाई gyroscope बाट निरन्तर (हरेक sensor
// sample मा, ~50-100Hz) अपडेट गर्छ, GPS fix आउनेबित्तिकै मात्र होइन —
// टर्न/मोडमा पनि तुरुन्तै, liquid-smooth प्रतिक्रिया दिन।
//
// Mounted-Phone Assumption — यो फोन बाइकमा दरिलो गरी टाँसिएको (mounted)
// मान्छ, फोन आफैं चलेको/घुमेको लाई बाइक नै त्यसरी चलेको/घुमेको भनी व्याख्या
// गर्छ। Handheld/खल्तीमा भएको फोनमा यो मान्यता गलत हुन्छ (driver को हात
// हल्लिँदा बाइक नचलिकन पनि "घुमेको" देखिन सक्छ) — caller ले यो सुनिश्चित
// गरेर मात्र `start()` बोलाउनुपर्छ।
//
// Complementary Filter (पूर्ण Kalman/EKF होइन, जानाजान) — पूर्ण Extended
// Kalman Filter (covariance matrix, noise-model सहित) ले राम्रोसँग tune
// नभए साँचो Kalman भन्दा नराम्रो नतिजा दिन सक्छ (गलत noise-अनुमानले नै
// ठूलो त्रुटि निम्त्याउन सक्छ)। Complementary filter (drone/AR app हरूमा
// व्यापक रूपमा प्रमाणित — production-proven, कम जोखिमपूर्ण) ले व्यवहारमा
// उस्तै सहज नतिजा दिन्छ: gyro ले तत्काल/हरेक-tick drive गर्छ, GPS ले
// बेला-बेला (हरेक fix मा) सानो अंश मात्र तानेर drift सच्याउँछ।
//
// Mount-Orientation-Independent Yaw Extraction — फोन कुन कोणमा माउन्ट भए
// पनि (सीधा ठड्याएर, आडो/landscape, वा झुकाएर) — gyroscope को 3D angular
// velocity लाई accelerometer-मापित gravity-दिशामाथि project (dot product)
// गर्दा ठ्याक्कै "संसारको vertical axis वरिपरिको घुम्ने दर" (yaw rate)
// निस्कन्छ — कुनै एउटा फिक्स axis (जस्तै सधैं फोनको Z) हार्डकोड गर्नुभन्दा
// बढी सही, वास्तविक mobile IMU navigation मा मानक प्रविधि।
//
// Sign Convention Note — पहिलो साँचो live device test मा अनिवार्य जाँच्नुपर्ने:
// बाइक दायाँ मोडिंदा आइकन पनि दायाँतिरै घुम्छ कि? होइन भने तल `_yawSign`
// (एउटै ठाउँ, स्पष्ट कमेन्ट सहित) लाई -1 बाट +1 (वा उल्टो) मा फर्काउनुहोस्
// — यो साधारण/अपेक्षित calibration step हो, कुनै गहिरो बग होइन (gyroscope
// sign convention device/platform अनुसार फरक हुन सक्छ)।
import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

class HeadingFusionEngine {
  HeadingFusionEngine({required this.onHeadingUpdate});

  /// हरेक पटक fused heading अपडेट हुँदा caller लाई सूचित गर्ने।
  final void Function(double headingDeg) onHeadingUpdate;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Low-pass-filtered gravity vector (device-local frame)।
  double _gx = 0, _gy = 0, _gz = 9.8;
  bool _gravityReady = false;

  double? _fusedHeadingDeg;
  DateTime? _lastGyroTime;

  /// पहिलो live device test मा दिशा उल्टो देखिए यहीं -1↔1 फर्काउनुहोस्।
  static const double _yawSign = -1;

  void start() {
    stop();
    _accelSub = accelerometerEventStream().listen(_onAccel, onError: (_) {});
    _gyroSub = gyroscopeEventStream().listen(_onGyro, onError: (_) {});
  }

  void stop() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
  }

  void dispose() => stop();

  void _onAccel(AccelerometerEvent e) {
    // Gravity-direction low-pass — छोटो-छोटो real acceleration transient
    // (ब्रेक/गति-वृद्धि) चाँडै "भुल्ने", स्थिर gravity-दिशा मात्र बाँकी
    // रहने — complementary filter कै उस्तै सिद्धान्त, यहाँ भने
    // orientation-reference निकाल्न प्रयोग।
    const alpha = 0.9;
    _gx = alpha * _gx + (1 - alpha) * e.x;
    _gy = alpha * _gy + (1 - alpha) * e.y;
    _gz = alpha * _gz + (1 - alpha) * e.z;
    _gravityReady = true;
  }

  void _onGyro(GyroscopeEvent e) {
    final now = DateTime.now();
    final last = _lastGyroTime;
    _lastGyroTime = now;
    if (!_gravityReady || last == null || _fusedHeadingDeg == null) return;
    final dt = now.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.5) return; // ग्याप/पहिलो-sample guard

    final gMag = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (gMag < 1e-6) return;
    final yawRateRadPerSec = (e.x * _gx + e.y * _gy + e.z * _gz) / gMag;
    final yawRateDegPerSec = _yawSign * yawRateRadPerSec * 180 / math.pi;

    _fusedHeadingDeg =
        _normalizeDeg(_fusedHeadingDeg! + yawRateDegPerSec * dt);
    onHeadingUpdate(_fusedHeadingDeg!);
  }

  /// GPS/route-tangent बाट आएको विश्वासिलो heading — gyro-drift सच्याउन
  /// (complementary filter को "correction" भाग)। caller ले confidence
  /// पहिल्यै जाँचेर मात्र बोलाउनुपर्छ (route_map_view.dart कै उस्तै गेट)।
  void anchorToGps(double gpsHeadingDeg) {
    final current = _fusedHeadingDeg;
    if (current == null) {
      _fusedHeadingDeg = gpsHeadingDeg;
      onHeadingUpdate(gpsHeadingDeg);
      return;
    }
    // Correction Gain — gyro ले अधिकांश (तत्काल, हरेक gyro-tick) drive
    // गर्छ; GPS ले बेला-बेलामा (हरेक fix मा) सानो अंश (15%) मात्र तान्छ
    // ताकि gyro drift संचित नहोस्, तर एकैचोटि ठूलो उफ्री/झट्का नदेखियोस्।
    const gpsCorrectionGain = 0.15;
    final delta = _shortestAngleDelta(current, gpsHeadingDeg);
    _fusedHeadingDeg = _normalizeDeg(current + delta * gpsCorrectionGain);
    onHeadingUpdate(_fusedHeadingDeg!);
  }

  static double _normalizeDeg(double d) => ((d % 360) + 360) % 360;

  static double _shortestAngleDelta(double from, double to) {
    var delta = (to - from) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }
}
