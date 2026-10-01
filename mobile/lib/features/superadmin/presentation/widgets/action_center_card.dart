import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/home_dashboard_widgets.dart';
import '../../domain/superadmin_dashboard.dart';

/// Single compact action card for items requiring operational attention.
class ActionCenterCard extends StatelessWidget {
  const ActionCenterCard({
    super.key,
    required this.title,
    required this.description,
    required this.count,
    required this.icon,
    required this.badgeBgColor,
    required this.badgeTextColor,
    required this.iconBgColor,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String description;
  final int count;
  final IconData icon;
  final Color badgeBgColor;
  final Color badgeTextColor;
  final Color iconBgColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.isDark ? AppColors.surface : iconBgColor,
                AppColors.surface,
              ],
            ),
            border: Border.all(
              color: AppColors.isDark ? AppColors.border : badgeBgColor,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Semantic Icon + Count Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(icon, size: 20, color: iconColor),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBgColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Card Title + Chevron Indicator
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Subtitle Description
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Action Center section rendering the 4 operational queues.
class SuperAdminActionCenterSection extends StatelessWidget {
  const SuperAdminActionCenterSection({super.key, required this.data});

  final SuperAdminDashboardData data;

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
          onLink: () => context.push(AppRoutes.superAdminApplications),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Adaptive Grid for 4 Action Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = constraints.maxWidth < 340;
            final isWide = constraints.maxWidth >= 600;

            final card1 = ActionCenterCard(
              title: 'Pending Applications',
              description: 'Technician registrations requiring document review',
              count: data.pendingApplicationsCount,
              icon: Icons.assignment_rounded,
              badgeBgColor: const Color(0xFFFEF3C7),
              badgeTextColor: const Color(0xFF92400E),
              iconBgColor: const Color(0xFFFFFBEB),
              iconColor: const Color(0xFFD97706),
              onTap: () => context.push(AppRoutes.superAdminApplications),
            );

            final card2 = ActionCenterCard(
              title: 'Active Technicians',
              description: 'Approved workforce field technicians',
              count: data.activeTechniciansCount,
              icon: Icons.how_to_reg_rounded,
              badgeBgColor: const Color(0xFFECFDF5),
              badgeTextColor: const Color(0xFF065F46),
              iconBgColor: const Color(0xFFF0FDF4),
              iconColor: const Color(0xFF059669),
              onTap: () => context.push(AppRoutes.superAdminWorkforce),
            );

            final card3 = ActionCenterCard(
              title: 'Jobs Awaiting Assignment',
              description: 'Customer bookings requiring technician dispatch',
              count: data.jobsAwaitingAssignmentCount,
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
                '${AppRoutes.superAdminApplications}?status=correction_required',
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
