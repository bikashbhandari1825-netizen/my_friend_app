// auth/phone_input_page.dart
// देश code छान्ने + फोन नम्बर → Firebase बाट OTP पठाउने।
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../widgets/app_ui.dart';
import 'dev_login.dart';
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

  Future<void> _continue() async {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      _snack(S.enterValidPhone);
      return;
    }
    final phone = _e164;
    setState(() => _sending = true);

    // Test नम्बर: पहिले real phone-auth कोसिस (console मा test number राखेको भए
    // SMS/reCAPTCHA बिनै चल्छ)। असफल भए Anonymous test-mode मा झर्ने।
    if (isTestPhone(phone)) {
      try {
        final result =
            await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        if (!mounted) return;
        setState(() => _sending = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationPage(
                phone: phone, confirmationResult: result),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _sending = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                OtpVerificationPage(phone: phone, testMode: true),
          ),
        );
      }
      return;
    }

    try {
      if (kIsWeb) {
        final result =
            await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        if (!mounted) return;
        setState(() => _sending = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationPage(
              phone: phone,
              confirmationResult: result,
            ),
          ),
        );
      } else {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (cred) async {
            await FirebaseAuth.instance.signInWithCredential(cred);
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const KaamMitraApp()),
              (_) => false,
            );
          },
          verificationFailed: (e) {
            if (!mounted) return;
            setState(() => _sending = false);
            _snack('${S.otpFailed}\n${e.message ?? e.code}');
          },
          codeSent: (verificationId, _) {
            if (!mounted) return;
            setState(() => _sending = false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtpVerificationPage(
                  phone: phone,
                  verificationId: verificationId,
                ),
              ),
            );
          },
          codeAutoRetrievalTimeout: (_) {},
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      if (e.code == 'operation-not-allowed' ||
          e.code == 'admin-restricted-operation') {
        _snack(S.phoneAuthNotEnabled);
      } else {
        _snack('${S.otpFailed}\n${e.message ?? e.code}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _snack('${S.otpFailed}\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.phoneInputTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(S.phoneInputSub,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 128,
                    child: DropdownButtonFormField<_Country>(
                      initialValue: _country,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: S.countryCode),
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
                      decoration:
                          InputDecoration(labelText: S.phoneNumberLabel),
                      onSubmitted: (_) => _continue(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${_country.name}  ·  ${_country.dial}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Free test login → 🇳🇵 +977  $kTestPhoneHint   code: $kTestCode',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: S.continueWord,
                icon: Icons.arrow_forward_rounded,
                loading: _sending,
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
