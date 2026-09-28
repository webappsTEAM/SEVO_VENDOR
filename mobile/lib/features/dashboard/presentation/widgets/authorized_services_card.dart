import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../profile/domain/employee_profile.dart';

/// Displays the technician's approved service capabilities on the dashboard,
/// matching web PortalCockpitLayout Authorized Service Capabilities section.
class AuthorizedServicesCard extends StatelessWidget {
  const AuthorizedServicesCard({
    super.key,
    required this.services,
    required this.onTapManage,
  });

  final List<RequestedService> services;
  final VoidCallback onTapManage;

  @override
  Widget build(BuildContext context) {
    final approvedServices = services.where((s) => s.status.toLowerCase() == 'approved').toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.isDark
                            ? AppColors.surfaceMuted
                            : const Color(0xFFE6F4F1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.handyman_outlined,
                        size: 15,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Authorized Service Capabilities',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.isDark
                        ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                        : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.isDark
                          ? const Color(0xFF059669)
                          : const Color(0xFF6EE7B7),
                    ),
                  ),
                  child: Text(
                    '${approvedServices.length} Approved',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.isDark
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF065F46),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (approvedServices.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final service in approvedServices.take(6))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 11,
                            color: Color(0xFF059669),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            service.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (approvedServices.length > 6)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+${approvedServices.length - 6} more',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ] else ...[
              Text(
                'No services authorized yet. Go to Credentials > Services & Skills to apply for service categories.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 6),
            InkWell(
              onTap: onTapManage,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'Manage Services & Skills',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: AppColors.primaryLight,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
