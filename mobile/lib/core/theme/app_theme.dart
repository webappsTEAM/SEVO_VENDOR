import 'package:flutter/material.dart';

import '../../features/settings/domain/appearance_preferences.dart';

/// Brand colors, matched to the existing web app's Tailwind palette.
///
/// `background`/`surface`/`border`/`textPrimary`/`textSecondary`/`textMuted`
/// are computed getters, not literal constants, driven by [configure] —
/// called once per frame from app.dart's build(), before any child widget
/// builds. This is a deliberate, pragmatic choice: the app has hundreds of
/// widgets that reference `AppColors.textPrimary` etc. directly (not via
/// `Theme.of(context)`), inherited from earlier phases. Converting every
/// call site to be theme-aware was out of scope for the Settings phase, so
/// this makes the existing call sites automatically pick up dark mode and
/// high contrast without changing them, at the cost of a small global-state
/// pattern instead of Flutter's usual InheritedWidget theming.
/// Model representing a semantic family (base, tint, tintBorder, onTint)
/// matching the web app's Tailwind enterprise styling.
class SemanticColor {
  const SemanticColor({
    required this.base,
    required this.tint,
    required this.tintBorder,
    required this.onTint,
  });

  final Color base;
  final Color tint;
  final Color tintBorder;
  final Color onTint;
}

class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.light;
  static bool _highContrast = false;

  static void configure({required Brightness brightness, required bool highContrast}) {
    _brightness = brightness;
    _highContrast = highContrast;
  }

  static bool get isDark => _brightness == Brightness.dark;
  static bool get _isDark => isDark;

  // SEVO Brand & Teal Palette (The source of truth matching Jobs UI)
  static const Color peacockNavy = Color(0xFF003B46); // Deep SEVO Teal
  static const Color peacockBlue = Color(0xFF005965); // SEVO Teal Primary
  static const Color primary = Color(0xFF005965); // SEVO Teal
  static const Color primaryDark = Color(0xFF003B46); // Deep Teal
  static const Color primaryLight = Color(0xFF028090); // Cyan Accent
  static const Color primaryAccent = Color(0xFF0D9488); // Teal Green
  static const Color accent = Color(0xFFF59E0B); // Amber
  static const Color emerald = Color(0xFF059669);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkSurface = Color(0xFF003B46);
  static Color get selectedTint => _isDark ? const Color(0xFF005965).withValues(alpha: 0.25) : const Color(0xFFE6F4F1);
  static Color get selectedOnTint => _isDark ? const Color(0xFF2DD4BF) : const Color(0xFF005965);

  // SEVO Header Gradient
  static const LinearGradient peacockGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF003B46), // Deep Teal
      Color(0xFF005965), // SEVO Teal
      Color(0xFF028090), // Cyan accent
    ],
  );

  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF003B46),
      Color(0xFF005965),
      Color(0xFF028090),
    ],
  );

  // Semantic color families
  static const SemanticColor success = SemanticColor(
    base: Color(0xFF15803D),
    tint: Color(0xFFDCFCE7),
    tintBorder: Color(0xFFBBF7D0),
    onTint: Color(0xFF15803D),
  );

  static const SemanticColor error = SemanticColor(
    base: Color(0xFFDC2626),
    tint: Color(0xFFFFE4E6),
    tintBorder: Color(0xFFFECDD3),
    onTint: Color(0xFFBE123C),
  );

  static const SemanticColor warning = SemanticColor(
    base: Color(0xFFD97706),
    tint: Color(0xFFFEF3C7),
    tintBorder: Color(0xFFFDE68A),
    onTint: Color(0xFF92400E),
  );

  static const SemanticColor info = SemanticColor(
    base: Color(0xFF0284C7),
    tint: Color(0xFFE0F2FE),
    tintBorder: Color(0xFFBAE6FD),
    onTint: Color(0xFF0369A1),
  );

  // Dynamic semantic badge helpers that adapt to dark theme
  static Color get successBg => _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFECFDF5);
  static Color get successBorder => _isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0);
  static Color get successText => _isDark ? const Color(0xFF34D399) : const Color(0xFF047857);

  static Color get warningBg => _isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7);
  static Color get warningBorder => _isDark ? const Color(0xFF92400E) : const Color(0xFFFDE68A);
  static Color get warningText => _isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

  static Color get errorBg => _isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.35) : const Color(0xFFFEF2F2);
  static Color get errorBorder => _isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA);
  static Color get errorText => _isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B);

  static Color get infoBg => _isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.35) : const Color(0xFFEFF6FF);
  static Color get infoBorder => _isDark ? const Color(0xFF1E40AF) : const Color(0xFFBFDBFE);
  static Color get infoText => _isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

  static Color get surfaceMuted => _isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

  static Color get background =>
      _isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);

  static Color get surface => _isDark ? const Color(0xFF151E2E) : Colors.white;

  static Color get border {
    if (_isDark) return _highContrast ? Colors.white54 : const Color(0xFF243044);
    return _highContrast ? Colors.black54 : const Color(0xFFE2E8F0);
  }

  static Color get textPrimary {
    if (_isDark) return _highContrast ? Colors.white : const Color(0xFFF1F5F9);
    return _highContrast ? Colors.black : const Color(0xFF0F172A);
  }

  static Color get textSecondary =>
      _isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);

  static Color get textMuted => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);
}

