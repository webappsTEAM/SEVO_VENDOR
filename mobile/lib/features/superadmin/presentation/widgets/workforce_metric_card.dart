import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/home_dashboard_widgets.dart';
import '../../domain/superadmin_dashboard.dart';

/// One figure of the Workforce Overview: pastel icon disc, label, big number
/// and a caption. With [tinted] it becomes the full-width tile (Pending Review)
/// with a chevron.
class WorkforceMetricCard extends StatelessWidget {
  const WorkforceMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.iconColor,
    required this.valueColor,
    this.tinted = false,
    this.onTap,
  });

  final String label;
  final int value;
  final String subtext;
  final IconData icon;
  final Color iconColor;
  final Color valueColor;
  final bool tinted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: valueColor,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              Text(
                subtext,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (tinted)
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      ],
    );

    final padded = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tinted ? 14 : 12,
        vertical: tinted ? 12 : 14,
      ),
      child: content,
    );

    if (!tinted) {
      return onTap == null ? padded : InkWell(onTap: onTap, child: padded);
    }
    return Material(
      color: AppColors.isDark
          ? iconColor.withValues(alpha: 0.12)
          : iconColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: iconColor.withValues(alpha: 0.18)),
          ),
          child: padded,
        ),
      ),
    );
  }
}

/// The Workforce Overview container shared by both admin homes: header, a
/// 2×2 grid of figures with dividers, and the full-width Pending Review tile.
class WorkforceOverviewPanel extends StatelessWidget {
  const WorkforceOverviewPanel({
    super.key,
    required this.totalRegistered,
    required this.approvedAndActive,
    required this.onlineAndAvailable,
    required this.onActiveJobs,
    required this.pendingReview,
    required this.onPendingReview,
  });

  final int totalRegistered;
  final int approvedAndActive;
  final int onlineAndAvailable;
  final int onActiveJobs;
  final int pendingReview;
  final VoidCallback onPendingReview;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final divider = Divider(height: 1, color: AppColors.border);
    final vdivider = VerticalDivider(width: 1, color: AppColors.border);

    Color value(Color light, Color darkColor) => dark ? darkColor : light;

    final total = WorkforceMetricCard(
      label: 'Total Registered',
      value: totalRegistered,
      subtext: 'Technicians on roster',
      icon: Icons.groups_rounded,
      iconColor: const Color(0xFF0F766E),
      valueColor: AppColors.textPrimary,
    );
    final approved = WorkforceMetricCard(
      label: 'Approved & Active',
      value: approvedAndActive,
      subtext: 'Authorized for jobs',
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF16A34A),
      valueColor: AppColors.textPrimary,
    );
    final online = WorkforceMetricCard(
      label: 'Online & Available',
      value: onlineAndAvailable,
      subtext: 'Ready for dispatch',
      icon: Icons.wifi_rounded,
      iconColor: const Color(0xFF2563EB),
      valueColor: AppColors.textPrimary,
    );
    final onJobs = WorkforceMetricCard(
      label: 'On Active Jobs',
      value: onActiveJobs,
      subtext: 'Currently in field',
      icon: Icons.work_rounded,
      iconColor: const Color(0xFFEA580C),
      valueColor: AppColors.textPrimary,
    );
    final pending = WorkforceMetricCard(
      label: 'Pending Review',
      value: pendingReview,
      subtext: 'Awaiting dossier check',
      icon: Icons.fact_check_rounded,
      iconColor: value(const Color(0xFF6D28D9), const Color(0xFFA78BFA)),
      valueColor: AppColors.textPrimary,
      tinted: true,
      onTap: onPendingReview,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppElevation.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: HomeSectionHeader(
              leading: Icon(
                Icons.groups_rounded,
                size: 30,
                color: dark ? Colors.white : const Color(0xFF005965),
              ),
              title: 'Workforce Overview',
              subtitle: 'Personnel roster, availability and field activity',
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(child: total),
                      vdivider,
                      Expanded(child: approved),
                    ],
                  ),
                ),
                divider,
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(child: online),
                      vdivider,
                      Expanded(child: onJobs),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                  child: pending,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// WORKFORCE OVERVIEW section of the Super Admin home.
class SuperAdminWorkforceOverviewSection extends StatelessWidget {
  const SuperAdminWorkforceOverviewSection({super.key, required this.data});

  final SuperAdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    return WorkforceOverviewPanel(
      totalRegistered: data.totalRegisteredCount,
      approvedAndActive: data.approvedAndActiveCount,
      onlineAndAvailable: data.onlineAndAvailableCount,
      onActiveJobs: data.onActiveJobsCount,
      pendingReview: data.pendingReviewCount,
      onPendingReview: () => context.push(AppRoutes.superAdminApplications),
    );
  }
}
