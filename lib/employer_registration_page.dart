// employer_registration_page.dart
// रोजगारदाता (Employer) को छुट्टै दर्ता — नाम, फोन, GPS स्थान → सिधै app मा।
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth/dev_login.dart';
import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import 'widgets/app_ui.dart';

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
    return Scaffold(
      appBar: gradientAppBar(
        S.employerRegTitle,
        leading: IconButton(
          icon:
              Icon(canGoBack ? Icons.arrow_back_rounded : Icons.logout_rounded),
          tooltip: canGoBack ? null : S.logOut,
          onPressed: _saving
              ? null
              : () => canGoBack ? Navigator.pop(context) : _exit(),
        ),
      ),
      body: AppGradientBackground(
        glows: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LimeIconBadge(Icons.badge_rounded,
                        size: 56, solid: true),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _firstName,
                      decoration: InputDecoration(labelText: S.firstName),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? S.enterName : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _lastName,
                      decoration: InputDecoration(labelText: S.lastName),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? S.enterName : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: S.phone),
                      validator: (v) => (v == null || v.trim().length < 7)
                          ? S.enterPhone
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Text(S.locationSection,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    LocationField(
                      onChanged: (lat, lng) => setState(() {
                        _lat = lat;
                        _lng = lng;
                      }),
                    ),
                    const SizedBox(height: 26),
                    PrimaryButton(
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
      ),
    );
  }
}
