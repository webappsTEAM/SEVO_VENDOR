import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_quotation.dart';
import 'admin_quotation_providers.dart';

/// Quotation Approvals & Review (Web parity: `AdminQuotationApprovalsPage.jsx`,
/// route `/workforce/admin/quotations`).
///
/// Three queues, in Web order:
/// 1. Held before sending — technician-submitted quotes awaiting CRM clearance
///    (`/quotes/pending-review/`); releasing sends the quote to the customer.
/// 2. Awaiting SEVO approval — customer-accepted quotes
///    (`/quotes/pending-approval/`); approving creates the booking + invoice.
/// 3. All Quotations & History (`/quotes/`).
class AdminQuotationApprovalsScreen extends ConsumerStatefulWidget {
  const AdminQuotationApprovalsScreen({super.key});

  static const tabs = <(String, String, String)>[
    (
      'presend',
      'Held before sending',
      'Submitted by technician for CRM/Operations clearance. Releasing sends the quote to the customer.',
    ),
    (
      'acceptance',
      'Awaiting SEVO approval',
      'The customer has accepted. Approving creates the work booking and issues the invoice.',
    ),
    (
      'all',
      'All Quotations & History',
      'Full historical log of all drafted, sent, customer accepted, approved, and converted quotations.',
    ),
  ];

  @override
  ConsumerState<AdminQuotationApprovalsScreen> createState() =>
      _AdminQuotationApprovalsScreenState();
}

