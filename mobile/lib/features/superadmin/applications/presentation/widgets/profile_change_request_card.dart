import 'package:flutter/material.dart';

import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/domain/admin_change_request.dart';
import 'package:mobile/shared/widgets/sevo/sevo_animated_card.dart';
import 'package:mobile/shared/widgets/sevo/sevo_controls.dart';
import 'package:mobile/shared/widgets/sevo/sevo_typography.dart';

/// A technician profile change request: request id and status, the field,
/// the current → requested value, the reason and the decision action.
class ProfileChangeRequestCard extends StatelessWidget {
  const ProfileChangeRequestCard({
    super.key,
    required this.changeRequest,
    required this.onDecide,
    this.index = 0,
  });

  final AdminChangeRequest changeRequest;
  final VoidCallback onDecide;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cr = changeRequest;
    final hasReason = cr.reason != null && cr.reason!.trim().isNotEmpty;
    final hasNotes = cr.adminNotes != null && cr.adminNotes!.trim().isNotEmpty;
    final who =
        '${cr.employeeName ?? "Technician"}${cr.employeeId != null && cr.employeeId!.isNotEmpty ? " (${cr.employeeId})" : ""}';
    final tone = switch (cr.status.toUpperCase()) {
      'APPROVED' => SevoTone.success,
      'REJECTED' => SevoTone.error,
      _ => SevoTone.warning,
    };

    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'REQUEST #${cr.id}',
                  style: SevoText.overline.copyWith(letterSpacing: 0.6),
                ),
              ),
              SevoBadge(label: cr.status.toUpperCase(), tone: tone),
            ],
          ),
          const SizedBox(height: 8),
          Text(cr.displayField, style: SevoText.cardTitle),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 15,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SevoText.caption.copyWith(color: AppColors.bodyText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _value('CURRENT VALUE', cr.oldValue, false)),
                Padding(
                  padding: const EdgeInsets.only(top: 14, left: 8, right: 8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
                Expanded(child: _value('REQUESTED VALUE', cr.newValue, true)),
              ],
            ),
          ),
          if (hasReason) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason: ',
                  style: SevoText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.headingText,
                  ),
                ),
                Expanded(
                  child: Text(
                    cr.reason!,
                    style: SevoText.caption.copyWith(color: AppColors.bodyText),
                  ),
                ),
              ],
            ),
          ],
          if (hasNotes) ...[
            const SizedBox(height: 6),
            Text(
              'Admin Notes: ${cr.adminNotes}',
              style: SevoText.caption.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (cr.isPending) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onDecide,
                icon: const Icon(Icons.gavel_rounded, size: 16),
                label: Text(
                  'Review / Decide',
                  style: SevoText.button.copyWith(color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.actionColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _value(String label, String? value, bool emphasise) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: SevoText.overline.copyWith(fontSize: 9.5)),
      const SizedBox(height: 3),
      Text(
        value?.isNotEmpty == true ? value! : '—',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: emphasise
            ? SevoText.bodyStrong.copyWith(color: AppColors.accentOnSurface)
            : SevoText.body,
      ),
    ],
  );
}
