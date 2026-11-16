// profile_registration_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';
import 'document_verification_page.dart';
import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

class ProfileRegistrationPage extends StatefulWidget {
  const ProfileRegistrationPage({super.key});

  @override
  State<ProfileRegistrationPage> createState() =>
      _ProfileRegistrationPageState();
}

class _ProfileRegistrationPageState extends State<ProfileRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();

  DateTime? _selectedDate;
  Uint8List?
      _photoBytes; // अहिलेलाई स्क्रिनमा मात्र देखाउने, Firebase मा save हुँदैन
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // यदि Google/Email बाट पहिल्यै इमेल थाहा भएमा त्यो पहिल्यै भरिदिने
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      _emailController.text = user!.email!;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _photoBytes = bytes;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('फोटो छान्न मिलेन: $e')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: S.dob,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.dobRequiredError)),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'dob': _selectedDate!.toIso8601String(),
        'profileComplete': true,
        // फोटो अहिले save हुँदैन; पछि Firebase Storage थपेपछि यहाँ 'photoUrl' थपिनेछ
      }, SetOptions(merge: true));

      if (!mounted) return;

// Firestore बाट role निकालेर जाँच्ने
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final role = userDoc.data()?['role'];

      if (role == 'worker') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const DocumentVerificationPage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const KaamMitraApp()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटि: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2027-स्तरको Glassmorphism Redesign — पहिले यहाँ सपाट solid violet
    // background + सेतो Material card थियो (बाँकी एपको glass भाषासँग
    // मेल नखाने)। अब `AuroraBackground` (ambient glow) + `GlassPanel`
    // (frosted card) + `kmInputDecoration` (अरू auth/registration स्क्रिन
    // सबैले प्रयोग गर्ने उही glass input style) + `KmCtaButton` — केवल
    // visual/structural मात्र बदलिएको, Firestore write/validation/routing
    // लजिक जस्ताको-त्यस्तै अपरिवर्तित।
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(S.profileRegistrationTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.kmText,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 24),

                  // Glass Profile-Photo Picker — frosted ring + भित्र
                  // camera icon/तस्बिर, बाँकी एपकै glass भाषामा।
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.kmGlass2Fill,
                          border: Border.all(
                              color: AppColors.kmGlass2Border, width: 1.4),
                          image: _photoBytes != null
                              ? DecorationImage(
                                  image: MemoryImage(_photoBytes!),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        child: _photoBytes == null
                            ? const Icon(Icons.camera_alt_rounded,
                                size: 34, color: AppColors.kmText)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(S.addPhotoHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.kmMuted, fontSize: 12.5)),
                  const SizedBox(height: 24),

                  GlassPanel(
                    radius: AppRadius.lg,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _firstNameController,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration(S.firstName),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? S.firstNameRequiredError
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _lastNameController,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration(S.lastName),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? S.lastNameRequiredError
                              : null,
                        ),
                        const SizedBox(height: 14),

                        // Date of Birth
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: kmInputDecoration(S.dob,
                                suffixIcon: const Icon(
                                    Icons.calendar_today_rounded,
                                    color: AppColors.kmMuted,
                                    size: 18)),
                            child: Text(
                              _selectedDate == null
                                  ? S.pickDate
                                  : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                              style:
                                  const TextStyle(color: AppColors.kmText),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration(S.emailLabel),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? S.validEmailRequiredError
                              : null,
                        ),
                        const SizedBox(height: 22),

                        KmCtaButton(
                          label: S.next,
                          icon: Icons.arrow_forward_rounded,
                          loading: _isSaving,
                          onPressed: _isSaving ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
