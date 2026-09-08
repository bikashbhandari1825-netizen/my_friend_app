// location_util.dart
// GPS location एकपटक लिने साझा helper (registration + अन्य ठाउँमा प्रयोग)।
import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double? lat;
  final double? lng;

  /// 'ok' | 'denied' | 'error'
  final String status;

  const LocationResult(this.lat, this.lng, this.status);

  bool get ok => status == 'ok' && lat != null && lng != null;
}

/// अनुमति माग्छ र अहिलेको स्थान फर्काउँछ। असफल भए lat/lng null सहित status भन्छ।
Future<LocationResult> getCurrentLocation() async {
  try {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return const LocationResult(null, null, 'denied');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.medium),
    ).timeout(const Duration(seconds: 12));
    return LocationResult(p.latitude, p.longitude, 'ok');
  } catch (_) {
    return const LocationResult(null, null, 'error');
  }
}
