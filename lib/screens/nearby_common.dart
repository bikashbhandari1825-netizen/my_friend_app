// screens/nearby_common.dart
// Nearby list र Nearby map दुवैले प्रयोग गर्ने साझा: geo helper + offer/bidding sheet।
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

// काठमाडौँ केन्द्र — location नपाउँदा fallback।
const double fallbackLat = 27.7172;
const double fallbackLng = 85.3240;

/// Google Maps को आफ्नै default POI icon (gym को दौडने-मान्छे, restaurant को
/// काँटा-चम्चा, पसलको कार्ट आदि — हाम्रो marker/pin होइनन्, base tile मै
/// baked भएका) ले नक्सा घुइँचो देखाउँथ्यो — worker/destination pin खोज्न
/// गाह्रो बनाउँदै। InDrive/Uber जस्ता राइड-हेलिङ एपले जस्तै ती सबै व्यापारिक
/// icon/label लुकाएर सडक, पानी, पार्कको हरियो जस्ता भू-सन्दर्भ भने ज्यूँका
/// त्यूँ राख्छ — यसैले route/road नेटवर्क अझै पूर्ण रूपमा देखिन्छ।
const String kCleanMapStyle = '''
[
  {"featureType": "poi", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "labels.text", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]}
]
''';

const List<Map<String, dynamic>> serviceFilters = [
  {
    // गाडीको चिन्ह (Driver सँग मिल्ने) होइन — स्पष्ट औजार चिन्ह।
    'name': 'Mechanic',
    'icon': Icons.build_rounded,
    'image': 'assets/images/services/mechanic.png'
  },
  {
    'name': 'Plumber',
    'icon': Icons.plumbing,
    'image': 'assets/images/services/plumber.png'
  },
  {
    'name': 'Electrician',
    'icon': Icons.electric_bolt,
    'image': 'assets/images/services/electrician.png'
  },
  {
    'name': 'Carpenter',
    'icon': Icons.carpenter,
    'image': 'assets/images/services/carpenter.png'
  },
  {
    'name': 'Painter',
    'icon': Icons.format_paint,
    'image': 'assets/images/services/painter.png'
  },
  {
    'name': 'Cleaner',
    'icon': Icons.cleaning_services,
    'image': 'assets/images/services/cleaner.png'
  },
  {
    'name': 'Driver',
    'icon': Icons.drive_eta,
    'image': 'assets/images/services/driver.png'
  },
  {
    'name': 'Tutor',
    'icon': Icons.school,
    'image': 'assets/images/services/tutor.png'
  },
];

/// सेवा प्रकारको वास्तविक तस्बिर asset path।
String serviceImageFor(String service) {
  for (final s in serviceFilters) {
    if ((s['name'] as String).toLowerCase() == service.toLowerCase()) {
      return (s['image'] as String?) ??
          'assets/images/services/${service.toLowerCase()}.png';
    }
  }
  return 'assets/images/services/${service.toLowerCase()}.png';
}

/// सेवा प्रकार अनुसार marker को रङ (rider icon होइन — काम अनुसार फरक)।
double serviceMarkerHue(String service) {
  switch (service.toLowerCase()) {
    case 'mechanic':
      return BitmapDescriptor.hueOrange;
    case 'plumber':
      return BitmapDescriptor.hueAzure;
    case 'electrician':
      return BitmapDescriptor.hueYellow;
    case 'carpenter':
      return BitmapDescriptor.hueRose;
    case 'painter':
      return BitmapDescriptor.hueViolet;
    case 'cleaner':
      return BitmapDescriptor.hueCyan;
    case 'driver':
      return BitmapDescriptor.hueBlue;
    case 'tutor':
      return BitmapDescriptor.hueMagenta;
    default:
      return BitmapDescriptor.hueRed;
  }
}

/// सेवा प्रकार अनुसार marker को ठोस रङ (custom avatar marker मा प्रयोग)।
Color serviceMarkerColor(String service) {
  switch (service.toLowerCase()) {
    case 'mechanic':
      return const Color(0xFFF77737); // orange
    case 'plumber':
      return const Color(0xFF2E7CF6); // azure
    case 'electrician':
      return const Color(0xFFF5B400); // amber
    case 'carpenter':
      return const Color(0xFFE1306C); // rose
    case 'painter':
      return AppColors.igViolet;
    case 'cleaner':
      return const Color(0xFF16B8C4); // cyan
    case 'driver':
      return const Color(0xFF3B82F6); // blue
    case 'tutor':
      return const Color(0xFFC13584); // magenta
    default:
      return AppColors.igRed;
  }
}

final Map<int, BitmapDescriptor> _avatarMarkerCache = {};

