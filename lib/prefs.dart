// prefs.dart
// theme / भाषा / notification setting लाई disk मा save/load (restart पछि पनि रहोस्)।
// web मा localStorage, mobile मा native prefs — shared_preferences ले सम्हाल्छ।
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_globals.dart';

class Prefs {
  Prefs._();

  static SharedPreferences? _p;
  static const _kTheme = 'settings.themeMode';
  static const _kLocale = 'settings.locale';
  static const _kNotif = 'settings.notifications';

  /// `runApp` अघि एकपटक — save गरेको setting notifier हरूमा लोड।
  static Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();

      final tm = _p!.getString(_kTheme);
      if (tm != null) {
        themeNotifier.value = ThemeMode.values.firstWhere(
          (m) => m.name == tm,
          orElse: () => ThemeMode.dark,
        );
      }
      final loc = _p!.getString(_kLocale);
      if (loc != null && (loc == 'en' || loc == 'ne')) {
        localeNotifier.value = Locale(loc);
      }

      final n = _p!.getBool(_kNotif);
      if (n != null) notificationsEnabled.value = n;
    } catch (_) {
      // prefs नपाए default मै चल्छ
    }

    // भविष्यका परिवर्तन आफै persist हुन्।
    themeNotifier
        .addListener(() => _p?.setString(_kTheme, themeNotifier.value.name));
    localeNotifier.addListener(
        () => _p?.setString(_kLocale, localeNotifier.value.languageCode));
    notificationsEnabled
        .addListener(() => _p?.setBool(_kNotif, notificationsEnabled.value));
  }
}
