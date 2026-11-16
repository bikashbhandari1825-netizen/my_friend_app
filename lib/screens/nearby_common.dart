// screens/nearby_common.dart
// Nearby list र Nearby map दुवैले प्रयोग गर्ने साझा: geo helper + offer/bidding sheet।
import 'dart:async';
import 'dart:math';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../app_globals.dart' show createNotificationForUser;
import '../config/app_config.dart' show FareMatrixConfig;
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/spring_tap.dart';
import '../widgets/worker_avatar.dart';

// काठमाडौँ केन्द्र — location नपाउँदा fallback।
const double fallbackLat = 27.7172;
const double fallbackLng = 85.3240;

/// "KaamMitra 2050" dark-glass Google Maps theme — एपभरिको हरेक `GoogleMap`
/// ले यही एउटै style प्रयोग गर्छ (home/service-map/route-view)। Google Maps
/// tile स्वयं server-rendered हुने भएकोले यसलाई literally `BackdropFilter`
/// ले धमिल्याउन मिल्दैन।
///
/// inDrive कै dark-mode screenshot लाई सिधै reference मानेर बनाइएको — एउटै
/// गाढा नेभी-निलो hue भरि (पहिलेको ग्रे/violet-accent दृष्टिकोण पूर्णतया
/// छोडियो): base/water सबैभन्दा गाढा नेभी, building footprint
/// (landscape.man_made) + generic POI अलि हल्का/बढी saturated नेभी block
/// भरण सहित (खुट्टा-खुट्टा छुट्याउन सकिने गरी, तर कालो होइन — गाढा नेभी
/// नै outline), सडक भने clearly उज्यालो slate-blue (हाइवे झन् उज्यालो, hierarchy
/// देखियोस् भनेर), र label सबै सेतो/crisp — ठ्याक्कै inDrive को screenshot
/// मा जस्तै। केवल Google का आफ्नै default POI icon (gym को दौडने-मान्छे,
/// restaurant को काँटा-चम्चा आदि — हाम्रो marker/pin होइनन्) र transit icon
/// मात्र लुकाइएको, जसले worker/destination pin खोज्न गाह्रो बनाउँथ्यो।
///
/// Building contrast — magenta/lime diagnostic ले styling साँच्चै लागू
/// भइरहेको पुष्टि गरेपछि (feature-type match नै फेल भएको/data नभएको होइन
/// रहेछ) पहिले fill मात्र उज्यालो पारिएको थियो (#5577b3), तर घना क्षेत्रमा
/// building polygon नै झण्डै पूरै स्क्रिन ओगट्छ — बाँकी खुला "base" जमिन
/// ज्यादै कम देखिन्छ, त्यसैले fill-vs-base भन्दा छेउछाउका building बीचको
/// stroke (gap/mortar line) नै असली "block" आकार छुट्याउने कुरा रहेछ।
///
/// `adb exec-out screencap` + pixel-level inspection (user लाई फेरि-फेरि
/// नसोधी फोनको real screen आफैं पढेर verify गरियो) ले यो थप पुष्टि
/// गर्‍यो: यो विशेष test क्षेत्र/zoom मा `landscape.man_made` fill
/// (#6f8fc9) ले नै झन्डै पूरै screen (non-road भाग) ओगटेको छ — एउटै ठूलो,
/// नभाँचिएको area polygon जस्तो। weight 6 को bright-yellow stroke
/// diagnostic ले पनि (648,000 pixel भर scan गर्दा) एउटै पनि yellow pixel
/// नदेखाएकोले — यो कुनै रङ/stroke-weight छनोटको गल्ती होइन, बरु: या त यो
/// दृश्यक्षेत्रभित्र साँच्चै एउटै मात्र polygon छ (भित्री building-to-building
/// छेउ नै छैन, जोड्ने कुरा नै छैन), वा Android Maps SDK ले यो featureType
/// को लागि geometry.stroke honour नै गर्दैन। दुवै अवस्थामा, Google Maps को
/// सार्वजनिक JSON styling API बाट inDrive-जस्तो individually-outlined
/// प्रति-घर building block यस ठाउँमा सम्भव छैन — यो data/platform सीमा हो,
/// अब पनि रङ बदलेर ठीक हुने होइन। stroke चाहिं राम्रो उज्यालो राखिएको छ
/// (कतै साँचो polygon-boundary भेटिए काम लागोस्)।
const String kCleanMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1f2b42"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#0e1420"}]},
  {"featureType": "administrative", "elementType": "geometry.stroke", "stylers": [{"color": "#3c4a68", "weight": 1}]},
  {"featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{"color": "#c9d3ea"}]},
  {"featureType": "administrative.land_parcel", "elementType": "geometry.stroke", "stylers": [{"color": "#30405f", "weight": 0.6}]},
  {"featureType": "administrative.land_parcel", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "administrative.neighborhood", "stylers": [{"visibility": "off"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.fill", "stylers": [{"color": "#6f8fc9"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.stroke", "stylers": [{"color": "#c9d6ef", "weight": 1.8}]},
  {"featureType": "landscape.natural", "elementType": "geometry", "stylers": [{"color": "#223024"}]},
  {"featureType": "poi", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "labels.text", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "geometry.fill", "stylers": [{"color": "#405e94"}]},
  {"featureType": "poi", "elementType": "geometry.stroke", "stylers": [{"color": "#c9d6ef", "weight": 1.2}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1f3b2e"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#7f93b8"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#44536f"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.local", "elementType": "geometry", "stylers": [{"color": "#6f84a8"}]},
  {"featureType": "road.local", "elementType": "geometry.stroke", "stylers": [{"color": "#3c4a68"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#8fa3c7"}]},
  {"featureType": "road.arterial", "elementType": "geometry.stroke", "stylers": [{"color": "#44536f"}]},
  {"featureType": "road.arterial", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#a8bbe0"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#2a3550"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.highway", "elementType": "labels.text.stroke", "stylers": [{"color": "#121a2b"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry", "stylers": [{"color": "#c3d2f0"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry.stroke", "stylers": [{"color": "#2a3550"}]},
  {"featureType": "transit", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "elementType": "labels.text", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit.line", "elementType": "geometry", "stylers": [{"color": "#4b5c80"}]},
  {"featureType": "transit.station", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#141d2d"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]}
]
''';

/// Google Cloud-based Maps styling Map ID — "landscape.man_made" JSON
/// styling (माथि `kCleanMapStyle`, अझै fallback/reference को लागि राखिएको)
/// ले यो app को test location मा building footprint लाई एउटै ठूलो, नभाँचिएको
/// polygon जस्तो मात्र देखाउँथ्यो (adb screencap बाट pixel-level verify
/// गरिएको — कुनै रङ/stroke छनोटको गल्ती थिएन)। Cloud Console मा अलग
/// "Buildings" layer भएको यो Map ID ले प्रति-building footprint देखाउन सक्ने
/// आशा छ। यो set भएको GoogleMap मा inline JSON `style` native SDK ले उपेक्षा
/// गर्छ — त्यसैले भविष्यको रङ/theme परिवर्तन अब यहाँ होइन, Cloud Console को
/// Map Styles editor मा गर्नुपर्छ।
/// पहिलेको Map ID (12845d467983d181e5fbb833) Raster type रहेछ — Raster Map
/// ID मा custom cloud style कहिल्यै लागू हुँदैन (कुनै error/warning बिना
/// silently उपेक्षा गर्छ, ठ्याक्कै "dark style देखिँदैन" समस्याको जड)।
/// यो नयाँ Map ID Vector type हो — "kaammitra dark map" (515a0d3afd188
/// 8955bd5b31c Style ID) यसैमा associate/publish गरिएको छ।
const String kCloudMapId = '12845d467983d181f1011516';

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

/// सेवा प्रकारको वास्तविक तस्बिर asset path। Bike/Car/Auto (`serviceFilters`
/// मा तिनको प्रविष्टि छैन — home screen मा एउटै 'Driver' tile कायमै राख्नु हो)
/// ले home screen कै उही neon illustration (`home_bike.png`/`home_car.png`/
/// `home_auto.png`) प्रयोग गर्छन्।
String serviceImageFor(String service) {
  final lower = service.toLowerCase();
  // Home screen कै उस्तै neon illustration (home_screen.dart::
  // _HomeQuickService) — पहिले यहाँ छुट्टै, पुरानो सेतो स्टुडियो-फोटो
  // (bike_ride.png/car_ride.png) थियो, र Auto को त आफ्नै तस्बिर नै
  // थिएन (generic fallback path नभेटिएर bare icon मा झर्थ्यो) — अब
  // तीनै vehicle service मा home screen सँगै ठ्याक्कै मिल्ने एउटै asset।
  if (lower == 'bike') return 'assets/images/home_bike.png';
  if (lower == 'car') return 'assets/images/home_car.png';
  if (lower == 'auto') return 'assets/images/home_auto.png';
  // "Handyman" आफैं कुनै छुट्टै trade होइन (Plumber/Electrician/Mechanic/...
  // छान्ने category-selection tile मात्र, `HandymanCategoriesScreen`) —
  // आफ्नै dedicated illustration कहिल्यै बनेको छैन, त्यसैले generic
  // `Icons.handyman_rounded` मा fallback नहोस् भनेर mechanic कै तस्बिर
  // (सबैभन्दा प्रतिनिधि trade) पुनःप्रयोग गर्ने।
  if (lower == 'handyman') return 'assets/images/services/mechanic.png';
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
    case 'bike':
      return BitmapDescriptor.hueOrange;
    case 'car':
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
      return AppColors.kmPurple;
    case 'cleaner':
      return const Color(0xFF16B8C4); // cyan
    case 'driver':
      return const Color(0xFF3B82F6); // blue
    case 'bike':
      return const Color(0xFF00BCD4); // teal/cyan — दुई-पांग्रे
    case 'car':
      return const Color(0xFF3B82F6); // blue — car/taxi
    case 'tutor':
      return const Color(0xFFC13584); // magenta
    case 'auto':
      return const Color(0xFF2ED573); // green — अटो रिक्सा
    case 'hotel booking':
      return AppColors.kmPurple;
    default:
      return AppColors.kmPink;
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
  img.dispose();
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
  img.dispose();
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _dotMarkerCache[key] = bd;
  return bd;
}

/// दुई बिन्दुबीचको bearing — उत्तरबाट clockwise डिग्रीमा (0–360)। नयाँ GPS
/// बिन्दु आउनेबित्तिकै [travelModeMarker] कुन दिशामा फर्किनुपर्छ भनेर
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

/// [from] देखि [to] (डिग्री, 0-360 मानिन्छ तर जुनसुकै मान चल्छ) सम्मको
/// सबैभन्दा छोटो कोणीय दूरी — ऋणात्मक पनि हुन सक्छ (वामावर्त)। उदाहरण:
/// 350→10 ले +20 दिन्छ (10° दायाँ, 340° घुमेर गएको जस्तो होइन)। route_map_
/// view.dart ले गाडी/बाइकको live-marker बेअरिङ एनिमेट गर्दा (snap/jerk
/// बिना, सधैँ छोटो बाटोबाट मात्र घुम्ने) प्रयोग गर्छ।
double shortestAngleDelta(double from, double to) {
  var delta = (to - from) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}

final Map<String, BitmapDescriptor> _travelMarkerCache = {};

/// चयन गरिएको यात्रा-मोड अनुसार फरक-फरक, माथिबाट-हेर्दाको (top-down) साँच्चीकै
/// सवारी-साधन/पैदल-यात्री आकृति — accept भएको काममा worker/employer
/// गन्तव्यतिर चलिरहँदा नक्सामा देखिने live-location marker। पहिले यहाँ
/// जुनसुकै मोडमा पनि एउटै जेनेरिक chevron/तीर (टाढाबाट "रातो V-आकार" जस्तो
/// देखिने साधारण pointer) देखिन्थ्यो, त्यसपछि एक अवधिसम्म gradient halo +
/// सेतो डिस्क भित्र देखिन्थ्यो (cartoonish गोलाकार फ्रेम) — अब InDrive/Bolt
/// जस्तै त्यो घेरा/डिस्क पूर्ण रूपमा हटाइएको छ: कार (driving), बाइक
/// (bicycling), वा पैदल-यात्री (walking) को असली, पारदर्शी-पृष्ठभूमि तस्बिर
/// (कुनै circle/background नथपी, ठ्याक्कै raw PNG) मात्र कोरिन्छ, र
/// [TravelModeChips] बाट मोड बदलिनासाथ (Firestore मार्फत अर्को पक्षमा पनि)
/// यही marker आइकन तुरुन्तै बदलिन्छ। उत्तरतिर (माथि, rotation = 0) देखाउने
/// गरी drawn हुन्छ; caller ले `Marker(rotation: bearingDeg, flat: true, ...)`
/// राखेर हालको दिशामा घुमाउँछ — त्यसैले यहाँ rotation logic छैन, स्थिर आकार
/// मात्र, मोड-अनुसार एकपटक मात्र बनाएर cache हुन्छ।
/// `iconOverride` — Auto-Rickshaw जस्तो `TravelMode` मा नभएको (routing मा
/// Auto पनि driving नै मानिन्छ, हेर्नुहोस् `travelModeForVehicle`) छुट्टै
/// आइकन देखाउन चाहिँदा, caller ले सिधै asset path दिन सक्छ — दिए सोही
/// (मोड जे भए पनि) बाक्छ।
Future<BitmapDescriptor> travelModeMarker(TravelMode mode,
    {String? iconOverride}) async {
  final cacheKey = iconOverride ?? mode.name;
  final hit = _travelMarkerCache[cacheKey];
  if (hit != null) return hit;

  const double s = 108;
  const double c = s / 2;

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);

  final assetPath = iconOverride ??
      switch (mode) {
        TravelMode.driving => 'assets/images/car_top.png',
        TravelMode.bicycling => 'assets/images/bike_top.png',
        TravelMode.walking => 'assets/images/walking_top.png',
      };
  await _paintAssetImage(canvas, c, assetPath, 92);

  final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _travelMarkerCache[cacheKey] = bd;
  return bd;
}

final Map<String, BitmapDescriptor> _rotatedTravelMarkerCache = {};

/// Flutter Web Marker-Rotation Workaround — `google_maps_flutter_web` (यो
/// प्रोजेक्टको vendored `third_party/google_maps_flutter_web` कै
/// `convert.dart` हेर्नुहोस्) ले साधारण (गैर-Advanced) marker मा
/// `Marker.rotation` लाई Android/iOS जस्तै लागू गर्दैन — त्यसैले web मा
/// बाइक/कार आइकन सधैँ उत्तरतिर (सीधा माथि) नै अडिग देखिन्थ्यो, बाटो
/// जतिसुकै मोडिए/तेर्सिए पनि (जस्तै Sportowa जस्तो कर्णमुखी सडकमा पनि)।
/// native मा चाहिं `flat:true, rotation:_bearing` ले नै ठीकसँग (GPU-side,
/// सस्तो) घुमाउँछ — त्यसैले त्यहाँ यो function चाहिँदैन। Web-मात्र यहाँ
/// आइकन आफैं (canvas मै) पहिल्यै घुमाएर bake गरिन्छ, अनि caller ले
/// `Marker(rotation: 0, icon: <यही नतिजा>, ...)` राख्छ। हरेक डिग्रीमा
/// नभई 5° bucket मा round गरेर cache हुन्छ — नत्र bearing-animation कै
/// हरेक frame मा नयाँ canvas rasterize हुँदा web मा जाँकिने (jank) थियो।
Future<BitmapDescriptor> travelModeMarkerRotated(
    TravelMode mode, double rotationDeg,
    {String? iconOverride}) async {
  final bucket = (((rotationDeg % 360) + 360) % 360 / 5).round() * 5 % 360;
  final key = '${iconOverride ?? mode.name}|$bucket';
  final hit = _rotatedTravelMarkerCache[key];
  if (hit != null) return hit;

  const double s = 108;
  const double c = s / 2;

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.translate(c, c);
  canvas.rotate(bucket * pi / 180);
  canvas.translate(-c, -c);

  final assetPath = iconOverride ??
      switch (mode) {
        TravelMode.driving => 'assets/images/car_top.png',
        TravelMode.bicycling => 'assets/images/bike_top.png',
        TravelMode.walking => 'assets/images/walking_top.png',
      };
  await _paintAssetImage(canvas, c, assetPath, 92);

  final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _rotatedTravelMarkerCache[key] = bd;
  return bd;
}

final Map<String, ui.Image> _assetImageCache = {};

/// `assets/images/car_top.png`/`bike_top.png`/`walking_top.png`
/// (माथिबाट-हेर्दाको साँच्चीकै आर्टवर्क/तस्बिर, owner ले दिएको फोटोबाट
/// halo/checkerboard हटाई सवारी-साधन/व्यक्ति मात्र काटिएको) एकपटक मात्र
/// decode गरेर cache हुन्छ — हरेक marker रिफ्रेसमा फेरि disk/asset बाट
/// पढ्नु नपरोस्।
Future<ui.Image> _loadAssetImage(String assetPath) async {
  final hit = _assetImageCache[assetPath];
  if (hit != null) return hit;
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  _assetImageCache[assetPath] = frame.image;
  return frame.image;
}

/// माथिबाट हेर्दाको साँच्चीकै सवारी-साधन तस्बिर (हातले कोरिएको आकृति होइन)
/// — halo डिस्क भित्रै aspect-ratio कायम राखी केन्द्रित गरेर राखिन्छ,
/// ठ्याक्कै worker/employer को लाइभ स्थानमा।
Future<void> _paintAssetImage(
    Canvas canvas, double c, String assetPath, double targetH) async {
  final img = await _loadAssetImage(assetPath);
  final double targetW = targetH * img.width / img.height;
  final dst =
      Rect.fromCenter(center: Offset(c, c), width: targetW, height: targetH);
  final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
  canvas.drawImageRect(
      img, src, dst, Paint()..filterQuality = FilterQuality.high);
}

final Map<String, BitmapDescriptor> _catPinCache = {};

// Bike/Car पिनमा कोर्ने असली फोटो — एकपटक decode गरेर cache (हरेक marker
// रिबिल्डमा फेरि decode गर्नु नपरोस्)।
final Map<String, ui.Image> _vehiclePinImageCache = {};

Future<ui.Image> _loadVehiclePinImage(String assetPath) async {
  final cached = _vehiclePinImageCache[assetPath];
  if (cached != null) return cached;
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  _vehiclePinImageCache[assetPath] = frame.image;
  return frame.image;
}

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
  final innerR = headR - 12 * scale;
  canvas.drawCircle(Offset(cx, centerY), innerR, Paint()..color = Colors.white);

  final lowerService = service.toLowerCase();
  if (lowerService == 'bike' || lowerService == 'car') {
    // Bike/Car पिनमा असली मोटरसाइकल/कार फोटो (कहिल्यै generic glyph होइन)।
    final vehicleImg = await _loadVehiclePinImage(serviceImageFor(service));
    final dstRect =
        Rect.fromCircle(center: Offset(cx, centerY), radius: innerR - 4);
    final srcSize =
        Size(vehicleImg.width.toDouble(), vehicleImg.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, srcSize, dstRect.size);
    final srcRect =
        Alignment.center.inscribe(fitted.source, Offset.zero & srcSize);
    final destRect = Alignment.center.inscribe(fitted.destination, dstRect);
    canvas.save();
    canvas.clipPath(Path()..addOval(dstRect));
    canvas.drawImageRect(vehicleImg, srcRect, destRect, Paint());
    canvas.restore();
  } else {
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
  }

  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final bd = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  _catPinCache[key] = bd;
  return bd;
}

/// सेवा प्रकारको icon (serviceFilters बाट)।
IconData serviceIconFor(String service) {
  // 'Driver' आफैं अब कहिल्यै साँचो bookable service होइन — home screen मा
  // एउटै tile मात्र देखिन्छ, तर tap गरेपछि Bike/Car मध्ये छानिएको वास्तविक
  // service value यहीँ (serviceFilters मा नभएकोले) छुट्टै handle हुन्छ।
  switch (service.toLowerCase()) {
    case 'bike':
      return Icons.two_wheeler_rounded;
    case 'car':
      return Icons.local_taxi_rounded;
    case 'auto':
      return Icons.electric_rickshaw_rounded;
    case 'hotel booking':
      return Icons.hotel_rounded;
  }
  for (final s in serviceFilters) {
    if ((s['name'] as String).toLowerCase() == service.toLowerCase()) {
      return s['icon'] as IconData;
    }
  }
  return Icons.handyman_rounded;
}

/// जहाँ पनि पहिले `Icon(serviceIconFor(service))` मात्र थियो त्यहाँ प्रयोग
/// गर्ने साझा widget — Bike/Car/Auto का लागि असली neon illustration (कहिल्यै
/// generic icon मा fallback नहुने गरी) र बाँकी सबै सेवाका लागि उही पुरानो
/// icon glyph देखाउँछ।
class ServiceGlyph extends StatelessWidget {
  final String service;
  final double size;
  final Color? color;

  const ServiceGlyph({
    super.key,
    required this.service,
    required this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final lower = service.toLowerCase();
    if (lower == 'bike' || lower == 'car' || lower == 'auto') {
      return Image.asset(
        serviceImageFor(service),
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Icon(serviceIconFor(service), size: size, color: color);
  }
}

/// List-row/preview-card मा प्रयोग हुने circular badge — Bike/Car/Auto
/// बाहेकका सेवाको लागि रंगीन circle background भित्र icon (पहिलेकै जस्तै),
/// तर Bike/Car/Auto को लागि त्यो circle/border पूर्ण रूपमा हटाएर असली वाहन
/// फोटो सिधै (InDrive/Bolt-style, कुनै "cartoonish" गोलाकार फ्रेम बिना)
/// देखाउने।
class ServiceIconBadge extends StatelessWidget {
  final String service;
  final double size;
  final Color? iconColor;
  final Gradient? gradient;
  final Color? backgroundColor;

  const ServiceIconBadge({
    super.key,
    required this.service,
    required this.size,
    this.iconColor,
    this.gradient,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final lower = service.toLowerCase();
    if (lower == 'bike' || lower == 'car' || lower == 'auto') {
      return Image.asset(
        serviceImageFor(service),
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        color: gradient == null ? backgroundColor : null,
      ),
      child: Icon(serviceIconFor(service), size: size * 0.55, color: iconColor),
    );
  }
}

/// worker/job list कार्डको square photo tile (44x44 जस्ता ठाउँमा) — Bike/Car
/// भए असली मोटरसाइकल/कार फोटो पूरै (crop नहुने गरी) `BoxFit.contain` मा,
/// नत्र बाँकी सेवाका profession photo `BoxFit.cover` मा (नभेटे icon fallback)।
class ServicePhotoTile extends StatelessWidget {
  final String service;
  final Color iconColor;

  const ServicePhotoTile({
    super.key,
    required this.service,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final lower = service.toLowerCase();
    final isVehicle = lower == 'bike' || lower == 'car' || lower == 'auto';
    return Image.asset(
      serviceImageFor(service),
      fit: isVehicle ? BoxFit.contain : BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          Icon(serviceIconFor(service), color: iconColor),
    );
  }
}

/// सेवा-ग्रिड (home screen को मुख्य ग्रिड, Handyman उप-श्रेणी पेज, आदि) मा
/// साझा रूपमा प्रयोग हुने कार्ड — गोलो icon/फोटो + द्विभाषी लेबल। पहिले
/// home_screen.dart भित्रै निजी (`_ServiceGridCard`) थियो, अब दुई ठाउँमा
/// (मुख्य grid + HandymanCategoriesScreen) उस्तै देखिनुपर्ने भएकोले यहाँ
/// साझा।
class ServiceGridCard extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const ServiceGridCard({super.key, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = serviceMarkerColor(name);
    // अंग्रेजी locale मा `S.serviceName(name)` ले अनुवाद नभेटे `name` आफैं
    // फिर्ता गर्छ — त्यसैले दोस्रो line (कच्चा अंग्रेजी) नेपालीमा मात्र
    // देखाउने, नत्र "Bike Bike"/"Car Car" जस्तो उही text दोहोरिने बग आउँथ्यो।
    final translated = S.serviceName(name);
    final showEnglishSubline = S.isNepali && translated != name;
    return SpringTap(
      onTap: onTap,
      pressedScale: 0.95,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                // वृत्ताकार (circle) को सट्टा भरिएको वर्गाकार/आयताकार
                // box — image/icon त्यही box भित्र (कुनामा हल्का गोलाइ
                // मात्र राखेर) पूरै ठूलो/स्पष्ट देखियोस् भनेर।
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [Color.lerp(color, Colors.white, 0.25)!, color],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.45), blurRadius: 14),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      serviceImageFor(name),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(serviceIconFor(name),
                          color: Colors.white, size: 44),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(translated,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.kmText)),
            if (showEnglishSubline)
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.kmMuted)),
          ],
        ),
      ),
    );
  }
}

/// InDrive-style अनुमानित भाडा — सेवा प्रकार + दूरी अनुसार, `FareMatrixConfig`
/// कै round-to मा round। दर आफैं (base/per-km/round-to) अब owner dashboard
/// बाट (config/fareMatrix) सेट गर्न मिल्ने — यहाँ भने अझै पूर्ण synchronous
/// (cache भएको मान मात्र पढ्ने, कुनै await छैन) किनभने यो UI build/gesture
/// भित्रैबाट सिधै कल हुन्छ।
///
/// [minutes] — साँचो OSRM/Directions यात्रा-समय (`RoadRoute.minutes`) थाहा
/// भएको ठाउँ (पिकअप→गन्तव्य route confirm भइसकेपछि) मात्र दिनुहोस् — त्यसले
/// per-minute दर पनि थप्छ (ट्राफिकमा अडिँदा लामो समय लाग्ने बाटोले उचित
/// बढी भाडा देखाओस् भनेर)। route अझै नआएको/नभएको बेला (जस्तै गन्तव्य छान्नुअघि,
/// वा ride-नभएका सेवाको nearest-worker distance) `null` नै छोड्नुहोस् — त्यो
/// बेला दूरी-मात्र अनुमान (base + perKm) प्रयोग हुन्छ। अन्त्यमा नतिजा कहिल्यै
/// [FareMatrixConfig.minimumFare] भन्दा तल नझरोस् भनेर clamp हुन्छ।
/// रातको समय (config/fareMatrix: nightStartHour देखि nightEndHour सम्म,
/// अर्को दिनसम्म फैलिने भए पनि) — [at] नदिए हालको device घडी प्रयोग हुन्छ।
/// UI ले "Night fare" जस्तो label देखाउन पनि यही प्रयोग गर्न सक्छ।
bool isNightFareHour([DateTime? at]) {
  final hour = (at ?? DateTime.now()).hour;
  final start = FareMatrixConfig.nightStartHour;
  final end = FareMatrixConfig.nightEndHour;
  return start > end
      ? (hour >= start || hour < end)
      : (hour >= start && hour < end);
}

int estimateFare(String service, double distanceKm, {int? minutes, DateTime? at}) {
  final b = FareMatrixConfig.baseByService[service.toLowerCase()] ?? 500;
  final byDist = (distanceKm.clamp(0.0, 40.0) * FareMatrixConfig.perKm).round();
  final byTime = minutes != null ? (minutes * FareMatrixConfig.perMinute) : 0;
  var raw = b + byDist + byTime;
  if (isNightFareHour(at)) {
    raw = (raw * FareMatrixConfig.nightSurchargeMultiplier).round();
  }
  final roundTo = FareMatrixConfig.roundTo;
  final rounded = (raw / roundTo).round() * roundTo;
  return rounded < FareMatrixConfig.minimumFare
      ? FareMatrixConfig.minimumFare
      : rounded;
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
/// driver को स्थान यति मिनेटभन्दा पुरानो भए नक्सामा नदेखाउने (offline/बन्द एप)।
const Duration kDriverLocationMaxAge = Duration(minutes: 5);

/// असली, ताजा स्थान मात्र — `lat/lng` नभए, वा `locationUpdatedAt` नभएको/पुरानो
/// (`kDriverLocationMaxAge` भन्दा) भए null (नक्सामा देखाउनै पर्दैन)। यसले
/// `workerPos` को नक्कली (id-hash बाट बनेको) स्थान कहिल्यै दिँदैन।
({double lat, double lng})? realWorkerPos(Map<String, dynamic> data) {
  final lat = (data['lat'] as num?)?.toDouble();
  final lng = (data['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  final ts = data['locationUpdatedAt'];
  if (ts is! Timestamp) return null;
  if (DateTime.now().difference(ts.toDate()) > kDriverLocationMaxAge) {
    return null;
  }
  return (lat: lat, lng: lng);
}

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
typedef RoadRoute = ({
  List<LatLng> points,
  double km,
  int minutes,
  bool real,
  TravelMode mode,
});

/// [query] बिन्दु route.points माथि कहाँ "snap" हुन्छ भन्ने — route_map_view.dart
/// कै private `_projectDistanceAlongRoute` कै उही algorithm (equirectangular
/// local-flat approximation), यहाँ सार्वजनिक प्रति — `RouteEtaPill` (तल) जस्ता
/// बाहिरी caller (native map माथिको Positioned overlay सहित) ले पनि उही
/// दूरी-गणना प्रयोग गर्न सकून्, छुट्टाछुट्टै फरक/बेमेल दूरी नदेखियोस्।
double projectDistanceAlongRouteKm(List<LatLng> pts, LatLng query) {
  if (pts.length < 2) return 0;
  const latKmPerDeg = 111.32;
  double bestDistSq = double.infinity;
  double bestCum = 0;
  double cum = 0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1];
    final b = pts[i];
    final segLen =
        haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
    final lngKmPerDeg = latKmPerDeg * cos(a.latitude * pi / 180);
    final bx = (b.longitude - a.longitude) * lngKmPerDeg;
    final by = (b.latitude - a.latitude) * latKmPerDeg;
    final qx = (query.longitude - a.longitude) * lngKmPerDeg;
    final qy = (query.latitude - a.latitude) * latKmPerDeg;
    final segLenSq = bx * bx + by * by;
    var t = segLenSq <= 0 ? 0.0 : (qx * bx + qy * by) / segLenSq;
    t = t.clamp(0.0, 1.0);
    final dx = qx - bx * t;
    final dy = qy - by * t;
    final distSq = dx * dx + dy * dy;
    if (distSq < bestDistSq) {
      bestDistSq = distSq;
      bestCum = cum + segLen * t;
    }
    cum += segLen;
  }
  return bestCum;
}

/// Native Android राइड-नक्सा (NativeRouteMapView — हेर्नुहोस् त्यसको doc-
/// comment "सीमा (हाल): summary pill... deliberately deferred") ले आफैं
/// दूरी/ETA देखाउँदैन — caller ले छुट्टै Positioned overlay थपेर मात्र।
/// यो pill त्यही overlay हो, job_route_screen.dart (driver, pickup अनि
/// ride सुरु भएपछि drop-off) र request_tracking_screen.dart (passenger,
/// driver pickup/drop-off मा कति बाँकी) दुवैतिर साझा — route_map_view.dart
/// भित्रैको उही remainingKm/remainingMinutes गणना (route पुनः-fetch नभई,
/// हरेक rebuild मा हालको स्थान route माथि प्रोजेक्ट गरेर, सहज घट्दै जाने)।
class RouteEtaPill extends StatelessWidget {
  final RoadRoute? route;
  final LatLng? currentPos;
  const RouteEtaPill(
      {super.key, required this.route, required this.currentPos});

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    final pos = currentPos;
    if (route == null || pos == null) return const SizedBox.shrink();
    final remainingKm = route.points.length >= 2
        ? (route.km - projectDistanceAlongRouteKm(route.points, pos))
            .clamp(0.0, route.km)
        : route.km;
    final remainingMinutes = route.km > 0
        ? (route.minutes * (remainingKm / route.km)).round()
        : route.minutes;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.kmSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: const [
          BoxShadow(
              color: Colors.black38, blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(route.mode.icon, size: 16, color: AppColors.kmText),
            const SizedBox(width: 8),
            Text(
              '${remainingKm.toStringAsFixed(remainingKm < 10 ? 1 : 0)} km  ·  ${S.minutesShort(remainingMinutes)}',
              style: const TextStyle(
                  color: AppColors.kmText,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Multi-modal यातायात — Google Directions/OSRM दुवैले चिन्ने canonical
/// नाम (`getRoute` Cloud Function हेर्नुहोस्)। worker ले यीमध्ये छान्छ;
/// employer ले सोही मोड (Firestore बाट, `RequestTrackingScreen`) अनुसार
/// उही route देख्छ — दुवैतिर फरक-फरक route नदेखियोस् भनेर।
enum TravelMode {
  driving('driving', Icons.directions_car_rounded),
  walking('walking', Icons.directions_walk_rounded),
  bicycling('bicycling', Icons.pedal_bike_rounded);

  const TravelMode(this.value, this.icon);
  final String value;
  final IconData icon;

  static TravelMode fromValue(String? v) => TravelMode.values.firstWhere(
        (m) => m.value == v,
        orElse: () => TravelMode.driving,
      );
}

/// Ride-Hailing (Bike/Car) मात्र — नक्सामा देखिने marker आइकन सधैँ ठ्याक्कै
/// त्यही राइडको साँचो सवारी-प्रकार अनुसार हुनुपर्छ, कहिल्यै Firestore को
/// `travelMode` field (जुन सामान्य काम — mechanic/plumber आदि — का लागि
/// मात्र प्रयोगकर्ताले छानेको हुन्छ, राइडमा अब त्यो picker नै लुकाइएको छ,
/// हेर्नुहोस् `!isRide` गेट job_route_screen.dart/request_tracking_screen.dart
/// मा) बाट होइन। त्यो field नलेखिँदा `TravelMode.fromValue(null)` ले सधैँ
/// default (`driving` → कार आइकन) फर्काउने भएकोले, Bike राइडमा पनि गलत
/// कार-आइकन देखिने बग ठ्याक्कै यसैले निम्त्याएको थियो — worker ले Bike
/// छानेपछि पनि नक्सामा कार देखिने।
TravelMode travelModeForVehicle(String service) => switch (service) {
      'Bike' => TravelMode.bicycling,
      'Car' => TravelMode.driving,
      'Auto' => TravelMode.driving,
      _ => TravelMode.driving,
    };

/// Multi-modal यातायात छान्ने — Driving/Walking/Bike, ride-hailing app
/// जस्तै गोलो chip row। worker/employer दुवैतिर उही एउटा widget (JobRouteScreen
/// र RequestTrackingScreen दुवैले प्रयोग गर्छन्) — दुवै पक्षले नै छान्न/बदल्न
/// पाउँछन् (जे बदलियो त्यही Firestore मार्फत अर्को पक्षलाई पनि तुरुन्तै देखिन्छ,
/// छुट्टाछुट्टै UI डुप्लिकेट नभई)।
class TravelModeChips extends StatelessWidget {
  final TravelMode selected;
  final ValueChanged<TravelMode> onChanged;
  const TravelModeChips(
      {super.key, required this.selected, required this.onChanged});

  String _label(TravelMode m) => switch (m) {
        TravelMode.driving => S.travelModeDriving,
        TravelMode.walking => S.travelModeWalking,
        TravelMode.bicycling => S.travelModeBicycling,
      };

  @override
  Widget build(BuildContext context) {
    // Driving-Only — Walking/Bike chip पूर्ण रूपमा हटाइयो, अनुरोधमा।
    // Driving नै स्थायी/एकमात्र mode (TravelMode enum, marker-icon switch,
    // glide-speed switch, र native vehicle-type string — ती कतै छोइएको
    // छैन, केवल यहाँको selector UI ले अब Driving बाहेक अरू option नै
    // नदेखाउने)।
    return SizedBox(
      height: 34,
      child: Row(
        children: [_chip(TravelMode.driving)],
      ),
    );
  }

  Widget _chip(TravelMode m) {
    final isSelected = m == selected;
    return GestureDetector(
      onTap: () => onChanged(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 34,
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.kmCtaGradient : null,
          color: isSelected ? null : AppColors.kmPurple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(m.icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.kmPurple),
            const SizedBox(width: 6),
            Text(_label(m),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AppColors.kmPurple)),
          ],
        ),
      ),
    );
  }
}

final FirebaseFunctions _functions = FirebaseFunctions.instance;

Future<RoadRoute?> fetchRoadRoute(LatLng a, LatLng b,
    {TravelMode mode = TravelMode.driving}) async {
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
      'mode': mode.value,
    });
    final data = result.data;
    final encoded = (data['polyline'] as String?) ?? '';
    final points = _decodePolyline(encoded);
    // दुई-बिन्दुको "route" ले पनि सीधा रेखा नै बनाउँछ — त्यो पनि साँचो
    // route जस्तै कहिल्यै नदेखियोस् भनेर कम्तिमा ३ बिन्दु अनिवार्य।
    if (points.length < 3) return null;
    final echoedMode = data['mode'] as String?;
    return (
      points: points,
      km: (data['km'] as num?)?.toDouble() ?? 0,
      minutes: (data['minutes'] as num?)?.toInt() ?? 0,
      real: (data['real'] as bool?) ?? true,
      // सर्भरले mode फर्काएको भए त्यही (साँचो प्रयोग भएको), नत्र (पुरानो
      // deploy भन्दा अघिको जवाफ) हामीले नै अनुरोध गरेको मोड मान्ने।
      mode: echoedMode != null ? TravelMode.fromValue(echoedMode) : mode,
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

/// `routePolyline` भन्दा फराकिलो, सेतो casing — मानक Google Maps navigation
/// जस्तै मुख्य रङको रेखामुनि सेतो border राखेर जुनसुकै नक्सा tile रङमा पनि
/// route प्रस्ट/छुट्टै देखियोस् भनेर। सधैँ [routePolyline] भन्दा पहिले (तल,
/// `zIndex` कम) थपिनुपर्छ।
Polyline routePolylineCasing(String id, RoadRoute route) => Polyline(
      polylineId: PolylineId('${id}_casing'),
      points: route.points,
      color: Colors.white,
      width: 12,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      zIndex: 0,
    );

/// मुख्य route polyline — Instagram violet accent मा बाक्लो/प्रमुख रेखा,
/// मानक Google Maps navigation जस्तै स्पष्ट देखिने (OSRM बाट real road
/// route भेटिएन भने dashed देखिन्छ ताकि "अनुमानित" हो भनेर छुट्टिओस्)।
Polyline routePolyline(String id, RoadRoute route) => Polyline(
      polylineId: PolylineId(id),
      points: route.points,
      color: AppColors.kmPurple,
      width: 7,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      zIndex: 1,
      patterns:
          route.real ? const [] : [PatternItem.dash(24), PatternItem.gap(14)],
    );

/// यो भन्दा कम भए (route कै अन्त्य बिन्दु र साँचो marker लगभग एउटै ठाउँमा
/// भएकोले) जोड्ने डट्टेड रेखा नै नदेखाउने — GPS jitter/rounding-मात्रको
/// नगन्य फरकमा अनावश्यक साना थोप्ला नआऊन्।
const double kWalkConnectorThresholdKm = 0.02; // ~20m

/// Google Maps-शैली "last-mile"/walking connector — सडक-पछ्याउने solid
/// route polyline ठ्याक्कै marker (गन्तव्य वा worker/employer को लाइभ
/// स्थान) सम्मै नपुगेको (उदाहरण: गन्तव्य कम्पाउन्ड भित्र, वा routing engine
/// ले नजिकैको सडकसम्म मात्र पुर्‍याएको) बेला त्यो खाली ठाउँलाई साना
/// थोप्लाहरू (dot pattern, dash होइन — त्यो अघिकै "अनुमानित route" अर्थमा
/// प्रयोग भइसकेको छ, यहाँ अर्कै अर्थ भएकोले छुट्टै देखिने) ले जोड्छ। फरक
/// नगण्य (< [kWalkConnectorThresholdKm]) भए `null` — कुनै polyline
/// देखाउँदैन।
Polyline? walkConnectorPolyline({
  required String id,
  required LatLng routeEnd,
  required LatLng markerPos,
}) {
  final gapKm = haversineKm(routeEnd.latitude, routeEnd.longitude,
      markerPos.latitude, markerPos.longitude);
  if (gapKm < kWalkConnectorThresholdKm) return null;
  return Polyline(
    polylineId: PolylineId(id),
    points: [routeEnd, markerPos],
    color: const Color(0xFF111111),
    width: 4,
    patterns: [PatternItem.dot, PatternItem.gap(10)],
    jointType: JointType.round,
    endCap: Cap.roundCap,
    startCap: Cap.roundCap,
  );
}

/// Destination-pin ज्यामिति — पहिले यहाँ पोल + झन्डा + चन्द्रमा + तारा
/// (राष्ट्रिय झन्डाको आकार सम्झाउने) procedurally कोरिन्थ्यो। Administrative/
/// compliance कारणले त्यो आकृति पूर्ण हटाइयो — अब destination marker पनि
/// एपभरि पहिल्यैदेखि "me"/pickup marker मा प्रयोग हुने उही आधिकारिक
/// Sahayatri ब्रान्ड-पिन (`sahayatri_pin.png`, हेर्नुहोस् [SahayatriPinGeometry])
/// बाट बन्छ — नयाँ ज्यामिति अड्कल नगरी, पहिल्यै pixel-नापिएको anchor नै
/// सिधै साझा गरेर (तलको `destinationFlagPin()`/`destinationFlagPinBytes()`
/// हेर्नुहोस्)।
class FlagPinGeometry {
  FlagPinGeometry._();

  static const double displayW = sahayatriPinDisplayW;
  static const double displayH = sahayatriPinDisplayH;

  /// `Marker.anchor` का लागि (0..1) fraction — `destinationFlagPin()` सँगै
  /// प्रयोग गर्ने। Sahayatri पिनकै (pixel-नापिएको) anchor सँग ठ्याक्कै उस्तै।
  static Offset get markerAnchorFraction => SahayatriPinGeometry.anchorFraction;

  static Offset get anchor =>
      Offset(SahayatriPinGeometry.anchorFraction.dx * displayW, displayH);
}

/// Custom 3D Pickup & Drop Pins — पुरानो procedural flag-pिन (माथिको
/// [FlagPinGeometry]) को ठाउँमा यी दुई 3D glass-style PNG (assets/images/
/// markers/) प्रयोग हुन्छन्: pickup = electric-blue glowing pin, dropoff =
/// सुनौलो/amber घर-पिन। दुवै वर्गाकार (1254×1254) भएकोले एउटै geometry
/// (साइज/anchor) साझा गर्छन्।
enum MapPinKind { pickup, dropoff }

String _pinAssetPath(MapPinKind kind) => switch (kind) {
      MapPinKind.pickup => 'assets/images/markers/pickup_pin.png',
      MapPinKind.dropoff => 'assets/images/markers/dropoff_pin.png',
    };

/// pin graphic ले क्यानभासमा ओगट्ने display साइज (वर्गाकार) — पुरानो
/// झन्डाको `FlagPinGeometry.displayW` भन्दा अलि ठूलो राखिएको, किनभने यी
/// नयाँ 3D icon बाक्लो/भरिएको आकारको हुन् (पातलो झन्डा जस्तो होइन),
/// साना साइजमा विवरण हराउन सक्ने।
const double _pinDisplaySize = 56;

/// दिइएको PNG को पिनको टुप्पो (जहाँ पिन काँचको disc मा टाँसिन्छ, साँचो
/// GPS-बिन्दु) तस्बिरको जम्मा उचाइको लगभग कति तल पर्छ — दुवै असेट उस्तै
/// 3D style/composition भएकोले एउटै अनुमानित fraction साझा गर्छन्। (Pixel-
/// सटीक होइन — डिभाइसमा हेरेर मिलाउनुपर्‍यो भने यही एउटा स्थिरांक बदल्नुहोस्।)
const double _pinTipYFraction = 0.78;

final Map<MapPinKind, ui.Image> _pinImageCache = {};

Future<ui.Image> _loadPinImage(MapPinKind kind) async {
  final cached = _pinImageCache[kind];
  if (cached != null) return cached;
  final data = await rootBundle.load(_pinAssetPath(kind));
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  _pinImageCache[kind] = frame.image;
  return frame.image;
}

final Map<MapPinKind, BitmapDescriptor> _pinBitmapCache = {};
final Map<MapPinKind, Uint8List> _pinBytesCache = {};

Future<Uint8List> _renderPinBytes(MapPinKind kind) async {
  final cached = _pinBytesCache[kind];
  if (cached != null) return cached;
  final image = await _loadPinImage(kind);
  const double scale = 2.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  // same missing-scale bug as `_renderSahayatriPinBytes` — see its comment.
  canvas.scale(scale);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const Rect.fromLTWH(0, 0, _pinDisplaySize, _pinDisplaySize),
    Paint()..filterQuality = FilterQuality.high,
  );
  final rendered = await rec
      .endRecording()
      .toImage((_pinDisplaySize * scale).ceil(), (_pinDisplaySize * scale).ceil());
  final bytesData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  final result = bytesData!.buffer.asUint8List();
  _pinBytesCache[kind] = result;
  return result;
}

/// Uber/inDrive-शैली pickup pin (कुनै label-ब्याज बिना, एक्लै) — Google
/// Maps `Marker` का लागि। `anchor: const Offset(0.5, _pinTipYFraction)`
/// दिनुहोस्।
Future<BitmapDescriptor> pickupPin() async {
  final cached = _pinBitmapCache[MapPinKind.pickup];
  if (cached != null) return cached;
  final bytes = await _renderPinBytes(MapPinKind.pickup);
  final bd = BitmapDescriptor.bytes(bytes,
      width: _pinDisplaySize, height: _pinDisplaySize);
  _pinBitmapCache[MapPinKind.pickup] = bd;
  return bd;
}

/// उही pickup pin, plain Flutter `Image.memory` overlay (screen-centered,
/// नक्सा आफैं pan हुने Uber/inDrive pattern) का लागि —
/// service_map_screen.dart::`_buildPickupPinOverlay()` हेर्नुहोस्।
Future<Uint8List> pickupPinBytes() => _renderPinBytes(MapPinKind.pickup);

/// Sahayatri Brand Pin — pickup/dropoff pin (माथि, वर्गाकार) भन्दा फरक,
/// कम्पनीको आफ्नै लोगो-आकारको पिन (लामो/साँघुरो, वर्गाकार होइन) — "N
/// providers nearby" (pickup-select, service_map_screen.dart) को केन्द्रित
/// पिन र "Waiting for driver" (request_tracking_screen.dart) को "me"
/// marker दुवैमा प्रयोग हुन्छ। pixel-विश्लेषण गरेर पहिल्यै नापिएको ज्यामिति
/// (1167×2085, टुप्पो झन्डै तल्लो किनारैमा) — नयाँ `ui.Image` बाट हरेक
/// पटक फेरि नमापी सिधै यिनै स्थिरांक प्रयोग गरिन्छ।
class SahayatriPinGeometry {
  SahayatriPinGeometry._();
  static const double naturalW = 1167;
  // स्रोत PNG (2085 अग्लो) को पुछारमा एउटा छुट्टै, पातलो धातुको टुप्पो
  // (spike) भन्दा तल्लो, फराकिलो drop-shadow ellipse थियो — बीचमा पूर्ण
  // transparent खाली ठाउँ छोडेर छुट्टिएको। Alpha-channel pixel-विश्लेषणले
  // (हरेक row स्क्यान गरेर) पुष्टि गर्छ: टुप्पोको अन्तिम देखिने (alpha>0)
  // pixel row ठ्याक्कै y=1873 मा हो (x-दायरा 618-629, केन्द्र≈623.5 —
  // तलको `anchorFraction.dx = 623/naturalW` यसैसँग मिल्छ); त्यसपछि
  // y=1874-1902 पूर्ण transparent (खाली खाडल), अनि y=1903 बाट मात्र
  // shadow ellipse सुरु हुन्छ। पहिले यो स्थिरांक 1882 थियो — त्यो खाली
  // खाडलकै बीचमा पर्थ्यो, अर्थात् anchor (dy=1.0, crop कै पुछार) टुप्पोको
  // साँचो अन्तिम pixel भन्दा ९ row तल (पारदर्शी ठाउँमा) पर्थ्यो, जसले
  // गर्दा ripple/marker anchor बिन्दु टुप्पोको भिजुअल टुप्पोभन्दा अलिक्ति
  // तल हुन्थ्यो। अब ठ्याक्कै 1874 (row 0..1873 समावेश, शून्य खाली
  // padding) — anchor (dy=1.0) ठ्याक्कै देखिने टुप्पोकै अन्तिम pixel row
  // मा नै पर्छ, कुनै फ्र्याक्सन-अड्कल वा खाली खाडल बाँकी रहँदैन।
  static const double croppedSourceH = 1874;
  static const double naturalH = croppedSourceH;
  static const Offset anchorFraction = Offset(623 / naturalW, 1.0);
}

const String _sahayatriPinAsset = 'assets/images/markers/sahayatri_pin.png';
// पुरानो झन्डा (FlagPinGeometry.displayH = 79) भन्दा स्पष्ट रूपमा ठूलो/
// प्रस्ट देखियोस् भनेर — पहिले 64 थियो, धेरै सानो देखिने गुनासो आएपछि।
// public (अब request_tracking_screen.dart ले पनि प्रयोग गर्छ — pin+ripple
// लाई एउटै Flutter overlay/anchor मा जोड्न, नत्र दुई फाइलमा छुट्टाछुट्टै
// नापिएको उचाइ राख्दा बिस्तारै मेल नखाने जोखिम हुन्थ्यो)।
const double sahayatriPinDisplayH = 108;
const double sahayatriPinDisplayW =
    sahayatriPinDisplayH * SahayatriPinGeometry.naturalW / SahayatriPinGeometry.naturalH;

BitmapDescriptor? _sahayatriPinCache;
Uint8List? _sahayatriPinBytesCache;

Future<Uint8List> _renderSahayatriPinBytes() async {
  final cached = _sahayatriPinBytesCache;
  if (cached != null) return cached;
  final data = await rootBundle.load(_sahayatriPinAsset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  final image = frame.image;

  const double scale = 2.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  // `toImage()` नीचे यो picture लाई (scale*displaySize) पिक्सेलको raster मा
  // कोर्छ — तर यो `canvas.scale(scale)` बिना, तलको drawImageRect ले अझै
  // LOGICAL (1x) आकारमै कोर्छ, अर्थात् रेखाचित्र canvas कै माथिल्लो-देब्रे
  // एक-चौथाइ (50%×50%) मा मात्र अटाउँछ — बाँकी ठूलो खाली/पारदर्शी ठाउँ
  // तल/दायाँ छोडिन्छ (Image.memory ले पछि त्यही खाली ठाउँसहित नै display
  // size मा तान्दा anchor बिन्दु टुप्पोभन्दा टाढा पर्छ)। यही file का अरू
  // सबै 2x/4x-scale render function (`labeledFlagPin`, `destinationFlagPin`,
  // `radarGlassWaveFrames`) ले यो गर्छन् — यहीँ छुटेको रहेछ।
  canvas.scale(scale);
  canvas.drawImageRect(
    image,
    // माथिको shadow-blob कटौती — स्रोतको पूरै उचाइ (image.height) होइन,
    // टुप्पोसम्म मात्र (croppedSourceH) कोर्नुहोस्।
    Rect.fromLTWH(0, 0, image.width.toDouble(), SahayatriPinGeometry.croppedSourceH),
    const Rect.fromLTWH(0, 0, sahayatriPinDisplayW, sahayatriPinDisplayH),
    Paint()..filterQuality = FilterQuality.high,
  );
  final rendered = await rec.endRecording().toImage(
      (sahayatriPinDisplayW * scale).ceil(),
      (sahayatriPinDisplayH * scale).ceil());
  final bytesData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  // `image` (decoded fresh above, not stored in any cache — unlike
  // `_loadPinImage`/`_loadAssetImage`/`_loadVehiclePinImage`) केवल यही
  // raster मा एकपटक कोर्न मात्र चाहिएको — rasterize (`toImage` माथि)
  // सकिएपछि अब यसको कुनै प्रयोजन छैन।
  image.dispose();
  final result = bytesData!.buffer.asUint8List();
  _sahayatriPinBytesCache = result;
  return result;
}

/// Native `Marker` का लागि (हाल कुनै screen ले यो प्रयोग गर्दैन —
/// request_tracking_screen.dart को "me" अब plain Flutter overlay हो,
/// `sahayatriPinBytes()` हेर्नुहोस् — पिन र ripple लाई एउटै anchor/screen-
/// projection मा टाँस्न) — `anchor: SahayatriPinGeometry.anchorFraction`
/// दिनुहोस्।
Future<BitmapDescriptor> sahayatriPin() async {
  final cached = _sahayatriPinCache;
  if (cached != null) return cached;
  final bytes = await _renderSahayatriPinBytes();
  final bd = BitmapDescriptor.bytes(bytes,
      width: sahayatriPinDisplayW, height: sahayatriPinDisplayH);
  _sahayatriPinCache = bd;
  return bd;
}

/// उही पिन, plain Flutter `Image.memory` overlay (screen-centered pickup-pin
/// preview, service_map_screen.dart::`_buildPickupPinOverlay()`) का लागि।
Future<Uint8List> sahayatriPinBytes() => _renderSahayatriPinBytes();

/// स्थिर काम/गन्तव्य स्थानको marker — Uber/InDrive को pin जस्तै। पहिले यहाँ
/// आफ्नै (राष्ट्रिय झन्डाको आकार सम्झाउने) procedural bitmap कोरिन्थ्यो —
/// अब त्यो पूर्ण हटाएर, आधिकारिक Sahayatri ब्रान्ड-पिन (`sahayatriPin()`,
/// माथि) नै सिधै reuse गरिन्छ — छुट्टै bitmap/cache चाहिँदैन।
/// Marker मा `anchor: FlagPinGeometry.markerAnchorFraction` प्रयोग गर्नुहोस्।
Future<BitmapDescriptor> destinationFlagPin() => sahayatriPin();

/// उही Sahayatri पिन bitmap, तर plain Flutter widget (`Image.memory`) मा
/// देखाउनको लागि — Google Maps-विशिष्ट `BitmapDescriptor` भन्दा फरक प्रकार।
/// service_map_screen.dart मा "पिन screen-center मा स्थिर रहने, प्रयोगकर्ताले
/// नक्सा नै pan गरेर आफ्नो स्थान म्यानुअली छान्ने" (Uber/inDrive-style)
/// pattern का लागि।
Future<Uint8List> destinationFlagPinBytes() => sahayatriPinBytes();

final Map<String, BitmapDescriptor> _labeledPinIconCache = {};
final Map<String, Offset> _labeledPinAnchorCache = {};
// Native-Map Bridge — route_map_view.dart (Dart-rendered GoogleMap) लाई
// `BitmapDescriptor` नै पुग्छ, तर native_ride_map_view.dart (AndroidView/
// ValueAnimator) ले platform-channel मार्फत raw PNG bytes + canvas साइज
// पठाउनुपर्छ (Kotlin आफैंले `BitmapDescriptor` बनाउँछ, Dart कै `BitmapDescriptor`
// वस्तु सिधै cross नगर्ने)। एउटै क्यानभास दुईपटक नबनाउन यहीं cache।
final Map<String, Uint8List> _labeledPinBytesCache = {};
final Map<String, Size> _labeledPinCanvasSizeCache = {};

/// Uber/inDrive-शैली — झन्डाको ठ्याक्कै माथि "Pickup"/"Drop-off" जस्तो छोटो
/// लेबल-ब्याज सधैँ टाँसिएको एउटै static bitmap (badge + पोल + झन्डा +
/// थोप्लो सबै एउटै PNG भित्रै baked)। किनभने यो पनि (माथिको [destinationFlagPin]
/// जस्तै) एउटै native `Marker` हो — नक्सा pan/zoom/drag गर्दा लेबल र झन्डा
/// सधैँ pixel-सटीक सँगसँगै सर्छन्; छुट्टै Flutter overlay/per-frame
/// screen-coordinate projection चाहिँदैन, त्यसैले lag/overflow/misalignment
/// को जोखिम शून्य। `anchorFraction` लाई `Marker(anchor: ...)` मा दिनैपर्छ —
/// badge को चौडाइअनुसार साँचो GPS-बिन्दु (थोप्लो) bitmap भित्र कहाँ पर्छ
/// भन्ने फरक-फरक हुन्छ, [FlagPinGeometry.markerAnchorFraction] (लेबल-रहित
/// झन्डाको लागि मात्र सही) यहाँ प्रयोग गर्न मिल्दैन।
Future<({BitmapDescriptor icon, Offset anchorFraction})> labeledFlagPin(
    String label, Color badgeColor, MapPinKind kind) async {
  final key = '$label|${badgeColor.toARGB32()}|$kind';
  final cachedIcon = _labeledPinIconCache[key];
  final cachedAnchor = _labeledPinAnchorCache[key];
  if (cachedIcon != null && cachedAnchor != null) {
    return (icon: cachedIcon, anchorFraction: cachedAnchor);
  }
  final r = await _buildLabeledFlagPin(label, badgeColor, kind);
  return (icon: r.icon, anchorFraction: r.anchorFraction);
}

/// Native-Map Bridge — `labeledFlagPin()` कै उही बिट्म्याप, तर Kotlin
/// (`NativeVehicleMapView.setLabeledIcon`) तर्फ raw PNG bytes + logical
/// canvas साइज पठाउन। उही cache (`_buildLabeledFlagPin`) साझा गर्छ —
/// दुवै caller ले एउटै label/रङ मागे एउटै क्यानभास दोहोरिएर नबनोस्।
Future<({Uint8List bytes, Offset anchorFraction, Size canvasSize})>
    labeledFlagPinBytes(String label, Color badgeColor, MapPinKind kind) async {
  final key = '$label|${badgeColor.toARGB32()}|$kind';
  final cachedBytes = _labeledPinBytesCache[key];
  final cachedAnchor = _labeledPinAnchorCache[key];
  final cachedSize = _labeledPinCanvasSizeCache[key];
  if (cachedBytes != null && cachedAnchor != null && cachedSize != null) {
    return (
      bytes: cachedBytes,
      anchorFraction: cachedAnchor,
      canvasSize: cachedSize
    );
  }
  final r = await _buildLabeledFlagPin(label, badgeColor, kind);
  return (
    bytes: r.bytes,
    anchorFraction: r.anchorFraction,
    canvasSize: r.canvasSize
  );
}

Future<
    ({
      BitmapDescriptor icon,
      Offset anchorFraction,
      Uint8List bytes,
      Size canvasSize
    })> _buildLabeledFlagPin(
    String label, Color badgeColor, MapPinKind kind) async {
  final key = '$label|${badgeColor.toARGB32()}|$kind';
  final pinImage = await _loadPinImage(kind);

  const double scale = 4.0;
  const double badgeH = 20;
  const double gap = 5;
  const double pinNaturalW = _pinDisplaySize;

  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final badgeW = (tp.width + 20).clamp(pinNaturalW, 200.0);
  final canvasW = badgeW;
  const canvasH = badgeH + gap + _pinDisplaySize;
  final pinOffsetX = (canvasW - pinNaturalW) / 2;

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(scale);

  // ── लेबल ब्याज — माथि, क्यानभासको बीचमा केन्द्रित ──
  final badgeRect = RRect.fromRectAndRadius(
    Rect.fromLTWH((canvasW - badgeW) / 2, 0, badgeW, badgeH),
    const Radius.circular(6),
  );
  canvas.drawRRect(badgeRect, Paint()..color = badgeColor);
  canvas.drawRRect(
    badgeRect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.55),
  );
  tp.paint(canvas, Offset((canvasW - tp.width) / 2, (badgeH - tp.height) / 2));
  final pointerCx = canvasW / 2;
  canvas.drawPath(
    Path()
      ..moveTo(pointerCx - 4, badgeH)
      ..lineTo(pointerCx + 4, badgeH)
      ..lineTo(pointerCx, badgeH + 4)
      ..close(),
    Paint()..color = badgeColor,
  );

  // ── Custom 3D pin (pickup=निलो, dropoff=सुनौलो) — झन्डाको ठाउँमा ──
  canvas.drawImageRect(
    pinImage,
    Rect.fromLTWH(0, 0, pinImage.width.toDouble(), pinImage.height.toDouble()),
    Rect.fromLTWH(pinOffsetX, badgeH + gap, pinNaturalW, _pinDisplaySize),
    Paint()..filterQuality = FilterQuality.high,
  );

  final img = await rec
      .endRecording()
      .toImage((canvasW * scale).ceil(), (canvasH * scale).ceil());
  final bytesData = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final bytes = bytesData!.buffer.asUint8List();

  final bd = BitmapDescriptor.bytes(bytes, width: canvasW, height: canvasH);
  final anchorFraction = Offset(
    (pinOffsetX + pinNaturalW / 2) / canvasW,
    (badgeH + gap + _pinDisplaySize * _pinTipYFraction) / canvasH,
  );
  final canvasSize = Size(canvasW, canvasH);
  _labeledPinIconCache[key] = bd;
  _labeledPinAnchorCache[key] = anchorFraction;
  _labeledPinBytesCache[key] = bytes;
  _labeledPinCanvasSizeCache[key] = canvasSize;
  return (
    icon: bd,
    anchorFraction: anchorFraction,
    bytes: bytes,
    canvasSize: canvasSize,
  );
}

final Map<int, List<BitmapDescriptor>> _waveFramesCache = {};

/// राडार/ripple मात्र — पिन **होइन** (माथिको `sahayatriPin()` ले दिने स्थिर
/// bitmap छुट्टै Marker को रूपमा राख्नुहोस्, कहिल्यै फेरि नबनाई, एकपटक मात्र
/// `initState` मा)। पिन+ripple दुवै एउटै bitmap मा सँगै बेक गरेर हरेक
/// animation-tick मा स्वयं पिन सहित पूरै bitmap नै फेरि-फेरि native marker
/// लाई पठाउँदा — "पिन टिम्किरहेको/बारम्बार हराएर देखिने" (flicker) समस्या
/// आयो, किनभने Google Maps Flutter plugin ले marker कै `icon` फेरिएको
/// देख्नेबित्तिकै सोही marker लाई native side मा हटाएर फेरि थप्छ (पिन
/// आफैं कहिल्यै नबदलिए पनि)। त्यसैले फर्केर यहाँ ripple-मात्र bitmap (सानो,
/// हल्का) र पिन (सधैँ स्थिर, छुट्टै marker) छुट्याइएको — दुवैको geometric
/// केन्द्र/anchor उही `position` मा नै मिल्छन् (पिनको anchor अब सधैँ
/// bitmap कै ठ्याक्कै पुछारमा पर्ने गरी crop गरिएको — माथि
/// `SahayatriPinGeometry` हेर्नुहोस्), त्यसैले दुई छुट्टै marker भए पनि
/// छुट्टिने जोखिम छैन।
Future<List<BitmapDescriptor>> radarGlassWaveFrames(Color color,
    {int frames = 24}) async {
  final key = color.toARGB32() * 1000 + frames;
  final hit = _waveFramesCache[key];
  if (hit != null) return hit;

  const double scale = 2.5;
  const double size = 240;
  const double c = size / 2;
  // ३ घेराहरू १/३ फरकले सुरु हुन्छन् ताकि एउटा हराउँदा अर्को सुरु भइरहेको
  // देखिन्छ — पानीमा ढुङ्गा हालेपछि निस्कने निरन्तर, ढिलो, नरम लहर जस्तै।
  const int ringCount = 3;
  const double minRadius = 14;
  const double maxRadius = 80;
  const double peakStop = 0.78;
  final glass = Color.lerp(color, Colors.white, 0.45)!;
  final out = <BitmapDescriptor>[];
  for (var f = 0; f < frames; f++) {
    final t = f / frames;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    for (var i = 0; i < ringCount; i++) {
      final p = (t + i / ringCount) % 1.0;
      // वास्तविक पानीको लहर जस्तै — सुरुमा छिटो फैलिएर बिस्तारै गति घट्दै
      // जाने (ease-out), अनि लहर फैलिंदै जाँदा झन्-झन् छिटो हराउने
      // (ease-in fade) — एकसमान रेखीय गतिभन्दा धेरै प्राकृतिक देखिन्छ।
      final radiusP = Curves.easeOut.transform(p);
      final fadeP = Curves.easeIn.transform((1 - p).clamp(0.0, 1.0));
      final radius = minRadius + radiusP * (maxRadius - minRadius);
      final outer = radius / peakStop;
      canvas.drawCircle(
        const Offset(c, c),
        outer,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(c, c),
            outer,
            [
              glass.withValues(alpha: 0),
              glass.withValues(alpha: 0),
              glass.withValues(alpha: 0.4 * fadeP),
              glass.withValues(alpha: 0),
              glass.withValues(alpha: 0),
            ],
            const [0.0, 0.6, peakStop, 0.93, 1.0],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.2),
      );
      canvas.drawCircle(
        const Offset(c, c),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.5 * fadeP)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
      );
    }
    final img = await rec
        .endRecording()
        .toImage((size * scale).ceil(), (size * scale).ceil());
    final bytesData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    out.add(BitmapDescriptor.bytes(bytesData!.buffer.asUint8List(),
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
  // `ValueNotifier` — +/- थिच्दा/quick-chip छान्दा पूरै sheet (avatar, title,
  // details TextField, आदि) फेरि नबनोस् भनेर; तल build() मा यही एउटा
  // `ValueListenableBuilder` ले मात्र (केवल मूल्य देखिने सानो Row) rebuild
  // हुन्छ — बाँकी सबै एकपटक मात्र बन्छ।
  late final ValueNotifier<int> _amount;
  bool _sending = false;

  static const int _step = 5;

  @override
  void initState() {
    super.initState();
    final digits = (widget.data['price'] ?? 'Rs. 500')
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    _asking = int.tryParse(digits) ?? 500;
    if (_asking < _step) _asking = 500;
    _amount = ValueNotifier<int>(_asking);
  }

  @override
  void dispose() {
    _amount.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  void _setAmount(int v) => _amount.value = v.clamp(_step, 1000000);

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      // users/{uid} बाट साँचो नाम/फोन — Auth कै email/phoneNumber भन्दा
      // भरपर्दो (इमेलबाट दर्ता भएकाको हकमा Auth phoneNumber सधैँ खाली हुन्छ,
      // जुन "Call गर्दा नम्बर भेटिएन" गुनासोको मूल कारण थियो)।
      // CUSTOMER-NAME-EMPTY FIX — service_map_screen.dart::_submitJob कै
      // उस्तै जड: `??` ले खाली string (`''`) लाई null ठान्दैन, त्यसैले
      // phone-auth-only प्रयोगकर्ताको `displayName` कहिलेकाहीं `''` हुँदा
      // worker ले देख्ने card मा ग्राहकको नाम पूर्ण रूपमा खाली देखिन्थ्यो।
      var employerName = 'Employer';
      if ((user?.displayName ?? '').trim().isNotEmpty) {
        employerName = user!.displayName!.trim();
      } else if ((user?.email ?? '').trim().isNotEmpty) {
        employerName = user!.email!.trim();
      }
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
      final workerUid = (widget.data['uid'] ?? widget.workerId).toString();
      final service = (widget.data['service'] ?? '').toString();
      final doc =
          await FirebaseFirestore.instance.collection('serviceRequests').add({
        'workerUid': workerUid,
        'employerUid': user?.uid ?? '',
        'employerName': employerName,
        'employerPhone': employerPhone,
        'workerName': widget.data['name'] ?? '',
        'service': service,
        'details': _detailsCtrl.text.trim(),
        'proposedPrice': _amount.value,
        'status': 'pending_worker',
        'createdAt': FieldValue.serverTimestamp(),
        'distanceKm': double.parse(widget.distanceKm.toStringAsFixed(2)),
        // स्थिर काम-स्थल coordinate — accept भएपछि दुवैतिर route-map (सडक
        // मार्ग + दूरी/समय) यसैबाट बन्छ।
        'employerLat': widget.employerLat,
        'employerLng': widget.employerLng,
      });
      // worker profile बाट सिधै पठाइएको यो offer पहिले Firestore मा मात्र
      // लेखिँदै थियो, worker लाई कतै notify नगरी — worker ले आफैं app
      // खोलेर आफ्नो requests list नहेरेसम्म थाहै नपाउने ("worker को home
      // screen मा notification आउनुपर्छ" भन्ने गुनासोको साँचो जड)। अब
      // broadcast/accept/arrival जस्तै उस्तै साझा बाटोबाट (in-app
      // notifications collection, push miss भए पनि पछि देखिने) worker लाई
      // पठाउने।
      if (workerUid.isNotEmpty) {
        unawaited(createNotificationForUser(
          workerUid,
          S.directOfferNotifTitle,
          S.directOfferNotifBody(employerName, service, _amount.value),
          data: {'requestId': doc.id, 'type': 'direct_offer'},
        ));
      }
      if (!mounted) return;
      // यो OfferSheet आफैं यहीँ pop हुने भएकोले, त्यसपछि (dialog देखाउन,
      // र dialog कै OK बटनले फेरि pop गर्न) यसैको `context` फेरि प्रयोग
      // गर्नु खतरनाक — sheet pop भएपछि यो State disposed हुन्छ, र OK बटन
      // थिचुन्जेल त्यो disposal पूरै भइसकेको हुन्छ, जसले "This widget has
      // been unmounted" क्र्यास दिन्थ्यो (ठ्याक्कै यो गुनासोको जड)। यसको
      // सट्टा Navigator पोप गर्नुअघि नै त्यसको State (सधैँ mounted रहने,
      // यो एउटा नेस्टेड route पप हुँदा असर नपर्ने) समातेर राख्ने।
      final navigator = Navigator.of(context);
      navigator.pop();
      if (!navigator.mounted) return;
      showKmDialog(
        context: navigator.context,
        title: S.offerSentTitle,
        message: S.offerSentBody,
        icon: Icons.check_circle_rounded,
        iconBg: const LinearGradient(
            colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
        actions: [
          KmDialogAction(
            label: S.ok,
            filled: true,
            onPressed: () {
              // OK थिचेपछि dialog मात्र होइन, यो पूरै nearby/map screen
              // (जहाँबाट offer पठाइयो) पनि बन्द हुनुपर्छ — offer पहिल्यै
              // पठाइसकेकोले उही पुरानो "Post job"/नजिकका worker list
              // पर्दामा फर्किनु user लाई अन्योलमा पार्थ्यो (फेरि केही
              // गर्नुपर्ने जस्तो देखिने), सिधै अघिल्लो (home) screen मा।
              navigator.pop(); // dialog
              navigator.pop(); // ServiceMapScreen
            },
          ),
        ],
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
    final name = (widget.data['name'] ?? '').toString();
    final service = (widget.data['service'] ?? '').toString();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget quickChip(String label, int value) => GestureDetector(
          onTap: () => _setAmount(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.kmText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        child: glassBackdrop(sigma: 26, child: Container(
            decoration: BoxDecoration(
              color: AppColors.kmGlass2Fill,
              border: Border(top: BorderSide(color: AppColors.kmGlass2Border)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    WorkerAvatar(
                        uid: (widget.data['uid'] ?? '').toString(), size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.isEmpty ? '—' : name,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          Text(
                              '${S.serviceName(service)}  ·  ${S.distanceLabel(widget.distanceKm)}',
                              style: const TextStyle(color: AppColors.kmMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                    '${S.askingPrice}: Rs. $_asking   ·   ${S.suggestedFare}: Rs. ${estimateFare(service, widget.distanceKm)}'
                    '${isNightFareHour() ? '  ·  🌙 ${S.nightFareLabel}' : ''}',
                    style: const TextStyle(color: AppColors.kmMuted)),
                const SizedBox(height: 6),
                Text(S.yourOffer,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                // +/- थिच्दा यही सानो Row मात्र फेरि बन्छ — बाँकी पूरै sheet
                // (avatar, title, details TextField, quick chip हरू) होइन।
                RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _amount,
                    builder: (context, amount, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PriceStepButton(
                            icon: Icons.remove_rounded,
                            onTap: () => _setAmount(amount - _step)),
                        const SizedBox(width: 18),
                        Column(
                          children: [
                            const Text('Rs.',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.kmMuted)),
                            Text('$amount',
                                style: const TextStyle(
                                    color: AppColors.kmText,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(width: 18),
                        PriceStepButton(
                            icon: Icons.add_rounded,
                            onTap: () => _setAmount(amount + _step)),
                      ],
                    ),
                  ),
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
                  style: const TextStyle(color: AppColors.kmText),
                  decoration: kmInputDecoration(S.describeTask,
                      hint: S.describeTaskHint),
                ),
                const SizedBox(height: 18),
                KmCtaButton(
                  label: S.sendOffer,
                  icon: Icons.send_rounded,
                  loading: _sending,
                  onPressed: _send,
                ),
              ],
            ),
          ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Icon(icon, color: AppColors.kmText),
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
