// settings_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_globals.dart';
import 'auth/dev_login.dart';
import 'auth/phone_landing_page.dart';
import 'l10n/strings.dart';
import 'main.dart'; // themeNotifier / localeNotifier प्रयोग गर्नको लागि
import 'theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDeleting = false;

  /// पूरा पृष्ठको पछाडि — Instagram-inspired: बैजनी → गुलाबी → सुन्तला।
  static const _pageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6A1B9A), // deep violet (AppBar area — सेतो text पढ्न)
      AppColors.igViolet, // #833AB4
      AppColors.igPink, // #E1306C
      AppColors.igOrange, // #F77737
      AppColors.igAmber, // #FCAF45
    ],
    stops: [0.0, 0.22, 0.55, 0.82, 1.0],
  );

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
    showModalBottomSheet(
      context: context,
      builder: (context) {
        Widget row(IconData icon, String label, ThemeMode mode) => ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: themeNotifier.value == mode
                  ? const Icon(Icons.check, color: AppColors.lime)
                  : null,
              onTap: () {
                themeNotifier.value = mode;
                Navigator.pop(context);
                _savedToast();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(Icons.light_mode, S.themeLight, ThemeMode.light),
              row(Icons.dark_mode, S.themeDark, ThemeMode.dark),
              row(Icons.settings_suggest, S.themeSystem, ThemeMode.system),
            ],
          ),
        );
      },
    ).then((_) => setState(() {}));
  }

  // भाषा (English / नेपाली) छान्ने पपअप — touch गर्दा तुरुन्तै बदलिन्छ
  void _showLanguageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        Widget row(String label, String code) => ListTile(
              leading: const Icon(Icons.translate),
              title: Text(label),
              trailing: localeNotifier.value.languageCode == code
                  ? const Icon(Icons.check, color: AppColors.lime)
                  : null,
              onTap: () {
                localeNotifier.value = Locale(code);
                Navigator.pop(context);
                _savedToast();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row('नेपाली', 'ne'),
              row('English', 'en'),
            ],
          ),
        );
      },
    ).then((_) => setState(() {}));
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.logoutConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.logOut, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await signOutClean();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PhoneLandingPage()),
        (route) => false,
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.deleteAccount),
        content: Text(S.deleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final uid = user.uid;

      // registeredWorkers collection बाट यो uid को सबै Entry हटाउने
      final registeredSnap = await FirebaseFirestore.instance
          .collection('registeredWorkers')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in registeredSnap.docs) {
        await doc.reference.delete();
      }

      // pendingWorkers collection बाट यो uid को सबै Entry हटाउने
      final pendingSnap = await FirebaseFirestore.instance
          .collection('pendingWorkers')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in pendingSnap.docs) {
        await doc.reference.delete();
      }

      // notifications collection पनि सफा गर्ने
      final notifSnap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in notifSnap.docs) {
        await doc.reference.delete();
      }

      // युजरको मुख्य प्रोफाइल मेटाउने
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // Firebase Auth बाट खाता मेटाउने
      await user.delete();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PhoneLandingPage()),
        (route) => false,
      );
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.legalDocuments),
        content: const Text(
            'Terms of Service र Privacy Policy चाँडै यहाँ उपलब्ध हुनेछ।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: _pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          title: Text(
            S.settings,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _isDeleting
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    _sectionLabel(S.settingsPrefsSection),
                    _SettingsCard(
                      icon: Icons.brightness_6_rounded,
                      iconColor: AppColors.igViolet,
                      title: S.appearance,
                      subtitle: _themeModeLabel(),
                      onTap: _showAppearanceOptions,
                    ),
                    _SettingsCard(
                      icon: Icons.language_rounded,
                      iconColor: AppColors.igPink,
                      title: S.language,
                      subtitle: S.isNepali ? 'नेपाली' : 'English',
                      onTap: _showLanguageOptions,
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: notificationsEnabled,
                      builder: (context, on, _) => _SettingsCard(
                        icon: Icons.notifications_active_rounded,
                        iconColor: AppColors.igOrange,
                        title: S.notificationsLabel,
                        subtitle: on ? S.notificationsOn : S.notificationsOff,
                        trailing: Switch(
                          value: on,
                          activeThumbColor: AppColors.lime,
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
                    _sectionLabel(S.settingsAboutSection),
                    _SettingsCard(
                      icon: Icons.description_rounded,
                      iconColor: AppColors.igAmber,
                      title: S.legalDocuments,
                      onTap: _showLegalDocuments,
                    ),
                    _sectionLabel(S.settingsAccountSection),
                    _SettingsCard(
                      icon: Icons.logout_rounded,
                      iconColor: AppColors.warning,
                      title: S.logOut,
                      onTap: _confirmLogout,
                    ),
                    _SettingsCard(
                      icon: Icons.delete_forever_rounded,
                      iconColor: AppColors.danger,
                      title: S.deleteAccount,
                      destructive: true,
                      onTap: _confirmDeleteAccount,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 20, 6, 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            shadows: [
              Shadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 1)),
            ],
          ),
        ),
      );
}

/// एउटा setting option — आधुनिक card: सफा padding, नरम border, vibrant icon badge।
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = destructive ? AppColors.danger : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: destructive
                    ? AppColors.danger.withValues(alpha: 0.35)
                    : scheme.outline.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          iconColor,
                          Color.lerp(iconColor, Colors.black, 0.28)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withValues(alpha: 0.40),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing ??
                      (onTap != null
                          ? Icon(Icons.chevron_right_rounded,
                              color: scheme.onSurfaceVariant)
                          : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