/// InDrive-style: standard pin होइन — worker profile icon भएको गोलो custom marker।
/// रङ सेवा अनुसार। एकपटक बनाएर cache हुन्छ।
Future<BitmapDescriptor> workerAvatarMarker(Color color) async {
  final key = color.toARGB32();
  final cached = _avatarMarkerCache[key];
  if (cached != null) return cached;

  const double size = 128;
  const double c = size / 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawCircle(const Offset(c, c + 4), c - 10,
      Paint()..color = Colors.black.withValues(alpha: 0.22));
  canvas.drawCircle(const Offset(c, c), c - 8, Paint()..color = color);
  canvas.drawCircle(const Offset(c, c), c - 18, Paint()..color = Colors.white);

  final tp = TextPainter(textDirection: TextDirection.ltr);
  tp.text = TextSpan(
    text: String.fromCharCode(Icons.engineering_rounded.codePoint),
    style: TextStyle(
      fontSize: 60,
      fontFamily: Icons.engineering_rounded.fontFamily,
      package: Icons.engineering_rounded.fontPackage,
      color: color,
    ),
  );
  tp.layout();
  tp.paint(canvas, Offset(c - tp.width / 2, c - tp.height / 2));

  final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final bd = BitmapDescriptor.bytes(data!.buffer.asUint8List());
  _avatarMarkerCache[key] = bd;
  return bd;
}

final Map<int, BitmapDescriptor> _dotMarkerCache = {};

/// "You are here" dot — filled circle + white ring + faint halo.
Future<BitmapDescriptor> pulseDotMarker(Color color) async {
  final key = color.toARGB32();
  final hit = _dotMarkerCache[key];
  if (hit != null) return hit;

  const double s = 96;
  const double c = s / 2;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawCircle(const Offset(c, c), c - 6,
      Paint()..color = color.withValues(alpha: 0.20));
  canvas.drawCircle(const Offset(c, c), 18, Paint()..color = Colors.white);
  canvas.drawCircle(const Offset(c, c), 13, Paint()..color = color);

  final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _dotMarkerCache[key] = bd;
  return bd;
}

/// दुई बिन्दुबीचको bearing — उत्तरबाट clockwise डिग्रीमा (0–360)। नयाँ GPS
/// बिन्दु आउनेबित्तिकै [navigationArrowMarker] कुन दिशामा फर्किनुपर्छ भनेर
/// live-tracking नक्साले प्रयोग गर्छ (लगातार दुई थाहा भएका बिन्दुबाट)।
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = _deg2rad(from.latitude);
  final lat2 = _deg2rad(to.latitude);
  final dLng = _deg2rad(to.longitude - from.longitude);
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  final deg = atan2(y, x) * 180 / pi;
  return (deg + 360) % 360;
}

final Map<int, BitmapDescriptor> _navArrowCache = {};

/// Navigation-app-शैलीको दिशा-सूचक तीर (Uber/Google Maps को नीलो
/// "you are heading this way" arrow जस्तै) — accept भएको काममा worker
/// गन्तव्यतिर चलिरहँदा नक्सामा देखिने marker। उत्तरतिर (माथि, rotation = 0)
/// देखाउने गरी drawn हुन्छ; caller ले `Marker(rotation: bearingDeg, flat:
/// true, ...)` राखेर हालको दिशामा घुमाउँछ — त्यसैले यहाँ rotation logic
/// छैन, स्थिर आकार मात्र, रङ अनुसार cache हुन्छ।
Future<BitmapDescriptor> navigationArrowMarker(Color color) async {
  final key = color.toARGB32();
  final hit = _navArrowCache[key];
  if (hit != null) return hit;

  const double s = 108;
  const double c = s / 2;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);

  // हल्का बाहिरी halo + सेतो डिस्क — जुनसुकै नक्सा/tile रङमा पनि arrow
  // छुट्टै र प्रस्ट देखियोस्।
  canvas.drawCircle(const Offset(c, c), c - 4,
      Paint()..color = color.withValues(alpha: 0.18));
  canvas.drawCircle(const Offset(c, c), c - 14, Paint()..color = Colors.white);

  // उत्तरतिर (माथि) देखाउने chevron — Marker.rotation ले घुमाउँछ, त्यसैले
  // यहाँ सधैँ "माथि" तिर मात्र कोरिन्छ।
  final path = Path()
    ..moveTo(c, 20)
    ..lineTo(c + 15, c + 16)
    ..lineTo(c, c + 6)
    ..lineTo(c - 15, c + 16)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white,
  );

  final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _navArrowCache[key] = bd;
  return bd;
}

