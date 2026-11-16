// screens/salon_registration_screen.dart
//
// Salon / Beauty provider दर्ता — "Earn with Us" → Salon / Beauty Provider।
// मालिक = `salons/{id}.ownerId` (firestore.rules ले आफ्नै uid मात्र दिन्छ);
// कुनै self-writable partner list छैन। दर्ता भएपछि सिधै Partner Dashboard मा।
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../models/salon_models.dart';
import '../services/salon_partner_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import 'salon_common.dart';
import 'salon_partner_dashboard_screen.dart';
import '../widgets/futuristic_ui.dart';

class SalonRegistrationScreen extends StatefulWidget {
  const SalonRegistrationScreen({super.key});

  @override
  State<SalonRegistrationScreen> createState() =>
      _SalonRegistrationScreenState();
}

class _SalonRegistrationScreenState extends State<SalonRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = kSalonCategories.first;
  SalonPickedImage? _logo;
  SalonPickedImage? _cover;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await createSalon(
        name: _nameCtrl.text,
        category: _category,
        address: _addressCtrl.text,
        phone: _phoneCtrl.text,
        description: _descCtrl.text,
      );
      // Logo अपलोड असफल भए पनि दर्ता रोकिँदैन — dashboard को Profile मा फेरि राख्न मिल्छ।
      var photoFailed = false;
      final logo = _logo;
      if (logo != null) {
        try {
          final url = await uploadSalonImage(id, 'logo', logo.bytes, logo.name);
          await setSalonLogo(id, url);
        } catch (_) {
          photoFailed = true;
        }
      }
      final cover = _cover;
      if (cover != null) {
        try {
          final url =
              await uploadSalonImage(id, 'cover', cover.bytes, cover.name);
          await setSalonCover(id, url);
        } catch (_) {
          photoFailed = true;
        }
      }
      if (photoFailed && mounted) {
        salonSnack(context,
            'Salon registered, but a photo could not be uploaded. Add it again from Profile.');
      }
      if (!mounted) return;
      // दर्ता फारम पछाडि नफर्कियोस् — dashboard ले यसलाई प्रतिस्थापन गर्छ।
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SalonPartnerDashboardScreen(salonId: id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      salonSnack(context, 'Could not register your salon: $e');
    }
  }

  /// Test Helper — `!kReleaseMode` (release APK मा कहिल्यै देखिँदैन)।
  Future<void> _createSample() async {
    setState(() => _saving = true);
    try {
      final id = await createSampleSalon();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SalonPartnerDashboardScreen(salonId: id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      salonSnack(context, 'Could not create the sample salon: $e');
    }
  }

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
                child: KmScreenHeader(title: 'Register your salon'),
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      const Text(
                          'List your salon, barbershop or beauty studio. After registering you can add services, team members and working hours, and start taking appointments.',
                          style: TextStyle(
                              color: AppColors.kmMuted,
                              fontSize: 12.5,
                              height: 1.4)),
                      const SizedBox(height: 16),
                      SalonPhotoField(
                        label: 'logo',
                        currentUrl: '',
                        icon: Icons.storefront_rounded,
                        onChanged: (p, _) => _logo = p,
                      ),
                      const SizedBox(height: 12),
                      SalonPhotoField(
                        label: 'cover / banner photo',
                        currentUrl: '',
                        icon: Icons.image_rounded,
                        onChanged: (p, _) => _cover = p,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                          'New salons are reviewed by our team before they appear to customers. You can add services, team and portfolio photos while you wait.',
                          style: TextStyle(
                              color: AppColors.kmMuted,
                              fontSize: 12,
                              height: 1.4)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameCtrl,
                        style: const TextStyle(color: AppColors.kmText),
                        decoration: kmInputDecoration('Business name'),
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Enter your business name'
                            : null,
                      ),
                      salonSectionLabel('CATEGORY'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in kSalonCategories)
                            ChoiceChip(
                              label: Text(c),
                              selected: _category == c,
                              onSelected: (_) => setState(() => _category = c),
                              selectedColor: AppColors.kmOrange,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              labelStyle: TextStyle(
                                  color: _category == c
                                      ? AppColors.kmInk
                                      : AppColors.kmText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressCtrl,
                        style: const TextStyle(color: AppColors.kmText),
                        decoration: kmInputDecoration('Address / area'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your address'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: AppColors.kmText),
                        decoration: kmInputDecoration('Contact phone'),
                        validator: (v) => (v == null || v.trim().length < 7)
                            ? 'Enter a valid phone number'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 3,
                        style: const TextStyle(color: AppColors.kmText),
                        decoration:
                            kmInputDecoration('About your business (optional)'),
                      ),
                      const SizedBox(height: 22),
                      KmCtaButton(
                        label: 'Register salon',
                        icon: Icons.check_circle_rounded,
                        loading: _saving,
                        onPressed: _saving ? null : _submit,
                      ),
                      if (!kReleaseMode) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _createSample,
                          icon: const Text('🧪'),
                          label: const Text('Create sample salon (Test only)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.kmOrange,
                            side: BorderSide(
                                color:
                                    AppColors.kmOrange.withValues(alpha: 0.4)),
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
