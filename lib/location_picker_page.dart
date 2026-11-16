// location_picker_page.dart
// नक्सामा pin सारेर स्थान छान्ने — Google Maps + Nominatim (OSM) reverse geocode।
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'l10n/strings.dart';
import 'location_util.dart';
import 'screens/nearby_common.dart' show kCloudMapId;
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

class PickedPlace {
  final String label;
  final String address;
  final double lat;
  final double lng;
  const PickedPlace(this.label, this.address, this.lat, this.lng);

  Map<String, dynamic> toMap() => {
        'label': label,
        'address': address,
        'lat': lat,
        'lng': lng,
        'savedAt': DateTime.now().toIso8601String(),
      };
}

class LocationPickerPage extends StatefulWidget {
  final String initialLabel;
  final double initialLat;
  final double initialLng;

  const LocationPickerPage({
    super.key,
    required this.initialLabel,
    this.initialLat = 27.7172,
    this.initialLng = 85.3240,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  GoogleMapController? _map;
  late LatLng _center = LatLng(widget.initialLat, widget.initialLng);
  late final TextEditingController _labelCtrl =
      TextEditingController(text: widget.initialLabel);
  final _addrCtrl = TextEditingController();
  bool _loadingAddr = false;
  bool _addrEdited = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reverseGeocode();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _labelCtrl.dispose();
    _addrCtrl.dispose();
    _map?.dispose();
    super.dispose();
  }

  void _onIdle() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _reverseGeocode);
  }

  String get _coordStr =>
      '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}';

  Future<void> _reverseGeocode() async {
    // प्रयोगकर्ताले हातले address बदलिसकेको भए overwrite नगर्ने।
    if (_addrEdited) return;
    setState(() => _loadingAddr = true);
    String found = '';
    for (var attempt = 0; attempt < 2 && found.isEmpty; attempt++) {
      try {
        final lang = S.isNepali ? 'ne' : 'en';
        final uri = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
            '&lat=${_center.latitude}&lon=${_center.longitude}'
            '&accept-language=$lang');
        final res = await http.get(uri, headers: {
          'User-Agent': 'KaamMitra/1.0 (location picker)',
        }).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          found = (body['display_name'] ?? '').toString();
        }
      } catch (_) {}
      if (found.isEmpty) await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() {
      // geocode ले नपाए coordinate string राख्ने — कहिल्यै blank नरहोस्।
      _addrCtrl.text = found.isNotEmpty ? found : _coordStr;
      _loadingAddr = false;
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loadingAddr = true;
      _addrEdited = false;
    });
    final r = await getCurrentLocation();
    if (!mounted) return;
    if (r.ok) {
      final target = LatLng(r.lat!, r.lng!);
      setState(() => _center = target);
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 18.5));
      _reverseGeocode();
    } else {
      setState(() => _loadingAddr = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.locationDeniedShort)));
    }
  }

  void _confirm() {
    final addr =
        _addrCtrl.text.trim().isEmpty ? _coordStr : _addrCtrl.text.trim();
    Navigator.pop(
      context,
      PickedPlace(
        _labelCtrl.text.trim().isEmpty
            ? widget.initialLabel
            : _labelCtrl.text.trim(),
        addr,
        _center.latitude,
        _center.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.kmText,
        title: Text(S.pickOnMap,
            style: const TextStyle(
                color: AppColors.kmText, fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            // Close-up — street/house-level, ठ्याक्कै ठाउँ छान्न सजिलो होस्।
            initialCameraPosition: CameraPosition(target: _center, zoom: 18.5),
            mapId: kCloudMapId,
            onMapCreated: (c) => _map = c,
            onCameraMove: (p) => _center = p.target,
            onCameraIdle: _onIdle,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // नक्सा सधैँ उत्तर-माथि रहोस् — pin छान्दा घुमेको नक्सा भ्रमपूर्ण
            // हुन्छ।
            rotateGesturesEnabled: false,
          ),

          // center pin (bottom tip at center)
          const Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: Icon(Icons.location_pin, size: 46, color: AppColors.kmRose),
          ),

          // address bar (top)
          Positioned(
            top: 12 + kToolbarHeight + 24,
            left: 16,
            right: 16,
            child: GlassPanel(
              radius: AppRadius.md,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 18, color: AppColors.kmOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadingAddr
                          ? S.fetchingAddress
                          : (_addrCtrl.text.isEmpty
                              ? S.moveMapHint
                              : _addrCtrl.text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // bottom sheet: label + confirm
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GlassPanel2(
              radius: AppRadius.lg,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _labelCtrl,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration: kmInputDecoration(S.placeLabel),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addrCtrl,
                      onChanged: (_) => _addrEdited = true,
                      maxLines: 2,
                      minLines: 1,
                      style: const TextStyle(color: AppColors.kmText),
                      decoration: kmInputDecoration(
                        S.jobAddressLabel,
                        suffixIcon: _loadingAddr
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.kmOrange)),
                              )
                            : const Icon(Icons.place_outlined,
                                color: AppColors.kmMuted),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.kmText,
                              side: BorderSide(color: AppColors.kmGlassBorder),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999)),
                            ),
                            onPressed: _useCurrentLocation,
                            icon:
                                const Icon(Icons.my_location_rounded, size: 18),
                            label: Text(S.useMyLocation),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KmCtaButton(
                            label: S.confirmLocation,
                            icon: Icons.check_rounded,
                            onPressed: _confirm,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
