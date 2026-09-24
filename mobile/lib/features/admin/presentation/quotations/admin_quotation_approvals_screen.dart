import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/workforce_app_bar.dart';
import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_quotation.dart';
import '../widgets/admin_drawer.dart';
import 'admin_quotation_providers.dart';

/// Super Admin / SEVO Platform Quotation Approvals Screen.
///
/// Features two authorization queues:
/// 1. Awaiting SEVO Approval: Quotes accepted by the customer. Approving creates
///    the work booking and issues the commercial invoice.
/// 2. Held before sending: Quotes held by high-value threshold or structural clearance.
class AdminQuotationApprovalsScreen extends ConsumerStatefulWidget {
  const AdminQuotationApprovalsScreen({super.key});

  @override
  ConsumerState<AdminQuotationApprovalsScreen> createState() =>
      _AdminQuotationApprovalsScreenState();
}

class _AdminQuotationApprovalsScreenState
    extends ConsumerState<AdminQuotationApprovalsScreen> {
  String? _flashMessage;
  bool _isActionInProgress = false;
  int? _busyQuoteId;

  String _formatTimeAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 60)}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _refresh() async {
    ref.invalidate(adminQuotesPendingApprovalProvider);
    ref.invalidate(adminQuotesPendingReviewProvider);
  }

  Future<void> _decideQuote({
    required AdminQuotation quote,
    required bool approve,
    required bool isPreSendTab,
  }) async {
    final verb = isPreSendTab
        ? (approve ? 'Release & send' : 'Reject')
        : (approve ? 'Approve' : 'Reject');

    String notes = '';
    if (!approve) {
      final reasonController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          title: Text('$verb ${quote.quoteNumber}',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter rejection reason (recorded in audit trail):',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Scope discrepancy or rate card mismatch',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: Text(verb),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      notes = reasonController.text.trim();
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          title: Text('$verb ${quote.quoteNumber}?',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          content: Text(
            isPreSendTab
                ? 'Release quote proposal of ₹${quote.netPayable.toStringAsFixed(2)} to ${quote.customerName}?'
                : 'Approving this quotation will create the work booking and issue the invoice.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
              ),
              child: Text(verb),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _isActionInProgress = true;
      _busyQuoteId = quote.id;
    });

    try {
      final api = ref.read(adminDashboardApiProvider);
      if (isPreSendTab) {
        await api.preSendReviewQuote(
          quote.id,
          action: approve ? 'APPROVE' : 'REJECT',
          notes: notes,
          reason: notes,
        );
        if (mounted) {
          setState(() {
            _flashMessage = approve
                ? '${quote.quoteNumber} released and sent to the customer.'
                : '${quote.quoteNumber} rejected.';
          });
        }
      } else {
        final res = await api.adminReviewQuote(
          quote.id,
          action: approve ? 'APPROVE' : 'REJECT',
          notes: notes,
          reason: notes,
        );
        if (mounted) {
          final invoice = res['invoice'];
          if (invoice is Map<String, dynamic> &&
              invoice['invoice_number'] != null) {
            final invNum = invoice['invoice_number'];
            final total = invoice['total_amount']?.toString() ??
                quote.totalAmount.toStringAsFixed(2);
            setState(() {
              _flashMessage =
                  '${quote.quoteNumber} approved. Invoice $invNum issued for ₹$total.';
            });
          } else {
            setState(() {
              _flashMessage = approve
                  ? '${quote.quoteNumber} approved and booking issued.'
                  : '${quote.quoteNumber} rejected.';
            });
          }
        }
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $verb ${quote.quoteNumber}: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _busyQuoteId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(adminQuotationTabProvider);
    final isAcceptanceTab = activeTab == 'acceptance';

    final quotesAsync = isAcceptanceTab
        ? ref.watch(adminQuotesPendingApprovalProvider)
        : ref.watch(adminQuotesPendingReviewProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WorkforceAppBar(
        titleText: 'Quotation Approvals',
        showStatusSubBar: false,
        showDrawerMenu: true,
      ),
      drawer: const AdminDrawer(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // ── Screen Header ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x040F172A),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.approval_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quotation Approvals',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isAcceptanceTab
                                    ? 'The customer has accepted. Approving creates the work booking and issues the invoice.'
                                    : 'Above the category review threshold, or needing structural clearance. Releasing sends the quote to the customer.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isActionInProgress ? null : _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: BorderSide(color: AppColors.border),
                            visualDensity: VisualDensity.compact,
                            textStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Queue Filter Tabs ──────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(
                        'Awaiting SEVO Approval',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      selected: isAcceptanceTab,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _flashMessage = null);
                          ref.read(adminQuotationTabProvider.notifier).state =
                              'acceptance';
                        }
                      },
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isAcceptanceTab ? Colors.white : AppColors.textSecondary,
                      ),
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isAcceptanceTab
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        'Held before sending',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      selected: !isAcceptanceTab,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _flashMessage = null);
                          ref.read(adminQuotationTabProvider.notifier).state =
                              'presend';
                        }
                      },
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: !isAcceptanceTab ? Colors.white : AppColors.textSecondary,
                      ),
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: !isAcceptanceTab
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Live Flash Notification ────────────────────────────────────
              if (_flashMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.successBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.successText, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _flashMessage!,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.successText,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: AppColors.successText,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _flashMessage = null),
                      ),
                    ],
                  ),
                ),

              // ── Async Quotation List ───────────────────────────────────────
              quotesAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: CircularProgressIndicator(color: AppColors.textPrimary),
                  ),
                ),
                error: (err, _) => AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Unable to load approval queue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        err.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text('Try again'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                data: (quotes) {
                  if (quotes.isEmpty) {
                    return AppCard(
                      padding: const EdgeInsets.symmetric(
                          vertical: 40, horizontal: 16),
                      child: const EmptyState(
                        icon: Icons.article_outlined,
                        title: 'Nothing waiting in this queue.',
                        message:
                            'No quotations require administrative action at this time.',
                      ),
                    );
                  }

                  return Column(
                    children: quotes.map((q) {
                      final isBusy = _busyQuoteId == q.id;
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x040F172A),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card Header: Quote Number + Badges + Amount
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            q.quoteNumber,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              fontFamily: 'monospace',
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          if (q.quoteVersion > 1)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: AppColors.surfaceMuted,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color: AppColors.border,
                                                    width: 0.5),
                                              ),
                                              child: Text(
                                                'v${q.quoteVersion}',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ),
                                          if (q.requiresStructuralClearance &&
                                              !q.isStructurallyCleared)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.warningBg,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                    color: AppColors.warningBorder),
                                              ),
                                              child: Text(
                                                'Structural clearance needed',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.warningText,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${q.serviceName} · ${q.customerName}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${q.serviceCategory} · job #${q.jobId}${q.submittedForApprovalAt != null ? ' · accepted ${_formatTimeAgo(q.submittedForApprovalAt)}' : ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${q.netPayable.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'incl. GST ₹${q.taxAmount.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Divider(height: 1, color: AppColors.border),
                            const SizedBox(height: 12),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: isBusy
                                        ? null
                                        : () => _decideQuote(
                                              quote: q,
                                              approve: true,
                                              isPreSendTab: !isAcceptanceTab,
                                            ),
                                    icon: isBusy
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            !isAcceptanceTab
                                                ? Icons.send_rounded
                                                : Icons.check_circle_outline_rounded,
                                            size: 15,
                                          ),
                                    label: Text(
                                      !isAcceptanceTab
                                          ? 'Release & send'
                                          : 'Approve',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      textStyle: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isBusy
                                        ? null
                                        : () => _decideQuote(
                                              quote: q,
                                              approve: false,
                                              isPreSendTab: !isAcceptanceTab,
                                            ),
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      size: 15,
                                      color: Color(0xFFDC2626),
                                    ),
                                    label: Text('Reject'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFDC2626),
                                      side: BorderSide(
                                          color: AppColors.border),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      textStyle: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}