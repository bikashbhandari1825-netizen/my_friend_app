// screens/fare_matrix_editor_screen.dart
// Admin (Owner Dashboard) ले भाडा दर (base/per-km/per-minute/minimum/round-to)
// कुनै नयाँ app release बिनै सिधै सम्पादन गर्ने ठाउँ — Firestore:
// config/fareMatrix (हेर्नुहोस् config/app_config.dart::FareMatrixConfig)।
// यहाँ Save गर्नेबित्तिकै (`FareMatrixConfig.setMatrix`) यही app-instance
// (admin आफैं) कै cache तुरुन्तै अपडेट हुन्छ; बाँकी अरू (passenger/worker)
// device हरूले भने `main.dart` कै startup live listener (हेर्नुहोस्
// `FareMatrixConfig.preload`) मार्फत अर्को कुनै भी अपडेट/read हुनेबित्तिकै
// स्वतः पाउँछन् — कसैले पनि app फेरि restart/re-install गर्नु पर्दैन।
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class FareMatrixEditorScreen extends StatefulWidget {
  const FareMatrixEditorScreen({super.key});

  @override
  State<FareMatrixEditorScreen> createState() =>
      _FareMatrixEditorScreenState();
}

class _FareMatrixEditorScreenState extends State<FareMatrixEditorScreen> {
  bool _loading = true;
  bool _saving = false;