/// A small, consistent spacing scale used across every screen so padding
/// and gaps don't drift screen-to-screen.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  AppRadius._();

  static const double card = 16;
  static const double cardStandard = 16;
  static const double chip = 10;
  static const double button = 10;
  static const double input = 12;
  static const double sheet = 20;
  static const double pill = 999;
}

class AppElevation {
  AppElevation._();

  static const List<BoxShadow> none = [];
  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x060A2540),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x0E0A2540),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}

/// A page transition that swaps instantly — used app-wide when the user
/// enables "Reduce Animations & Transitions".
class InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

Color colorForAccent(AccentColorOption accent) {
  switch (accent) {
    case AccentColorOption.blue:
      return const Color(0xFF005965);
    case AccentColorOption.emerald:
      return const Color(0xFF059669);
    case AccentColorOption.indigo:
      return const Color(0xFF4F46E5);
    case AccentColorOption.violet:
      return const Color(0xFF7C3AED);
    case AccentColorOption.amber:
      return const Color(0xFFD97706);
  }
}

class AppTheme {
  AppTheme._();

  /// Builds the live ThemeData for the given resolved appearance.
  /// `AppColors.configure(...)` must be called with the same brightness/
  /// high-contrast values before this widget tree builds, so the two stay
  /// in sync — app.dart does this immediately before calling build().
  static ThemeData build({
    required Brightness brightness,
    required AccentColorOption accent,
    required LayoutDensityOption density,
    required bool highContrast,
    required bool reducedMotion,
  }) {
    final seed = colorForAccent(accent);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: const Color(0xFF005965),
    );

    final pageTransitionsTheme = reducedMotion
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: InstantPageTransitionsBuilder(),
              TargetPlatform.iOS: InstantPageTransitionsBuilder(),
            },
          )
        : const PageTransitionsTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      visualDensity: density == LayoutDensityOption.compact
          ? VisualDensity.compact
          : VisualDensity.standard,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.surface,
      pageTransitionsTheme: pageTransitionsTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF003B46),
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border, width: highContrast ? 1.4 : 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: highContrast ? 1.2 : 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF005965),
        elevation: 4,
        shadowColor: const Color(0x12000000),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected
                ? (brightness == Brightness.dark ? const Color(0xFF38BDF8) : const Color(0xFF005965))
                : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? Colors.white : AppColors.textSecondary,
            size: 22,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF005965),
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF005965),
          side: const BorderSide(color: Color(0xFF005965)),
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontSize: 15, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.6,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF005965), width: 1.5),
        ),
        hintStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textMuted,
        ),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),
    );
  }
}
