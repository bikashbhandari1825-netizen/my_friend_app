// utils/live_gps_metrics.dart
//
// लाइभ GPS ट्र्याकिङ को असली ढिलाइ नाप्ने (debug build मा मात्र; release मा
// केही चल्दैन)। यात्रीको स्क्रिनमा driver को हरेक नयाँ स्थान आउँदा:
//   • latency = अहिलेको समय − driver ले Firestore मा लेखेको समय
//     (`workerLocationUpdatedAt`, सर्भर timestamp) — दुवै फोनको घडी सही
//     भएमा मात्र विश्वसनीय;
//   • gap = अघिल्लो स्थान र यसबीचको अन्तर (आइकन कति बेर अडियो)।
// हरेक १० नमूनामा `GPS_LATENCY_SUMMARY` छापिन्छ।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class LiveGpsMetrics {
  static Timestamp? _lastTs;
  static DateTime? _lastRecv;
  static int _n = 0;
  static int _sumLatency = 0;
  static int _maxLatency = 0;
  static int _latencyOver3s = 0;
  static int _maxGap = 0;
  static int _gapOver5s = 0;

  // driver तर्फ — लेखाइ गन्ती/असफलता।
  static int _writes = 0;
  static int _writeFailures = 0;

  static void sample(Map<String, dynamic> data) {
    if (!kDebugMode) return;
    final ts = data['workerLocationUpdatedAt'];
    if (ts is! Timestamp) return;
    if (_lastTs != null && ts.compareTo(_lastTs!) == 0) return; // उही नमूना
    _lastTs = ts;
    final now = DateTime.now();
    final latency = now.difference(ts.toDate()).inMilliseconds;
    final gap =
        _lastRecv == null ? 0 : now.difference(_lastRecv!).inMilliseconds;
    _lastRecv = now;
    _n++;
    _sumLatency += latency;
    if (latency > _maxLatency) _maxLatency = latency;
    if (latency > 3000) _latencyOver3s++;
    if (gap > _maxGap) _maxGap = gap;
    if (gap > 5000) _gapOver5s++;
    debugPrint('GPS_LATENCY ms=$latency gapMs=$gap');
    if (_n % 10 == 0) {
      debugPrint('GPS_LATENCY_SUMMARY n=$_n avg=${_sumLatency ~/ _n}ms '
          'max=${_maxLatency}ms over3s=$_latencyOver3s '
          'maxGap=${_maxGap}ms gapOver5s=$_gapOver5s');
    }
  }

  static void driverWrite() {
    if (kDebugMode) _writes++;
  }

  static void driverWriteFailed() {
    if (!kDebugMode) return;
    _writeFailures++;
    debugPrint('GPS_WRITE_FAILED failures=$_writeFailures of $_writes writes');
  }
}
