import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/admin_greeting.dart';
import '../../../shared/widgets/app_fade_in.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/workforce_app_bar.dart';
import '../../admin/presentation/widgets/admin_drawer.dart';
import '../domain/superadmin_dashboard.dart';
import 'superadmin_dashboard_providers.dart';
import 'widgets/action_center_card.dart';
import 'widgets/recent_operation_card.dart';
import 'widgets/superadmin_dashboard_header.dart';
import 'widgets/workforce_metric_card.dart';

/// The official Super Admin Platform Dashboard (Workforce Operations Center).
///
/// Provides live monitoring, dossier verification, and dynamic dispatch overview
/// natively adapted for mobile screens with zero mock data.
class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(superAdminDashboardDataProvider);

    return Scaffold(
      appBar: const WorkforceAppBar(
        showStatusSubBar: false,
        showDrawerMenu: true,
        flatBottom: true,
      ),
      drawer: const AdminDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(superAdminDashboardDataProvider);
          await ref.read(superAdminDashboardDataProvider.future);
        },
        child: AsyncValueView<SuperAdminDashboardData>(
          value: dashboardAsync,
          errorMessage: 'Unable to load platform dashboard',
          onRetry: () => ref.invalidate(superAdminDashboardDataProvider),
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
                    child: SuperAdminDashboardHeader(
                      onRefresh: () =>
                          ref.invalidate(superAdminDashboardDataProvider),
                      isRefreshing: dashboardAsync.isLoading,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Center
                pad(
                  AppFadeIn(
                    index: 2,
                    child: SuperAdminActionCenterSection(data: data),
                  ),
                ),
                const SizedBox(height: 20),

                // Workforce Overview
                pad(
                  AppFadeIn(
                    index: 3,
                    child: SuperAdminWorkforceOverviewSection(data: data),
                  ),
                ),
                const SizedBox(height: 20),

                // Recent Operations & Service Bookings
                pad(
                  AppFadeIn(
                    index: 3,
                    child: SuperAdminRecentOperationsSection(data: data),
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
