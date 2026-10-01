import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The SEVO premium type scale.
///
/// Typeface: **Poppins** (bundled asset font, SIL OFL) — a geometric sans whose
/// round letterforms echo the SEVO wordmark and give the friendly, confident
/// feel of modern quick-commerce apps. Poppins runs wide, so sizes are kept
/// modest; headline figures in particular are small (18–20) and medium weight.
///
/// * Headings use a softened ink ([AppColors.headingText]), never above w700.
/// * Tracking is neutral for text and only widened on small uppercase labels.
/// * Line heights are explicit (Poppins' natural leading is very tall).
/// * Numbers use tabular figures so counts line up.
class SevoText {
  SevoText._();

  static const family = 'Poppins';
  static const _tabular = [FontFeature.tabularFigures()];

  /// Page title (on the hero header it is recoloured white).
  static TextStyle get pageTitle => TextStyle(
    fontFamily: family,
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.headingText,
  );

  /// Page title on narrow phones.
  static TextStyle get pageTitleCompact => pageTitle.copyWith(fontSize: 17);

  /// Line under a page title.
  static TextStyle get pageSubtitle => TextStyle(
    fontFamily: family,
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Section heading inside a screen.
  static TextStyle get section => TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.headingText,
  );

  /// Title of a card or list row.
  static TextStyle get cardTitle => TextStyle(
    fontFamily: family,
    fontSize: 14.5,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.headingText,
  );

  /// Emphasised body line (a person's name, a key value).
  static TextStyle get bodyStrong => TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: AppColors.headingText,
  );

  /// Default reading text.
  static TextStyle get body => TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.bodyText,
  );

  /// Secondary detail (contact lines, helper text).
  static TextStyle get caption => TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// IDs / counts in low emphasis.
  static TextStyle get meta => TextStyle(
    fontFamily: family,
    fontSize: 11.5,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    fontFeatures: _tabular,
  );

  /// Small uppercase label ("REGISTERED VENDORS").
  static TextStyle get overline => TextStyle(
    fontFamily: family,
    fontSize: 10,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    color: AppColors.textMuted,
  );

  /// A headline figure — deliberately compact.
  static TextStyle get metric => TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: AppColors.headingText,
    fontFeatures: _tabular,
  );

  /// Text inside a badge / pill.
  static TextStyle get badge => const TextStyle(
    fontFamily: family,
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Button labels.
  static TextStyle get button => const TextStyle(
    fontFamily: family,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
}
