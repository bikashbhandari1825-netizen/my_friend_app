// auth/email_auth_page.dart
// साधारण user/worker को इमेल + पासवर्ड लगइन/साइनअप + Google Sign-In।
// (admin को auth_page.dart भन्दा छुट्टै) — सफल भएपछि gate (app.dart) ले role
// अनुसार routing सम्हाल्छ।
//
// टेस्टिङ: हरेक इमेल/Google account = स्थिर, छुट्टै account (anonymous uid जस्तो
// बदलिँदैन)। test-emp@k.com, test-worker1@k.com … गरेर धेरै mock account सजिलै।
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../auth_page.dart' show kGoogleWebClientId;
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'auth_config.dart';
import 'phone_input_page.dart';

class EmailAuthPage extends StatefulWidget {
  const EmailAuthPage({super.key});

  @override
  State<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends State<EmailAuthPage> {
  // इमेल र पासवर्डका लागि छुट्टाछुट्टै controller + focus node।
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode(debugLabel: 'emailField');
  final _passFocus = FocusNode(debugLabel: 'passwordField');
  bool _isLogin = true;
  bool _busy = false;
  bool _obscure = true;
  String? _emailError;
  String? _error; // रातो — असफल
  String? _notice; // नीलो — जानकारी (जस्तै: Login मा सारियो)

  static const _timeout = Duration(seconds: 20);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null || _emailError != null) {
      setState(() {
        _error = null;
        _emailError = null;
      });
    }
  }

  /// Login ⇄ Sign-up tab स्विच — form पूरै रिसेट गरेर भ्रम नहोस्।
  void _setMode(bool login) {
    if (_isLogin == login || _busy) return;
    setState(() {
      _isLogin = login;
      _error = null;
      _notice = null;
      _emailError = null;
    });
  }

  /// लगइन सफल भएपछि यहाँबाट सिधै root मा फर्किने — **नयाँ `KaamMitraApp()`
  /// कहिल्यै नबनाउने**। root (`app.dart`) कै `authStateChanges()` माथिको
  /// StreamBuilder ले नै sign-in हुनेबित्तिकै सही screen देखाइसक्छ (त्यही
  /// एउटै Navigator/MaterialApp भित्र); यहाँबाट फेरि arts एउटा नयाँ
  /// `KaamMitraApp()` push गर्दा दुइटा MaterialApp (दुइटा Navigator) एकैचोटि
  /// उही `rootNavigatorKey` दाबी गर्थे — त्यही "duplicate GlobalKey"
  /// ले `_elements.contains(element)` assertion (red/black-screen crash,
  /// web+Android दुवैतिर) निम्त्याउँथ्यो। यहाँ त यो पेज नै pop गरेर हटाउनु
  /// मात्र पर्छ — बाँकी root ले आफैं गर्छ।
  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// सबै whitespace हटाएको, lowercase इमेल।
  String get _cleanEmail =>
      _email.text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// Sign-up बाट "पहिले नै दर्ता" भेटिँदा Login tab मा फर्काउने (जानकारी सन्देशसहित)।
  void _switchToLogin(String hint) {
    setState(() {
      _isLogin = true;
      _busy = false;
      _emailError = null;
      _error = null;
      _notice = hint;
      _password.clear();
    });
    _passFocus.requestFocus();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _cleanEmail;
    final pass = _password.text;

    // client जाँच न्यूनतम — साँचो validation Firebase ले गर्छ।
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _emailError = S.enterValidEmail);
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = S.passwordTooShort);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _emailError = null;
    });

    final auth = FirebaseAuth.instance;
    try {
      if (_isLogin) {
        // ── LOGIN: credentials verify मात्र। कहिल्यै नयाँ खाता बनाउँदैन। ──
        try {
          await auth
              .signInWithEmailAndPassword(email: email, password: pass)
              .timeout(_timeout);
        } on FirebaseAuthException catch (e) {
          if (!mounted) return;
          // Email-enumeration-protection ले wrong-password / user-not-found
          // दुवैलाई 'invalid-credential' मा जोड्छ — त्यसैले हामी account
          // बनाउने होइन, स्पष्ट सन्देश देखाउने।
          switch (e.code) {
            case 'invalid-credential':
            case 'INVALID_LOGIN_CREDENTIALS':
            case 'user-not-found':
              setState(() {
                _busy = false;
                _error = S.loginNoMatchHint;
              });
              _passFocus
                  .requestFocus(); // keyboard locked नहोस् — तुरुन्तै retry
              return;
            case 'wrong-password':
              setState(() {
                _busy = false;
                _error = S.wrongPasswordHint;
              });
              _passFocus.requestFocus();
              return;
            default:
              rethrow;
          }
        }
      } else {
        // ── SIGN UP: नयाँ खाता मात्र। पहिले नै छ भने Login मा फर्काउने। ──
        try {
          await auth
              .createUserWithEmailAndPassword(email: email, password: pass)
              .timeout(_timeout);
        } on FirebaseAuthException catch (e) {
          if (!mounted) return;
          if (e.code == 'email-already-in-use') {
            _switchToLogin(S.emailTakenSwitchLogin);
            return;
          }
          rethrow;
        }
      }
      _goHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.code == 'invalid-email') {
          _emailError = S.isNepali
              ? 'Firebase ले "$email" लाई अमान्य भन्यो'
              : 'Firebase rejected "$email" as invalid';
        } else {
          _error = _mapError(e);
        }
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = S.isNepali
            ? 'सर्भरबाट जवाफ आएन — फेरि प्रयास गर्नुहोस्'
            : 'No response from the server — try again';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${S.errorWord}: $e';
      });
    }
  }

  String _mapError(FirebaseAuthException e) {
    final base = switch (e.code) {
      'operation-not-allowed' => S.emailPasswordDisabled,
      'email-already-in-use' => S.haveAccountLogin,
      'wrong-password' ||
      'invalid-credential' =>
        S.isNepali ? 'इमेल वा पासवर्ड मिलेन' : 'Wrong email or password',
      'user-not-found' => S.noAccountSignup,
      'weak-password' => S.passwordTooShort,
      'invalid-email' => S.enterValidEmail,
      'network-request-failed' =>
        S.isNepali ? 'इन्टरनेट जाँच्नुहोस्' : 'Check your connection',
      'too-many-requests' => S.tooManyAttemptsHint,
      _ => e.message ?? e.code,
    };
    return '$base  (${e.code})';
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance
            .signInWithPopup(GoogleAuthProvider())
            .timeout(const Duration(seconds: 90));
      } else {
        // नोट: Android मा `clientId` param ले केही गर्दैन (google_sign_in
        // plugin ले त्यसलाई बेवास्ता गर्छ) — बरु `serverClientId` (Firebase
        // को Web client ID) चाहिन्छ, ताकि फर्कने idToken को audience Firebase
        // प्रोजेक्टसँग मिलोस्। यो नमिलेको भए पनि बेग्लै लक्षणसहित असफल हुन्थ्यो
        // (ApiException: 10 भने प्रायः SHA-1 प्रमाणपत्र Firebase Console मा
        // दर्ता नभएकोले आउँछ)।
        final gsi = GoogleSignIn(serverClientId: kGoogleWebClientId);
        final acc = await gsi.signIn();
        if (acc == null) {
          setState(() => _busy = false);
          return;
        }
        final gAuth = await acc.authentication;
        await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(
            accessToken: gAuth.accessToken,
            idToken: gAuth.idToken,
          ),
        );
      }
      _goHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Google account को इमेलमा पहिल्यै password-based खाता छ — त्यो प्रयोग
      // गर्न Login mode मा सारेर स्पष्ट सन्देश देखाउने (नयाँ खाता बन्दैन)।
      if (e.code == 'account-exists-with-different-credential') {
        _switchToLogin(S.passwordAccountExistsHint);
        return;
      }
      setState(() {
        _busy = false;
        _error = _mapError(e);
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = S.isNepali
            ? 'Google popup बन्द भयो वा जवाफ आएन'
            : 'Google popup closed or timed out';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      // Android native Google Sign-In sheet ले दिने असफलता — क्र्यास वा raw
      // "PlatformException(sign_in_failed, ... ApiException: 10 ...)" जस्तो
      // बुझ्न नसकिने पाठको सट्टा प्रस्ट सन्देश। code 10 (DEVELOPER_ERROR) ले
      // प्रायः SHA-1 प्रमाणपत्र Firebase मा दर्ता नभएको जनाउँछ; user आफैंले
      // network/SHA-1 केही गर्न सक्दैनन् तर यो सन्देशले developer लाई सही
      // दिशामा पुर्‍याउँछ (यही app को हकमा अब त्यो प्रमाणपत्र दर्ता गरिएको छ)।
      final msg = e.message ?? '';
      setState(() {
        _busy = false;
        _error = (e.code == 'sign_in_failed' || msg.contains('ApiException'))
            ? S.googleSignInConfigError
            : S.googleSignInGenericError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${S.errorWord}: $e';
      });
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
                Text(_isLogin ? S.loginAction : S.signupAction,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 10)
                        ])),
                const SizedBox(height: 8),
                Text(_isLogin ? S.loginToYourAccount : S.createNewAccount,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13)),
                const SizedBox(height: 20),
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
                  child: AutofillGroup(
                    child: Column(
                      children: [
                        _tabs(),
                        const SizedBox(height: 14),
                        _modeBanner(),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _email,
                          focusNode: _emailFocus,
                          enabled: true,
                          readOnly: false,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          mouseCursor: SystemMouseCursors.text,
                          autofillHints: const [AutofillHints.email],
                          onTap: () => _emailFocus.requestFocus(),
                          onChanged: (_) => _clearError(),
                          onEditingComplete: () => _passFocus.requestFocus(),
                          decoration: InputDecoration(
                            labelText: S.emailLabel,
                            errorText: _emailError,
                            prefixIcon: const Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          focusNode: _passFocus,
                          enabled: true,
                          readOnly: false,
                          obscureText: _obscure,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          mouseCursor: SystemMouseCursors.text,
                          // autofill hint stable — runtime मा बदल्दा web input
                          // connection टुट्न सक्छ।
                          autofillHints: const [AutofillHints.password],
                          onTap: () => _passFocus.requestFocus(),
                          onChanged: (_) => _clearError(),
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: S.passwordLabel,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            // toggle ले field को focus/tab slot नखाओस्।
                            suffixIcon: ExcludeFocus(
                              child: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                        ),
                        if (_notice != null) ...[
                          const SizedBox(height: 12),
                          _msgBox(_notice!, info: true),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _msgBox(_error!, info: false),
                        ],
                        const SizedBox(height: 18),
                        PrimaryButton(
                          label: _isLogin ? S.loginAction : S.signupAction,
                          icon: _isLogin
                              ? Icons.login_rounded
                              : Icons.person_add_alt_1_rounded,
                          loading: _busy,
                          onPressed: _submit,
                        ),
                        if (kEnableGoogleSignIn) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(S.orWord,
                                    style: const TextStyle(
                                        color: Colors.black45, fontSize: 12)),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _google,
                              icon: const Icon(Icons.g_mobiledata_rounded,
                                  size: 26, color: Color(0xFFDB4437)),
                              label: Text(S.signInWithGoogle,
                                  style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                side: const BorderSide(color: Colors.black26),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.pill)),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _busy ? null : () => _setMode(!_isLogin),
                          child: Text(_isLogin
                              ? S.noAccountSignup
                              : S.haveAccountLogin),
                        ),
                      ],
                    ),
                  ),
                ),
                if (kEnablePhoneAuth) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PhoneInputPage()),
                    ),
                    icon: const Icon(Icons.phone_iphone_rounded,
                        color: Colors.white70, size: 18),
                    label: Text(S.usePhoneInstead,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Login | Sign-up — एउटै pill भित्र सर्ने (sliding) active indicator।
  Widget _tabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.igViolet.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.igViolet.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final segW = (c.maxWidth - 8) / 2;
          return Stack(
            children: [
              // सर्ने highlight — सजावट मात्र, कुनै pointer capture छैन।
              IgnorePointer(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment:
                      _isLogin ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    width: segW,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: AppColors.buttonGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.igPink.withValues(alpha: 0.35),
                            blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _tab(S.loginAction, _isLogin, () => _setMode(true)),
                  _tab(S.signupAction, !_isLogin, () => _setMode(false)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                    color: active ? Colors.white : AppColors.igViolet,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5),
                child: Text(label),
              ),
            ),
          ),
        ),
      );

  /// अहिले कुन form भरिँदैछ भन्ने प्रस्ट पट्टी।
  Widget _modeBanner() {
    final c = _isLogin ? AppColors.igViolet : AppColors.igOrange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(
              _isLogin
                  ? Icons.lock_open_rounded
                  : Icons.person_add_alt_1_rounded,
              size: 15,
              color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_isLogin ? S.loginModeNote : S.signupModeNote,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.7))),
          ),
        ],
      ),
    );
  }

  Widget _msgBox(String text, {required bool info}) {
    final c = info ? AppColors.igViolet : AppColors.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(info ? Icons.info_outline_rounded : Icons.error_outline_rounded,
              size: 15, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: c, fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
