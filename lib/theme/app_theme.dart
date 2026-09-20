// theme/app_theme.dart
//
// inDrive-inspired layout + Instagram signature gradient (purple → pink → orange)
// as the sole accent. No green anywhere: pill-shaped buttons, large rounded
// cards, bold headings. Light र dark दुवै variant छ; inDrive जस्तै default dark
// हो (app_globals.dart).
import 'package:flutter/material.dart';

/// एपभरि प्रयोग हुने रंगहरू। Screen हरूमा सिधै `Colors.green` नलेखी यी token
/// प्रयोग गर्नुहोस् (वा `Theme.of(context).colorScheme`).
class AppColors {
  AppColors._();

  // Brand accent — Instagram-style vibrant (lime हटाइयो)।
  // पुरानो नाम `lime` राखिएको छ ताकि ठाउँ-ठाउँका reference नबिग्रियोस्; अब यो
  // brand accent (magenta/pink) हो।
  static const lime = Color(0xFFE1306C); // Instagram pink/magenta
  static const limePressed = Color(0xFFC13584); // deeper magenta
  static const onLime = Color(0xFFFFFFFF); // accent माथिको text/icon (सेतो)

  // Instagram gradient stops
  static const igViolet = Color(0xFF833AB4);
  static const igPink = Color(0xFFE1306C);
  static const igOrange = Color(0xFFF77737);
  static const igAmber = Color(0xFFFCAF45);

  // Instagram spec: linear-gradient(45deg, #833ab4, #fd1d1d, #fcb045)
  static const igRed = Color(0xFFFD1D1D); // pink/magenta-red
  static const igYellow = Color(0xFFFCB045); // orange/yellow

  /// ठ्याक्कै Instagram 45° gradient — panel / dashboard / form background मा।
  static const igGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight, // ≈ 45deg
    colors: [igViolet, igRed, igYellow],
  );

  /// Full-screen auth background — माथि dark anchor ताकि सेतो text पढियोस्।
  static const instaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2A0A4A),
      igViolet,
      igRed,
      igYellow,
    ],
    stops: [0.0, 0.32, 0.66, 1.0],
  );

  /// छोटो gradient — button हरूको लागि।
  static const buttonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [igViolet, igRed, igYellow],
  );

  // Dark surfaces
  static const bgDark = Color(0xFF0B0B0C);
  static const surfaceDark = Color(0xFF17181A);
  static const surfaceDarkAlt = Color(0xFF212327);
  static const borderDark = Color(0xFF2B2D31);
  static const textDark = Color(0xFFFFFFFF);
  static const textMutedDark = Color(0xFF9A9DA3);

  // Light surfaces
  static const bgLight = Color(0xFFF5F6F4);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceLightAlt = Color(0xFFEDEFEA);

  // Google Maps ले natively नरेन्डर गर्दासम्म देखिने खाली माटो-रङ tile
  // background — Google Maps SDK आफैंले पनि नक्सा तयार नहुँदासम्म यही रङ
  // देखाउँछ। नक्सा भएको स्क्रिनको Scaffold background यही राखे, native
  // platform view attach हुनुअघिको क्षणभरको खाली ठाउँमा (dark theme को
  // झन्डै-कालो पृष्ठभूमिको सट्टा) यही हल्का रङ देखिन्छ — त्यसैले नक्सा
  // पपअप हुँदा कालो-देखि-हल्को कुनै jarring flash हुँदैन, सहज देखिन्छ।
  static const mapPlaceholderBg = Color(0xFFE5E3DF);
  static const borderLight = Color(0xFFE3E5E0);
  static const textLight = Color(0xFF0B0B0C);
  static const textMutedLight = Color(0xFF6A6E75);

  // Status — green हटाइयो; "positive / done / active" अब brand magenta-pink।
  static const success = Color(0xFFE1306C);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF5A5F);
}

/// साझा border-radius मानहरू।
class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const pill = 999.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceAlt =
        isDark ? AppColors.surfaceDarkAlt : AppColors.surfaceLightAlt;
    final text = isDark ? AppColors.textDark : AppColors.textLight;
    final muted = isDark ? AppColors.textMutedDark : AppColors.textMutedLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.lime,
      onPrimary: AppColors.onLime,
      primaryContainer: AppColors.lime,
      onPrimaryContainer: AppColors.onLime,
      secondary: AppColors.lime,
      onSecondary: AppColors.onLime,
      tertiary: AppColors.lime,
      onTertiary: AppColors.onLime,
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
    );

    final baseText =
        (isDark ? Typography.whiteMountainView : Typography.blackMountainView);

    TextStyle h(double size, FontWeight w) =>
        TextStyle(fontSize: size, fontWeight: w, color: text, height: 1.15);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      splashColor: AppColors.lime.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: text),
      primaryIconTheme: IconThemeData(color: text),
      textTheme: baseText.copyWith(
        displaySmall: h(30, FontWeight.w800),
        headlineMedium: h(24, FontWeight.w800),
        headlineSmall: h(20, FontWeight.w700),
        titleLarge: h(18, FontWeight.w700),
        titleMedium: h(16, FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 15, color: text, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, color: text, height: 1.35),
        bodySmall: TextStyle(fontSize: 12.5, color: muted, height: 1.3),
        labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: text,
        titleTextStyle: h(20, FontWeight.w700),
        iconTheme: IconThemeData(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed)
                  ? AppColors.limePressed
                  : AppColors.lime),
          foregroundColor: const WidgetStatePropertyAll(AppColors.onLime),
          overlayColor: const WidgetStatePropertyAll(Color(0x1A000000)),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill))),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(text),
          side: WidgetStatePropertyAll(BorderSide(color: border, width: 1.5)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill))),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.lime),
          textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.lime, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: AppColors.lime,
        disabledColor: surfaceAlt,
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: AppColors.onLime),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.lime,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.lime.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.horizontal(right: Radius.circular(AppRadius.lg)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: text,
        textColor: text,
        titleTextStyle:
            TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text),
        subtitleTextStyle: TextStyle(fontSize: 13, color: muted),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        titleTextStyle: h(18, FontWeight.w700),
        contentTextStyle: TextStyle(fontSize: 14, color: muted, height: 1.4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.surfaceDarkAlt : const Color(0xFF1B1C1E),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.lime,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: muted,
        indicatorColor: AppColors.lime,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.lime),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.lime,
        foregroundColor: AppColors.onLime,
      ),
    );
  }
}
