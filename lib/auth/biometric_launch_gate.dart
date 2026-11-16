// auth/biometric_launch_gate.dart
// App-launch biometric lock — Settings को "App Lock (Biometric/Passkey)"
// toggle (settings_page.dart, app_globals.dart::biometricEnabled, prefs.dart
// मा persist) on भएमा मात्र, app खोल्नेबित्तिकै (एकपटक, process-lifetime भरि)
// device कै fingerprint/face/passcode नसोधी कुनै पनि screen (login भए पनि
// नभए पनि) नदेखियोस् भनेर `app.dart`::KaamMitraApp को MaterialApp(home:)
// लाई यसैले wrap गर्छ। toggle off भए यो पूर्ण रूपमा invisible (कुनै
// extra frame/delay समेत थपिँदैन)।
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../app_globals.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_ui.dart';

class BiometricLaunchGate extends StatefulWidget {
  final Widget child;
  const BiometricLaunchGate({super.key, required this.child});

  @override
  State<BiometricLaunchGate> createState() => _BiometricLaunchGateState();
}

class _BiometricLaunchGateState extends State<BiometricLaunchGate> {
  // toggle off भए सुरुमै नै unlocked — कुनै gate UI फ्ल्यास समेत हुँदैन।
  late bool _unlocked = !biometricEnabled.value;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!_unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
    }
  }

  Future<void> _attemptUnlock() async {
    if (_checking || !mounted) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!supported && !canCheck) {
        // Defensive fail-open — यो flag सामान्यतया settings_page.dart कै
        // toggle बाट मात्र on हुन्छ, जुन पहिल्यै एकपटक सफल biometric
        // confirm भइसकेपछि मात्र सेट हुन्छ; तर OS अपडेट/restored prefs
        // जस्ता edge case मा समेत कहिल्यै app पूर्ण रूपमा lock भएर
        // अनुपयोगी नहोस् भनेर।
        if (!mounted) return;
        setState(() {
          _unlocked = true;
          _checking = false;
        });
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: S.appLockSubtitle,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        if (ok) {
          _unlocked = true;
        } else {
          _error = S.appLockFailed;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = S.appLockFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

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
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                    border:
                        Border.all(color: AppColors.kmGlass2Border, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.kmTealBlue.withValues(alpha: 0.28),
                          blurRadius: 36,
                          spreadRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.lock_rounded,
                      size: 52, color: AppColors.kmTealBlue),
                ),
                const SizedBox(height: 28),
                Text(S.appLockTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmText,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.3)),
                const SizedBox(height: 10),
                Text(
                  S.appLockSubtitle,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.kmMuted, fontSize: 13.5),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.kmRose, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 32),
                KmCtaButton(
                  label: S.appLockUnlockButton,
                  icon: Icons.fingerprint_rounded,
                  loading: _checking,
                  onPressed: _checking ? () {} : _attemptUnlock,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
