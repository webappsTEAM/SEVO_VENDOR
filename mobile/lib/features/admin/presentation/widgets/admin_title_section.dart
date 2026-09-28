import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../auth/presentation/auth_controller.dart';

/// Clean Executive Header for Workforce Operations Center:
/// - Title: Workforce Operations Center
/// - Subtitle: Real-time personnel monitoring, dossier verifications, and dynamic dispatch
/// - Actions: Refresh Data, Database Egress (Admin) & Open Dispatch Console
class AdminTitleSection extends ConsumerWidget {
  const AdminTitleSection({
    super.key,
    required this.onRefresh,
    this.isRefreshing = false,
  });

  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).user?.isAdmin == true;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x040A2540),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Row with SEVO Peacock Icon Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Workforce Operations Center',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.isDark
                                ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.isDark
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFA7F3D0),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF059669),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real-time personnel monitoring, dossier verifications, and dynamic dispatch',
                      style: TextStyle(
                        fontSize: 11.5,
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
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          // Actions Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Refresh Button
              OutlinedButton.icon(
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Icon(Icons.refresh_rounded, size: 15, color: AppColors.primary),
                label: Text('Refresh Data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  backgroundColor: AppColors.surfaceMuted,
                  side: BorderSide(color: AppColors.border),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  textStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              // Database Egress Button (Admin only)
              if (isAdmin)
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.adminMonitoringDatabaseEgress),
                  icon: Icon(
                    Icons.storage_rounded,
                    size: 14,
                    color: AppColors.isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                  ),
                  label: Text('Database Egress'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                    backgroundColor: AppColors.isDark
                        ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                        : const Color(0xFFECFDF5),
                    side: BorderSide(
                      color: AppColors.isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    textStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              // Open Dispatch Console Button
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.adminDispatch),
                icon: const Icon(Icons.send_rounded, size: 13, color: Colors.white),
                label: Text('Open Dispatch Console'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  textStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}