final Map<String, BitmapDescriptor> _catPinCache = {};

/// क्याटेगोरी-विशेष आधुनिक map marker: Instagram-रङको gradient teardrop pin +
/// neon glow + भित्र सेतो badge मा सेवाको glyph। `highlighted` भए ठूलो + चम्किलो
/// (छानिएको worker का लागि)। एकपटक बनाएर cache हुन्छ। Marker anchor (0.5, 1.0)।
Future<BitmapDescriptor> categoryPinMarker(String service,
    {bool highlighted = false}) async {
  final key = '${service.toLowerCase()}|$highlighted';
  final hit = _catPinCache[key];
  if (hit != null) return hit;

  final base = serviceMarkerColor(service);
  // हल्का शेड — gradient को माथिल्लो छेउ।
  final light = Color.lerp(base, Colors.white, 0.42)!;
  final dark = Color.lerp(base, Colors.black, 0.18)!;

  final double scale = highlighted ? 1.18 : 1.0;
  final double w = 132 * scale;
  final double h = 168 * scale;
  final double cx = w / 2;
  final double headR = 50 * scale;
  final double centerY = headR + 10 * scale;

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);

  // ग्राउन्ड छाया
  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(cx, h - 8 * scale),
        width: 52 * scale,
        height: 18 * scale),
    Paint()..color = Colors.black.withValues(alpha: 0.18),
  );

  // neon glow ring
  canvas.drawCircle(
    Offset(cx, centerY),
    headR + (highlighted ? 12 : 7) * scale,
    Paint()
      ..color = base.withValues(alpha: highlighted ? 0.55 : 0.38)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale),
  );

  // पिनको पुच्छर
  final tail = Path()
    ..moveTo(cx - 22 * scale, centerY + 26 * scale)
    ..lineTo(cx + 22 * scale, centerY + 26 * scale)
    ..lineTo(cx, h - 6 * scale)
    ..close();
  canvas.drawPath(tail, Paint()..color = dark);

  // gradient टाउको
  final headRect = Rect.fromCircle(center: Offset(cx, centerY), radius: headR);
  canvas.drawCircle(
    Offset(cx, centerY),
    headR,
    Paint()
      ..shader = ui.Gradient.linear(
        headRect.topLeft,
        headRect.bottomRight,
        [light, base, dark],
        [0.0, 0.55, 1.0],
      ),
  );
  canvas.drawCircle(
      Offset(cx, centerY),
      headR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scale
        ..color = Colors.white.withValues(alpha: 0.85));

  // सेतो भित्री badge
  canvas.drawCircle(
      Offset(cx, centerY), headR - 12 * scale, Paint()..color = Colors.white);

  // सेवाको glyph
  final glyph = serviceIconFor(service);
  final tp = TextPainter(textDirection: TextDirection.ltr);
  tp.text = TextSpan(
    text: String.fromCharCode(glyph.codePoint),
    style: TextStyle(
      fontSize: 52 * scale,
      fontFamily: glyph.fontFamily,
      package: glyph.fontPackage,
      color: base,
    ),
  );
  tp.layout();
  tp.paint(canvas, Offset(cx - tp.width / 2, centerY - tp.height / 2));

  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _catPinCache[key] = bd;
  return bd;
}

/// सेवा प्रकारको icon (serviceFilters बाट)।
IconData serviceIconFor(String service) {
  for (final s in serviceFilters) {
    if ((s['name'] as String).toLowerCase() == service.toLowerCase()) {
      return s['icon'] as IconData;
    }
  }
  return Icons.handyman_rounded;
}

/// InDrive-style अनुमानित भाडा — सेवा प्रकार + दूरी अनुसार, रु. ५० मा round।
int estimateFare(String service, double distanceKm) {
  const base = {
    'mechanic': 400,
    'plumber': 500,
    'electrician': 500,
    'carpenter': 600,
    'painter': 800,
    'cleaner': 700,
    'driver': 250,
    'tutor': 500,
  };
  final b = base[service.toLowerCase()] ?? 500;
  final byDist = (distanceKm.clamp(0.0, 40.0) * 35).round();
  final raw = b + byDist;
  return (raw / 50).round() * 50;
}

