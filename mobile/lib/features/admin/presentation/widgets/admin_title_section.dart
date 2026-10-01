import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/home_dashboard_widgets.dart';
import '../../../auth/presentation/auth_controller.dart';

/// "Workforce Operations Center" card of the Admin home: title, subtitle,
/// Refresh Data, Open Dispatch Console and (Admin only) Database Egress.
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
    final dark = AppColors.isDark;
    return HomeOpsCard(
      onRefresh: onRefresh,
      isRefreshing: isRefreshing,
      extraActions: [
        if (isAdmin)
          OutlinedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.adminMonitoringDatabaseEgress),
            icon: Icon(
              Icons.storage_rounded,
              size: 16,
              color: dark ? const Color(0xFF34D399) : const Color(0xFF059669),
            ),
            label: const Text('Database Egress'),
            style: OutlinedButton.styleFrom(
              foregroundColor: dark
                  ? const Color(0xFF34D399)
                  : const Color(0xFF065F46),
              backgroundColor: dark
                  ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                  : const Color(0xFFECFDF5),
              side: BorderSide(
                color: dark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
              ),
              minimumSize: const Size(0, 40),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }
}
