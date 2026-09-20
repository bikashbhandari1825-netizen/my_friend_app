// location_util.dart
// GPS location एकपटक लिने साझा helper (registration + अन्य ठाउँमा प्रयोग)।
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'l10n/strings.dart';

class LocationResult {
  final double? lat;
  final double? lng;

  /// 'ok' | 'denied' | 'denied_forever' | 'service_disabled' | 'error'
  final String status;

  const LocationResult(this.lat, this.lng, this.status);

  bool get ok => status == 'ok' && lat != null && lng != null;

  /// प्रयोगकर्ताले "Don't ask again" गरेर सधैँका लागि अस्वीकार गरेको —
  /// फेरि माग्दा केही देखिँदैन, settings मै पुग्नुपर्छ।
  bool get permanentlyDenied => status == 'denied_forever';
}

/// अनुमति माग्छ र अहिलेको स्थान फर्काउँछ। असफल भए lat/lng null सहित status भन्छ
/// — caller ले status हेरेर ठ्याक्कै किन असफल भयो (permission, OS-level
/// location toggle, वा अरू) भन्ने प्रयोगकर्तालाई देखाउन सक्छ, होइन भने सधैँ
/// उस्तै generic सन्देश देखाउनुपर्ने हुन्थ्यो।
Future<LocationResult> getCurrentLocation() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (!serviceEnabled) {
      return const LocationResult(null, null, 'service_disabled');
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationResult(null, null, 'denied_forever');
    }
    if (perm == LocationPermission.denied) {
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

/// worker/employer को user profile मा पहिल्यै बचत भएको अन्तिम थाहा भएको
/// coordinate — लाइभ GPS भेटिएन/लेखिएन भने fallback को रूपमा प्रयोग गर्न।
Future<({double lat, double lng})?> lastKnownProfileLocation(String uid) async {
  try {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final lat = (snap.data()?['lat'] as num?)?.toDouble();
    final lng = (snap.data()?['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  } catch (_) {
    return null;
  }
}

/// प्रयोगकर्तालाई सिधै फोनको App Settings मा लैजाने — permanently-denied
/// अवस्थामा फेरि in-app prompt देखाएर फाइदा हुँदैन, settings मै गएर अनुमति
/// फेरि on गर्नुपर्छ।
Future<void> openLocationAppSettings() => Geolocator.openAppSettings();

/// lat/lng बाट मानिसले पढ्न मिल्ने ठेगाना (Nominatim / OSM)। असफल भए खाली।
Future<String> reverseGeocode(double lat, double lng) async {
  try {
    final lang = S.isNepali ? 'ne' : 'en';
    final uri =
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2'
            '&lat=$lat&lon=$lng&accept-language=$lang');
    final res = await http.get(uri, headers: {
      'User-Agent': 'KaamMitra/1.0 (job address)',
    }).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['display_name'] ?? '').toString();
    }
  } catch (_) {}
  return '';
}
