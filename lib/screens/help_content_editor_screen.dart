// screens/help_content_editor_screen.dart
// Admin (Owner Dashboard) ले Help & Support screen भित्रका सबै लामो
// content (Service Standard, FAQ, Privacy Policy, Data Security) कुनै
// नयाँ app release बिनै सिधै सम्पादन गर्ने ठाउँ — Firestore:
// config/helpContent (हेर्नुहोस् config/app_config.dart::HelpContentConfig)।
// पहिलोपटक खोल्दा अहिलेकै मूल (`LegalText`) copy pre-fill हुन्छ, सम्पादन
// नगरेको field खाली/छोटो नरहोस् भनेर।
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../content/legal_text.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class HelpContentEditorScreen extends StatefulWidget {
  const HelpContentEditorScreen({super.key});

  @override
  State<HelpContentEditorScreen> createState() =>
      _HelpContentEditorScreenState();
}

class _FaqDraft {
  final qEn = TextEditingController();
  final qNe = TextEditingController();
  final aEn = TextEditingController();
  final aNe = TextEditingController();

  void dispose() {
    qEn.dispose();
    qNe.dispose();
    aEn.dispose();
    aNe.dispose();
  }
}

class _HelpContentEditorScreenState extends State<HelpContentEditorScreen> {
  bool _loading = true;
  bool _saving = false;

  final _ssEn = TextEditingController();
  final _ssNe = TextEditingController();
  final _ppEn = TextEditingController();
  final _ppNe = TextEditingController();
  final _dsEn = TextEditingController();
  final _dsNe = TextEditingController();
  final List<_FaqDraft> _faqs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ssEn.dispose();
    _ssNe.dispose();
    _ppEn.dispose();
    _ppNe.dispose();
    _dsEn.dispose();
    _dsNe.dispose();
    for (final f in _faqs) {
      f.dispose();
    }
    super.dispose();
  }

  String _field(Map<String, dynamic> data, String key, String fallback) {
    final v = (data[key] ?? '').toString();
    return v.trim().isEmpty ? fallback : v;
  }

  Future<void> _load() async {
    final data = await HelpContentConfig.once();
    _ssEn.text = _field(data, 'serviceStandardEn', LegalText.serviceStandardEn);
    _ssNe.text = _field(data, 'serviceStandardNe', LegalText.serviceStandardNe);
    _ppEn.text = _field(data, 'privacyPolicyEn', LegalText.privacyPolicyEn);
    _ppNe.text = _field(data, 'privacyPolicyNe', LegalText.privacyPolicyNe);
    _dsEn.text = _field(data, 'dataSecurityEn', LegalText.dataSecurityEn);
    _dsNe.text = _field(data, 'dataSecurityNe', LegalText.dataSecurityNe);

    final rawFaq = data['faq'];
    _faqs.clear();
    if (rawFaq is List && rawFaq.isNotEmpty) {
      for (final e in rawFaq) {
        final m = Map<String, dynamic>.from(e as Map);
        final d = _FaqDraft();
        d.qEn.text = (m['qEn'] ?? '').toString();
        d.qNe.text = (m['qNe'] ?? '').toString();
        d.aEn.text = (m['aEn'] ?? '').toString();
        d.aNe.text = (m['aNe'] ?? '').toString();
        _faqs.add(d);
      }
    } else {
      for (final e in LegalText.faqDefaults) {
        final d = _FaqDraft();
        d.qEn.text = e.qEn;
        d.qNe.text = e.qNe;
        d.aEn.text = e.aEn;
        d.aNe.text = e.aNe;
        _faqs.add(d);
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _addFaq() => setState(() => _faqs.add(_FaqDraft()));

  void _removeFaq(int i) {
    final removed = _faqs.removeAt(i);
    removed.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await HelpContentConfig.saveAll({
        'serviceStandardEn': _ssEn.text.trim(),
        'serviceStandardNe': _ssNe.text.trim(),
        'privacyPolicyEn': _ppEn.text.trim(),
        'privacyPolicyNe': _ppNe.text.trim(),
        'dataSecurityEn': _dsEn.text.trim(),
        'dataSecurityNe': _dsNe.text.trim(),
        'faq': _faqs
            .where((f) =>
                f.qEn.text.trim().isNotEmpty || f.qNe.text.trim().isNotEmpty)
            .map((f) => {
                  'qEn': f.qEn.text.trim(),
                  'qNe': f.qNe.text.trim(),
                  'aEn': f.aEn.text.trim(),
                  'aNe': f.aNe.text.trim(),
                })
            .toList(),
      });
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

  Widget _sectionTitle(String text) => KmSectionLabel(text);

  Widget _bilingualField(String label, TextEditingController ctrl) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          maxLines: null,
          minLines: 3,
          style: const TextStyle(color: AppColors.kmText),
          decoration: kmInputDecoration(label),
        ),
      );

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
                  title: 'Help Content',
                  actions: [
                    GlassIconButton(
                      icon: Icons.save_rounded,
                      tooltip: 'Save All',
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
                          _sectionTitle('Service Standard'),
                          _bilingualField('English', _ssEn),
                          _bilingualField('नेपाली', _ssNe),
                          _sectionTitle('Privacy Policy'),
                          _bilingualField('English', _ppEn),
                          _bilingualField('नेपाली', _ppNe),
                          _sectionTitle('Data Security'),
                          _bilingualField('English', _dsEn),
                          _bilingualField('नेपाली', _dsNe),
                          _sectionTitle('FAQ'),
                          for (var i = 0; i < _faqs.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassPanel(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('FAQ #${i + 1}',
                                            style: const TextStyle(
                                                color: AppColors.kmText,
                                                fontWeight:
                                                    FontWeight.w700)),
                                        const Spacer(),
                                        GlassIconButton(
                                          icon: Icons
                                              .delete_outline_rounded,
                                          iconColor: AppColors.kmRose,
                                          size: 36,
                                          onTap: () => _removeFaq(i),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _faqs[i].qEn,
                                      style: const TextStyle(
                                          color: AppColors.kmText),
                                      decoration: kmInputDecoration(
                                          'Question (English)'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _faqs[i].qNe,
                                      style: const TextStyle(
                                          color: AppColors.kmText),
                                      decoration: kmInputDecoration(
                                          'प्रश्न (नेपाली)'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _faqs[i].aEn,
                                      maxLines: null,
                                      minLines: 2,
                                      style: const TextStyle(
                                          color: AppColors.kmText),
                                      decoration: kmInputDecoration(
                                          'Answer (English)'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _faqs[i].aNe,
                                      maxLines: null,
                                      minLines: 2,
                                      style: const TextStyle(
                                          color: AppColors.kmText),
                                      decoration: kmInputDecoration(
                                          'उत्तर (नेपाली)'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.kmText,
                              side:
                                  BorderSide(color: AppColors.kmGlassBorder),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(999)),
                            ),
                            onPressed: _addFaq,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add FAQ'),
                          ),
                          const SizedBox(height: 24),
                          KmCtaButton(
                            label: _saving ? 'Saving…' : 'Save All',
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
