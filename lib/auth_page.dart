// auth_page.dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'l10n/strings.dart';

// Web OAuth client ID — यो lib/firebase_options.dart कै project (504837034251 /
// kaammitra-87e38) को हुनुपर्छ। मोबाइलमा मात्र google_sign_in लाई चाहिन्छ।
const String kGoogleWebClientId =
    '504837034251-h3ol9ehaksf1biicqgig2o5hn6fv14u2.apps.googleusercontent.com';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoginMode = true;
  bool _obscurePassword = true;
  // Google/email दुवै sign-inले network round-trip पर्खनुपर्छ — त्यो बेला
  // बटन disable + spinner नदेखाए user "केही भएन" भनेर बीचमै app बाट
  // बाहिरिन्छन् वा फेरि tap गर्छन्, जसले गर्दा process backgrounded हुँदा
  // (यो device जस्तो aggressive-kill भएको OEM मा) in-flight sign-in हराएर
  // "welcome screen मा बाउन्स भएको" जस्तो देखिन्थ्यो — साँचो कारण यही थियो।
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    // इमेल मात्र trim/lowercase — पासवर्ड जस्ताको तस्तै (trim गर्दा mismatch हुन्छ)।
    final email =
        _emailController.text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final pass = _passwordController.text;
    if (!email.contains('@') || !email.contains('.') || pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.enterValidEmail)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isLoginMode) {
        // LOGIN: verify मात्र — कहिल्यै नयाँ खाता बनाउँदैन।
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: pass);
      } else {
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: pass);
      }

      if (!mounted) return;
      // नयाँ KaamMitraApp() कहिल्यै नबनाउने — root कै authStateChanges()
      // StreamBuilder ले नै sign-in भएपछि सही screen देखाइसक्छ। यहाँबाट
      // दोस्रोपटक फेरि नयाँ MaterialApp push गर्दा (दुइटाले उही
      // rootNavigatorKey दाबी गर्दा) element-lifecycle assertion (red/black
      // screen crash) आउँथ्यो — यो पेज pop गरेर हटाउनु मात्र पर्छ।
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = switch (e.code) {
        'invalid-credential' ||
        'INVALID_LOGIN_CREDENTIALS' ||
        'wrong-password' ||
        'user-not-found' =>
          S.loginNoMatchHint,
        'email-already-in-use' => S.emailTakenSwitchLogin,
        'invalid-email' => S.enterValidEmail,
        'user-disabled' => S.isNepali
            ? 'यो खाता निष्क्रिय गरिएको छ।'
            : 'This account has been disabled.',
        'operation-not-allowed' => S.emailPasswordDisabled,
        'too-many-requests' => S.tooManyAttemptsHint,
        'network-request-failed' =>
          S.isNepali ? 'इन्टरनेट जाँच्नुहोस्।' : 'Check your connection.',
        _ => '${e.message ?? e.code}  (${e.code})',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${S.errorWord}: $e")),
      );
    }
  }

  /// Google बाट दर्ता भएको (password कहिल्यै नबनेको) खातालाई password सेट
  /// गर्न दिने — Firebase को reset email ले provider जे भए पनि त्यो
  /// खातामा password auth थप्छ, त्यसैले यो नै on-device credential-linking
  /// नचाहिने, भरपर्दो "Google account link" बाटो हो।
  Future<void> _forgotPassword() async {
    if (_busy) return;
    final email =
        _emailController.text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.resetEmailEnterFirst)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.resetEmailSent)),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${S.errorWord}: $e")),
      );
    }
  }

  // Google बाट लगइन।
  //  - Web: Firebase को signInWithPopup प्रयोग गर्छ। यसले Firebase auth domain
  //    (kaammitra-87e38.firebaseapp.com) लाई OAuth origin बनाउँछ, जुन Firebase ले
  //    आफै authorize गर्छ — त्यसैले `origin_mismatch` (400) आउँदैन।
  //  - Mobile: google_sign_in प्लगिन प्रयोग गर्छ।
  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Android मा `clientId` param बेवास्ता हुन्छ — `serverClientId`
        // (Firebase Web client ID) ले मात्र सही audience भएको idToken दिन्छ।
        final GoogleSignIn googleSignIn =
            GoogleSignIn(serverClientId: kGoogleWebClientId);
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          if (mounted) setState(() => _busy = false);
          return; // प्रयोगकर्ताले रद्द गर्‍यो
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return; // प्रयोगकर्ताले popup बन्द गर्‍यो — त्रुटि देखाउनु पर्दैन
      }
      if (e.code == 'account-exists-with-different-credential') {
        setState(() => _isLoginMode = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.passwordAccountExistsHint)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Google Sign-In त्रुटि: ${e.message ?? e.code}")),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Android native sign-in sheet बाट आउने असफलता — raw
      // "PlatformException(sign_in_failed, ... ApiException: 10 ...)" को
      // सट्टा प्रस्ट सन्देश। code 10 (DEVELOPER_ERROR) प्रायः SHA-1
      // प्रमाणपत्र Firebase Console मा दर्ता नभएको जनाउँछ।
      final msg = e.message ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              (e.code == 'sign_in_failed' || msg.contains('ApiException'))
                  ? S.googleSignInConfigError
                  : S.googleSignInGenericError),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google Sign-In त्रुटि: $e")),
      );
    }
  }

  // Glass card भित्रको light-on-dark input styling
  InputDecoration _glassField(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0B2E),
      body: Stack(
        children: [
          // ── Premium Instagram-style mesh gradient ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2A0A4A), // deep purple
                  Color(0xFF7B1FA2), // violet
                  Color(0xFFD81B60), // magenta / pink
                  Color(0xFFF4511E), // deep orange
                  Color(0xFFFFC107), // warm amber
                ],
                stops: [0.0, 0.28, 0.55, 0.8, 1.0],
              ),
            ),
          ),
          // glow blobs — mesh जस्तो depth
          _glow(const Alignment(-1.1, -0.9), const Color(0xFFFF4FD8), 320),
          _glow(const Alignment(1.2, -0.4), const Color(0xFF7C4DFF), 300),
          _glow(const Alignment(0.9, 1.1), const Color(0xFFFFB300), 340),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),

                  // १. Custom logo image — rounded corners + shadow
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color:
                              const Color(0xFFFF4FD8).withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/images/login_logo.png',
                        width: 108,
                        height: 108,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.handyman_rounded,
                            size: 60,
                            color: Color(0xFF7B1FA2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'KaamMitra',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      shadows: [
                        Shadow(
                            color: Colors.black45,
                            blurRadius: 12,
                            offset: Offset(0, 3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.isNepali
                        ? 'भरपर्दो स्थानीय कामदार'
                        : 'Trusted local workers',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 26),

                  // २. Frosted-glass login card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: Column(
                          children: [
                            const CircleAvatar(
                              radius: 34,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.person_rounded,
                                  size: 38, color: Colors.white),
                            ),
                            const SizedBox(height: 18),

                            // इमेल — logic उस्तै
                            TextField(
                              controller: _emailController,
                              style: const TextStyle(color: Colors.white),
                              keyboardType: TextInputType.emailAddress,
                              decoration: _glassField(
                                  S.emailLabel, Icons.email_outlined),
                            ),
                            const SizedBox(height: 14),

                            // पासवर्ड — logic उस्तै
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: const TextStyle(color: Colors.white),
                              decoration: _glassField(
                                      S.passwordLabel, Icons.lock_outline)
                                  .copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                            ),
                            if (_isLoginMode) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy ? null : _forgotPassword,
                                  child: Text(S.forgotPassword,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5)),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),

                            // लगइन/साइन-अप बटन — onPressed: _submit उस्तै
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF7B1FA2),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Color(0xFF7B1FA2)),
                                      )
                                    : Text(
                                        _isLoginMode
                                            ? S.loginAction
                                            : S.signupAction,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ३. toggle — logic उस्तै
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _isLoginMode = !_isLoginMode),
                    child: Text(
                      _isLoginMode ? S.toSignup : S.toLogin,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // divider
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.4))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(S.orWord,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85))),
                      ),
                      Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.4))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Google Sign-In — onPressed: _signInWithGoogle उस्तै।
                  // network slow भएमा seconds लाग्न सक्छ — त्यो बेला बटन
                  // disable + spinner देखाएर user लाई "अझै काम भइरहेको छ"
                  // भन्ने प्रस्ट संकेत दिने (यो नभएकोले नै पहिले user बीचमै
                  // app बाट बाहिरिएर/अर्को app मा गएर in-flight sign-in
                  // हराउँथ्यो — "welcome screen मा बाउन्स" जस्तो देखिने
                  // साँचो कारण)।
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _signInWithGoogle,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.black54),
                            )
                          : const Icon(Icons.g_mobiledata,
                              size: 28, color: Colors.red),
                      label: Text(
                        S.signInWithGoogle,
                        style: const TextStyle(
                            color: Colors.black87, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        elevation: 6,
                        shadowColor: Colors.black38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Alignment align, Color color, double size) => Align(
        alignment: align,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.55),
                  color.withValues(alpha: 0.0)
                ],
              ),
            ),
          ),
        ),
      );
}