class _AdminQuotationApprovalsScreenState
    extends ConsumerState<AdminQuotationApprovalsScreen> {
  String? _flashMessage;
  int? _busyQuoteId;
  final Set<int> _expanded = {};

  static String _money(double v) => '₹${v.toStringAsFixed(2)}';

  String _ago(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 60)}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  AutoDisposeFutureProvider<List<AdminQuotation>> _providerFor(String tab) =>
      switch (tab) {
        'acceptance' => adminQuotesPendingApprovalProvider,
        'all' => adminQuotesAllProvider,
        _ => adminQuotesPendingReviewProvider,
      };

  Future<void> _refresh() async {
    ref.invalidate(adminQuotesPendingApprovalProvider);
    ref.invalidate(adminQuotesPendingReviewProvider);
    ref.invalidate(adminQuotesAllProvider);
  }

  /// `preSend` follows the quote's own state (PENDING_REVIEW) like the Web.
  Future<void> _decideQuote({
    required AdminQuotation quote,
    required bool approve,
    required bool preSend,
  }) async {
    final verb = preSend
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
          title: Text(
            '$verb ${quote.quoteNumber}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reason for rejection (shown in audit trail):',
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
              child: const Text('Cancel'),
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
      // The Web requires a reason to reject.
      if (notes.isEmpty) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          title: Text(
            '$verb ${quote.quoteNumber}?',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Text(
            preSend
                ? 'Release ${quote.quoteNumber} and send to customer for approval?'
                : 'Approve ${quote.quoteNumber} and issue invoice? This creates the work booking.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
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

    setState(() => _busyQuoteId = quote.id);
    try {
      final api = ref.read(adminDashboardApiProvider);
      final action = approve ? 'APPROVE' : 'REJECT';
      final res = preSend
          ? await api.preSendReviewQuote(
              quote.id,
              action: action,
              notes: notes,
              reason: notes,
            )
          : await api.adminReviewQuote(
              quote.id,
              action: action,
              notes: notes,
              reason: notes,
            );
      if (mounted) {
        final invoice = res['invoice'];
        setState(() {
          if (invoice is Map && invoice['invoice_number'] != null) {
            final total =
                double.tryParse('${invoice['total_amount']}') ??
                quote.totalAmount;
            _flashMessage =
                '${quote.quoteNumber} approved. Invoice ${invoice['invoice_number']} issued for ${_money(total)}.';
          } else if (preSend && approve) {
            _flashMessage =
                '${quote.quoteNumber} released and delivered to the customer for approval.';
          } else {
            _flashMessage =
                '${quote.quoteNumber} ${approve ? 'approved' : 'rejected'}.';
          }
        });
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process ${quote.quoteNumber}: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyQuoteId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(adminQuotationTabProvider);
    final tab = AdminQuotationApprovalsScreen.tabs.firstWhere(
      (t) => t.$1 == activeTab,
      orElse: () => AdminQuotationApprovalsScreen.tabs.first,
    );
    final quotesAsync = ref.watch(_providerFor(tab.$1));

    return SevoModuleFrame(
      module: SevoModule.quotations,
      title: 'Quotation Approvals',
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _header(tab.$3),
              const SizedBox(height: AppSpacing.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in AdminQuotationApprovalsScreen.tabs) ...[
                      _tabChip(t.$1, t.$2, t.$1 == tab.$1),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_flashMessage != null) _flash(),
              quotesAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: AppColors.textPrimary),
                        const SizedBox(height: 10),
                        Text(
                          'Loading quotations...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                error: (err, _) => _error(err),
                data: (quotes) => quotes.isEmpty
                    ? AppCard(
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 16,
                        ),
                        child: const EmptyState(
                          icon: Icons.article_outlined,
                          title: 'No Quotations Pending',
                          message:
                              'All quotations in this queue have been processed. New quotations submitted by '
                              'technicians or accepted by customers will appear here.',
                        ),
                      )
                    : Column(children: [for (final q in quotes) _quoteCard(q)]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String blurb) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
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
                  Icons.calculate_rounded,
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
                      'Quotation Approvals & Review',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      blurb,
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
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _busyQuoteId != null ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Refresh Queue'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String key, String label, bool selected) {
    final count = ref.watch(_providerFor(key)).valueOrNull?.length;
    return ChoiceChip(
      label: Text(
        count == null ? label : '$label ($count)',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      onSelected: (_) {
        setState(() => _flashMessage = null);
        ref.read(adminQuotationTabProvider.notifier).state = key;
      },
    );
  }

  Widget _flash() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.successText,
            size: 20,
          ),
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
    );
  }

  Widget _error(Object err) {
    return AppCard(
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
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try again'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    if (const [
      'CUSTOMER_ACCEPTED',
      'CONVERTED',
      'ADMIN_APPROVED',
    ].contains(status))
      return const Color(0xFF059669);
    if (status == 'SENT_TO_CUSTOMER' || status == 'SENT')
      return const Color(0xFF2563EB);
    if (const [
      'PENDING_REVIEW',
      'CRM_REVIEW',
      'CHANGES_REQUESTED',
    ].contains(status))
      return const Color(0xFFD97706);
    if (const [
      'ADMIN_REJECTED',
      'REJECTED',
      'DECLINED',
      'CUSTOMER_DECLINED',
    ].contains(status)) {
      return const Color(0xFFE11D48);
    }
    return const Color(0xFF475569);
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _quoteCard(AdminQuotation q) {
    final isBusy = _busyQuoteId == q.id;
    final expanded = _expanded.contains(q.id);
    final meta = [
      'Job ID: #${q.jobId}',
      if (q.submittedForApprovalAt != null)
        'Submitted ${_ago(q.submittedForApprovalAt)}',
      if (q.customerDecidedAt != null) 'Accepted ${_ago(q.customerDecidedAt)}',
      if (q.items.isNotEmpty) '${q.items.length} Scope Item(s)',
      if (q.measurements.isNotEmpty)
        '${q.measurements.length} Area(s) (${q.totalArea.toStringAsFixed(0)} sq.ft)',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(
              () => expanded ? _expanded.remove(q.id) : _expanded.add(q.id),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
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
                            _pill(
                              'v${q.quoteVersion}',
                              const Color(0xFF475569),
                            ),
                          _pill(q.serviceCategory, const Color(0xFF4F46E5)),
                          if (q.status.isNotEmpty)
                            _pill(
                              q.statusLabel.toUpperCase(),
                              _statusColor(q.status),
                            ),
                          if (q.requiresStructuralClearance &&
                              !q.isStructurallyCleared)
                            _pill(
                              'Structural clearance needed',
                              const Color(0xFFD97706),
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
                        meta,
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
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (expanded) ...[const SizedBox(height: 12), _breakdown(q)],
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          _actions(q, isBusy),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _openDetails(q),
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('View Full Details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(AdminQuotation q, bool isBusy) {
    Widget busy(IconData icon) => isBusy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(icon, size: 15);

    if (q.isHeldForReview || q.isAwaitingApproval) {
      final preSend = q.isHeldForReview;
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: isBusy
                  ? null
                  : () =>
                        _decideQuote(quote: q, approve: true, preSend: preSend),
              icon: busy(
                preSend
                    ? Icons.send_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              label: Text(
                preSend
                    ? 'Release & Send to Customer'
                    : 'Approve & Issue Work Invoice',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: preSend
                    ? AppColors.textPrimary
                    : AppColors.emerald,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () =>
                      _decideQuote(quote: q, approve: false, preSend: preSend),
            icon: const Icon(
              Icons.cancel_outlined,
              size: 15,
              color: Color(0xFFDC2626),
            ),
            label: Text(preSend ? 'Reject Quote' : 'Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Color(0xFF059669),
        ),
        const SizedBox(width: 6),
        Text(
          'Status: ${q.statusLabel}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Inline breakdown (Web expanded accordion).
  Widget _breakdown(AdminQuotation q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            _stat('Total Quoted', _money(q.netPayable)),
            _stat(
              '50% Advance Milestone',
              _money(q.advance),
              color: const Color(0xFF4F46E5),
            ),
            _stat(
              '50% Completion Balance',
              _money(q.balance),
              color: AppColors.emerald,
            ),
            _stat('GST Tax', _money(q.taxAmount)),
          ],
        ),
        if (q.measurements.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Room & Surface Measurements · Total Area: ${q.totalArea.toStringAsFixed(0)} sq.ft',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          for (var i = 0; i < q.measurements.length; i++)
            _measurementRow(q.measurements[i], i),
        ],
        if (q.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Itemized Scope & Rate-Card Breakdown (${q.items.length})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          for (final item in q.items) _itemRow(item),
        ],
        if (q.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'TECHNICIAN INSPECTION & SCOPE NOTES',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            q.description,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _measurementRow(AdminQuoteMeasurement m, int index) {
    final dims = m.length != null && m.width != null
        ? ' (${m.length}ft × ${m.width}ft${m.height != null ? ' × ${m.height}ft' : ''})'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${m.name.isEmpty ? 'Area #${index + 1}' : m.name}$dims',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Text(
            '${m.area.toStringAsFixed(0)} sq.ft',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(AdminQuoteItem item) {
    final details = [
      '${item.quantity} ${item.unit} × ₹${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
      if (item.taxRate > 0) 'GST ${item.taxRate}%',
      if (item.section != null) item.section!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  details,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _money(item.total),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  /// Full detail sheet (Web "Open Detailed Modal").
  void _openDetails(AdminQuotation q) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${q.quoteNumber}${q.quoteVersion > 1 ? '  v${q.quoteVersion}' : ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${q.serviceName} · Job #${q.jobId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [_pill(q.serviceCategory, const Color(0xFF4F46E5))],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _stat('Customer', q.customerName)),
                const SizedBox(width: 8),
                Expanded(
                  child: _stat('Consultation Booking', 'Job #${q.jobId}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _stat(
              'Status',
              q.isHeldForReview ? 'Held for CRM Review' : q.statusLabel,
              color: const Color(0xFFB45309),
            ),
            const SizedBox(height: 12),
            _breakdown(q),
            const SizedBox(height: 16),
            _actions(q, _busyQuoteId == q.id),
          ],
        ),
      ),
    );
  }
}
