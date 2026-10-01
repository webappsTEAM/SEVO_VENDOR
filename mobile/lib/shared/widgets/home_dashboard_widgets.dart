import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../routing/app_routes.dart';

const _teal = Color(0xFF005965);

/// "Workforce Operations Center" card at the top of the admin homes: hub icon,
/// title, subtitle and the Refresh / Open Dispatch Console buttons.
class HomeOpsCard extends StatelessWidget {
  const HomeOpsCard({
    super.key,
    required this.onRefresh,
    this.isRefreshing = false,
    this.extraActions = const [],
  });

  final VoidCallback onRefresh;
  final bool isRefreshing;

  /// Extra buttons shown under the two primary ones (e.g. Database Egress).
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final refresh = OutlinedButton.icon(
      onPressed: isRefreshing ? null : onRefresh,
      icon: isRefreshing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
            )
          : const Icon(Icons.sync_rounded, size: 20),
      label: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('Refresh Data', maxLines: 1),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? Colors.white : _teal,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: dark ? AppColors.border : _teal.withValues(alpha: 0.55),
          width: 1.2,
        ),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    final dispatch = FilledButton.icon(
      onPressed: () => context.push(AppRoutes.adminDispatch),
      icon: const Icon(Icons.send_rounded, size: 18),
      label: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('Open Dispatch Console', maxLines: 1),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: dark
              ? [AppColors.surface, AppColors.surface]
              : const [Color(0xFFFFFFFF), Color(0xFFE6F5EF)],
        ),
        border: Border.all(color: AppColors.border),
        boxShadow: AppElevation.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: dark ? 0.35 : 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _teal.withValues(alpha: 0.18)),
                ),
                child: Icon(
                  Icons.hub_rounded,
                  size: 28,
                  color: dark ? Colors.white : _teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workforce Operations Center',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real-time personnel monitoring, dossier verifications, and dynamic dispatch',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [refresh, const SizedBox(height: 8), dispatch],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 2, child: refresh),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: dispatch),
                ],
              );
            },
          ),
          if (extraActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: extraActions),
          ],
        ],
      ),
    );
  }
}

/// Section title with an optional accent bar / leading widget, a subtitle and
/// a right-aligned "View All >" style link.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.accent,
    this.leading,
    this.linkLabel,
    this.onLink,
    this.titleSuffix,
  });

  final String title;
  final String? subtitle;

  /// Coloured vertical bar shown before the title.
  final Color? accent;
  final Widget? leading;
  final String? linkLabel;
  final VoidCallback? onLink;

  /// e.g. `(100)` rendered lighter after the title.
  final String? titleSuffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (accent != null) ...[
          Container(
            width: 4,
            height: subtitle == null ? 22 : 36,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: title,
                  children: [
                    if (titleSuffix != null)
                      TextSpan(
                        text: ' $titleSuffix',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        if (linkLabel != null && onLink != null)
          InkWell(
            onTap: onLink,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    linkLabel!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.isDark ? Colors.white : _teal,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.isDark ? Colors.white : _teal,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
