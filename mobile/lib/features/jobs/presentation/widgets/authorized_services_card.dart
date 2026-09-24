import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../profile/presentation/profile_providers.dart';

/// Displays the technician's authorized dispatch services dynamically.
class AuthorizedServicesCard extends ConsumerStatefulWidget {
  const AuthorizedServicesCard({super.key});

  @override
  ConsumerState<AuthorizedServicesCard> createState() => _AuthorizedServicesCardState();
}

class _AuthorizedServicesCardState extends ConsumerState<AuthorizedServicesCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(employeeProfileProvider);
    final approvedServices = profileAsync.valueOrNull?.approvedServices ?? const [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Your Authorized Dispatch Services (${approvedServices.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (approvedServices.length > 6)
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isExpanded ? 'Show less' : 'View all',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (approvedServices.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'Awaiting Admin service authorizations.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ),
          ] else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final svc in _isExpanded ? approvedServices : approvedServices.take(6))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            svc.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isExpanded && approvedServices.length > 6)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.isDark
                            ? AppColors.surfaceMuted
                            : const Color(0xFFE6F4F1),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(
                          color: AppColors.isDark
                              ? AppColors.primaryLight
                              : const Color(0xFFB2DFDB),
                        ),
                      ),
                      child: Text(
                        '+${approvedServices.length - 6} more',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.isDark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