double _deg2rad(double d) => d * pi / 180.0;

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return earthKm * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Worker को coordinate — Firestore मा `lat`/`lng` छ भने त्यही, नत्र docId बाट
/// deterministic रूपमा origin वरिपरि 0.4–6 किमी भित्र (placeholder)।
({double lat, double lng}) workerPos(
    Map<String, dynamic> data, String id, double originLat, double originLng) {
  final lat = (data['lat'] as num?)?.toDouble();
  final lng = (data['lng'] as num?)?.toDouble();
  if (lat != null && lng != null) return (lat: lat, lng: lng);

  final h = id.hashCode;
  final bearing = (h % 360) * pi / 180.0;
  final distKm = 0.4 + (h.abs() % 560) / 100.0;
  final dLat = (distKm / 111.0) * cos(bearing);
  final dLng = (distKm / (111.0 * cos(_deg2rad(originLat)))) * sin(bearing);
  return (lat: originLat + dLat, lng: originLng + dLng);
}

/// दुई बिन्दुबीचको सडक-मार्ग — Google Directions API अब सिधै यो (Flutter)
/// client बाट कहिल्यै कल हुँदैन। Flutter web बाट सिधै कल गर्दा Google ले
/// CORS header नपठाउने भएकोले browser ले response नै block गर्थ्यो, र त्यो
/// silently सीधा-रेखा fallback मा गिर्थ्यो — देख्दा "route" जस्तै तर वास्तवमा
/// होइन। अब त्यो पूरै Cloud Function (`getRoute`, server-side — CORS ले
/// नछुने ठाउँ) मा सारिएको छ, जसले Directions/OSRM दुवै आफैं कोसिस गरेर
/// polyline+दूरी+समय फर्काउँछ, र API key browser को network tab मा कहिल्यै
/// नदेखियोस्। दुवै असफल भए यो function null फर्काउँछ — caller ले त्यसलाई
/// "route unavailable" भनेर देखाउनुपर्छ, कहिल्यै सीधा-रेखालाई साँचो route
/// भनेर देखाउनु हुँदैन (त्यसैले यहाँ कुनै haversine/सीधा-रेखा fallback छैन)।
/// Android/web दुवैले उही function, उही जवाफ पाउँछन् — दुई फरक बाटो होइन।
typedef RoadRoute = ({List<LatLng> points, double km, int minutes, bool real});

final FirebaseFunctions _functions = FirebaseFunctions.instance;

Future<RoadRoute?> fetchRoadRoute(LatLng a, LatLng b) async {
  try {
    final callable = _functions.httpsCallable(
      'getRoute',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'originLat': a.latitude,
      'originLng': a.longitude,
      'destLat': b.latitude,
      'destLng': b.longitude,
    });
    final data = result.data;
    final encoded = (data['polyline'] as String?) ?? '';
    final points = _decodePolyline(encoded);
    // ROUTE-DEBUG PROBE — polyline mismatch (web straight line) कारण पत्ता लगाउन।
    // ignore: avoid_print
    print('[ROUTE-DEBUG] platform=${kIsWeb ? "web" : "native"} '
        'encodedLen=${encoded.length} decodedCount=${points.length} '
        'first3=${points.take(3).map((p) => '(${p.latitude},${p.longitude})').join(' | ')} '
        'last3=${points.skip((points.length - 3).clamp(0, points.length)).map((p) => '(${p.latitude},${p.longitude})').join(' | ')}');
    // दुई-बिन्दुको "route" ले पनि सीधा रेखा नै बनाउँछ — त्यो पनि साँचो
    // route जस्तै कहिल्यै नदेखियोस् भनेर कम्तिमा ३ बिन्दु अनिवार्य।
    if (points.length < 3) return null;
    return (
      points: points,
      km: (data['km'] as num?)?.toDouble() ?? 0,
      minutes: (data['minutes'] as num?)?.toInt() ?? 0,
      real: (data['real'] as bool?) ?? true,
    );
  } catch (_) {
    // Cloud Function नै असफल (network/quota/दुवै route स्रोत असफल) —
    // caller ले "route unavailable" देखाउने, कुनै fallback geometry होइन।
    return null;
  }
}

