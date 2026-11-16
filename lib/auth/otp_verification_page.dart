// auth/otp_verification_page.dart
// SMS बाट आएको 6-अंकको code हालेर Firebase बाट verify → app भित्र।
import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';
import '../widgets/success_feedback.dart' show playSuccessFeedback;
import 'account_confirmation_page.dart';
import 'dev_login.dart' show linkPhoneToUid;
import 'passkey_setup_page.dart';
import 'phone_format.dart' show friendlyPhoneAuthError;

class OtpVerificationPage extends StatefulWidget {
  final String phone;

  /// Web बाट आएको confirmation (signInWithPhoneNumber ले फर्काएको)।
  final ConfirmationResult? confirmationResult;

  /// Mobile बाट आएको verificationId (verifyPhoneNumber → codeSent)।
  final String? verificationId;

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
    this.existingAccount = false,
    this.autoCredential,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  // 6-Digit Glassmorphism PIN Boxes — पहिले यहाँ एउटै 6-अंक लामो TextField
  // थियो (letterSpacing ले अलग-अलग "देखिने" मात्र, साँचो 6 वटा अलग-अलग
  // frosted box होइन)। अब साँच्चै 6 वटा छुट्टाछुट्टै glass box — हरेकको
  // आफ्नै controller/FocusNode, एउटा अंक टाइप गर्नेबित्तिकै अर्को box मा
  // auto-advance, Backspace ले अघिल्लोमा फर्कने, र पूरै 6-अंक paste
  // (जस्तै SMS autofill) आए सबै box मा छरिने।
  static const _digitCount = 6;
  final _digitControllers =
      List.generate(_digitCount, (_) => TextEditingController());
  final _digitFocusNodes = List.generate(_digitCount, (_) => FocusNode());
  // CRASH FIX — पहिले तलको `KeyboardListener` ले यही `_digitFocusNodes[index]`
  // (TextField कै उही FocusNode) सिधै आफैं पनि प्रयोग गर्थ्यो। एउटै FocusNode
  // एकैचोटि दुई ठाउँमा (KeyboardListener आफैं + त्यसको descendant TextField)
  // bind हुँदा Flutter को focus tree ले त्यसलाई आफ्नै ancestor बनाउन खोज्छ —
  // live device मा ठ्याक्कै यही कारणले OTP page खुल्नेबित्तिकै
  // `FocusNode._reparent` अनन्त recursion मा गई Out-of-Memory भई पूरै app
  // ANR/crash हुन्थ्यो (कहिलेकाहीं मात्र, build timing-अनुसार — त्यसैले यो
  // अघि पत्ता नलागेको)। KeyboardListener लाई छुट्टै आफ्नै FocusNode दिंदा पनि
  // key event दुवैतिर उस्तै आउँछ — Flutter ले focus-tree ancestor हरू हुँदै
  // key event bubble गराउँछ, उही FocusNode instance साझा गर्नुपर्दैन।
  final _keyListenerNodes = List.generate(_digitCount, (_) => FocusNode());
  bool _verifying = false;
  bool _verified = false;

