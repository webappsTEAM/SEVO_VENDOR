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
          child: Icon(Icons.handyman_rounded, size: size * 0.55, color: Colors.white),
        ),
      ),
    );
  }
}

/// Standard SEVO branded header title used across all screens.
///
/// Features:
/// - Prominent stylized 'SEVO' logo text with cyan gradient 'V' matching the Jobs screen
/// - Clean brand presence across all AppBars
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
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SE',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
                height: 1.05,
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00F5D4), Color(0xFF00BBF9)],
              ).createShader(bounds),
              child: Text(
                'V',
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
            Text(
              'O',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
                height: 1.05,
              ),
            ),
          ],
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