/// Google को Encoded Polyline Algorithm Format decoder — Directions API ले
/// `overview_polyline.points` मा compact string रूपमा दिने मार्ग-बिन्दुहरू
/// फिर्ता LatLng list मा फर्काउने। (कुनै थप package नचाहिने साना ~35 लाइनको
/// standard algorithm।)
List<LatLng> _decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;

  // एउटा VLQ-जस्तै 5-bit-group chain लाई शुद्ध अंकगणित (+, -, *, ~/) बाट
  // पढ्ने — कुनै bitwise operator (<<, >>, |, ~) होइन। किन: dart2js (web) मा
  // `int` JS double मा compile हुन्छ, र bitwise operator हरू 32-bit JS
  // सेमान्टिक्समा काम गर्छन् — जुन Dart VM (Android) कै साँचो 64-bit int
  // व्यवहारभन्दा फरक हुन सक्छ। ठ्याक्कै यही भिन्नताले पहिलो बिन्दुपछिका सबै
  // बिन्दु web मा बिग्रिने (lat=90 मा clamp हुने, lng जथाभावी) बग दिएको थियो
  // — Android र web ले ठ्याक्कै उही encoded string बाट फरक-फरक संख्या
  // निकालेका थिए। शुद्ध अंकगणितले दुवैतिर एउटै नतिजा दिन्छ।
  int readSignedDelta() {
    var result = 0;
    var factor = 1;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result += (b % 32) * factor; // (b & 0x1f) कै अंकगणितीय बराबर
      factor *= 32;
    } while (b >= 0x20);
    // zigzag decode: सम भए result/2, बिजोर भए -(result+1)/2 — यो
    // `(result & 1) != 0 ? ~(result >> 1) : (result >> 1)` कै अंकगणितीय
    // बराबर हो, कुनै bitwise op बिना।
    return result.isOdd ? -((result + 1) ~/ 2) : (result ~/ 2);
  }

  while (index < encoded.length) {
    lat += readSignedDelta();
    lng += readSignedDelta();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// InDrive-शैलीको route polyline — कालो, solid (OSRM बाट real road route
/// भेटिएन भने dashed देखिन्छ ताकि "अनुमानित" हो भनेर छुट्टिओस्)।
Polyline routePolyline(String id, RoadRoute route) => Polyline(
      polylineId: PolylineId(id),
      points: route.points,
      color: const Color(0xFF111111),
      width: 5,
      patterns:
          route.real ? const [] : [PatternItem.dash(24), PatternItem.gap(14)],
    );

/// झन्डा-पिनको SVG-सटीक ज्यामिति — दिइएको Leaflet SVG (viewBox 0 0 96 200,
/// display 48×100) सँग ठ्याक्कै मिल्ने "display space" (48×100) मा। यही
/// coordinate system दुवैतिर प्रयोग हुन्छ: [destinationFlagPin] ले पोल +
/// आधार-थोप्लो (स्थिर marker bitmap) कोर्छ, अनि screens/request_tracking_screen.dart
/// को waving-flag overlay ले झन्डा + चन्द्रमा + तारा (animated) कोर्छ — दुवै
/// उस्तै anchor/coordinate प्रयोग गर्दा एक-अर्कामा ठ्याक्कै पर्छन्।
class FlagPinGeometry {
  FlagPinGeometry._();

  static const double displayW = 48;
  // झन्डा (0-52) + पोल (52-71) + थोप्लो — कुल अग्लाइ।
  static const double displayH = 79;

  /// आधार-थोप्लो ठ्याक्कै GPS coordinate मा — पोल छोटो भएपछि यहीँ सर्‍यो।
  static const Offset anchor = dotCenter;

  /// `Marker.anchor` का लागि (0..1) fraction — `destinationFlagPin()` सँगै
  /// प्रयोग गर्ने।
  static Offset get markerAnchorFraction =>
      Offset(anchor.dx / displayW, anchor.dy / displayH);

  // पोल झन्डाको सीधा किनारा (flagOrigin.dx = 6) मै केन्द्रित — बगलमा होइन,
  // ठ्याक्कै झन्डाको बीचको भागमुनि। लम्बाइ 16 बाट 19 पुर्‍याइयो।
  static const double poleW = 2.5;
  static const double poleX =
      6 - poleW / 2; // = 4.75, flagOrigin.dx मा केन्द्रित
  static const double poleY = 52;
  static const double poleH = 19;
  static const double poleRadius = 1.25;

  // थोप्लो पनि पोलकै केन्द्र (x=6) मा — ठ्याक्कै पोलको फेदमुनि, बगलमा होइन।
  static const Offset dotCenter = Offset(6, 69);
  static const double dotRadius = 3;
  static const double dotBorder = 1.25;

  /// झन्डा समूहको उत्पत्ति (सिरानमा, पोल त्यसको ठ्याक्कै तल टाँसिन्छ)।
  static const Offset flagOrigin = Offset(6, 0);
  static const double flagW = 41;
  static const double flagH = 52;
  static const double flagStrokeWidth = 1.75;

  static const flagGradient = [Color(0xFF3A3A3A), Color(0xFF050505)];
  static const rimGradient = [Color(0xFF7B2FF7), Color(0xFFF107A3)];

  static Path flagPath() => Path()
    ..moveTo(flagOrigin.dx + 0, flagOrigin.dy + 0)
    ..lineTo(flagOrigin.dx + 30, flagOrigin.dy + 18)
    ..lineTo(flagOrigin.dx + 11, flagOrigin.dy + 18)
    ..lineTo(flagOrigin.dx + 41, flagOrigin.dy + 52)
    ..lineTo(flagOrigin.dx + 0, flagOrigin.dy + 52)
    ..close();

  static Path moonPath() {
    const o = flagOrigin;
    return Path()
      ..moveTo(o.dx + 5, o.dy + 10)
      ..arcToPoint(Offset(o.dx + 12, o.dy + 10),
          radius: const Radius.circular(3.5), clockwise: false)
      ..arcToPoint(Offset(o.dx + 5, o.dy + 10),
          radius: const Radius.elliptical(3.5, 1.5), clockwise: true)
      ..close();
  }

  static const List<Offset> _starPts = [
    Offset(18.5, 38),
    Offset(16.38, 38.905),
    Offset(17.765, 40.75),
    Offset(15.475, 40.475),
    Offset(15.75, 42.765),
    Offset(13.905, 41.38),
    Offset(13, 43.5),
    Offset(12.095, 41.38),
    Offset(10.25, 42.765),
    Offset(10.525, 40.475),
    Offset(8.235, 40.75),
    Offset(9.62, 38.905),
    Offset(7.5, 38),
    Offset(9.62, 37.095),
    Offset(8.235, 35.25),
    Offset(10.525, 35.525),
    Offset(10.25, 33.235),
    Offset(12.095, 34.62),
    Offset(13, 32.5),
    Offset(13.905, 34.62),
    Offset(15.75, 33.235),
    Offset(15.475, 35.525),
    Offset(17.765, 35.25),
    Offset(16.38, 37.095),
  ];

  static Path starPath() {
    const o = flagOrigin;
    final p = Path()..moveTo(o.dx + _starPts[0].dx, o.dy + _starPts[0].dy);
    for (final pt in _starPts.skip(1)) {
      p.lineTo(o.dx + pt.dx, o.dy + pt.dy);
    }
    return p..close();
  }
}

BitmapDescriptor? _flagPinCache;

/// स्थिर काम/गन्तव्य स्थानको marker — पोल + झन्डा (चन्द्रमा+तारा सहित) +
/// आधार-थोप्लो **सबै एउटै static bitmap भित्र**। Uber/InDrive को pin जस्तै
/// — यो एउटै native `Marker` भएकाले नक्सा pan/zoom/rotate गर्दा यो सधैँ
/// नक्साकै अरू सबैसँग ठ्याक्कै सँगसँगै सर्छ, छुट्टै Flutter overlay भएको
/// भए जस्तो कहिल्यै लड्खडाउँदैन वा भाग-भाग देखिँदैन। (पहिले झन्डालाई अलग
/// एनिमेटेड overlay बनाइएको थियो — त्यसले pan गर्दा async screen-coordinate
/// lag का कारण पोल र झन्डा एक-अर्कादेखि छुट्टिएको देखिन्थ्यो; अब हटाइयो।)
/// Marker मा `anchor: FlagPinGeometry.markerAnchorFraction` प्रयोग गर्नुहोस्।
Future<BitmapDescriptor> destinationFlagPin() async {
  final cached = _flagPinCache;
  if (cached != null) return cached;

  const double scale = 4.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(scale);

  // पोल
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(FlagPinGeometry.poleX, FlagPinGeometry.poleY,
          FlagPinGeometry.poleW, FlagPinGeometry.poleH),
      const Radius.circular(FlagPinGeometry.poleRadius),
    ),
    Paint()..color = const Color(0xFF111111),
  );

  // झन्डा + चन्द्रमा + तारा — स्थिर (कुनै wave transform छैन)
  final flagPath = FlagPinGeometry.flagPath();
  final flagRect = flagPath.getBounds();
  canvas.drawPath(
    flagPath,
    Paint()
      ..shader = ui.Gradient.linear(
          flagRect.topLeft, flagRect.bottomRight, FlagPinGeometry.flagGradient),
  );
  canvas.drawPath(
    flagPath,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = FlagPinGeometry.flagStrokeWidth
      ..strokeJoin = StrokeJoin.round
      ..shader = ui.Gradient.linear(
          flagRect.topLeft, flagRect.bottomRight, FlagPinGeometry.rimGradient),
  );
  canvas.drawPath(FlagPinGeometry.moonPath(), Paint()..color = Colors.white);
  canvas.drawPath(FlagPinGeometry.starPath(), Paint()..color = Colors.white);

  // आधार-थोप्लो
  canvas.drawCircle(
      FlagPinGeometry.dotCenter,
      FlagPinGeometry.dotRadius + FlagPinGeometry.dotBorder,
      Paint()..color = Colors.white);
  canvas.drawCircle(FlagPinGeometry.dotCenter, FlagPinGeometry.dotRadius,
      Paint()..color = const Color(0xFF111111));

  final img = await rec.endRecording().toImage(
      (FlagPinGeometry.displayW * scale).ceil(),
      (FlagPinGeometry.displayH * scale).ceil());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  // width/height दिएर Maps लाई bitmap ठ्याक्कै display size मा (48×displayH
  // logical px) देखाउन भन्ने — नत्र 4× supersampled raw pixel साइजमै (4 गुणा
  // ठूलो) देखिन्थ्यो।
  final bd = BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: FlagPinGeometry.displayW,
    height: FlagPinGeometry.displayH,
  );
  _flagPinCache = bd;
  return bd;
}

