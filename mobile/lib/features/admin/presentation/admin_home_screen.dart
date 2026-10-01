import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/admin_greeting.dart';
import '../../../../shared/widgets/app_fade_in.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/workforce_app_bar.dart';
import '../domain/admin_dashboard_metrics.dart';
import 'admin_dashboard_providers.dart';
import 'widgets/action_center_section.dart';
import 'widgets/admin_drawer.dart';
import 'widgets/admin_title_section.dart';
import 'widgets/recent_operations_section.dart';
import 'widgets/workforce_overview_section.dart';

/// The Workforce Operations Center / Admin Home Screen.
///
/// Designed natively for Android portrait mobile devices while preserving the
/// exact hierarchy, information, actions, and visual identity from the live
/// enterprise Operations Center.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardDataProvider);

    return Scaffold(
      appBar: const WorkforceAppBar(
        showStatusSubBar: false,
        showDrawerMenu: true,
        flatBottom: true,
      ),
      drawer: const AdminDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminDashboardDataProvider);
          await ref.read(adminDashboardDataProvider.future);
        },
        child: AsyncValueView<AdminDashboardData>(
          value: dashboardAsync,
          onRetry: () => ref.invalidate(adminDashboardDataProvider),
          builder: (context, data) {
            Widget pad(Widget child) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: child,
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                // Teal greeting band, continuous with the app bar
                const AppFadeIn(child: AdminGreeting()),
                const SizedBox(height: AppSpacing.md),

                // Workforce Operations Center card + primary actions
                pad(
                  AppFadeIn(
                    index: 1,
                    child: AdminTitleSection(
                      onRefresh: () =>
                          ref.invalidate(adminDashboardDataProvider),
                      isRefreshing: dashboardAsync.isLoading,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Center
                pad(
                  AppFadeIn(index: 2, child: ActionCenterSection(data: data)),
                ),
                const SizedBox(height: 20),

                // Workforce Overview
                pad(
                  AppFadeIn(
                    index: 3,
                    child: WorkforceOverviewSection(data: data),
                  ),
                ),
                const SizedBox(height: 20),

                // Recent Operations & Service Bookings
                pad(
                  AppFadeIn(
                    index: 3,
                    child: RecentOperationsSection(data: data),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
