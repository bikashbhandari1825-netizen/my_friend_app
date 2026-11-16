// screens/hotel_search_screen.dart
//
// Hotel Booking System — Phase 2: खोजी फारम (destination, date-range,
// guest/room counter, price/star/amenity/distance filter)। "Search Hotels"
// थिचेपछि बनेको `HotelSearchQuery` लिएर `HotelResultsScreen` खुल्छ। हाल
// Phase 2 (UI/mock-data) — साँचो inventory/availability जाँच Phase 3 मा।
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/hotel_mock_data.dart' show hydrateHotelsFromFirestore;
import '../location_util.dart' show searchPlaces;
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'hotel_common.dart';
import 'hotel_results_screen.dart';
import '../widgets/futuristic_ui.dart';

class HotelSearchScreen extends StatefulWidget {
  const HotelSearchScreen({super.key});

  @override
  State<HotelSearchScreen> createState() => _HotelSearchScreenState();
}

class _HotelSearchScreenState extends State<HotelSearchScreen> {
  final _destCtrl = TextEditingController();
  Timer? _debounce;
  List<({String label, double lat, double lng})> _results = const [];
  bool _searching = false;
  double? _destLat;
  double? _destLng;

  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 2));
  int _adults = 2;
  int _children = 0;
  int _rooms = 1;
  RangeValues _priceRange = const RangeValues(0, 15000);
  int _minStars = 0;
  final Set<String> _amenities = {};
  double _maxDistanceKm = 50;

  @override
  void initState() {
    super.initState();
    // Self-registered (अघिल्लो session मा) होटल भए in-memory catalog मा
    // ल्याउने — hotel_mock_data.dart::hydrateHotelsFromFirestore हेर्नुहोस्।
    hydrateHotelsFromFirestore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destCtrl.dispose();
    super.dispose();
  }

  void _onDestChanged(String q) {
    _destLat = null;
    _destLng = null;
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final r = await searchPlaces(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _checkIn, end: _checkOut),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: AppColors.kmOrange,
                surface: AppColors.kmSurface,
              ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _checkIn = picked.start;
      _checkOut = picked.end.isAfter(picked.start)
          ? picked.end
          : picked.start.add(const Duration(days: 1));
    });
  }

  void _search() {
    final query = HotelSearchQuery(
      destinationLabel:
          _destCtrl.text.trim().isEmpty ? 'Anywhere' : _destCtrl.text.trim(),
      destinationLat: _destLat,
      destinationLng: _destLng,
      checkIn: _checkIn,
      checkOut: _checkOut,
      adults: _adults,
      children: _children,
      rooms: _rooms,
      priceRange: _priceRange,
      minStarRating: _minStars,
      amenities: _amenities,
      maxDistanceKm: _maxDistanceKm,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HotelResultsScreen(query: query)),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return OledBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: KmScreenHeader(title: 'Find Hotels'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  _sectionLabel('Destination'),
                  _glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _destCtrl,
                          onChanged: _onDestChanged,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: InputDecoration(
                            hintText: 'Where are you going?',
                            hintStyle:
                                const TextStyle(color: AppColors.kmMuted),
                            prefixIcon: const Icon(Icons.location_on_rounded,
                                color: AppColors.kmOrange),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                          ),
                        ),
                        if (_results.isNotEmpty)
                          ..._results.take(5).map((r) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.place_rounded,
                                    color: AppColors.kmMuted, size: 18),
                                title: Text(r.label,
                                    style: const TextStyle(
                                        color: AppColors.kmText,
                                        fontSize: 13)),
                                onTap: () {
                                  _destCtrl.text = r.label;
                                  _destLat = r.lat;
                                  _destLng = r.lng;
                                  setState(() => _results = const []);
                                },
                              )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionLabel('Dates'),
                  _glassCard(
                    child: InkWell(
                      onTap: _pickDateRange,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded,
                              color: AppColors.kmOrange, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_fmt(_checkIn)}  →  ${_fmt(_checkOut)}',
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.kmMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionLabel('Guests & Rooms'),
                  _glassCard(
                    child: Column(
                      children: [
                        _counterRow('Adults', _adults,
                            (v) => setState(() => _adults = v), min: 1),
                        _counterRow('Children', _children,
                            (v) => setState(() => _children = v)),
                        _counterRow('Rooms', _rooms,
                            (v) => setState(() => _rooms = v),
                            min: 1),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionLabel('Filters'),
                  _glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Price per night: ${formatHotelPrice(_priceRange.start)} - ${formatHotelPrice(_priceRange.end)}',
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                        RangeSlider(
                          values: _priceRange,
                          min: 0,
                          max: 20000,
                          divisions: 40,
                          activeColor: AppColors.kmOrange,
                          labels: RangeLabels(
                            formatHotelPrice(_priceRange.start),
                            formatHotelPrice(_priceRange.end),
                          ),
                          onChanged: (v) => setState(() => _priceRange = v),
                        ),
                        const SizedBox(height: 6),
                        const Text('Star rating',
                            style: TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [0, 1, 2, 3, 4, 5].map((s) {
                            final selected = _minStars == s;
                            return ChoiceChip(
                              label: Text(s == 0 ? 'Any' : '$s★+'),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _minStars = s),
                              selectedColor: AppColors.kmOrange,
                              labelStyle: TextStyle(
                                  color: selected
                                      ? AppColors.kmInk
                                      : AppColors.kmText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        const Text('Amenities',
                            style: TextStyle(
                                color: AppColors.kmText,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kHotelAmenities.map((a) {
                            final selected = _amenities.contains(a);
                            return FilterChip(
                              avatar: Icon(hotelAmenityIcon(a),
                                  size: 16,
                                  color: selected
                                      ? AppColors.kmInk
                                      : AppColors.kmMuted),
                              label: Text(a),
                              selected: selected,
                              onSelected: (sel) => setState(() {
                                if (sel) {
                                  _amenities.add(a);
                                } else {
                                  _amenities.remove(a);
                                }
                              }),
                              selectedColor: AppColors.kmOrange,
                              labelStyle: TextStyle(
                                  color: selected
                                      ? AppColors.kmInk
                                      : AppColors.kmText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Max distance: ${_maxDistanceKm.round()} km',
                          style: const TextStyle(
                              color: AppColors.kmText,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                        Slider(
                          value: _maxDistanceKm,
                          min: 1,
                          max: 50,
                          activeColor: AppColors.kmOrange,
                          label: '${_maxDistanceKm.round()} km',
                          onChanged: (v) =>
                              setState(() => _maxDistanceKm = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  KmCtaButton(
                    label: 'Search Hotels',
                    icon: Icons.search_rounded,
                    onPressed: _search,
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.kmMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4)),
      );

  Widget _glassCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      );

  Widget _counterRow(String label, int value, ValueChanged<int> onChanged,
      {int min = 0, int max = 10}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.kmText, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            onPressed:
                value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: AppColors.kmOrange,
          ),
          SizedBox(
            width: 24,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.kmText, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            onPressed:
                value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.kmOrange,
          ),
        ],
      ),
    );
  }
}
