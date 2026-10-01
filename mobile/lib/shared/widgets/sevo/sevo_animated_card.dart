import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../app_fade_in.dart';

/// The premium SEVO card: moderate radius, soft shadow in light theme, a thin
/// border in dark theme, a staggered fade/slide entrance and a subtle press
/// scale when it is tappable.
class SevoAnimatedCard extends StatefulWidget {
  const SevoAnimatedCard({
    super.key,
    required this.child,
    this.index = 0,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.gradient,
    this.animateEntrance = true,
    this.semanticLabel,
  });

  final Widget child;

  /// Position in a list; later cards enter slightly later (capped).
  final int index;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// Replaces the surface colour (used by hero call-to-action cards).
  final Gradient? gradient;
  final bool animateEntrance;
  final String? semanticLabel;

  @override
  State<SevoAnimatedCard> createState() => _SevoAnimatedCardState();
}

class _SevoAnimatedCardState extends State<SevoAnimatedCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    final hero = widget.gradient != null;

    Widget card = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: AppMotion.resolve(AppMotion.fast),
      curve: AppMotion.curve,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: hero ? null : AppColors.surface,
          gradient: widget.gradient,
          borderRadius: radius,
          border: Border.all(
            color: hero ? Colors.transparent : AppColors.border,
          ),
          boxShadow: hero ? null : AppColors.cardShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            onHighlightChanged: _setPressed,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );

    if (widget.semanticLabel != null) {
      card = Semantics(
        label: widget.semanticLabel,
        container: true,
        child: card,
      );
    }
    card = Padding(padding: widget.margin, child: card);
    return widget.animateEntrance
        ? AppFadeIn(
            index: widget.index,
            duration: AppMotion.entrance,
            child: card,
          )
        : card;
  }
}