final Map<int, List<BitmapDescriptor>> _waveFramesCache = {};

/// "advanced" radar-wave को हरेक फ्रेम आफैं एउटा native Marker bitmap हो —
/// Flutter overlay/`getScreenCoordinate` ट्र्याकिङ होइन। यसलाई झन्डाकै
/// ठ्याक्कै उही `position` (lat/lng) मा अर्को Marker (`anchor: Offset(0.5,
/// 0.5)`) को रूपमा राख्नुहोस्: दुवै marker ठ्याक्कै एउटै coordinate मा
/// भएकाले Google Maps आफैंले तिनलाई एउटै क्यामेरा transform बाट सँगसँगै
/// कोर्छ — zoom/pan मा झन्डाको केन्द्रबिन्दुबाट यो कहिल्यै विचलित हुँदैन,
/// किनकि यहाँ कुनै async screen-position पछ्याउने कोड नै छैन। एनिमेसनको
/// लागि frame-index लाई timer/AnimationController ले बदलिरहनुपर्छ (bitmap
/// स्वयं static हो, हरेक frame फरक स्थिर तस्बिर मात्र हो)।
Future<List<BitmapDescriptor>> radarWaveFrames(Color color,
    {int frames = 30}) async {
  final key = color.toARGB32() * 1000 + frames;
  final hit = _waveFramesCache[key];
  if (hit != null) return hit;

  const double scale = 3.0;
  const double size = 176;
  const double c = size / 2;
  // पानीमा ढुङ्गा हालेपछि निस्कने ripple जस्तै — शुद्ध गोलो रेखा (कुनै भरिएको
  // ग्लो/ब्लब छैन): एउटा पातलो घेरा सानो/गाढा भएर सुरु हुन्छ, त्यही स्थिरगतिमा
  // बाहिरतिर फैलिँदै जान्छ र किनारमा पुग्दा पूर्ण रूपमा हराउँछ (fade-out)।
  // ३ घेराहरू १/३ फरकले सुरु हुन्छन् ताकि एउटा हराउँदा अर्को सुरु भइरहेको देखिन्छ
  // — निरन्तर, स्मूथ pulsation (राडार/मुटुको धड्कन जस्तै)।
  const int ringCount = 3;
  const double minRadius = 8;
  const double maxRadius = 62;
  const double maxAlpha = 0.85;
  final out = <BitmapDescriptor>[];
  for (var f = 0; f < frames; f++) {
    final t = f / frames;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    for (var i = 0; i < ringCount; i++) {
      final p = (t + i / ringCount) % 1.0;
      final radius = minRadius + p * (maxRadius - minRadius);
      final fade = (1 - p).clamp(0.0, 1.0);
      canvas.drawCircle(
        const Offset(c, c),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = color.withValues(alpha: maxAlpha * fade),
      );
    }
    final img = await rec
        .endRecording()
        .toImage((size * scale).ceil(), (size * scale).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    out.add(BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: size, height: size));
  }
  _waveFramesCache[key] = out;
  return out;
}

