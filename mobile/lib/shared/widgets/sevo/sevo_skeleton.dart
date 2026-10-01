import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';

/// Wraps skeleton blocks in one shared shimmer sweep. Under reduced motion the
/// blocks stay static.
class SevoShimmer extends StatefulWidget {
  const SevoShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SevoShimmer> createState() => _SevoShimmerState();
}

class _SevoShimmerState extends State<SevoShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (!AppMotion.isReduced) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surfaceMuted;
    final glow = AppColors.isDark
        ? const Color(0xFF2A3850)
        : const Color(0xFFF8FAFC);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final t = _c.value;
            return LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, -0.3),
              end: Alignment(-0.6 + 3.2 * t, 0.3),
              colors: [base, glow, base],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(rect);
          },
          child: child,
        );
      },
    );
  }
}

/// A single rounded placeholder block.
class SevoSkeletonBox extends StatelessWidget {
  const SevoSkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A card-shaped skeleton (avatar + two lines + footer chips) for list screens.
class SevoCardSkeleton extends StatelessWidget {
  const SevoCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SevoSkeletonBox(width: 44, height: 44, radius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SevoSkeletonBox(width: 150, height: 14),
                    SizedBox(height: 8),
                    SevoSkeletonBox(width: 90, height: 10),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SevoSkeletonBox(height: 10),
          SizedBox(height: 8),
          SevoSkeletonBox(width: 180, height: 10),
          SizedBox(height: 16),
          Row(
            children: [
              SevoSkeletonBox(width: 70, height: 22, radius: 11),
              Spacer(),
              SevoSkeletonBox(width: 96, height: 30, radius: 10),
            ],
          ),
        ],
      ),
    );
  }
}

/// A list of [count] card skeletons under one shimmer.
class SevoListSkeleton extends StatelessWidget {
  const SevoListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SevoShimmer(
        child: Column(
          children: [for (var i = 0; i < count; i++) const SevoCardSkeleton()],
        ),
      ),
    );
  }
}
