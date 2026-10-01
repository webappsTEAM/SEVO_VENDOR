import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import 'sevo_module_art.dart';
import 'sevo_typography.dart';

/// Empty state with the module's artwork gently floating above a short
/// message and an optional action.
class SevoEmptyState extends StatefulWidget {
  const SevoEmptyState({
    super.key,
    required this.module,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final SevoModule module;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<SevoEmptyState> createState() => _SevoEmptyStateState();
}

class _SevoEmptyStateState extends State<SevoEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (!AppMotion.isReduced) _float.repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _float,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -5 * Curves.easeInOut.transform(_float.value)),
              child: child,
            ),
            child: SevoModuleArt(
              module: widget.module,
              size: 150,
              onDark: false,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: SevoText.section,
          ),
          const SizedBox(height: 6),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: SevoText.caption.copyWith(fontSize: 13.5, height: 1.45),
          ),
          if (widget.actionLabel != null && widget.onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionColor,
              ),
              child: Text(widget.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Friendly error card with a clear explanation and a Retry button. Never
/// shows a raw exception.
class SevoErrorState extends StatelessWidget {
  const SevoErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.offline = true,
  });

  final String message;
  final VoidCallback onRetry;

  /// Shows the "check your connection" hint; pass false for server-side errors.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Column(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
            size: 34,
            color: AppColors.errorText,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: SevoText.bodyStrong,
          ),
          const SizedBox(height: 4),
          if (offline)
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: SevoText.caption,
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.actionColor,
            ),
          ),
        ],
      ),
    );
  }
}
