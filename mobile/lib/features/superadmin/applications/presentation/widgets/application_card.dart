import 'package:flutter/material.dart';

import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/domain/admin_application.dart';
import 'package:mobile/shared/widgets/sevo/sevo_animated_card.dart';
import 'package:mobile/shared/widgets/sevo/sevo_controls.dart';
import 'package:mobile/shared/widgets/sevo/sevo_typography.dart';
import 'package:mobile/shared/widgets/workforce_avatar.dart';

import 'application_status_badge.dart';

/// A technician applicant: identity, status, contact, document posture and a
/// "View Application" action.
class ApplicationCard extends StatelessWidget {
  const ApplicationCard({
    super.key,
    required this.application,
    required this.onViewDetail,
    this.index = 0,
  });

  final AdminApplication application;
  final VoidCallback onViewDetail;
  final int index;

  @override
  Widget build(BuildContext context) {
    final docs = application.uploadedDocumentsCount;
    final verified = application.verifiedDocumentsCount;
    final services = application.requestedServicesCount;
    final allVerified = docs > 0 && verified == docs;
    final applied = application.createdAt == null
        ? null
        : '${application.createdAt!.day.toString().padLeft(2, '0')}/${application.createdAt!.month.toString().padLeft(2, '0')}/${application.createdAt!.year}';

    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onViewDetail,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              WorkforceAvatar(
                imageUrl: application.avatar,
                name: application.name,
                initial: application.initial,
                radius: 22,
                fontSize: 16,
                backgroundColor: AppColors.selectedTint,
                foregroundColor: AppColors.selectedOnTint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.name ?? 'Technician #${application.id}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      application.employeeId ?? 'APP-#${application.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.meta,
                    ),
                    if (application.companyName != null &&
                        application.companyName!.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.business_rounded,
                            size: 12,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              application.companyName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SevoText.meta,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // status + document posture together, on their own row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ApplicationStatusBadge(
                status: application.registrationStatus,
                dense: true,
              ),
              SevoBadge(
                label: 'Docs: $verified/$docs',
                tone: allVerified ? SevoTone.success : SevoTone.neutral,
                icon: allVerified
                    ? Icons.check_circle_rounded
                    : Icons.description_outlined,
              ),
              if (services > 0) SevoBadge(label: '$services Services'),
            ],
          ),
          if ((application.phone?.isNotEmpty ?? false) ||
              (application.email?.isNotEmpty ?? false) ||
              applied != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (application.phone != null && application.phone!.isNotEmpty)
                  _meta(Icons.phone_outlined, application.phone!),
                if (application.email != null && application.email!.isNotEmpty)
                  _meta(Icons.email_outlined, application.email!),
                if (applied != null)
                  _meta(Icons.calendar_today_outlined, 'Applied: $applied'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onViewDetail,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.selectedOnTint,
                backgroundColor: AppColors.selectedTint,
                padding: const EdgeInsets.only(left: 14, right: 8),
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Application',
                    style: SevoText.button.copyWith(fontSize: 12.5),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.textMuted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SevoText.caption.copyWith(color: AppColors.bodyText),
        ),
      ),
    ],
  );
}
