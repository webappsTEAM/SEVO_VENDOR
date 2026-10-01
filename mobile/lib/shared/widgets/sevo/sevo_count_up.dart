import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';

/// A figure that counts up from 0 to [value] once when it first appears (and
/// re-tweens from the old value if it changes). Ends on the exact value, so
/// tests and screen readers always see the real number. Under reduced motion
/// it shows the value immediately.
class SevoCountUp extends StatelessWidget {
  const SevoCountUp({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReduced || value <= 0) {
      return Text('$value', style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$v', style: style),
    );
  }
}
