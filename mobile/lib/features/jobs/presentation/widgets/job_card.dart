import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/job_actions_repository.dart';
import '../../domain/job.dart';
import '../../domain/job_presentation.dart';
import '../jobs_providers.dart';
import 'category_helper.dart';
import 'job_customer_row.dart';

/// Modern SEVO Job Card precisely matching the reference UI:
/// 1. Top Section: Category Icon Square + Category Name & Job Title (left) | Status Pill & Earnings (right)
/// 2. Schedule & Location Details: 📅 Date & Time | 📍 Address & Distance Pill
/// 3. Customer Row: Avatar Initial + Customer Name + Circular Call & Chat buttons
/// 4. Action Bar: Outlined [ 👁 View Details ] + Filled [ Continue Job ➔ ] / [ ✔ Mark as Completed ] / [ Accept / Decline ]
class JobCard extends ConsumerStatefulWidget {
  const JobCard({
    super.key,
    required this.job,
    this.hasActiveJob = false,
  });

  final Job job;
  final bool hasActiveJob;

  @override
  ConsumerState<JobCard> createState() => _JobCardState();
}

class _JobCardState extends ConsumerState<JobCard> {
  bool _isAccepting = false;
  bool _isDeclining = false;
  String? _inlineError;

  Future<void> _refreshJobs() async {
    ref.invalidate(activeJobsProvider);
    ref.invalidate(completedJobsProvider);
    await Future.wait([
      ref.read(activeJobsProvider.future),
      ref.read(completedJobsProvider.future),
    ]);
  }

