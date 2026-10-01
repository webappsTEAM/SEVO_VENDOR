import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/home_dashboard_widgets.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../../jobs/domain/job.dart';
import '../../domain/superadmin_dashboard.dart';

const _teal = Color(0xFF005965);

/// One dense row of the Recent Operations list: booking id, customer, service,
/// location on the left; status, schedule and the Dispatch button on the right.
class RecentOperationCard extends StatelessWidget {
  const RecentOperationCard({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final customer = job.customerName?.trim();
    final address = job.address?.trim();
    final date = job.preferredDate?.trim();
    final time = job.preferredTime?.trim();
    final tech = job.technicianName?.trim();

    var schedule = '—';
    if (date != null && date.isNotEmpty) {
      schedule = (time != null && time.isNotEmpty) ? '$date $time' : date;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.requestId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.isDark ? Colors.white : _teal,
                    letterSpacing: 0.2,
                  ),
                ),
                if (customer != null && customer.isNotEmpty)
                  Text(
                    customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  job.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.25,
                  ),
                ),
                if (tech != null && tech.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Technician: $tech',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ),
                if (address != null && address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.25,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: StatusChip(status: job.status, dense: true),
                ),
                const SizedBox(height: 4),
                Text(
                  schedule,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: () => context.push(
                      '${AppRoutes.adminDispatch}?job_id=${job.requestId}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Dispatch'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent Operations & Service Bookings: the header with a "View All Jobs"
/// link and one card of dense rows, or an empty state. Shared by both homes.
class RecentOperationsPanel extends StatelessWidget {
  const RecentOperationsPanel({
    super.key,
    required this.jobs,
    required this.total,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<Job> jobs;
  final int total;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final rows = jobs.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          leading: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: _teal,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
          title: 'Recent Operations & Service Bookings',
          titleSuffix: '($total)',
          linkLabel: 'View All Jobs',
          onLink: () => context.push(AppRoutes.adminJobs),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (rows.isEmpty)
          EmptyState(
            icon: Icons.assignment_outlined,
            title: emptyTitle,
            message: emptyMessage,
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: AppElevation.subtle,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  RecentOperationCard(job: rows[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// RECENT OPERATIONS & SERVICE BOOKINGS section of the Super Admin home.
class SuperAdminRecentOperationsSection extends StatelessWidget {
  const SuperAdminRecentOperationsSection({super.key, required this.data});

  final SuperAdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    return RecentOperationsPanel(
      jobs: data.recentJobs,
      total: data.jobs.length,
      emptyTitle: 'No recent operations or service bookings found.',
      emptyMessage:
          'New customer bookings and workforce activity will appear here.',
    );
  }
}
