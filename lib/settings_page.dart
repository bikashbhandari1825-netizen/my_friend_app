// settings_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_globals.dart';
import 'auth/dev_login.dart';
import 'l10n/strings.dart';
import 'main.dart'; // themeNotifier / localeNotifier प्रयोग गर्नको लागि
import 'theme/app_theme.dart';
import 'widgets/glass_ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDeleting = false;

  void _savedToast() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      backgroundColor: AppColors.success,
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(S.saved),
      ]),
    ));
  }

  // Appearance (Light / Dark / System) छान्ने पपअप
  void _showAppearanceOptions() {
    showKmSheet(
      context: context,
      title: S.appearance,
      children: [
        KmSheetOption(
          icon: Icons.light_mode_rounded,
          label: S.themeLight,
          selected: themeNotifier.value == ThemeMode.light,
          onTap: () {
            themeNotifier.value = ThemeMode.light;
            Navigator.pop(context);
            _savedToast();
          },
        ),
        KmSheetOption(
          icon: Icons.dark_mode_rounded,
          label: S.themeDark,
          selected: themeNotifier.value == ThemeMode.dark,
          onTap: () {
            themeNotifier.value = ThemeMode.dark;
            Navigator.pop(context);
            _savedToast();
          },
        ),
        KmSheetOption(
          icon: Icons.settings_suggest_rounded,
          label: S.themeSystem,
          selected: themeNotifier.value == ThemeMode.system,
          onTap: () {
            themeNotifier.value = ThemeMode.system;
            Navigator.pop(context);
            _savedToast();
          },
        ),
      ],
    ).then((_) => setState(() {}));
  }

  // भाषा (English / नेपाली) छान्ने पपअप — touch गर्दा तुरुन्तै बदलिन्छ
  void _showLanguageOptions() {
    showKmSheet(
      context: context,
      title: S.language,
      children: [
        KmSheetOption(
          icon: Icons.translate_rounded,
          label: 'नेपाली',
          selected: localeNotifier.value.languageCode == 'ne',
          onTap: () {
            localeNotifier.value = const Locale('ne');
            Navigator.pop(context);
            _savedToast();
          },
        ),
        KmSheetOption(
          icon: Icons.translate_rounded,
          label: 'English',
          selected: localeNotifier.value.languageCode == 'en',
          onTap: () {
            localeNotifier.value = const Locale('en');
            Navigator.pop(context);
            _savedToast();
          },
        ),
      ],
    ).then((_) => setState(() {}));
  }

  Future<void> _confirmLogout() async {
    final confirm = await showKmDialog<bool>(
      context: context,
      title: S.logoutConfirmTitle,
      icon: Icons.logout_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: S.logOut,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );

    if (confirm == true) {
      await signOutClean();
      if (!mounted) return;
      // नयाँ PhoneLandingPage() push नगर्ने — root StreamBuilder<User?>
      // (app.dart) लाई नै signOut() पछिको auth state अनुसार देखाउन दिने।
      // पहिले यहाँ pushAndRemoveUntil ले त्यो reactive root route नै
      // हटाएर एउटा static PhoneLandingPage राख्दिन्थ्यो — त्यसपछि फेरि
      // नयाँ नम्बरले OTP verify सफल भए पनि otp_verification_page.dart कै
      // `popUntil((route) => route.isFirst)` त्यही static page मै फर्केर
      // अडिन्थ्यो (login सफल भए पनि welcome screen मै फर्किएको जस्तो)।
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showKmDialog<bool>(
      context: context,
      title: S.deleteAccount,
      message: S.deleteAccountBody,
      icon: Icons.delete_forever_rounded,
      iconBg: const LinearGradient(
          colors: [AppColors.kmRose, AppColors.kmPinkDeep]),
      actions: [
        KmDialogAction(
          label: S.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        KmDialogAction(
          label: S.delete,
          destructive: true,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // CRITICAL FIX — डिलिट गर्नुअघि यही फोन नम्बर समातिराख्ने (real
      // phone-auth भए `user.phoneNumber`, test-mode भए `activeTestPhone`)।
      // `deleteAccountCascade` भित्र `phoneAccounts` index पूरै मेटाउनको
      // लागि चाहिने — नत्र त्यो index पुरानै uid तिर नै देखाइरहने (नयाँ
      // account auth मात्र मेटिएर, index भने बाँकी रहने) र भोलि उही
      // नम्बरले फेरि login गर्दा `linkPhoneToUid()` ले त्यो (अब नष्ट
      // भइसकेको) पुरानो uid बाट "migrate" प्रयास गर्ने।
      final deletedPhone = user.phoneNumber ?? activeTestPhone;
      await deleteAccountCascade(user.uid, phone: deletedPhone);

      if (!mounted) return;
      // नयाँ PhoneLandingPage() push नगर्ने — root StreamBuilder<User?>
      // (app.dart) लाई नै signOut() पछिको auth state अनुसार देखाउन दिने
      // (हेर्नुहोस् माथिकै logout बटनको उस्तै fix)।
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'सुरक्षा कारणले, कृपया लगआउट गरेर फेरि लगइन गरी अकाउन्ट डिलिट प्रयास गर्नुहोस्।')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.errorWord}: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.errorWord}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  String _themeModeLabel() {
    switch (themeNotifier.value) {
      case ThemeMode.light:
        return S.themeLight;
      case ThemeMode.dark:
        return S.themeDark;
      case ThemeMode.system:
        return S.themeSystem;
    }
  }

  void _showLegalDocuments() {
    showKmDialog(
      context: context,
      title: S.legalDocuments,
      message: 'Terms of Service र Privacy Policy चाँडै यहाँ उपलब्ध हुनेछ।',
      icon: Icons.description_rounded,
      actions: [
        KmDialogAction(
          label: S.ok,
          filled: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      orbs: const [
        KmOrb(Alignment.topRight, AppColors.kmPurple),
        KmOrb(Alignment.bottomLeft, AppColors.kmOrangeDeep),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _isDeleting
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.kmTeal),
              )
            : SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: KmScreenHeader(title: S.settings),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                        children: [
                          KmSectionLabel(S.settingsPrefsSection),
                          const SizedBox(height: 10),
                          KmListTile(
                            icon: Icons.brightness_6_rounded,
                            iconBg: KmListTile.gradients[0],
                            title: S.appearance,
                            subtitle: _themeModeLabel(),
                            onTap: _showAppearanceOptions,
                          ),
                          const SizedBox(height: 10),
                          KmListTile(
                            icon: Icons.language_rounded,
                            iconBg: KmListTile.gradients[1],
                            title: S.language,
                            subtitle: S.isNepali ? 'नेपाली' : 'English',
                            onTap: _showLanguageOptions,
                          ),
                          const SizedBox(height: 10),
                          ValueListenableBuilder<bool>(
                            valueListenable: notificationsEnabled,
                            builder: (context, on, _) => KmListTile(
                              icon: Icons.notifications_active_rounded,
                              iconBg: KmListTile.gradients[2],
                              title: S.notificationsLabel,
                              subtitle:
                                  on ? S.notificationsOn : S.notificationsOff,
                              trailing: Switch(
                                value: on,
                                activeThumbColor: AppColors.kmTeal,
                                onChanged: (v) {
                                  notificationsEnabled.value = v;
                                  _savedToast();
                                },
                              ),
                              onTap: () {
                                notificationsEnabled.value = !on;
                                _savedToast();
                              },
                            ),
                          ),
                          KmSectionLabel(S.settingsAboutSection),
                          const SizedBox(height: 10),
                          KmListTile(
                            icon: Icons.description_rounded,
                            iconBg: KmListTile.gradients[4],
                            title: S.legalDocuments,
                            onTap: _showLegalDocuments,
                          ),
                          KmSectionLabel(S.settingsAccountSection),
                          const SizedBox(height: 10),
                          KmListTile(
                            icon: Icons.logout_rounded,
                            iconBg: KmListTile.gradients[4],
                            title: S.logOut,
                            onTap: _confirmLogout,
                          ),
                          const SizedBox(height: 10),
                          KmListTile(
                            icon: Icons.delete_forever_rounded,
                            iconBg: KmListTile.gradients[1],
                            title: S.deleteAccount,
                            titleColor: AppColors.kmRose,
                            borderColor: AppColors.kmRoseSoft.withValues(alpha: 0.5),
                            fillColor: AppColors.kmPink.withValues(alpha: 0.08),
                            onTap: _confirmDeleteAccount,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