  String get _enteredCode => _digitControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    final cred = widget.autoCredential;
    if (cred != null) {
      // build() भित्रैबाट होइन, पहिलो frame पूरा भएपछि मात्र — context यो
      // बेलासम्म पूर्ण रूपमा mount भइसकेको ग्यारेन्टी हुन्छ।
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _completeWithCredential(cred));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _digitFocusNodes.first.requestFocus();
      });
    }
    for (final node in _digitFocusNodes) {
      node.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final n in _digitFocusNodes) {
      n.dispose();
    }
    for (final n in _keyListenerNodes) {
      n.dispose();
    }
    super.dispose();
  }

  /// एउटा box मा टाइप भयो (वा SMS/clipboard बाट पूरै code paste भयो)।
  void _onDigitChanged(int index, String value) {
    // Paste Handling — एकैचोटि धेरै अंक आए (OS ले SMS autofill/clipboard
    // paste गर्दा सामान्यतया यसरी नै आउँछ) — बाँकी box हरूमा क्रमैसँग छर्ने।
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (var i = 0; i < digits.length && index + i < _digitCount; i++) {
        _digitControllers[index + i].text = digits[i];
      }
      final nextIndex = (index + digits.length).clamp(0, _digitCount - 1);
      _digitFocusNodes[nextIndex].requestFocus();
      if (digits.length + index >= _digitCount) {
        FocusScope.of(context).unfocus();
        if (_enteredCode.length == _digitCount) _verify();
      }
      return;
    }
    if (value.isNotEmpty && index < _digitCount - 1) {
      _digitFocusNodes[index + 1].requestFocus();
    }
    if (value.isNotEmpty && index == _digitCount - 1) {
      FocusScope.of(context).unfocus();
    }
    if (_enteredCode.length == _digitCount) _verify();
  }

  /// Backspace हालेर खाली भएको box बाट अघिल्लोमा फर्कने — एउटा standard
  /// OTP-UX व्यवहार (Flutter को plain `onChanged` ले खाली भएको संकेत
  /// स्पष्ट रूपमा नदिने भएकोले `KeyboardListener`/`onKeyEvent` बाट)।
  void _onDigitKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _digitControllers[index].text.isEmpty &&
        index > 0) {
      _digitControllers[index - 1].clear();
      _digitFocusNodes[index - 1].requestFocus();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// साँचो Firebase Phone Auth (SMS) ले सफल sign-in पछि दिने uid लाई
  /// यही फोन नम्बरको `phoneAccounts` index सँग जोड्ने — कुनै पुरानो
  /// (legacy test-mode) uid यही नम्बरमा भेटिए त्यसको profile यहीं migrate
  /// हुन्छ (dev_login.dart::linkPhoneToUid हेर्नुहोस्)। Best-effort —
  /// असफल भए पनि sign-in आफैं कहिल्यै नरोकियोस्।
  Future<void> _linkIfNeeded(String? uid) async {
    if (uid == null) return;
    try {
      await linkPhoneToUid(widget.phone, uid);
    } catch (_) {}
  }

  /// Android SMS auto-retrieval बाट पहिल्यै तयार भएको credential — यहीं मात्र
  /// (phone_input_page.dart ले होइन) verify + "home फर्कने" निर्णय गर्ने।
  Future<void> _completeWithCredential(PhoneAuthCredential cred) async {
    if (!mounted || _verifying || _verified) return;
    setState(() => _verifying = true);
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(cred);
      await _linkIfNeeded(result.user?.uid);
      if (!mounted) return;
      await _completeSignIn(result.user?.uid);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack(friendlyPhoneAuthError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack('${S.otpFailed}\n$e');
    }
  }

  /// Smart Account Recognition + optional Passkey setup — OTP verify
  /// भइसकेपछि, checkmark animation पछि, home फर्कनुअघि। Firebase ले phone
  /// नम्बर अनुसार uid पहिल्यै निश्चित गरिदिन्छ (एउटै नम्बरले दुई फरक
  /// account हुँदैन) — त्यसैले यहाँ "कुन account" भन्ने host अस्पष्टता
  /// छैन, बरु "यो profile तपाईं नै हो?" भन्ने friendly trust-step मात्र,
  /// नाम भएको (फिर्ता आउने) प्रयोगकर्तालाई मात्र देखिने।
  ///
  /// साँचो नयाँ प्रयोगकर्ता (Firestore मा role नै नभएको) भए — पुरानो
  /// forced "First/Last name" फारम (EmployerRegistrationPage) देखाइँदैन;
  /// यहीं न्यूनतम doc (फोन नम्बर + role मात्र) लेखेर सिधै home। नाम/
  /// इमेल/फोटो पछि जहिले पनि Profile tab बाट ऐच्छिक रूपमा थप्न सकिन्छ।
  Future<void> _afterSignIn(String? uid) async {
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await ref.get();
      final data = doc.data();
      final existingName = (data?['name'] ?? '').toString().trim();
      if (existingName.isNotEmpty) {
        if (!mounted) return;
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => AccountConfirmationPage(name: existingName),
          ),
        );
        // "Change account" ले आफैं sign out + root मा pop गरिसक्छ —
        // त्यो बेला यहाँ अब अगाडि बढ्नु (Passkey/home) पर्दैन।
        if (confirmed != true) return;
      } else if (data == null || data['role'] == null) {
        final user = FirebaseAuth.instance.currentUser;
        await ref.set({
          'uid': uid,
          'phone': user?.phoneNumber ?? widget.phone,
          'role': 'employer',
          'accountStatus': 'active',
          'verificationStatus': 'none',
          'isVerified': false,
          'profileComplete': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Best-effort — Firestore पढ्न/लेख्न नसके पनि sign-in कहिल्यै
      // नरोकियोस्; root gate ले आवश्यक परे पुरानै fallback देखाउला।
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PasskeySetupPage()),
    );
  }

  /// Verify सफल भएको क्षणमा मात्र (checkmark-morph) — Smart Account
  /// Recognition/Passkey step हरू अघि छोटो "सफल भयो" feedback पहिल्यै
  /// देखाइदिने, haptic+chime सहित (`playSuccessFeedback()` — बाँकी एपकै
  /// उही success-feedback भाषा)।
  Future<void> _showSuccessAnimation() async {
    // AUTOFILL FIX (असली जड) — `AutofillGroup` र manifest कै
    // `importantForAutofill` दुवैले live device मा काम गरेन, किनभने
    // Flutter ले Android कै साँचो View-tree होइन, आफ्नै छुट्टै platform-
    // channel-based text-input connection प्रयोग गर्छ — Autofill
    // Framework ले त्यो नदेखी, केवल IME बाट bridge भएको typed value मात्र
    // देख्छ, र 6-PIN box हरू disappear/dispose हुनेबित्तिकै (verify
    // सफल भएपछि field हरू बन्द हुँदा) त्यसलाई "login form submit भयो,
    // save गर्ने?" ठानेर आफैं commit/save-prompt देखाइदिन्थ्यो — ठ्याक्कै
    // त्यही क्षणमा success-pop navigation चलिरहेको हुन्थ्यो। यो नै
    // Flutter ले आधिकारिक रूपमा दिएको समाधान हो: screen बन्द गर्नुअघि नै
    // platform लाई स्पष्ट भन्ने — "यो autofill session सकियो, केही
    // save नगर्नु।"
    TextInput.finishAutofillContext(shouldSave: false);
    // BATTERY-KILL FIX — live device testing (Realme/ColorOS) ले नै
    // बारम्बार पक्रिएको: sign-in सफल भएपछि app छोटो क्षणको लागि भए पनि
    // background/launcher मा गए, यो OS कै आफ्नै aggressive battery
    // management ले पूरै Flutter process नै मार्थ्यो (नयाँ PID सँगै
    // cold-restart) — त्यही क्षणमा Firebase session restore हुँदै गर्दा
    // प्रयोगकर्ताले क्षणिक रूपमा "फेरि logged-out" देखेर फेरि login
    // प्रयास गर्थे, यसैले "login पछि फेरि Welcome screen मा फर्कने" जस्तो
    // देखिन्थ्यो। Best-effort — प्रयोगकर्ताले अस्वीकार गरे पनि (वा
    // ColorOS कै अलग्गै proprietary restriction ले यो standard Android
    // API लाई नै बेवास्ता गरे पनि) sign-in/navigation कहिल्यै रोकिनु
    // हुँदैन।
    if (!kIsWeb) {
      unawaited(Permission.ignoreBatteryOptimizations.request());
    }
    unawaited(playSuccessFeedback());
    setState(() {
      _verifying = false;
      _verified = true;
    });
    await Future.delayed(const Duration(milliseconds: 650));
  }

  /// Checkmark animation + Account Recognition + Passkey step — सबै
  /// सकिएपछि मात्र अन्तिम home फर्काउने। नयाँ `KaamMitraApp()` नबनाउने —
  /// same rootNavigatorKey collision bug (देख्नुहोस् email_auth_page.dart
  /// मा विस्तृत note)।
  Future<void> _goHome() async {
    if (!mounted) return;
    debugPrint(
        'ROUTE_TRACE: _goHome → popUntil, currentUser=${FirebaseAuth.instance.currentUser?.uid}');
    Navigator.of(context).popUntil((route) => route.isFirst);
    debugPrint('ROUTE_TRACE: popUntil done');
  }

  /// `_verify()`/`_completeWithCredential()` दुवैले sign-in सफल भएपछि
  /// बोलाउने साझा tail — checkmark → Account Recognition (फिर्ता
  /// प्रयोगकर्ता भए) वा न्यूनतम doc लेखाइ (नयाँ भए) → Passkey setup →
  /// home।
  Future<void> _completeSignIn(String? uid) async {
    await _showSuccessAnimation();
    if (!mounted) return;
    await _afterSignIn(uid);
    await _goHome();
  }

  Future<void> _verify() async {
    // CRITICAL FIX — पहिले यहाँ re-entrancy guard नै थिएन। `_onDigitChanged`
    // ले सबै ६ अंक भरिनेबित्तिकै हरेक keystroke मा (फेरि-फेरि पनि — जस्तै
    // SMS autofill आइरहेकै बेला प्रयोगकर्ताले आफैं पनि Verify बटन थिचे, वा
    // अन्तिम box मा फेरि टाइप गरे) `_verify()` लाई दोहोर्‍याएर बोलाउँथ्यो।
    // दुई समानान्तर (concurrent) `_verify()` ले दुवैले आ-आफ्नै
    // sign-in पूरा गरेर दुवैले `_completeSignIn()` →
    // `Navigator.popUntil` बोलाउँदा, दोस्रो कलले पहिल्यै unmount हुँदै
    // गरेको context मा नेभिगेट गर्न खोज्दा — ठ्याक्कै "OTP पठाएपछि अडिने/
    // dashboard मा नपुग्ने" गुनासोको जड। अब पहिलो कल सकिनेबित्तिकै (वा
    // सफल भइसकेपछि) कुनै पनि थप कल सिधै no-op हुन्छ।
    if (_verifying || _verified) return;
    final code = _enteredCode;
    if (code.length != 6) {
      _snack(S.enterOtp);
      return;
    }
    setState(() => _verifying = true);
    try {
      String? uid;
      if (widget.confirmationResult != null) {
        final result = await widget.confirmationResult!.confirm(code);
        uid = result.user?.uid;
        await _linkIfNeeded(uid);
      } else if (widget.verificationId != null) {
        final cred = PhoneAuthProvider.credential(
          verificationId: widget.verificationId!,
          smsCode: code,
        );
        final result = await FirebaseAuth.instance.signInWithCredential(cred);
        uid = result.user?.uid;
        await _linkIfNeeded(uid);
      } else {
        _snack(S.otpFailed);
        setState(() => _verifying = false);
        return;
      }

      if (!mounted) return;
      await _completeSignIn(uid);
    } on FirebaseAuthException catch (e) {
      debugPrint('FIREBASE_AUTH_ERROR: ${e.code} - ${e.message}');
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack(friendlyPhoneAuthError(e));
    } catch (e) {
      debugPrint('FIREBASE_AUTH_ERROR (non-Firebase): $e');
      if (!mounted) return;
      setState(() => _verifying = false);
      _snack('${S.otpFailed}\n$e');
    }
  }

  /// एउटा glassmorphism PIN box — focus भएको बेला teal glow outline,
  /// अंक भरिएपछि हल्का सेतो border, दुवै बेला AnimatedContainer ले
  /// smooth transition।
  Widget _digitBox(int index) {
    final focused = _digitFocusNodes[index].hasFocus;
    final filled = _digitControllers[index].text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 46,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.kmGlass2Fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused
              ? AppColors.kmTeal
              : (filled
                  ? Colors.white.withValues(alpha: 0.32)
                  : AppColors.kmGlass2Border),
          width: focused ? 1.6 : 1.1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.kmTeal.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: KeyboardListener(
        focusNode: _keyListenerNodes[index],
        onKeyEvent: (event) => _onDigitKey(index, event),
        child: TextField(
          controller: _digitControllers[index],
          focusNode: _digitFocusNodes[index],
          // Verify भइरहेको/भइसकेको बेला थप टाइप/paste ले फेरि
          // `_onDigitChanged` → `_verify()` नदोहोर्‍याओस् भनेर।
          enabled: !(_verifying || _verified),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // पहिलो box मात्र पूरै 6-अंक paste/SMS-autofill स्वीकार गर्छ
          // (बाँकी box हरू एक-एक अंकमै सीमित)।
          maxLength: index == 0 ? _digitCount : 1,
          cursorColor: AppColors.kmTeal,
          style: const TextStyle(
              color: AppColors.kmText,
              fontSize: 22,
              fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) => _onDigitChanged(index, v),
        ),
      ),
    );
  }

  /// Verify बटन — सामान्य/loading/success तीन अवस्था बीच scale-morph।
  /// सफल भएपछि teal-gradient circle भित्र checkmark (बाँकी एपकै
  /// `_PaymentSuccessCard` checkmark-celebration भाषासँग मेल खाने)।
  Widget _buildVerifyButton() {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: _verified
            ? Container(
                key: const ValueKey('otpSuccess'),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [AppColors.kmTeal, AppColors.kmTealBlue]),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.kmTeal.withValues(alpha: 0.55),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.kmInk, size: 28),
              )
            : SizedBox(
                key: const ValueKey('otpCta'),
                width: double.infinity,
                child: KmCtaButton(
                  label: S.verify,
                  icon: Icons.check_rounded,
                  loading: _verifying,
                  onPressed: _verify,
                ),
              ),
      ),
    );
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
                      // AUTOFILL FIX — live device logcat ले नै पक्रिएको:
                      // code सफलतापूर्वक verify भएपछि (native FirebaseAuth
                      // log ले सही uid सँग confirm गरिसकेपछि) पनि, Android
                      // कै आफ्नै system "Autofill UI" overlay यी 6 PIN box
                      // लाई ६ वटा छुट्टाछुट्टै (असम्बन्धित) login field
                      // जस्तो heuristically चिनेर पटक-पटक (~७ सेकेन्डसम्म,
                      // ३ पटक) focus खोस्दै देखिन्थ्यो — ठ्याक्कै त्यही
                      // झ्यालमा app चाहिएको success-pop navigation
                      // हुनुपर्ने हो। `AutofillGroup` ले यी सबैलाई एउटै
                      // logical form हो भनेर Android लाई स्पष्ट बताउँछ,
                      // ताकि per-field "save गर्ने?" heuristic ट्रिगर
                      // नहोस्।
                      AutofillGroup(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var i = 0; i < _digitCount; i++) _digitBox(i),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildVerifyButton(),
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
