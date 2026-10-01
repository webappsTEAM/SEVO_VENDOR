import 'package:flutter/material.dart';

import '../../../superadmin/presentation/widgets/recent_operation_card.dart';
import '../../domain/admin_dashboard_metrics.dart';

/// RECENT OPERATIONS & SERVICE BOOKINGS section of the Admin home.
class RecentOperationsSection extends StatelessWidget {
  const RecentOperationsSection({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    return RecentOperationsPanel(
      jobs: data.recentJobs,
      total: data.jobs.length,
      emptyTitle: 'No Active Operations',
      emptyMessage: 'No active customer service operations in queue.',
    );
  }
}
