import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../domain/admin_dashboard_metrics.dart';
import '../../../../shared/widgets/home_dashboard_widgets.dart';
import 'action_center_card.dart';

/// ACTION CENTER Section:
/// Displays the 4 operational queue cards requiring immediate attention.
class ActionCenterSection extends StatelessWidget {
  const ActionCenterSection({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          accent: const Color(0xFF16A34A),
          title: 'Action Center',
          subtitle: 'Items requiring immediate operational attention',
          linkLabel: 'View All',
          onLink: () => context.push(AppRoutes.adminApplications),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Adaptive Grid of 4 Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = constraints.maxWidth < 340;
            final isWide = constraints.maxWidth >= 600;

            final card1 = ActionCenterCard(
              title: 'Pending Applications',
              description: 'Technician registrations requiring document review',
              count: data.pendingApplicationsCount,
              icon: Icons.assignment_rounded,
              badgeBgColor: AppColors.isDark
                  ? const Color(0xFF78350F).withValues(alpha: 0.35)
                  : const Color(0xFFFEF3C7),
              badgeTextColor: AppColors.isDark
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFF92400E),
              iconBgColor: AppColors.isDark
                  ? const Color(0xFF78350F).withValues(alpha: 0.2)
                  : const Color(0xFFFFFBEB),
              iconColor: AppColors.isDark
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFFD97706),
              onTap: () => context.push(AppRoutes.adminApplications),
            );

            final card2 = ActionCenterCard(
              title: 'Active Technicians',
              description: 'Approved workforce field technicians',
              count: data.activeTechniciansCount,
              icon: Icons.how_to_reg_rounded,
              badgeBgColor: AppColors.isDark
                  ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                  : const Color(0xFFDCFCE7),
              badgeTextColor: AppColors.isDark
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFF166534),
              iconBgColor: AppColors.isDark
                  ? const Color(0xFF064E3B).withValues(alpha: 0.2)
                  : const Color(0xFFF0FDF4),
              iconColor: AppColors.isDark
                  ? const Color(0xFF34D399)
                  : const Color(0xFF16A34A),
              onTap: () => context.push(AppRoutes.adminEmployees),
            );

            final card3 = ActionCenterCard(
              title: 'Jobs Awaiting Assignment',
              description: 'Customer bookings requiring technician dispatch',
              count: data.unassignedJobsCount,
              icon: Icons.send_rounded,
              badgeBgColor: const Color(0xFFDBEAFE),
              badgeTextColor: const Color(0xFF1E3A8A),
              iconBgColor: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF2563EB),
              onTap: () => context.push(AppRoutes.adminDispatch),
            );

            final card4 = ActionCenterCard(
              title: 'Corrections Pending Resubmission',
              description: 'Technicians notified to re-upload flagged files',
              count: data.correctionsPendingCount,
              icon: Icons.edit_note_rounded,
              badgeBgColor: const Color(0xFFEDE9FE),
              badgeTextColor: const Color(0xFF4C1D95),
              iconBgColor: const Color(0xFFF5F3FF),
              iconColor: const Color(0xFF7C3AED),
              onTap: () => context.push(
                '${AppRoutes.adminApplications}?status=correction_required',
              ),
            );

            if (isSmall) {
              return Column(
                children: [
                  card1,
                  const SizedBox(height: 10),
                  card2,
                  const SizedBox(height: 10),
                  card3,
                  const SizedBox(height: 10),
                  card4,
                ],
              );
            }

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 10),
                  Expanded(child: card2),
                  const SizedBox(width: 10),
                  Expanded(child: card3),
                  const SizedBox(width: 10),
                  Expanded(child: card4),
                ],
              );
            }

            return Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: card1),
                      const SizedBox(width: 10),
                      Expanded(child: card2),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: card3),
                      const SizedBox(width: 10),
                      Expanded(child: card4),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