/// inDrive-style offer/bidding sheet देखाउने।
Future<void> showOfferSheet(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String workerId,
  required double distanceKm,
  required double employerLat,
  required double employerLng,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OfferSheet(
      data: data,
      workerId: workerId,
      distanceKm: distanceKm,
      employerLat: employerLat,
      employerLng: employerLng,
    ),
  );
}

class OfferSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String workerId;
  final double distanceKm;
  // ग्राहकको हालको स्थान — worker ले offer स्वीकार गरेपछि देखिने route-map
  // (JobRouteScreen/RequestTrackingScreen) लाई यही coordinate चाहिन्छ। पहिले
  // यहाँ नसारिएकोले त्यो नक्सा कहिल्यै नखुल्ने बग थियो — अब हरेक offer सँगै
  // सधैँ साथमा जान्छ।
  final double employerLat;
  final double employerLng;

  const OfferSheet({
    super.key,
    required this.data,
    required this.workerId,
    required this.distanceKm,
    required this.employerLat,
    required this.employerLng,
  });

  @override
  State<OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<OfferSheet> {
  final _detailsCtrl = TextEditingController();
  late int _asking;
  late int _amount;
  bool _sending = false;

  static const int _step = 50;

  @override
  void initState() {
    super.initState();
    final digits = (widget.data['price'] ?? 'Rs. 500')
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    _asking = int.tryParse(digits) ?? 500;
    if (_asking < _step) _asking = 500;
    _amount = _asking;
  }

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  void _setAmount(int v) => setState(() => _amount = v.clamp(_step, 1000000));

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      // users/{uid} बाट साँचो नाम/फोन — Auth कै email/phoneNumber भन्दा
      // भरपर्दो (इमेलबाट दर्ता भएकाको हकमा Auth phoneNumber सधैँ खाली हुन्छ,
      // जुन "Call गर्दा नम्बर भेटिएन" गुनासोको मूल कारण थियो)।
      var employerName = user?.displayName ?? user?.email ?? 'Employer';
      var employerPhone = user?.phoneNumber ?? '';
      try {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .get();
        final n = (u.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) employerName = n;
        final p = (u.data()?['phone'] ?? '').toString().trim();
        if (p.isNotEmpty) employerPhone = p;
      } catch (_) {}
      await FirebaseFirestore.instance.collection('serviceRequests').add({
        'workerUid': widget.data['uid'] ?? widget.workerId,
        'employerUid': user?.uid ?? '',
        'employerName': employerName,
        'employerPhone': employerPhone,
        'workerName': widget.data['name'] ?? '',
        'service': widget.data['service'] ?? '',
        'details': _detailsCtrl.text.trim(),
        'proposedPrice': _amount,
        'status': 'pending_worker',
        'createdAt': FieldValue.serverTimestamp(),
        'distanceKm': double.parse(widget.distanceKm.toStringAsFixed(2)),
        // स्थिर काम-स्थल coordinate — accept भएपछि दुवैतिर route-map (सडक
        // मार्ग + दूरी/समय) यसैबाट बन्छ।
        'employerLat': widget.employerLat,
        'employerLng': widget.employerLng,
      });
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(S.offerSentTitle),
          content: Text(S.offerSentBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text(S.ok)),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.errorWord}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (widget.data['name'] ?? '').toString();
    final service = (widget.data['service'] ?? '').toString();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget quickChip(String label, int value) => GestureDetector(
          onTap: () => _setAmount(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const LimeIconBadge(Icons.person, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? '—' : name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                          '${S.serviceName(service)}  ·  ${S.distanceLabel(widget.distanceKm)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
                '${S.askingPrice}: Rs. $_asking   ·   ${S.suggestedFare}: Rs. ${estimateFare(service, widget.distanceKm)}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(S.yourOffer,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PriceStepButton(
                    icon: Icons.remove_rounded,
                    onTap: () => _setAmount(_amount - _step)),
                const SizedBox(width: 18),
                Column(
                  children: [
                    const Text('Rs.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('$_amount',
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(width: 18),
                PriceStepButton(
                    icon: Icons.add_rounded,
                    onTap: () => _setAmount(_amount + _step)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                quickChip('−20%', (_asking * 0.8).round()),
                const SizedBox(width: 8),
                quickChip(S.askingPrice, _asking),
                const SizedBox(width: 8),
                quickChip('+10%', (_asking * 1.1).round()),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _detailsCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: S.describeTask,
                hintText: S.describeTaskHint,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: S.sendOffer,
              icon: Icons.send_rounded,
              loading: _sending,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class PriceStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const PriceStepButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: theme.dividerColor),
        ),
        child: Icon(icon, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

/// कुनै पनि पिन/मार्करको फेदमाथि धड्किने (expanding + fading) घेराहरू —
/// InDrive/Uber शैलीको "advanced" radar-wave। शुद्ध animated overlay हो, पिनको
/// static bitmap भित्र बेकिएको छैन — त्यसैले पिन आफैं map pan/zoom मा कहिल्यै
/// लाग्दैन (त्यो अलग गारेन्टी हो); यो घेरा भने पिनको screen-position पछ्याउँदै
/// हल्का shimmer मात्र थप्छ।
class PulseRings extends StatelessWidget {
  final Animation<double> t;
  final Color color;
  const PulseRings({super.key, required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 140,
        height: 140,
        child: AnimatedBuilder(
          animation: t,
          builder: (_, __) =>
              CustomPaint(painter: _RingPainter(t.value, color)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  final Color color;
  _RingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final radius = 16 + p * 52;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: (1 - p) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}
