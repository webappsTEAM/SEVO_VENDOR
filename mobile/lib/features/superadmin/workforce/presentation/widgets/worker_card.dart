import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../../../../shared/widgets/sevo/sevo_typography.dart';
import '../../domain/platform_worker.dart';

/// One technician: identity, classification (solo/tied), skills, contact and
/// the tie / reassign action.
class WorkerCard extends StatelessWidget {
  const WorkerCard({
    super.key,
    required this.worker,
    required this.onManageTie,
    this.index = 0,
  });

  final PlatformWorker worker;
  final VoidCallback onManageTie;
  final int index;

  static const _tiedAccent = Color(0xFF059669);
  static const _soloAccent = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    final isTied = worker.isTied;
    final accent = isTied ? _tiedAccent : _soloAccent;
    final initial = worker.name.isNotEmpty ? worker.name[0].toUpperCase() : 'T';
    final approved = worker.registrationStatus.toLowerCase() == 'approved';
    final skills = worker.skills;

    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Identity ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accent.withValues(alpha: 0.85), accent],
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
                    Positioned(
                      bottom: -1,
                      right: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: worker.isOnline
                              ? const Color(0xFF10B981)
                              : AppColors.textMuted,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SevoText.cardTitle,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              worker.employeeId.isNotEmpty
                                  ? worker.employeeId
                                  : '#${worker.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SevoText.meta,
                            ),
                          ),
                          if (worker.city.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text('•', style: SevoText.meta),
                            ),
                            Flexible(
                              child: Text(
                                worker.city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SevoText.meta,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SevoBadge(
                  label: isTied ? 'TIED' : 'SOLO',
                  tone: isTied ? SevoTone.success : SevoTone.info,
                  icon: isTied ? Icons.business_rounded : Icons.person_rounded,
                ),
              ],
            ),
          ),

          // ── Tied vendor ──────────────────────────────────────────────
          if (isTied && worker.tiedVendor != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.successBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.business_rounded,
                    size: 16,
                    color: AppColors.successText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tied to:',
                    style: SevoText.caption.copyWith(
                      color: AppColors.successText,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      worker.tiedVendor!.companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.bodyStrong.copyWith(
                        fontSize: 12.5,
                        color: AppColors.successText,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Skills ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in skills.take(3)) _chip(skill),
                if (skills.length > 3)
                  _chip('+${skills.length - 3} more', strong: true),
                if (skills.isEmpty) _chip('General Technician', italic: true),
              ],
            ),
          ),

          // ── Contact ──────────────────────────────────────────────────
          if (worker.phone.isNotEmpty || worker.email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  if (worker.phone.isNotEmpty)
                    _contact(Icons.phone_outlined, worker.phone),
                  if (worker.email.isNotEmpty)
                    _contact(Icons.mail_outline_rounded, worker.email),
                ],
              ),
            ),

          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),

          // ── Status + action ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SevoBadge(
                      label: worker.registrationStatus.toUpperCase(),
                      tone: approved ? SevoTone.success : SevoTone.warning,
                      dot: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onManageTie,
                  icon: Icon(
                    isTied ? Icons.sync_rounded : Icons.link_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isTied ? 'Reassign / Untie' : 'Tie to Vendor',
                    style: SevoText.button.copyWith(fontSize: 12.5),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: isTied
                        ? AppColors.warningText
                        : AppColors.infoText,
                    backgroundColor: isTied
                        ? AppColors.warningBg
                        : AppColors.infoBg,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {bool strong = false, bool italic = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: SevoText.badge.copyWith(
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: italic ? AppColors.textMuted : AppColors.bodyText,
          ),
        ),
      );

  Widget _contact(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.textMuted),
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
