import 'package:flutter/material.dart';

/// The small SEVO logo mark used in AppBar titles across the app.
///
/// Centralizes the `sevo_logo.png` + fallback-icon treatment that
/// [WorkforceAppBar] already used inline, so every other header (Jobs,
/// Services, Documents, Locations, detail screens, ...) can show the same
/// brand mark next to its title instead of plain text.
class SevoBrandMark extends StatelessWidget {
  const SevoBrandMark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.25;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/sevo_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Icon(
            Icons.handyman_rounded,
            size: size * 0.55,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Standard SEVO branded header title used across all screens.
///
/// Shows the official wordmark (`sevo_name_white.png`): geometric letters with
/// the E drawn as three rounded bars whose middle bar is SEVO green. Sized from
/// [fontSize] so existing call sites keep their proportions. If the asset is
/// unavailable it falls back to plain text.
class SevoHeaderTitle extends StatelessWidget {
  const SevoHeaderTitle({
    super.key,
    this.moduleName,
    this.subtitle,
    this.fontSize = 22,
    this.subtitleFontSize = 10,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String? moduleName;
  final String? subtitle;
  final double fontSize;
  final double subtitleFontSize;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle ?? moduleName;
    // The artwork is 5.4:1. 0.6 × fontSize keeps the wordmark in proportion with
    // a ~20px page title (fontSize 22 → 13px tall, ~71px wide).
    final height = fontSize * 0.6;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'SEVO',
          child: Image.asset(
            'assets/images/sevo_name_white.png',
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) => Text(
              'SEVO',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
                height: 1.05,
              ),
            ),
          ),
        ),
        if (sub != null && sub.trim().isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: subtitleFontSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE0F2FE),
              letterSpacing: 0.5,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
  }
}
