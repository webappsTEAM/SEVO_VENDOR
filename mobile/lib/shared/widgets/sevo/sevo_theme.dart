import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'sevo_typography.dart';

/// Applies the SEVO look to everything inside a module page, without editing
/// each widget: Poppins text, consistent button / input / dialog / tab shapes
/// and the brand action colour. Colours come from [AppColors], so light and
/// dark both work.
class SevoTheme {
  SevoTheme._();

  /// Poppins runs about 6–8% wider than Roboto. Existing dense screens were
  /// laid out for Roboto, so their text is scaled by this factor (on top of the
  /// user's own accessibility text scale) to keep every row fitting.
  static const double legacyTextScale = 0.94;

  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    final action = AppColors.actionColor;
    final radius12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: SevoText.family),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: SevoText.family,
      ),
      colorScheme: base.colorScheme.copyWith(primary: action),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: action,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          shape: radius12,
          textStyle: SevoText.button.copyWith(fontSize: 13),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: action,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 44),
          shape: radius12,
          textStyle: SevoText.button.copyWith(fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.isDark ? Colors.white : AppColors.primary,
          side: BorderSide(
            color: AppColors.isDark
                ? AppColors.border
                : AppColors.primary.withValues(alpha: 0.55),
          ),
          minimumSize: const Size(0, 44),
          shape: radius12,
          textStyle: SevoText.button.copyWith(fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentOnSurface,
          shape: radius12,
          textStyle: SevoText.button.copyWith(fontSize: 13),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: SevoText.caption,
        hintStyle: SevoText.body.copyWith(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: action, width: 1.6),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: AppColors.elevatedSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: SevoText.section.copyWith(fontSize: 16),
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: AppColors.accentOnSurface,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: action,
        labelStyle: SevoText.button,
        unselectedLabelStyle: SevoText.button.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        backgroundColor: AppColors.surface,
        selectedColor: action,
        side: BorderSide(color: AppColors.border),
        labelStyle: SevoText.badge.copyWith(
          fontSize: 12,
          color: AppColors.bodyText,
        ),
        secondaryLabelStyle: SevoText.badge.copyWith(
          fontSize: 12,
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: radius12,
        contentTextStyle: SevoText.body.copyWith(color: Colors.white),
      ),
    );
  }

  /// Wraps [child] with the SEVO theme, Poppins default text and the legacy
  /// text-scale compensation.
  static Widget wrap(
    BuildContext context,
    Widget child, {
    bool compensateLegacyWidth = true,
  }) {
    final mq = MediaQuery.of(context);
    final userScale = mq.textScaler.scale(100) / 100;
    return Theme(
      data: of(context),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: SevoText.family),
        child: compensateLegacyWidth
            ? MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(userScale * legacyTextScale),
                ),
                child: child,
              )
            : child,
      ),
    );
  }
}
