import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/admin/presentation/widgets/admin_drawer.dart';
import '../workforce_app_bar.dart';
import 'sevo_module_art.dart';
import 'sevo_module_transition.dart';
import 'sevo_page_header.dart';
import 'sevo_typography.dart';

/// The one layout every Platform Governance module uses, so they all look and
/// behave identically:
///
/// * light app bar (SEVO wordmark + menu) joined to a teal [SevoHeroHeader]
///   holding the page title, subtitle, an optional action and an optional
///   search field;
/// * a short branded [SevoModuleTransition] over the page as it opens;
/// * pull-to-refresh, the body laid out as a lazy list with 16px gutters;
/// * Poppins for all text inside the page (the drawer keeps its own style).
class SevoModuleScaffold extends StatelessWidget {
  const SevoModuleScaffold({
    super.key,
    required this.module,
    required this.title,
    required this.subtitle,
    required this.children,
    this.onRefresh,
    this.ready = true,
    this.heroTrailing,
    this.heroBottom,
    this.floatingActionButton,
    this.transition = true,
  });

  final SevoModule module;
  final String title;
  final String subtitle;

  /// Body widgets below the hero; each gets the standard horizontal gutter.
  final List<Widget> children;

  /// Pull-to-refresh handler; when null the list is not refreshable.
  final Future<void> Function()? onRefresh;

  /// Whether the module's first data has loaded (lets the transition leave early).
  final bool ready;
  final Widget? heroTrailing;
  final Widget? heroBottom;
  final Widget? floatingActionButton;

  /// Show the branded cover while the module opens. Drill-down pages (details)
  /// pass false; the layout is otherwise identical.
  final bool transition;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl + AppSpacing.md),
      children: [
        SevoHeroHeader(
          title: title,
          subtitle: subtitle,
          trailing: heroTrailing,
          bottom: heroBottom,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final c in children)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: c,
          ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WorkforceAppBar(
        showStatusSubBar: false,
        showDrawerMenu: true,
        flatBottom: true,
      ),
      drawer: const AdminDrawer(),
      floatingActionButton: floatingActionButton,
      body: Theme(
        data: base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: SevoText.family),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: SevoText.family),
          child: () {
            final page = onRefresh == null
                ? list
                : RefreshIndicator(
                    color: AppColors.actionColor,
                    onRefresh: onRefresh!,
                    child: list,
                  );
            return transition
                ? SevoModuleTransition(
                    module: module,
                    ready: ready,
                    child: page,
                  )
                : page;
          }(),
        ),
      ),
    );
  }
}
