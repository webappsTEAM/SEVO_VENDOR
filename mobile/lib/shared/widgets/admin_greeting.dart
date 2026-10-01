import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_controller.dart';

/// Gradient of the admin app bar and the greeting band under it, so the two
/// read as one continuous teal header.
const adminHeaderGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF003B46), Color(0xFF005965), Color(0xFF028090)],
);

/// The teal "Hello, Admin" band that continues the app bar on the admin homes:
/// wave badge, greeting, one-line summary and the Live / Updated stamp. It adds
/// no data of its own — the time is when the screen was last built/refreshed.
class AdminGreeting extends ConsumerWidget {
  const AdminGreeting({super.key, this.updatedAt});

  /// Time shown as "Updated …"; defaults to now.
  final DateTime? updatedAt;

  /// First name when the profile has one, otherwise `Admin`.
  static String nameFor(String? firstName) {
    final n = firstName?.trim() ?? '';
    return n.isEmpty ? 'Admin' : n;
  }

  /// `4:14 PM`.
  static String timeLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final name = nameFor(user?.firstName);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: Container(
        decoration: const BoxDecoration(gradient: adminHeaderGradient),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              right: 60,
              bottom: -60,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                6,
                AppSpacing.md,
                22,
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  // Narrow screens / large text: the Live stamp drops under the greeting.
                  final narrow =
                      c.maxWidth < 380 ||
                      MediaQuery.textScalerOf(context).scale(10) > 12;
                  final stamp = _LiveStamp(
                    text: 'Updated ${timeLabel(updatedAt ?? DateTime.now())}',
                    alignEnd: !narrow,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Icon(
                              Icons.waving_hand_rounded,
                              size: 28,
                              color: Color(0xFFFFC94D),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hello, $name',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  "Here's what's happening with your workforce today.",
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.3,
                                    color: Color(0xE6FFFFFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!narrow) ...[const SizedBox(width: 8), stamp],
                        ],
                      ),
                      if (narrow)
                        Padding(
                          padding: const EdgeInsets.only(top: 10, left: 66),
                          child: stamp,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "● Live" pill with the "Updated h:mm AM/PM" caption.
class _LiveStamp extends StatelessWidget {
  const _LiveStamp({required this.text, required this.alignEnd});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: Color(0xFF34D399)),
          SizedBox(width: 6),
          Text(
            'Live',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
    final caption = Text(
      text,
      style: const TextStyle(fontSize: 11, color: Color(0xCCFFFFFF)),
    );
    if (alignEnd) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [pill, const SizedBox(height: 6), caption],
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [pill, caption],
    );
  }
}
