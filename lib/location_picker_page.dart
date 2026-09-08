// location_picker_page.dart
// नक्सामा pin सारेर स्थान छान्ने — Google Maps + Nominatim (OSM) reverse geocode।
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'l10n/strings.dart';
import 'location_util.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';

class PickedPlace {
  final String label;
  final String address;
  final double lat;
  final double lng;
  const PickedPlace(this.label, this.address, this.lat, this.lng);
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
  String _address = '';
  bool _loadingAddr = false;
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
    _map?.dispose();
    super.dispose();
  }

  void _onIdle() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    setState(() => _loadingAddr = true);
    try {
      final lang = S.isNepali ? 'ne' : 'en';
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
          '&lat=${_center.latitude}&lon=${_center.longitude}'
          '&accept-language=$lang');
      final res = await http.get(uri, headers: {
        'User-Agent': 'KaamMitra/1.0 (location picker)',
      }).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _address = (body['display_name'] ?? '').toString();
          _loadingAddr = false;
        });
      } else {
        setState(() => _loadingAddr = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAddr = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingAddr = true);
    final r = await getCurrentLocation();
    if (!mounted) return;
    if (r.ok) {
      final target = LatLng(r.lat!, r.lng!);
      setState(() => _center = target);
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      _reverseGeocode();
    } else {
      setState(() => _loadingAddr = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.locationDeniedShort)));
    }
  }

  void _confirm() {
    Navigator.pop(
      context,
      PickedPlace(
        _labelCtrl.text.trim().isEmpty
            ? widget.initialLabel
            : _labelCtrl.text.trim(),
        _address,
        _center.latitude,
        _center.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.pickOnMap)),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _center, zoom: 15),
            onMapCreated: (c) => _map = c,
            onCameraMove: (p) => _center = p.target,
            onCameraIdle: _onIdle,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // center pin (bottom tip at center)
          const Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: Icon(Icons.location_pin,
                size: 46, color: AppColors.danger),
          ),

          // address bar (top)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 18, color: AppColors.lime),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadingAddr
                          ? S.fetchingAddress
                          : _address.isEmpty
                              ? S.moveMapHint
                              : _address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
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
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg)),
                border: Border.all(color: theme.dividerColor),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _labelCtrl,
                      decoration: InputDecoration(labelText: S.placeLabel),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: S.useMyLocation,
                            icon: Icons.my_location_rounded,
                            onPressed: _useCurrentLocation,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
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
