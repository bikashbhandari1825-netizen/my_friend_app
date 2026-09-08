// auth/otp_verification_page.dart
// SMS बाट आएको 6-अंकको code हालेर Firebase बाट verify → app भित्र।
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../widgets/app_ui.dart';
import 'dev_login.dart';

class OtpVerificationPage extends StatefulWidget {
  final String phone;

  /// Web बाट आएको confirmation (signInWithPhoneNumber ले फर्काएको)।
  final ConfirmationResult? confirmationResult;

  /// Mobile बाट आएको verificationId (verifyPhoneNumber → codeSent)।
  final String? verificationId;

  /// नि:शुल्क test bypass — code मिले Anonymous sign-in।
  final bool testMode;

  const OtpVerificationPage({
    super.key,
    required this.phone,
    this.confirmationResult,
    this.verificationId,
    this.testMode = false,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _controller = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      _snack(S.enterOtp);
      return;
    }
    setState(() => _verifying = true);
    try {
      if (widget.testMode) {
        if (code != kTestCode) {
          setState(() => _verifying = false);
          _snack(S.otpFailed);
          return;
        }
        await devTestSignIn();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const KaamMitraApp()),
          (_) => false,
        );
        return;
      }

      if (widget.confirmationResult != null) {
        await widget.confirmationResult!.confirm(code);
      } else if (widget.verificationId != null) {
        final cred = PhoneAuthProvider.credential(
          verificationId: widget.verificationId!,
          smsCode: code,
        );
        await FirebaseAuth.instance.signInWithCredential(cred);
      } else {
        _snack(S.otpFailed);
        setState(() => _verifying = false);
        return;
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const KaamMitraApp()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      if (e.code == 'admin-restricted-operation' ||
          e.code == 'operation-not-allowed') {
        _snack(widget.testMode ? S.anonNotEnabled : S.phoneAuthNotEnabled);
      } else {
        _snack('${S.otpFailed}\n${e.message ?? e.code}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
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
              Text(S.otpTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(S.otpSentTo(widget.phone),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  labelText: S.otpCodeLabel,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: S.verify,
                icon: Icons.check_rounded,
                loading: _verifying,
                onPressed: _verify,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(S.wrongNumber),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
