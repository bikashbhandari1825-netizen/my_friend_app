// location_util.dart
// GPS location एकपटक लिने साझा helper (registration + अन्य ठाउँमा प्रयोग)।
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
/// Nominatim को free tier ले धेरैपटक झट्टाझट्टै आउने request (rate-limit)
/// कहिलेकाहीं खाली जवाफ दिन्छ — त्यसैले एक-पटक असफल/खाली भए छोटो पर्खाइपछि
/// फेरि एकपटक कोसिस (location_picker_page.dart मा पहिल्यै प्रयोग हुने
/// उस्तै resilience, अब यहीं साझा ठाउँमा — यो function प्रयोग गर्ने सबैले
/// फाइदा पाउने गरी)।
/// ठेगाना/ठाउँको नाम (जस्तै "Bhaktapur" वा पूर्ण ठेगाना) ले खोजेर सम्भावित
/// स्थानहरू फर्काउने — Ride-Hailing को "Where to?" खोज बक्समा प्रयोग हुन्छ।
/// पहिले सिधै Nominatim (OSM, free) बाट हुँदै थियो — त्यसले `countrycodes=np`
/// प्रतिबन्धका कारण Nepal-बाहिरका ठेगाना (टेस्ट/भ्रमणकारी) कहिल्यै भेट्दैनथ्यो,
/// र प्रायः native Google Maps जस्तो सही/पूर्ण नतिजा दिँदैनथ्यो। अब त्यही
/// एउटै Maps API key (Directions/`getRoute` कै) प्रयोग गर्ने server-side
/// Google Geocoding API (`geocodeSearch` Cloud Function, functions/index.js)
/// बाट — global खोजी, key कहिल्यै client मा एक्स्पोज नहुने।
Future<List<({String label, double lat, double lng})>> searchPlaces(
    String query, {double? biasLat, double? biasLng}) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  try {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'geocodeSearch',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'query': q,
      if (biasLat != null && biasLng != null) 'biasLat': biasLat,
      if (biasLat != null && biasLng != null) 'biasLng': biasLng,
    });
    final list = (result.data['results'] as List?) ?? const [];
    return list.map((e) {
      // `e as Map<String, dynamic>` (कडा generic cast) ले यहाँ silently
      // असफल हुँदै थियो — Android platform channel ले nested map हरू
      // प्रायः `Map<Object?, Object?>` को रूपमा फर्काउँछ (सिधै
      // `Map<String, dynamic>` होइन), जसले गर्दा हरेक खोजी नतिजा (server
      // ले सही डेटा फर्काए पनि) यहीँ `catch` भएर सधैँ खाली सूची फर्किरहेको
      // थियो। untyped `Map` मा cast गर्दा दुवै किसिमको map चल्छ।
      final m = e as Map;
      return (
        label: (m['label'] ?? '').toString(),
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
      );
    }).where((r) => r.label.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

Future<String> reverseGeocode(double lat, double lng) async {
  final lang = S.isNepali ? 'ne' : 'en';
  final uri =
      Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2'
          '&lat=$lat&lon=$lng&accept-language=$lang');
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'KaamMitra/1.0 (job address)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final found = (body['display_name'] ?? '').toString();
        if (found.isNotEmpty) return found;
      }
    } catch (_) {}
    if (attempt == 0) await Future.delayed(const Duration(seconds: 1));
  }
  return '';
}
