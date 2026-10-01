import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../app_fade_in.dart';

/// Diameter of the round action buttons in the top bar (34 on narrow phones).
double sevoActionSize(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 360 ? 34 : 38;

/// A frosted "glass" round button for the teal app bar: translucent white fill,
/// a hairline highlight border, a soft ripple and a small press-scale. All the
/// top-bar icons (theme, search, notifications) are built on it so they read as
/// one family. Enters with a short fade; [index] staggers a row of them.
class SevoGlassButton extends StatefulWidget {
  const SevoGlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
    this.index = 0,
  });

  final Widget child;
  final VoidCallback onPressed;
  final String tooltip;
  final int index;

  @override
  State<SevoGlassButton> createState() => _SevoGlassButtonState();
}

class _SevoGlassButtonState extends State<SevoGlassButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final d = sevoActionSize(context);
    return AppFadeIn(
      index: widget.index,
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedScale(
          scale: _down ? 0.88 : 1,
          duration: AppMotion.resolve(AppMotion.fast),
          curve: AppMotion.curve,
          child: Container(
            width: d,
            height: d,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: _down ? 0.24 : 0.13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                splashColor: Colors.white.withValues(alpha: 0.25),
                highlightColor: Colors.transparent,
                onHighlightChanged: _set,
                onTap: widget.onPressed,
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The notification bell: a glass button that gives a short ring when it first
/// appears with unread items (and whenever the count goes up), and shows a
/// count badge with a soft one-off pulse. Nothing loops, so screens settle.
class SevoBellButton extends StatefulWidget {
  const SevoBellButton({
    super.key,
    required this.unread,
    required this.onPressed,
    this.index = 0,
  });

  final int unread;
  final VoidCallback onPressed;
  final int index;

  @override
  State<SevoBellButton> createState() => _SevoBellButtonState();
}

class _SevoBellButtonState extends State<SevoBellButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.unread > 0 && !AppMotion.isReduced) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _c.forward(from: 0);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SevoBellButton old) {
    super.didUpdateWidget(old);
    if (widget.unread > old.unread && !AppMotion.isReduced) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.unread > 99 ? '99+' : '${widget.unread}';
    return SevoGlassButton(
      index: widget.index,
      tooltip: 'Notifications',
      onPressed: widget.onPressed,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              // decaying wobble, pivoting at the top of the bell
              final t = _c.value;
              final angle = math.sin(t * math.pi * 6) * 0.32 * (1 - t);
              return Transform.rotate(
                angle: angle,
                alignment: Alignment.topCenter,
                child: child,
              );
            },
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 21,
              color: Colors.white,
            ),
          ),
          if (widget.unread > 0)
            Positioned(
              right: -5,
              top: -6,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final pulse = 1 + 0.18 * math.sin(_c.value * math.pi);
                  return Transform.scale(scale: pulse, child: child);
                },
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF005965),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A gradient ring (mint → teal → cyan) with a soft glow around the profile
/// avatar, with the same press-scale as the other top-bar buttons.
class SevoAvatarRing extends StatefulWidget {
  const SevoAvatarRing({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<SevoAvatarRing> createState() => _SevoAvatarRingState();
}

class _SevoAvatarRingState extends State<SevoAvatarRing> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return AppFadeIn(
      index: widget.index,
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: AppMotion.resolve(AppMotion.fast),
          curve: AppMotion.curve,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xFF34D399),
                  Color(0xFF22D3EE),
                  Color(0xFF10B981),
                  Color(0xFF34D399),
                ],
              ),
              boxShadow: [BoxShadow(color: Color(0x5510B981), blurRadius: 10)],
            ),
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF003B46),
              ),
              child: ClipOval(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
