import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../../../../shared/widgets/sevo/sevo_typography.dart';
import '../../domain/platform_relieving_request.dart';

/// A resignation / relieving request awaiting (or past) the SEVO audit.
class RelievingAuditCard extends StatelessWidget {
  const RelievingAuditCard({
    super.key,
    required this.request,
    required this.onAudit,
    this.index = 0,
  });

  final PlatformRelievingRequest request;
  final VoidCallback onAudit;
  final int index;

  static const _violet = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final initial = request.technicianName.isNotEmpty
        ? request.technicianName[0].toUpperCase()
        : 'T';
    final needsAudit = request.isPendingSevoAudit;
    final completed = request.isCompleted;
    final cleared = request.vendorSettlementNotes != null;

    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: needsAudit
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: _violet.withValues(alpha: 0.45),
                  width: 1.4,
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Technician + status ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontFamily: SevoText.family,
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.technicianName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SevoText.cardTitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Req #${request.id} • ${request.vendorName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SevoText.meta,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusBadge(request.status),
                ],
              ),
            ),

            // ── Resignation reason ─────────────────────────────────────
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: SevoBadge(
                          label:
                              request.reasonDisplay ?? request.reasonCategory,
                          tone: SevoTone.info,
                        ),
                      ),
                      if (request.desiredRelievingDate != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Effective: ${request.desiredRelievingDate}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SevoText.caption,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (request.resignationNotes != null &&
                      request.resignationNotes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '"${request.resignationNotes}"',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.caption.copyWith(
                        fontStyle: FontStyle.italic,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Vendor dues ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    cleared
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    size: 16,
                    color: cleared
                        ? AppColors.successText
                        : AppColors.warningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cleared
                          ? 'Vendor Clearance: ${request.vendorSettlementNotes}'
                          : 'Awaiting Vendor Dues Clearance & Signoff',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.caption.copyWith(
                        color: cleared
                            ? AppColors.successText
                            : AppColors.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.border),

            // ── Contact + action ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      request.technicianPhone.isNotEmpty
                          ? request.technicianPhone
                          : request.technicianEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.caption,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (needsAudit)
                    FilledButton.icon(
                      onPressed: onAudit,
                      icon: const Icon(Icons.verified_user_rounded, size: 16),
                      label: Text(
                        'Audit & Clear',
                        style: SevoText.button.copyWith(color: Colors.white),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _violet,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  else if (completed)
                    Text(
                      'Relieved (Solo Active)',
                      style: SevoText.badge.copyWith(
                        color: AppColors.successText,
                      ),
                    )
                  else
                    Text(
                      'Vendor Pending',
                      style: SevoText.badge.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    switch (status.toUpperCase()) {
      case 'VENDOR_APPROVED':
        return const SevoBadge(
          label: 'AUDIT REQUIRED',
          tone: SevoTone.violet,
          icon: Icons.gavel_rounded,
        );
      case 'COMPLETED':
        return const SevoBadge(
          label: 'RELIEVED',
          tone: SevoTone.success,
          icon: Icons.check_circle_rounded,
        );
      case 'SEVO_APPROVED':
        return const SevoBadge(
          label: 'APPROVED',
          tone: SevoTone.info,
          icon: Icons.shield_rounded,
        );
      default:
        return const SevoBadge(
          label: 'REQUESTED',
          tone: SevoTone.warning,
          icon: Icons.hourglass_empty_rounded,
        );
    }
  }
}
