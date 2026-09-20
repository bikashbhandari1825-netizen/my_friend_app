// auth/otp_verification_page.dart
// SMS बाट आएको 6-अंकको code हालेर Firebase बाट verify → app भित्र।
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
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

  /// यो नम्बरसँग पहिले account छ (login) कि नयाँ (signup)?
  final bool existingAccount;

  const OtpVerificationPage({
    super.key,
    required this.phone,
    this.confirmationResult,
    this.verificationId,
    this.testMode = false,
    this.existingAccount = false,
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
        await devTestSignIn(widget.phone);
        if (!mounted) return;
        // नयाँ KaamMitraApp() नबनाउने — same rootNavigatorKey collision bug
        // (देख्नुहोस् email_auth_page.dart मा विस्तृत note)।
        Navigator.of(context).popUntil((route) => route.isFirst);
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
      Navigator.of(context).popUntil((route) => route.isFirst);
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
                Text(widget.existingAccount ? S.welcomeBack : S.otpTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 10)
                        ])),
                const SizedBox(height: 8),
                Text(
                    widget.existingAccount
                        ? S.loginToExisting
                        : S.otpSentTo(widget.phone),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
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
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: S.verify,
                        icon: Icons.check_rounded,
                        loading: _verifying,
                        onPressed: _verify,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(S.wrongNumber,
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
