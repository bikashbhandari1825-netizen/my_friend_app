// settings_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth/phone_landing_page.dart';
import 'l10n/strings.dart';
import 'main.dart'; // themeNotifier / localeNotifier प्रयोग गर्नको लागि

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDeleting = false;

  // Appearance (Light / Dark / System) छान्ने पपअप
  void _showAppearanceOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        Widget row(IconData icon, String label, ThemeMode mode) => ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: themeNotifier.value == mode
                  ? const Icon(Icons.check, color: Color(0xFFC1F11D))
                  : null,
              onTap: () {
                themeNotifier.value = mode;
                Navigator.pop(context);
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
                  ? const Icon(Icons.check, color: Color(0xFFC1F11D))
                  : null,
              onTap: () {
                localeNotifier.value = Locale(code);
                Navigator.pop(context);
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
      await FirebaseAuth.instance.signOut();
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

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFC1F11D);
    return Scaffold(
      appBar: AppBar(title: Text(S.settings)),
      body: _isDeleting
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6, color: accent),
                  title: Text(S.appearance),
                  subtitle: Text(_themeModeLabel()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAppearanceOptions,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.language, color: accent),
                  title: Text(S.language),
                  subtitle:
                      Text(S.isNepali ? 'नेपाली' : 'English'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showLanguageOptions,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.description, color: accent),
                  title: Text(S.legalDocuments),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
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
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.orange),
                  title: Text(S.logOut),
                  onTap: _confirmLogout,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(S.deleteAccount,
                      style: const TextStyle(color: Colors.red)),
                  onTap: _confirmDeleteAccount,
                ),
              ],
            ),
    );
  }
}
