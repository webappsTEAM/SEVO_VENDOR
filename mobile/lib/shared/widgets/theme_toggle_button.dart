import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/domain/appearance_preferences.dart';
import '../../features/settings/presentation/providers/appearance_providers.dart';

/// Instant Theme Mode Toggle Button (Light ☀️ / Dark 🌙) for AppBar and headers.
///
/// Features:
/// - Smooth animated icon transition between sun and moon
/// - Live instant switching of app brightness & palette
/// - Persists preference via AppearanceController
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({
    super.key,
    this.color = Colors.white,
    this.size = 21,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(currentAppearanceProvider);
    final isDark = appearance.theme == AppThemeMode.dark;

    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
          key: ValueKey(isDark),
          color: color,
          size: size,
        ),
      ),
      tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: () {
        ref.read(appearanceControllerProvider.notifier).toggleThemeMode();
      },
    );
  }
}
