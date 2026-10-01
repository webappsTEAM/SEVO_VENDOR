import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/admin/presentation/widgets/admin_drawer.dart';
import '../admin_greeting.dart' show adminHeaderGradient;
import '../app_fade_in.dart';
import '../workforce_app_bar.dart';
import 'sevo_module_art.dart';
import 'sevo_module_transition.dart';
import 'sevo_theme.dart';
import 'sevo_typography.dart';

/// Marks a subtree as living inside a [SevoModuleFrame], so widgets that used
/// to draw their own page title (e.g. `SellerHubHeader`) can show only their
/// actions and avoid repeating the title the frame already displays.
class SevoFrameScope extends InheritedWidget {
  const SevoFrameScope({super.key, required super.child});

  static bool isInside(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SevoFrameScope>() != null;

  @override
  bool updateShouldNotify(covariant SevoFrameScope oldWidget) => false;
}

/// The SEVO shell for an existing module screen.
///
/// Unlike [SevoModuleScaffold] (which lays out a list itself), the frame keeps
/// the screen's own scrolling [body] — including its refresh indicator, tabs
/// and controllers — and adds the shared chrome around it:
///
/// * the flat teal app bar joined to a hero band with the page title;
/// * the band collapses when the user scrolls the body down and returns when
///   they scroll back up (or reach the top), so lists keep their full height;
/// * the short branded [SevoModuleTransition] as the module opens;
/// * Poppins + consistent controls via [SevoTheme].
class SevoModuleFrame extends StatefulWidget {
  const SevoModuleFrame({
    super.key,
    required this.module,
    required this.title,
    required this.body,
    this.subtitle,
    this.ready = true,
    this.heroTrailing,
    this.floatingActionButton,
    this.transition = true,
    this.backgroundColor,
    this.withDrawer = true,
    this.showNotifications = true,
  });

  final SevoModule module;
  final String title;
  final String? subtitle;

  /// The screen's existing content (usually a refreshable, scrollable list).
  final Widget body;

  /// Whether the module's first data has loaded (lets the transition leave early).
  final bool ready;
  final Widget? heroTrailing;
  final Widget? floatingActionButton;

  /// Show the branded cover while the module opens (off for drill-down pages).
  final bool transition;
  final Color? backgroundColor;

  /// Admin-style shell with the navigation drawer. Drill-down pages (pushed
  /// from a technician screen) pass `false` to get a back arrow instead.
  final bool withDrawer;
  final bool showNotifications;

  @override
  State<SevoModuleFrame> createState() => _SevoModuleFrameState();
}

class _SevoModuleFrameState extends State<SevoModuleFrame> {
  bool _collapsed = false;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final delta = n.scrollDelta ?? 0;
      if (!_collapsed && delta > 0 && n.metrics.pixels > 56) {
        setState(() => _collapsed = true);
      } else if (_collapsed && delta < -2) {
        setState(() => _collapsed = false);
      }
    }
    if (_collapsed && n.metrics.pixels <= 0) setState(() => _collapsed = false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _Hero(
          title: widget.title,
          subtitle: widget.subtitle,
          trailing: widget.heroTrailing,
          collapsed: _collapsed,
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.body,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: widget.backgroundColor ?? AppColors.background,
      appBar: WorkforceAppBar(
        showStatusSubBar: false,
        showDrawerMenu: widget.withDrawer,
        showNotifications: widget.showNotifications,
        flatBottom: true,
      ),
      drawer: widget.withDrawer ? const AdminDrawer() : null,
      floatingActionButton: widget.floatingActionButton,
      body: SevoTheme.wrap(
        context,
        SevoFrameScope(
          child: widget.transition
              ? SevoModuleTransition(
                  module: widget.module,
                  ready: widget.ready,
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.collapsed,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 340;
    final dur = AppMotion.resolve(const Duration(milliseconds: 260));
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: adminHeaderGradient),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -44,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              left: -36,
              bottom: -56,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Column(
              children: [
                // The title band; shrinks away while scrolling down.
                ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.topCenter,
                    heightFactor: collapsed ? 0 : 1,
                    duration: dur,
                    curve: AppMotion.curve,
                    child: AnimatedOpacity(
                      opacity: collapsed ? 0 : 1,
                      duration: dur,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 14, 0),
                        child: AppFadeIn(
                          duration: AppMotion.entrance,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(
                                      header: true,
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: SevoText.pageTitle.copyWith(
                                          color: Colors.white,
                                          fontSize: narrow ? 17 : 20,
                                        ),
                                      ),
                                    ),
                                    if (subtitle != null &&
                                        subtitle!.isNotEmpty) ...[
                                      const SizedBox(height: 1),
                                      Text(
                                        subtitle!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: SevoText.pageSubtitle.copyWith(
                                          color: const Color(0xCCFFFFFF),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              ?trailing,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
