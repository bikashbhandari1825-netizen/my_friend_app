// screens/edit_profile_page.dart
// Optional profile editing — First name/Last name/Email जहिले पनि Profile
// tab बाट स्वेच्छाले अपडेट गर्न। OTP login पछि अब कुनै पनि forced फारम
// छैन (otp_verification_page.dart::_afterSignIn हेर्नुहोस्) — नाम/इमेल
// यहीं, आफ्नै समयमा थप्ने/बदल्ने।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/futuristic_ui.dart';

class EditProfilePage extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;

  const EditProfilePage({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final _firstName = TextEditingController(text: widget.firstName);
  late final _lastName = TextEditingController(text: widget.lastName);
  late final _email = TextEditingController(text: widget.email);
  bool _saving = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final first = _firstName.text.trim();
      final last = _lastName.text.trim();
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': first,
        'lastName': last,
        'name': '$first $last'.trim(),
        'email': _email.text.trim(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
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
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(title: 'Edit Profile'),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: NeonCard(
                    radius: 28,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _firstName,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration(S.firstName),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _lastName,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration(S.surnameLabel),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: AppColors.kmText),
                          decoration: kmInputDecoration(S.emailLabel),
                        ),
                        const SizedBox(height: 22),
                        KmCtaButton(
                          label: S.save,
                          loading: _saving,
                          onPressed: _saving ? () {} : _save,
                        ),
                      ],
                    ),
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
