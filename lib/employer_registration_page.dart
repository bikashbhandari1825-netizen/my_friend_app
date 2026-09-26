// employer_registration_page.dart
// रोजगारदाता (Employer) को छुट्टै दर्ता — नाम, फोन, GPS स्थान → सिधै app मा।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth/dev_login.dart';
import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart' show LocationField;
import 'widgets/glass_ui.dart';

class EmployerRegistrationPage extends StatefulWidget {
  const EmployerRegistrationPage({super.key});

  @override
  State<EmployerRegistrationPage> createState() =>
      _EmployerRegistrationPageState();
}

class _EmployerRegistrationPageState extends State<EmployerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  double? _lat;
  double? _lng;
  bool _saving = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'name': '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
        'phone': _phone.text.trim().isEmpty
            ? (user.phoneNumber ?? '')
            : _phone.text.trim(),
        'email': user.email ?? '',
        'role': 'employer',
        'accountStatus': 'active',
        'verificationStatus': 'none',
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': true,
        if (_lat != null && _lng != null) ...{
          'lat': _lat,
          'lng': _lng,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      // नयाँ KaamMitraApp() नबनाउने — same rootNavigatorKey collision bug
      // (देख्नुहोस् email_auth_page.dart मा विस्तृत note)। profileComplete
      // लेखेपछि root कै users-doc StreamBuilder ले आफैं सही screen देखाउँछ।
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${S.errorWord}: $e')));
    }
  }

  Future<void> _exit() async {
    await signOutClean();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topRight, AppColors.kmPink),
        KmOrb(Alignment.bottomLeft, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: KmScreenHeader(
                  title: S.employerRegTitle,
                  onBack: _saving
                      ? () {}
                      : () => canGoBack ? Navigator.pop(context) : _exit(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: GlassPanel(
                    radius: 28,
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [
                                AppColors.kmRose,
                                AppColors.kmPink
                              ]),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.badge_rounded,
                                color: AppColors.kmInk, size: 30),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _firstName,
                            style: const TextStyle(color: AppColors.kmText),
                            decoration: kmInputDecoration(S.firstName),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? S.enterName
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _lastName,
                            style: const TextStyle(color: AppColors.kmText),
                            decoration: kmInputDecoration(S.lastName),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? S.enterName
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: AppColors.kmText),
                            decoration: kmInputDecoration(S.phone),
                            validator: (v) => (v == null || v.trim().length < 7)
                                ? S.enterPhone
                                : null,
                          ),
                          const SizedBox(height: 20),
                          Text(S.locationSection,
                              style: const TextStyle(
                                  color: AppColors.kmText,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          LocationField(
                            onChanged: (lat, lng) => setState(() {
                              _lat = lat;
                              _lng = lng;
                            }),
                          ),
                          const SizedBox(height: 26),
                          KmCtaButton(
                            label: S.next,
                            loading: _saving,
                            onPressed: _submit,
                          ),
                        ],
                      ),
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