  Future<void> _accept() async {
    setState(() {
      _isAccepting = true;
      _inlineError = null;
    });

    try {
      await ref.read(jobActionsRepositoryProvider).acceptOffer(widget.job.id);
      await _refreshJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job offer accepted! Heading to customer site.'),
            backgroundColor: Color(0xFF005965),
          ),
        );
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map ? data['code'] as String? : null;
      String message;
      switch (code) {
        case 'JOB_ALREADY_ACCEPTED':
          message = 'This job was already accepted by another technician.';
          break;
        case 'OFFER_EXPIRED':
          message = 'This job offer has expired.';
          break;
        case 'EMPLOYEE_ALREADY_BUSY':
          message = 'You already have an active job in progress.';
          break;
        default:
          message = describeDioError(e, fallback: 'Failed to accept job offer.');
      }
      if (mounted) setState(() => _inlineError = message);
      if (code == 'JOB_ALREADY_ACCEPTED' || code == 'OFFER_EXPIRED') {
        await _refreshJobs();
      }
    } catch (_) {
      if (mounted) setState(() => _inlineError = 'Failed to accept job offer.');
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _decline() async {
    final reason = await _showDeclineReasonModal(context);
    if (reason == null || !mounted) return;

    setState(() {
      _isDeclining = true;
      _inlineError = null;
    });

    try {
      await ref.read(jobActionsRepositoryProvider).rejectOffer(widget.job.id, reason);
      await _refreshJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job offer declined.')),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _inlineError = describeDioError(e, fallback: 'Failed to decline job offer.'));
      }
    } catch (_) {
      if (mounted) setState(() => _inlineError = 'Failed to decline job offer.');
    } finally {
      if (mounted) setState(() => _isDeclining = false);
    }
  }

  Future<String?> _showDeclineReasonModal(BuildContext context) {
    String selectedReason = 'Too far';
    String customReason = '';

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cancel_outlined, size: 20, color: Color(0xFFDC2626)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Decline Job Offer — ${widget.job.requestId}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Please select a reason for declining this job offer. The system will dispatch the job to the next available professional.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...[
                    'Too far',
                    'Busy / Heavy traffic',
                    'Vehicle issue',
                    'Service mismatch',
                    'Personal reason',
                    'Other',
                  ].map((reason) {
                    final isSelected = selectedReason == reason;
                    return InkWell(
                      onTap: () => setModalState(() => selectedReason = reason),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.only(right: 10, left: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF94A3B8),
                                  width: isSelected ? 5 : 1.5,
                                ),
                              ),
                            ),
                            Text(
                              reason,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      autofocus: true,
                      onChanged: (val) => customReason = val,
                      decoration: const InputDecoration(
                        hintText: 'Specify reason...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Keep Offer'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final finalReason = selectedReason == 'Other'
                                ? (customReason.trim().isNotEmpty ? customReason.trim() : 'Other')
                                : selectedReason;
                            Navigator.of(context).pop(finalReason);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Confirm Decline'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentation = buildJobPresentation(widget.job, hasActiveJob: widget.hasActiveJob);
    final categoryName = widget.job.serviceCategory ?? 'Service Request';
    final categoryIcon = iconForCategory(widget.job.serviceCategory ?? widget.job.displayTitle);

    // Extra items count & subtitle
    final extraItemsCount = widget.job.cartData.length > 1 ? widget.job.cartData.length - 1 : 0;
    final extraItemsSuffix = extraItemsCount > 0
        ? ' (+$extraItemsCount other item${extraItemsCount > 1 ? 's' : ''})'
        : '';

    // Formatted schedule text
    final scheduleText = widget.job.preferredDate != null && widget.job.preferredTime != null
        ? '${widget.job.preferredDate} • ${widget.job.preferredTime}'
        : (widget.job.preferredDate ?? widget.job.preferredTime ?? 'Flexible schedule');

    // Amount text
    final formattedAmount = widget.job.totalAmount != null
        ? '₹${widget.job.totalAmount! >= 1000 ? widget.job.totalAmount!.toStringAsFixed(2) : widget.job.totalAmount!.toStringAsFixed(0)}'
        : '₹0';

    final isOffer = presentation.isOffer;
    final isCompleted = widget.job.status.toLowerCase() == 'completed' ||
        presentation.state == JobPresentationState.completed;
    final isCancelled = ['cancelled', 'rejected', 'declined'].contains(widget.job.status.toLowerCase());
    final isInProgress = !isOffer && !isCompleted && !isCancelled;

    // Status pill badge color styles
    final Color badgeBgColor;
    final Color badgeTextColor;
    final String badgeLabel;

    if (isCompleted) {
      badgeBgColor = AppColors.isDark
          ? const Color(0xFF064E3B).withValues(alpha: 0.4)
          : const Color(0xFFDCFCE7);
      badgeTextColor = AppColors.isDark
          ? const Color(0xFF34D399)
          : const Color(0xFF15803D);
      badgeLabel = 'Completed';
    } else if (isInProgress) {
      badgeBgColor = AppColors.isDark
          ? const Color(0xFF0369A1).withValues(alpha: 0.4)
          : const Color(0xFFE0F2FE);
      badgeTextColor = AppColors.isDark
          ? const Color(0xFF38BDF8)
          : const Color(0xFF0369A1);
      badgeLabel = 'In Progress';
    } else if (isOffer) {
      badgeBgColor = AppColors.isDark
          ? const Color(0xFFB45309).withValues(alpha: 0.4)
          : const Color(0xFFFEF3C7);
      badgeTextColor = AppColors.isDark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFB45309);
      badgeLabel = 'Available';
    } else {
      badgeBgColor = AppColors.isDark
          ? const Color(0xFF334155).withValues(alpha: 0.5)
          : const Color(0xFFF1F5F9);
      badgeTextColor = AppColors.isDark
          ? const Color(0xFF94A3B8)
          : const Color(0xFF64748B);
      badgeLabel = presentation.displayStatus;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060A2540),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/jobs/${widget.job.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. Top Section: Category Icon + Title + Status Pill + Price ─
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Icon Square (44x44, light teal bg)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.isDark
                            ? const Color(0xFF005965).withValues(alpha: 0.3)
                            : const Color(0xFFE6F4F1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        categoryIcon,
                        size: 22,
                        color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title & Category Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.job.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              height: 1.25,
                            ),
                          ),
                          if (extraItemsSuffix.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              extraItemsSuffix,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Right: Status Badge & Earnings
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: badgeBgColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formattedAmount,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Earn on finish',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 2. Schedule, Address, and Distance ──────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        scheduleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.job.address != null && widget.job.address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.job.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Distance Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.isDark
                              ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                              : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.place_rounded,
                              size: 11,
                              color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${(widget.job.distanceKm ?? 0.0).toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // ── 3. Customer Row with Call & Chat buttons ───────────────────
                JobCustomerRow(job: widget.job),

                if (_inlineError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _inlineError!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // ── 4. Bottom Action Bar ───────────────────────────────────────
                _buildActionBar(
                  context,
                  isOffer: isOffer,
                  isCompleted: isCompleted,
                  isCancelled: isCancelled,
                  isInProgress: isInProgress,
                  amountText: formattedAmount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context, {
    required bool isOffer,
    required bool isCompleted,
    required bool isCancelled,
    required bool isInProgress,
    required String amountText,
  }) {
    if (isOffer) {
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: (_isAccepting || _isDeclining) ? null : _decline,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: BorderSide(
                  color: AppColors.isDark ? const Color(0xFF991B1B) : const Color(0xFFFECDD3),
                ),
                backgroundColor: AppColors.isDark ? const Color(0xFF450A0A).withValues(alpha: 0.3) : AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isDeclining
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Decline'),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: (_isAccepting || _isDeclining) ? null : _accept,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005965),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isAccepting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Accept • $amountText'),
                    ),
            ),
          ),
        ],
      );
    }

    if (isCompleted) {
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () => context.push('/jobs/${widget.job.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                side: BorderSide(
                  color: AppColors.isDark ? const Color(0xFF028090) : const Color(0xFF005965),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 15,
                    color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 1,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.isDark
                    ? const Color(0xFF005965).withValues(alpha: 0.3)
                    : const Color(0xFFE6F4F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Mark as Completed',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (isCancelled) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push('/jobs/${widget.job.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF64748B),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_outlined, size: 15, color: Color(0xFF64748B)),
                  SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // In Progress / Accepted Job
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: OutlinedButton(
            onPressed: () => context.push('/jobs/${widget.job.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
              side: BorderSide(
                color: AppColors.isDark ? const Color(0xFF028090) : const Color(0xFF005965),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 15,
                  color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 1,
          child: ElevatedButton(
            onPressed: () => context.push('/jobs/${widget.job.id}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005965),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Continue Job'),
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
