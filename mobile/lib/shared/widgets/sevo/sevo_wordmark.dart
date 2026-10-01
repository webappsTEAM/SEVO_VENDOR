import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';

/// The official SEVO wordmark: geometric letters with the E drawn as three
/// rounded bars whose middle bar is SEVO green.
///
/// Static by default. With [animate] the white letters fade up first, then the
/// green bar of the E wipes in left-to-right with a soft glow — a short, single
/// play (~[duration]) that is skipped under reduced motion. Both modes render
/// the same artwork at the same size, so it can replace plain "Sevo" text
/// anywhere.
class SevoWordmark extends StatefulWidget {
  const SevoWordmark({
    super.key,
    this.height = 28,
    this.animate = false,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 900),
  });

  final double height;
  final bool animate;
  final Duration delay;
  final Duration duration;

  // Source artwork is 1864 × 345.
  static const double aspect = 1864 / 345;

  @override
  State<SevoWordmark> createState() => _SevoWordmarkState();
}

class _SevoWordmarkState extends State<SevoWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool get _animated => widget.animate && !AppMotion.isReduced;

  @override
  void initState() {
    super.initState();
    if (_animated) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final w = h * SevoWordmark.aspect;
    return Semantics(
      label: 'SEVO',
      child: ExcludeSemantics(
        child: SizedBox(
          width: w,
          height: h,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final letters = Curves.easeOut.transform(
                (t / 0.45).clamp(0.0, 1.0),
              );
              final wipe = Curves.easeInOutCubic.transform(
                ((t - 0.35) / 0.5).clamp(0.0, 1.0),
              );
              final glow = t < 0.8 ? 0.0 : ((t - 0.8) / 0.2).clamp(0.0, 1.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: letters,
                    child: Transform.translate(
                      offset: Offset(0, (1 - letters) * h * 0.18),
                      child: Image.asset(
                        'assets/images/sevo_wordmark_letters.png',
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  // green bar of the E, revealed left-to-right
                  ClipRect(
                    clipper: _WipeClipper(wipe),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: glow > 0
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(
                                    alpha:
                                        0.35 *
                                        (1 - (glow - 0.5).abs() * 2).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                  ),
                                  blurRadius: h * 0.5,
                                ),
                              ]
                            : null,
                      ),
                      child: Image.asset(
                        'assets/images/sevo_wordmark_bar.png',
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Reveals the bar layer from its left edge to [progress] × width of the bar's
/// own span (x 491…871 of 1864), so the wipe starts exactly at the E.
class _WipeClipper extends CustomClipper<Rect> {
  _WipeClipper(this.progress);

  final double progress;

  static const _barLeft = 491 / 1864;
  static const _barRight = 871 / 1864;

  @override
  Rect getClip(Size size) {
    final left = size.width * _barLeft;
    final right = size.width * (_barLeft + (_barRight - _barLeft) * progress);
    return Rect.fromLTRB(left - 1, 0, right + 1, size.height);
  }

  @override
  bool shouldReclip(covariant _WipeClipper old) => old.progress != progress;
}
