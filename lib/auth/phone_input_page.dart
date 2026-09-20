// auth/phone_input_page.dart
// देश code छान्ने + फोन नम्बर → Firebase बाट OTP पठाउने।
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'dev_login.dart';
import 'email_auth_page.dart';
import 'otp_verification_page.dart';

class _Country {
  final String flag;
  final String name;
  final String dial;
  const _Country(this.flag, this.name, this.dial);
}

const List<_Country> _countries = [
  _Country('🇳🇵', 'Nepal', '+977'),
  _Country('🇮🇳', 'India', '+91'),
  _Country('🇺🇸', 'USA', '+1'),
  _Country('🇬🇧', 'UK', '+44'),
  _Country('🇦🇺', 'Australia', '+61'),
  _Country('🇦🇪', 'UAE', '+971'),
  _Country('🇶🇦', 'Qatar', '+974'),
  _Country('🇲🇾', 'Malaysia', '+60'),
  _Country('🇰🇷', 'South Korea', '+82'),
  _Country('🇸🇦', 'Saudi Arabia', '+966'),
];

class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});

  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  final _controller = TextEditingController();
  _Country _country = _countries.first;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _e164 {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    return '${_country.dial}$digits';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goOtp({
    ConfirmationResult? confirmationResult,
    String? verificationId,
    bool testMode = false,
    required bool existing,
    required String phone,
  }) {
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpVerificationPage(
          phone: phone,
          confirmationResult: confirmationResult,
          verificationId: verificationId,
          testMode: testMode,
          existingAccount: existing,
        ),
      ),
    );
  }

  Future<void> _continue() async {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      _snack(S.enterValidPhone);
      return;
    }
    final phone = _e164;
    setState(() => _sending = true);

    // यो नम्बरसँग पहिले account छ कि? (login vs signup देखाउन)
    final existing = await phoneAccountExists(phone);
    if (!mounted) return;

    // टेस्टिङ चरणमा साँचो Firebase Phone Auth (SMS + web reCAPTCHA) सिधै
    // छुँदैनौं — त्यही नै "अड्किने/break वा loop हुने" गुनासोको मूल कारण
    // थियो (reCAPTCHA popup-block, unauthorized domain, दोस्रोपटक "already
    // rendered" त्रुटि आदि)। सिधै अन्तर्निहित नि:शुल्क test-mode मा जाने —
    // बटन/screen उस्तै काम गर्छन्, केवल SMS चाहिँदैन। kUseRealPhoneSms
    // (config/app_config.dart) लाई `true` पारेपछि मात्र तलको साँचो-SMS
    // बाटो फेरि प्रयोग हुन्छ।
    if (!kUseRealPhoneSms) {
      _goOtp(testMode: true, existing: existing, phone: phone);
      return;
    }

    // साँचो Phone Auth कोसिस; enable नभए / असफल भए फेरि नि:शुल्क test-mode।
    try {
      if (kIsWeb) {
        final result = await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        _goOtp(confirmationResult: result, existing: existing, phone: phone);
        return;
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          if (!mounted) return;
          // नयाँ KaamMitraApp() नबनाउने — same rootNavigatorKey collision bug
          // (देख्नुहोस् email_auth_page.dart मा विस्तृत note)।
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        verificationFailed: (_) =>
            _goOtp(testMode: true, existing: existing, phone: phone),
        codeSent: (verificationId, __) => _goOtp(
            verificationId: verificationId, existing: existing, phone: phone),
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (_) {
      // Phone sign-in enable छैन / reCAPTCHA fail → test-mode मा झर्ने
      _goOtp(testMode: true, existing: existing, phone: phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: AppGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(S.phoneInputTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 10)
                        ])),
                const SizedBox(height: 8),
                Text(S.phoneInputSub,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13)),
                const SizedBox(height: 20),
                // Glass card holding the inputs
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: DropdownButtonFormField<_Country>(
                              initialValue: _country,
                              isExpanded: true,
                              decoration:
                                  InputDecoration(labelText: S.countryCode),
                              items: _countries
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text('${c.flag} ${c.dial}',
                                            overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (c) => setState(() => _country = c!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              keyboardType: TextInputType.phone,
                              autofocus: true,
                              decoration: InputDecoration(
                                  labelText: S.phoneNumberLabel),
                              onSubmitted: (_) => _continue(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${_country.name}  ·  ${_country.dial}',
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Free test login → any number, code: $kTestCode\n'
                    'Same number always signs into the same account.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: S.continueWord,
                  icon: Icons.arrow_forward_rounded,
                  loading: _sending,
                  onPressed: _continue,
                ),
                TextButton.icon(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const EmailAuthPage()),
                  ),
                  icon: const Icon(Icons.mail_outline_rounded,
                      color: Colors.white70, size: 18),
                  label: Text(S.useEmailInstead,
                      style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
