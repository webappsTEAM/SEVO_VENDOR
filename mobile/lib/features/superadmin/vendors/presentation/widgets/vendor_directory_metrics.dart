import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_motion.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../../shared/widgets/sevo/sevo_count_up.dart';
import '../../../../../shared/widgets/sevo/sevo_typography.dart';
import '../superadmin_vendor_providers.dart';

/// Overview for the Vendor Directory: the primary "Manage All Workforce"
/// action, two headline metrics, and the platform-status strip.
class VendorDirectoryMetricsCards extends StatelessWidget {
  const VendorDirectoryMetricsCards({
    super.key,
    required this.metrics,
    required this.onManageWorkforce,
  });

  final VendorDirectoryMetrics metrics;
  final VoidCallback onManageWorkforce;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroAction(onTap: onManageWorkforce),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final registered = _MetricTile(
              index: 1,
              label: 'REGISTERED VENDORS',
              value: metrics.registeredVendors,
              icon: Icons.business_rounded,
              accent: const Color(0xFF2563EB),
            );
            final tied = _MetricTile(
              index: 2,
              label: 'TOTAL TIED WORKFORCE',
              value: metrics.totalTiedWorkforce,
              icon: Icons.link_rounded,
              accent: const Color(0xFF059669),
            );
            if (constraints.maxWidth < 330) {
              return Column(
                children: [registered, const SizedBox(height: 10), tied],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: registered),
                  const SizedBox(width: 10),
                  Expanded(child: tied),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Platform status strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shield_rounded,
                size: 20,
                color: AppColors.accentOnSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PLATFORM OPERATIONS', style: SevoText.overline),
                    const SizedBox(height: 2),
                    Text(
                      'Multi-Tenant Architecture Active',
                      style: SevoText.bodyStrong,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.successBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 7, color: AppColors.successText),
                    const SizedBox(width: 5),
                    Text(
                      'LIVE',
                      style: SevoText.badge.copyWith(
                        letterSpacing: 0.6,
                        color: AppColors.successText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The primary "Manage All Workforce" call-to-action: a gradient card with one
/// soft shine sweep shortly after it appears and a small arrow nudge, both
/// finite (no endless animation) and skipped under reduced motion.
class _HeroAction extends StatefulWidget {
  const _HeroAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_HeroAction> createState() => _HeroActionState();
}

class _HeroActionState extends State<_HeroAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!AppMotion.isReduced) {
      _delay = Timer(const Duration(milliseconds: 900), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SevoAnimatedCard(
      gradient: AppColors.heroGradient,
      onTap: widget.onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Stack(
        children: [
          // one-time shine sweep
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Align(
                    alignment: Alignment(
                      -1.6 + 3.4 * Curves.easeInOut.transform(_c.value),
                      0,
                    ),
                    child: Opacity(
                      opacity: _c.value == 0 || _c.value == 1 ? 0 : 1,
                      child: Transform(
                        transform: Matrix4.skewX(-0.35),
                        child: Container(
                          width: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.16),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Manage All Workforce (Solo & Tied)',
                        maxLines: 1,
                        style: SevoText.bodyStrong.copyWith(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Platform-wide technician directory & assignment',
                      style: SevoText.caption.copyWith(
                        fontSize: 11.5,
                        color: const Color(0xCCFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  // two small nudges to the right (decaying) while the shine passes
                  final nudge =
                      math.sin(_c.value * 4 * math.pi).abs() *
                      5 *
                      (1 - _c.value);
                  return Transform.translate(
                    offset: Offset(nudge, 0),
                    child: child,
                  );
                },
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact metric: tinted gradient card, icon chip, a count-up figure and an
/// oversized faint icon watermark for depth.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.index,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final int index;
  final String label;
  final int value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final chip = accent.withValues(alpha: dark ? 0.22 : 0.12);
    final on = dark ? Color.lerp(accent, Colors.white, 0.45)! : accent;
    return SevoAnimatedCard(
      index: index,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [accent.withValues(alpha: 0.16), AppColors.surface]
            : [accent.withValues(alpha: 0.10), Colors.white],
      ),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              top: -12,
              child: ExcludeSemantics(
                child: Icon(
                  icon,
                  size: 70,
                  color: accent.withValues(alpha: dark ? 0.09 : 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: chip,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 19, color: on),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SevoCountUp(value: value, style: SevoText.metric),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SevoText.overline.copyWith(
                            fontSize: 9.5,
                            letterSpacing: 0.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