  // सेवा-अनुसारको आधार भाडा — `FareMatrixConfig.defaultBaseByService` कै
  // उही क्रम/keys मा (नयाँ सेवा थपिए त्यहीँ पनि थप्नुपर्छ)।
  final Map<String, TextEditingController> _baseCtrls = {
    for (final k in FareMatrixConfig.defaultBaseByService.keys)
      k: TextEditingController(),
  };
  final _perKmCtrl = TextEditingController();
  final _perMinuteCtrl = TextEditingController();
  final _minimumFareCtrl = TextEditingController();
  final _roundToCtrl = TextEditingController();
  final _nightMultiplierCtrl = TextEditingController();
  final _nightStartHourCtrl = TextEditingController();
  final _nightEndHourCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _baseCtrls.values) {
      c.dispose();
    }
    _perKmCtrl.dispose();
    _perMinuteCtrl.dispose();
    _minimumFareCtrl.dispose();
    _roundToCtrl.dispose();
    _nightMultiplierCtrl.dispose();
    _nightStartHourCtrl.dispose();
    _nightEndHourCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await FareMatrixConfig.readOnce();
    final base = data['baseByService'];
    final baseMap = base is Map
        ? base.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    for (final entry in _baseCtrls.entries) {
      final saved = baseMap[entry.key];
      final fallback = FareMatrixConfig.defaultBaseByService[entry.key] ?? 0;
      entry.value.text = ((saved as num?)?.toInt() ?? fallback).toString();
    }
    _perKmCtrl.text =
        ((data['perKm'] as num?)?.toInt() ?? FareMatrixConfig.defaultPerKm)
            .toString();
    _perMinuteCtrl.text = ((data['perMinute'] as num?)?.toInt() ??
            FareMatrixConfig.defaultPerMinute)
        .toString();
    _minimumFareCtrl.text = ((data['minimumFare'] as num?)?.toInt() ??
            FareMatrixConfig.defaultMinimumFare)
        .toString();
    _roundToCtrl.text = ((data['roundTo'] as num?)?.toInt() ??
            FareMatrixConfig.defaultRoundTo)
        .toString();
    _nightMultiplierCtrl.text = ((data['nightSurchargeMultiplier'] as num?)
                ?.toDouble() ??
            FareMatrixConfig.defaultNightSurchargeMultiplier)
        .toString();
    _nightStartHourCtrl.text = ((data['nightStartHour'] as num?)?.toInt() ??
            FareMatrixConfig.defaultNightStartHour)
        .toString();
    _nightEndHourCtrl.text = ((data['nightEndHour'] as num?)?.toInt() ??
            FareMatrixConfig.defaultNightEndHour)
        .toString();
    if (mounted) setState(() => _loading = false);
  }

  int _parse(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  double _parseDouble(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim()) ?? fallback;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final baseByService = {
        for (final entry in _baseCtrls.entries)
          entry.key: _parse(
              entry.value, FareMatrixConfig.defaultBaseByService[entry.key]!),
      };
      await FareMatrixConfig.setMatrix(
        baseByService: baseByService,
        perKm: _parse(_perKmCtrl, FareMatrixConfig.defaultPerKm),
        perMinute: _parse(_perMinuteCtrl, FareMatrixConfig.defaultPerMinute),
        minimumFare:
            _parse(_minimumFareCtrl, FareMatrixConfig.defaultMinimumFare),
        roundTo: _parse(_roundToCtrl, FareMatrixConfig.defaultRoundTo),
        nightSurchargeMultiplier: _parseDouble(_nightMultiplierCtrl,
            FareMatrixConfig.defaultNightSurchargeMultiplier),
        nightStartHour:
            _parse(_nightStartHourCtrl, FareMatrixConfig.defaultNightStartHour),
        nightEndHour:
            _parse(_nightEndHourCtrl, FareMatrixConfig.defaultNightEndHour),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numberField(String label, TextEditingController ctrl,
          {String? prefix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.kmText),
          decoration: kmInputDecoration(label,
              suffixIcon: prefix == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(prefix,
                            style:
                                const TextStyle(color: AppColors.kmMuted)),
                      ),
                    )),
        ),
      );

  // Night surcharge multiplier जस्तो दशमलव (1.25) चाहिने field — माथिको
  // `_numberField` ले `digitsOnly` formatter लगाएर दशमलव बिन्दु नै रोक्छ।
  Widget _decimalField(String label, TextEditingController ctrl,
          {String? prefix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          style: const TextStyle(color: AppColors.kmText),
          decoration: kmInputDecoration(label,
              suffixIcon: prefix == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(prefix,
                            style:
                                const TextStyle(color: AppColors.kmMuted)),
                      ),
                    )),
        ),
      );

  String _serviceLabel(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(
                  title: 'Fare Management',
                  actions: [
                    GlassIconButton(
                      icon: Icons.save_rounded,
                      tooltip: 'Save',
                      onTap: _saving || _loading ? null : _save,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.kmOrange))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        children: [
                          const KmSectionLabel('Global rate'),
                          _numberField('Per-km rate', _perKmCtrl,
                              prefix: 'Rs./km'),
                          _numberField('Per-minute rate', _perMinuteCtrl,
                              prefix: 'Rs./min'),
                          _numberField('Minimum fare', _minimumFareCtrl,
                              prefix: 'Rs.'),
                          _numberField(
                              'Round to nearest', _roundToCtrl,
                              prefix: 'Rs.'),
                          const KmSectionLabel('Night surcharge'),
                          _decimalField(
                              'Multiplier', _nightMultiplierCtrl,
                              prefix: '×'),
                          _numberField(
                              'Start hour (24h)', _nightStartHourCtrl,
                              prefix: 'hr'),
                          _numberField(
                              'End hour (24h)', _nightEndHourCtrl,
                              prefix: 'hr'),
                          const SizedBox(height: 4),
                          const Text(
                            'Fares get multiplied by this during the night '
                            'window (wraps past midnight if start > end, '
                            'e.g. 21 → 6).',
                            style: TextStyle(
                                color: AppColors.kmMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          const KmSectionLabel('Base fare by service'),
                          for (final key in _baseCtrls.keys)
                            _numberField(
                                _serviceLabel(key), _baseCtrls[key]!,
                                prefix: 'Rs.'),
                          const SizedBox(height: 10),
                          const Text(
                            'Fare = base + (distance km × per-km) + '
                            '(duration min × per-minute), rounded, then '
                            'clamped to at least the minimum fare.',
                            style: TextStyle(
                                color: AppColors.kmMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 24),
                          KmCtaButton(
                            label: _saving ? 'Saving…' : 'Save',
                            icon: Icons.save_rounded,
                            loading: _saving,
                            onPressed: _saving ? null : _save,
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
}
