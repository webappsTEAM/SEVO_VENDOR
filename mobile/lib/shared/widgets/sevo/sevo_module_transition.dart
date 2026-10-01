import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import 'sevo_module_art.dart';
import 'sevo_typography.dart';
import 'sevo_wordmark.dart';

/// SEVO's tagline, shown while a module opens.
const sevoTagline = 'You need it, Sevo for it';

/// A very short branded reveal shown over a module screen as it opens:
/// animated module artwork, the tagline and the module name on the SEVO teal
/// gradient, then a fade into the real page.
///
/// It never delays the page: [child] is built underneath from the first frame
/// (so its data loads immediately). The cover stays for at least [minDuration]
/// so it reads as intentional, leaves as soon as [ready] is true, and is
/// force-removed after [maxDuration] even if data is still loading (the page
/// then shows its own skeleton). Reduced motion skips the cover entirely.
/// It is presentation only — no business logic depends on it.
class SevoModuleTransition extends StatefulWidget {
  const SevoModuleTransition({
    super.key,
    required this.module,
    required this.child,
    this.ready = true,
    this.minDuration = const Duration(milliseconds: 800),
    this.maxDuration = const Duration(milliseconds: 1100),
  });

  final SevoModule module;
  final Widget child;

  /// Whether the destination has what it needs to show (data loaded).
  final bool ready;
  final Duration minDuration;
  final Duration maxDuration;

  @override
  State<SevoModuleTransition> createState() => _SevoModuleTransitionState();
}

class _SevoModuleTransitionState extends State<SevoModuleTransition> {
  Timer? _minTimer;
  Timer? _maxTimer;
  bool _minElapsed = false;
  bool _maxElapsed = false;

  bool get _skip => AppMotion.isReduced;

  @override
  void initState() {
    super.initState();
    if (_skip) return;
    _minTimer = Timer(widget.minDuration, () {
      if (mounted) setState(() => _minElapsed = true);
    });
    _maxTimer = Timer(widget.maxDuration, () {
      if (mounted) setState(() => _maxElapsed = true);
    });
  }

  @override
  void dispose() {
    _minTimer?.cancel();
    _maxTimer?.cancel();
    super.dispose();
  }

  bool get _covering =>
      !_skip && !(_minElapsed && (widget.ready || _maxElapsed));

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedSwitcher(
          duration: AppMotion.resolve(const Duration(milliseconds: 320)),
          switchOutCurve: Curves.easeIn,
          child: _covering
              ? _TransitionCover(
                  key: const ValueKey('sevo-cover'),
                  module: widget.module,
                )
              : const SizedBox.shrink(key: ValueKey('sevo-clear')),
        ),
      ],
    );
  }
}

class _TransitionCover extends StatelessWidget {
  const _TransitionCover({super.key, required this.module});

  final SevoModule module;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final art = (width * 0.74).clamp(200.0, 300.0);
    return Semantics(
      liveRegion: true,
      label: '$sevoTagline. Opening ${module.label}',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF002B34), Color(0xFF005965), Color(0xFF028090)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: AppMotion.resolve(
                        const Duration(milliseconds: 420),
                      ),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - v)),
                          child: child,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SevoModuleArt(module: module, size: art),
                          const SizedBox(height: 28),
                          const Text(
                            'You need it,',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: SevoText.family,
                              fontSize: 22,
                              height: 1.3,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // "Sevo" is drawn as the logo (E with the green bar), then "for it".
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: const [
                              SevoWordmark(
                                height: 30,
                                animate: true,
                                delay: Duration(milliseconds: 80),
                                duration: Duration(milliseconds: 650),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'for it',
                                style: TextStyle(
                                  fontFamily: SevoText.family,
                                  fontSize: 24,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            module.label.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: SevoText.family,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                              color: Color(0xB3FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
