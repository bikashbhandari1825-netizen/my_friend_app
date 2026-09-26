// auth/otp_verification_page.dart
// SMS बाट आएको 6-अंकको code हालेर Firebase बाट verify → app भित्र।
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
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

  /// Android SMS auto-retrieval ले `verifyPhoneNumber()`'s
  /// `verificationCompleted` मार्फत आफैं तयार पारेको credential — दिइएको भए
  /// यो पेज खुल्नेबित्तिकै आफैं verify गर्छ (प्रयोगकर्ताले केही टाइप गर्नु
  /// पर्दैन)। स्थायी नियम: sign-in "पूरा भयो, home फर्कने" भन्ने अन्तिम
  /// निर्णय सधैँ यही पेजले मात्र गर्छ — `phone_input_page.dart` ले कहिल्यै
  /// आफैं सिधै sign-in/pop गर्दैन (देख्नुहोस् त्यहाँको `_goOtp` doc-comment)।
  final PhoneAuthCredential? autoCredential;

  const OtpVerificationPage({
    super.key,
    required this.phone,
    this.confirmationResult,
    this.verificationId,
    this.testMode = false,
    this.existingAccount = false,
    this.autoCredential,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _controller = TextEditingController();
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    final cred = widget.autoCredential;
    if (cred != null) {
      // build() भित्रैबाट होइन, पहिलो frame पूरा भएपछि मात्र — context यो
      // बेलासम्म पूर्ण रूपमा mount भइसकेको ग्यारेन्टी हुन्छ।
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _completeWithCredential(cred));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Android SMS auto-retrieval बाट पहिल्यै तयार भएको credential — यहीं मात्र
  /// (phone_input_page.dart ले होइन) verify + "home फर्कने" निर्णय गर्ने।
  Future<void> _completeWithCredential(PhoneAuthCredential cred) async {
    if (!mounted || _verifying) return;
    setState(() => _verifying = true);
    try {
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (!mounted) return;
      // नयाँ KaamMitraApp() नबनाउने — same rootNavigatorKey collision bug
      // (देख्नुहोस् email_auth_page.dart मा विस्तृत note)।
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack('${S.otpFailed}\n${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack('${S.otpFailed}\n$e');
    }
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
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.maybePop(context),
                  ),
                ),
                const SizedBox(height: 16),
                Text(widget.existingAccount ? S.welcomeBack : S.otpTitle,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                    widget.existingAccount
                        ? S.loginToExisting
                        : S.otpSentTo(widget.phone),
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 13)),
                const SizedBox(height: 24),
                GlassPanel(
                  radius: AppRadius.lg,
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
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
                            color: AppColors.kmText,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 12),
                        decoration: kmInputDecoration(S.otpCodeLabel,
                                hint: '••••••')
                            .copyWith(counterText: ''),
                        onSubmitted: (_) => _verify(),
                      ),
                      const SizedBox(height: 18),
                      KmCtaButton(
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
                      style: const TextStyle(color: AppColors.kmMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
