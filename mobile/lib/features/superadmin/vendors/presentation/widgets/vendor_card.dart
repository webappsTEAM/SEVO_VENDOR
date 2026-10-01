import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../../shared/widgets/sevo/sevo_typography.dart';
import '../../domain/platform_vendor.dart';

/// A single vendor business in the Vendor Directory: identity, owner contact
/// and workforce summary, with a "View Workers" action.
class VendorCard extends StatelessWidget {
  const VendorCard({
    super.key,
    required this.vendor,
    required this.onViewWorkers,
    this.index = 0,
  });

  final PlatformVendor vendor;
  final VoidCallback onViewWorkers;

  /// Position in the list, for the staggered entrance.
  final int index;

  @override
  Widget build(BuildContext context) {
    final hasOwnerContact =
        vendor.ownerName.isNotEmpty ||
        vendor.ownerEmail.isNotEmpty ||
        vendor.ownerPhone.isNotEmpty;

    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onViewWorkers,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Identity ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: _avatarGradient(vendor.id),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text(
                      vendor.initial,
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
                        vendor.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SevoText.cardTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vendor.slug.isNotEmpty
                            ? 'ID: #${vendor.id} • ${vendor.slug}'
                            : 'ID: #${vendor.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SevoText.meta,
                      ),
                    ],
                  ),
                ),
                if (vendor.effectiveLocation != 'Not specified') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 84),
                          child: Text(
                            vendor.effectiveLocation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SevoText.badge.copyWith(
                              fontWeight: FontWeight.w500,
                              color: AppColors.bodyText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Owner / contact ────────────────────────────────────────────
          if (hasOwnerContact) ...[
            Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vendor.ownerName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              vendor.ownerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SevoText.bodyStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (vendor.ownerEmail.isNotEmpty)
                        _contact(Icons.email_outlined, vendor.ownerEmail),
                      if (vendor.ownerPhone.isNotEmpty)
                        _contact(Icons.phone_outlined, vendor.ownerPhone),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── Workforce summary + action ─────────────────────────────────
          Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _badge(
                        icon: Icons.groups_rounded,
                        label: '${vendor.tiedWorkersCount} active',
                        bg: AppColors.successBg,
                        border: AppColors.successBorder,
                        fg: AppColors.successText,
                      ),
                      if (vendor.pendingInvitationsCount > 0)
                        _badge(
                          label: '${vendor.pendingInvitationsCount} invites',
                          bg: AppColors.warningBg,
                          border: AppColors.warningBorder,
                          fg: AppColors.warningText,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onViewWorkers,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.selectedOnTint,
                    backgroundColor: AppColors.selectedTint,
                    padding: const EdgeInsets.only(left: 12, right: 6),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Workers',
                        style: SevoText.button.copyWith(fontSize: 13),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A friendly, varied avatar colour per vendor (stable for a given id).
  static LinearGradient _avatarGradient(int id) {
    const palette = <List<Color>>[
      [Color(0xFF0D9488), Color(0xFF005965)], // teal
      [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // blue
      [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // violet
      [Color(0xFFF59E0B), Color(0xFFD97706)], // amber
      [Color(0xFF10B981), Color(0xFF047857)], // green
    ];
    final c = palette[id.abs() % palette.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: c,
    );
  }

  Widget _contact(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.textMuted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: SevoText.caption.copyWith(
            fontSize: 13,
            color: AppColors.bodyText,
          ),
        ),
      ),
    ],
  );

  Widget _badge({
    IconData? icon,
    required String label,
    required Color bg,
    required Color border,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          // Flexible + ellipsis: the pill can never overflow its row.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SevoText.badge.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
