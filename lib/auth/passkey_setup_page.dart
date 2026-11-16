// auth/passkey_setup_page.dart
// "Fast and secure login with passkey" — optional step, OTP-verify भइसकेपछि।
// साँचो FIDO2/WebAuthn Passkey, Firebase Auth को Flutter SDK ले हाल
// support गर्दैन — त्यसैले यहाँ device-level biometric (fingerprint/face,
// `local_auth` प्याकेज, Android/iOS दुवैको आधिकारिक "fast & secure"
// प्रमाणीकरण मेकानिज्म) प्रयोग गरिएको — Skip जहिले पनि उपलब्ध, biometric
// उपलब्ध/सफल नभए पनि login कहिल्यै रोकिँदैन।
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../app_globals.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart' show SecondaryButton;
import '../widgets/glass_ui.dart';

const String kPasskeyEnabledPrefKey = 'passkey_enabled';

class PasskeySetupPage extends StatefulWidget {
  const PasskeySetupPage({super.key});

  @override
  State<PasskeySetupPage> createState() => _PasskeySetupPageState();
}

class _PasskeySetupPageState extends State<PasskeySetupPage> {
  bool _working = false;

  Future<void> _createPasskey() async {
    setState(() => _working = true);
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!supported && !canCheck) {
        _finish(enabled: false, message: 'This device does not support biometric login.');
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Confirm your identity to enable fast, secure login',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok) {
        // prefs.dart ले यो listener सुनेर आफैं disk मा persist गर्छ —
        // यहाँ र Settings को toggle दुवैले यही एउटै global state साझा गर्छन्।
        biometricEnabled.value = true;
      }
      _finish(enabled: ok, message: ok ? null : null);
    } catch (e) {
      // Biometric नभएको/रद्द भएको/API असमर्थित जुनसुकै कारणले पनि —
      // login कहिल्यै यहीं रोकिनु हुँदैन, सधैं अगाडि बढ्न दिने।
      _finish(enabled: false, message: 'Could not set up passkey right now — you can try again later from Profile.');
    }
  }

  void _finish({required bool enabled, String? message}) {
    if (!mounted) return;
    setState(() => _working = false);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topLeft, AppColors.kmTealBlue),
        KmOrb(Alignment.bottomRight, AppColors.kmPurple),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Illustration placeholder।
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                        color: AppColors.kmGlass2Border, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.kmTealBlue.withValues(alpha: 0.28),
                          blurRadius: 36,
                          spreadRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.fingerprint_rounded,
                      size: 76, color: AppColors.kmTealBlue),
                ),
                const SizedBox(height: 32),
                const Text('Fast and secure login with passkey',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.kmText,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.3)),
                const SizedBox(height: 10),
                const Text(
                  'Use your fingerprint or face to sign in faster next time — no OTP needed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.kmMuted, fontSize: 13.5),
                ),
                const SizedBox(height: 36),
                KmCtaButton(
                  label: 'Create passkey',
                  icon: Icons.fingerprint_rounded,
                  loading: _working,
                  onPressed: _working ? () {} : _createPasskey,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Skip',
                  color: AppColors.kmMuted,
                  onPressed:
                      _working ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
