import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/domain/admin_application.dart';
import 'package:mobile/shared/widgets/workforce_avatar.dart';

import 'application_status_badge.dart';

/// Responsive card displaying a technician applicant's overview, status,
/// document posture, and quick action to inspect full dossier.
class ApplicationCard extends StatelessWidget {
  const ApplicationCard({
    super.key,
    required this.application,
    required this.onViewDetail,
  });

  final AdminApplication application;
  final VoidCallback onViewDetail;

  @override
  Widget build(BuildContext context) {
    final docsCount = application.uploadedDocumentsCount;
    final verifiedDocsCount = application.verifiedDocumentsCount;
    final servicesCount = application.requestedServicesCount;
    final appliedDateFormatted = application.createdAt != null
        ? '${application.createdAt!.day.toString().padLeft(2, '0')}/${application.createdAt!.month.toString().padLeft(2, '0')}/${application.createdAt!.year}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onViewDetail,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Avatar + Name & ID + Status Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkforceAvatar(
                      imageUrl: application.avatar,
                      name: application.name,
                      initial: application.initial,
                      radius: 20,
                      fontSize: 14,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      foregroundColor: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            application.name ?? 'Technician #${application.id}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  application.employeeId ?? 'APP-#${application.id}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (application.companyName != null &&
                                  application.companyName!.isNotEmpty)
                                Container(
                                  constraints: const BoxConstraints(maxWidth: 130),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.business_rounded,
                                        size: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          application.companyName!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ApplicationStatusBadge(
                      status: application.registrationStatus,
                      dense: true,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Contact Details Row (Email / Mobile / Applied Date)
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (application.phone != null && application.phone!.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_outlined, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            application.phone!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    if (application.email != null && application.email!.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.email_outlined, size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                application.email!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (appliedDateFormatted != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Applied: $appliedDateFormatted',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 10),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 8),

                // Footer Row: Document Verification Badge + "View Application →"
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    // Document & Services Info Pills
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (docsCount > 0 && verifiedDocsCount == docsCount) ? AppColors.successBg : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (docsCount > 0 && verifiedDocsCount == docsCount) ? AppColors.successBorder : AppColors.border,
                            ),
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: Icon(
                                      (docsCount > 0 && verifiedDocsCount == docsCount)
                                          ? Icons.check_circle_rounded
                                          : Icons.description_outlined,
                                      size: 12,
                                      color: (docsCount > 0 && verifiedDocsCount == docsCount) ? AppColors.successText : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                TextSpan(
                                  text: 'Docs: $verifiedDocsCount/$docsCount',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: (docsCount > 0 && verifiedDocsCount == docsCount) ? AppColors.successText : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (servicesCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '$servicesCount Services',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // "View Application →" link
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.infoBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View Application',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
