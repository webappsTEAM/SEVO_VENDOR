import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/domain/appearance_preferences.dart';
import '../../features/settings/presentation/providers/appearance_providers.dart';
import '../../core/theme/app_motion.dart';
import 'sevo/sevo_app_bar_actions.dart';

/// Theme mode toggle (light ☀️ / dark 🌙) for app bars, as a frosted glass
/// button. The icon morphs with a short rotate + scale + fade.
///
/// - Live instant switching of app brightness & palette
/// - Persists preference via AppearanceController
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({
    super.key,
    this.color = Colors.white,
    this.size = 20,
    this.index = 0,
  });

  final Color color;
  final double size;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(currentAppearanceProvider);
    final isDark = appearance.theme == AppThemeMode.dark;

    return SevoGlassButton(
      index: index,
      tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
      onPressed: () =>
          ref.read(appearanceControllerProvider.notifier).toggleThemeMode(),
      child: AnimatedSwitcher(
        duration: AppMotion.resolve(const Duration(milliseconds: 320)),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(anim),
          child: ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
        ),
        child: Icon(
          isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          key: ValueKey(isDark),
          color: isDark ? const Color(0xFFFFD166) : color,
          size: size,
        ),
      ),
    );
  }
}
