import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../admin_greeting.dart' show adminHeaderGradient;
import '../app_fade_in.dart';
import 'sevo_typography.dart';

/// The title block every premium screen starts with, at the top-left of the
/// content area (not in the app bar): a title, an optional subtitle and an
/// optional trailing action. Enters with a short fade + upward settle.
class SevoPageHeader extends StatelessWidget {
  const SevoPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// e.g. a refresh icon button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 340;
    return AppFadeIn(
      duration: AppMotion.entrance,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: narrow
                        ? SevoText.pageTitleCompact
                        : SevoText.pageTitle,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: SevoText.pageSubtitle),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A small section label ("Overview", "All vendors") used between blocks.
class SevoSectionHeader extends StatelessWidget {
  const SevoSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: SevoText.section)),
        ?trailing,
      ],
    );
  }
}

/// A colourful hero header that continues the teal app bar (use with
/// `WorkforceAppBar(flatBottom: true)`): white title + subtitle, an optional
/// trailing action and an optional [bottom] widget (typically the search
/// field), over soft decorative circles and a dotted accent. The title still
/// sits at the top-left of the content, just inside the hero.
class SevoHeroHeader extends StatelessWidget {
  const SevoHeroHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 340;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: adminHeaderGradient),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -46,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              left: -40,
              bottom: -60,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              right: 78,
              top: 10,
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: const Size(56, 40),
                  painter: _DotsPainter(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFadeIn(
                    duration: AppMotion.entrance,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  title,
                                  style:
                                      (narrow
                                              ? SevoText.pageTitleCompact
                                              : SevoText.pageTitle)
                                          .copyWith(
                                            color: Colors.white,
                                            fontSize: narrow ? 18 : 21,
                                          ),
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  style: SevoText.pageSubtitle.copyWith(
                                    color: const Color(0xCCFFFFFF),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                  ),
                  if (bottom != null) ...[
                    const SizedBox(height: 16),
                    AppFadeIn(
                      index: 1,
                      duration: AppMotion.entrance,
                      child: bottom!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.16);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        canvas.drawCircle(Offset(c * 12.0 + 2, r * 12.0 + 2), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
