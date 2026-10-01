import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_routes.dart';
import '../../../superadmin/presentation/widgets/workforce_metric_card.dart';
import '../../domain/admin_dashboard_metrics.dart';

/// WORKFORCE OVERVIEW section of the Admin home (shares the panel with the
/// Super Admin home).
class WorkforceOverviewSection extends StatelessWidget {
  const WorkforceOverviewSection({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    return WorkforceOverviewPanel(
      totalRegistered: data.totalRegisteredCount,
      approvedAndActive: data.approvedAndActiveCount,
      onlineAndAvailable: data.onlineAndAvailableCount,
      onActiveJobs: data.onActiveJobsCount,
      pendingReview: data.pendingReviewCount,
      onPendingReview: () => context.push(AppRoutes.adminApplications),
    );
  }
}
