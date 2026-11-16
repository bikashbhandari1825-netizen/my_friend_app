// lib/demo_route_map.dart
// थप-कोड बिनाको छुट्टै demo entrypoint — production main.dart/app.dart लाई
// कुनै असर नपुर्‍याई, साँचो production `RouteMapView` (inDrive/Bolt-style
// glide + bearing-rotation, screens/route_map_view.dart) लाई synthetic
// (हरेक २ सेकेन्डमा अर्को GPS बिन्दु आउने) डेटाले लाइभ चलाएर देखाउने।
// यो फाइल कुनै production flow बाट कहिल्यै import/चल्दैन — केवल म्यानुअल
// रूपमा `flutter run -d chrome -t lib/demo_route_map.dart` बाट मात्र।
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'screens/nearby_common.dart' show RoadRoute, TravelMode;
import 'screens/route_map_view.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DemoTrackingScreen(),
      );
}

class DemoTrackingScreen extends StatefulWidget {
  const DemoTrackingScreen({super.key});

  @override
  State<DemoTrackingScreen> createState() => _DemoTrackingScreenState();
}

class _DemoTrackingScreenState extends State<DemoTrackingScreen> {
  // पिकअप बिन्दु — स्थिर झन्डा।
  static const _destination = LatLng(27.7172, 85.3240);

  // बाइक pickup तिर आउँदै गरेको GPS trail — असमान दूरीका बिन्दु (साँचो
  // GPS fix जस्तै), प्रत्येक tick मा अर्को बिन्दु "आइपुग्छ"।
  static const _path = <LatLng>[
    LatLng(27.7230, 85.3312),
    LatLng(27.7222, 85.3300),
    LatLng(27.7213, 85.3288),
    LatLng(27.7206, 85.3277),
    LatLng(27.7199, 85.3267),
    LatLng(27.7193, 85.3259),
    LatLng(27.7188, 85.3251),
    LatLng(27.7182, 85.3248),
    LatLng(27.7178, 85.3244),
    LatLng(27.7174, 85.3242),
    LatLng(27.7172, 85.3240),
  ];

  static const RoadRoute _route = (
    points: _path,
    km: 1.4,
    minutes: 5,
    real: true,
    mode: TravelMode.bicycling,
  );

  int _i = 0;
  bool _forward = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // हरेक २ सेकेन्डमा अर्को "GPS fix" — बीचको glide/rotation त
    // RouteMapView आफैंले (production कोड, यहाँ कुनै नयाँ animation
    // लेखिएको छैन) ह्यान्डल गर्छ। पुगेपछि फर्केर (ping-pong) फेरि — कहिल्यै
    // ठाडो "टेलिपोर्ट" जम्प नहोस्, सधैँ सहज glide मात्र देखियोस्।
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      setState(() {
        if (_forward) {
          if (_i >= _path.length - 1) {
            _forward = false;
            _i--;
          } else {
            _i++;
          }
        } else {
          if (_i <= 0) {
            _forward = true;
            _i++;
          } else {
            _i--;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Live glide demo — point ${_i + 1}/${_path.length}'),
      ),
      body: RouteMapView(
        origin: _path[_i],
        originLabel: 'Demo Driver',
        destination: _destination,
        destinationLabel: 'Pickup point',
        destinationAddress: 'Demo pickup address',
        route: _route,
        travelMode: TravelMode.bicycling,
      ),
    );
  }
}
