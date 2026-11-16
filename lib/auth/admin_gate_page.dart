// auth/admin_gate_page.dart
//
// गुप्त Admin Gate — सामान्य "Continue with phone" फिल्डमै विशेष गोप्य
// नम्बर (config/app_config.dart::isAdminGatePhone) हालेपछि मात्र यहाँ
// आइपुगिन्छ (हेर्नुहोस् phone_input_page.dart::_continue())। यो पेजतिर
// जाने कुनै दृश्य लिङ्क/बटन/मेनु/सर्च-बार सर्टकट कतै छैन — सामान्य
// प्रयोगकर्ताको लागि यो सम्पूर्ण रूपमा अदृश्य।
//
// Google Sign-In मात्र (email/password छैन)। साइन-इन भएपछि इमेल ठ्याक्कै
// `kAdminEmail` सँग नमिले तुरुन्तै sign-out गरिन्छ — त्यो account ले यो गुप्त
// ढोकाबाट कुनै हालतमा (सामान्य प्रयोगकर्ताको रूपमा समेत) भित्र पस्न पाउँदैन।
import 'dart:async' show TimeoutException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class AdminGatePage extends StatefulWidget {
  const AdminGatePage({super.key});

  @override
  State<AdminGatePage> createState() => _AdminGatePageState();
}

class _AdminGatePageState extends State<AdminGatePage> {
  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// auth_page.dart कै उस्तै — root (`app.dart`) कै `authStateChanges()`
  /// StreamBuilder ले नयाँ user event नपाएसम्म pop नगर्ने, नत्र मुनि अझै
  /// पुरानो (signed-out) screen देखिने बग फर्किन्छ (त्यहाँको doc-comment
  /// हेर्नुहोस्)।
  Future<void> _waitForRootAuthSync() async {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await Future.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Mobile मात्र — गलत/अनधिकृत account छानिए native GoogleSignIn सेसन
    // (Firebase सँग स्वतन्त्र आफ्नै cache राख्छ) पनि सफा गर्नुपर्छ, नत्र
    // फेरि "Google बाट लगइन" थिच्दा picker नै नदेखाई त्यही अस्वीकृत account
    // चुपचाप पुनः-प्रयोग हुन्थ्यो — प्रयोगकर्ता अर्को account कहिल्यै छान्न
    // नपाउने बग।
    GoogleSignIn? mobileGoogleSignIn;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        try {
          await FirebaseAuth.instance
              .signInWithPopup(provider)
              .timeout(const Duration(seconds: 12));
        } on FirebaseAuthException catch (e) {
          if (e.code == 'popup-blocked') {
            await FirebaseAuth.instance.signInWithRedirect(provider);
            return;
          }
          rethrow;
        } on TimeoutException {
          await FirebaseAuth.instance.signInWithRedirect(provider);
          return;
        }
      } else {
        mobileGoogleSignIn = GoogleSignIn(serverClientId: kGoogleWebClientId);
        final googleUser = await mobileGoogleSignIn.signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _busy = false);
          return; // प्रयोगकर्ताले रद्द गर्‍यो
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (!mounted) return;
      // ── कडा जाँच — admin बाहेक अरू जुनसुकै Google account ले यो गुप्त
      // ढोकाबाट कुनै हालतमा (सामान्य प्रयोगकर्ताको रूपमा समेत) भित्र पस्न
      // नपाओस्। तुरुन्तै sign-out गरेर पूर्ण रूपमा फर्काउने।
      // Google को OAuth profile ले email फरक case मा (वा वरिपरि whitespace
      // सहित) फर्काउन सक्छ — कडा `==` compare गर्दा साँचो admin account
      // पनि "unauthorized" भनेर अस्वीकृत हुन्थ्यो। trim + lowercase गरेरै
      // तुलना गर्ने।
      final signedInEmail =
          FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
      if (signedInEmail != kAdminEmail.trim().toLowerCase()) {
        await FirebaseAuth.instance.signOut();
        await mobileGoogleSignIn?.signOut();
        if (!mounted) return;
        setState(() => _busy = false);
        _snack(S.adminGateDenied);
        return;
      }

      await _waitForRootAuthSync();
      if (!mounted) return;
      // नयाँ KaamMitraApp() कहिल्यै नबनाउने — root कै authStateChanges()
      // StreamBuilder ले नै admin इमेल भेटेपछि Owner Dashboard देखाइसक्छ।
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return; // प्रयोगकर्ताले popup बन्द गर्‍यो — त्रुटि देखाउनु पर्दैन
      }
      _snack('${S.errorWord}: ${e.message ?? e.code}');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.message ?? '';
      _snack((e.code == 'sign_in_failed' || msg.contains('ApiException'))
          ? S.googleSignInConfigError
          : S.googleSignInGenericError);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('${S.errorWord}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
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
                const Spacer(flex: 2),
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.kmPurple, AppColors.kmPurpleDeep],
                      ),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 20),
                Text(S.adminGateTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(S.adminGateSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmMuted, fontSize: 13)),
                const SizedBox(height: 28),
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
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
