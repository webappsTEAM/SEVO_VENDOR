import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/workforce_app_bar.dart';
import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_invoice.dart';
import '../widgets/admin_drawer.dart';
import 'admin_invoices_providers.dart';

/// Super Admin / SEVO Platform Commercial Invoices Screen.
///
/// Invoices raised automatically from approved quotations: tracks billing,
/// outstanding balances, paid amounts, payment recording, and PDF invoices.
class AdminInvoicesScreen extends ConsumerStatefulWidget {
  const AdminInvoicesScreen({super.key});

  @override
  ConsumerState<AdminInvoicesScreen> createState() => _AdminInvoicesScreenState();
}

class _AdminInvoicesScreenState extends ConsumerState<AdminInvoicesScreen> {
  final TextEditingController _searchController = TextEditingController();

  static const _statusFilters = [
    {'id': '', 'label': 'All Statuses'},
    {'id': 'ISSUED', 'label': 'Issued'},
    {'id': 'PARTIALLY_PAID', 'label': 'Partially Paid'},
    {'id': 'PAID', 'label': 'Paid'},
    {'id': 'CANCELLED', 'label': 'Cancelled'},
    {'id': 'REFUNDED', 'label': 'Refunded'},
    {'id': 'DRAFT', 'label': 'Draft'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(adminInvoicesListProvider);
  }

  void _openInvoiceDetail(AdminInvoice invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InvoiceDetailBottomSheet(
        initialInvoice: invoice,
        onPaid: (updated, message) {
          _refresh();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(adminInvoicesSearchQueryProvider);
    final statusFilter = ref.watch(adminInvoicesStatusFilterProvider);
    final invoicesAsync = ref.watch(adminInvoicesListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WorkforceAppBar(
        titleText: 'Invoices & Billing',
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
                            Icons.receipt_long_rounded,
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
                                'Invoices',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Raised automatically when SEVO approves a quotation.',
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
                          onPressed: _refresh,
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

              // ── Search & Filter Controls ───────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    ref.read(adminInvoicesSearchQueryProvider.notifier).state =
                        val;
                  },
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Invoice number, customer, phone',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: AppColors.textMuted),
                    suffixIcon: search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(adminInvoicesSearchQueryProvider.notifier)
                                  .state = '';
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Status Filters Carousel ────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _statusFilters.map((st) {
                    final isSelected = statusFilter == st['id'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          st['label']!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            ref
                                .read(adminInvoicesStatusFilterProvider.notifier)
                                .state = st['id']!;
                          }
                        },
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        backgroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Invoices List ──────────────────────────────────────────────
              invoicesAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: CircularProgressIndicator(color: AppColors.primary),
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
                        'Unable to load invoices',
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
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return AppCard(
                      padding: const EdgeInsets.symmetric(
                          vertical: 40, horizontal: 16),
                      child: const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No invoices yet.',
                        message:
                            'No invoices match the selected filter criteria.',
                      ),
                    );
                  }

                  return Column(
                    children: invoices.map((inv) {
                      return _InvoiceCard(
                        invoice: inv,
                        onTap: () => _openInvoiceDetail(inv),
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

/// Responsive card presenting an individual commercial invoice.
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.onTap,
  });

  final AdminInvoice invoice;
  final VoidCallback onTap;

  Color _getStatusBg() {
    switch (invoice.status) {
      case 'ISSUED':
        return AppColors.infoBg;
      case 'PARTIALLY_PAID':
        return AppColors.warningBg;
      case 'PAID':
        return AppColors.successBg;
      default:
        return AppColors.surfaceMuted;
    }
  }

  Color _getStatusTextColor() {
    switch (invoice.status) {
      case 'ISSUED':
        return AppColors.infoText;
      case 'PARTIALLY_PAID':
        return AppColors.warningText;
      case 'PAID':
        return AppColors.successText;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x040F172A),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                          invoice.invoiceNumber,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusBg(),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            invoice.statusDisplay,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _getStatusTextColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${invoice.billToName} · ${invoice.serviceName}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (invoice.issuedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Issued ${invoice.issuedAt!.day.toString().padLeft(2, '0')}/${invoice.issuedAt!.month.toString().padLeft(2, '0')}/${invoice.issuedAt!.year}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${invoice.totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (invoice.balanceDue > 0)
                    Text(
                      '₹${invoice.balanceDue.toStringAsFixed(2)} outstanding',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detailed Bottom Sheet with invoice line items, payments history, and recording flow.
class _InvoiceDetailBottomSheet extends ConsumerStatefulWidget {
  const _InvoiceDetailBottomSheet({
    required this.initialInvoice,
    required this.onPaid,
  });

  final AdminInvoice initialInvoice;
  final void Function(AdminInvoice updated, String message) onPaid;

  @override
  ConsumerState<_InvoiceDetailBottomSheet> createState() =>
      _InvoiceDetailBottomSheetState();
}

class _InvoiceDetailBottomSheetState
    extends ConsumerState<_InvoiceDetailBottomSheet> {
  late AdminInvoice _invoice;
  late TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();
  String _selectedMethod = 'ONLINE';
  bool _isSavingPayment = false;

  static const _paymentMethods = ['ONLINE', 'UPI', 'CARD', 'CASH', 'OTHER'];

  @override
  void initState() {
    super.initState();
    _invoice = widget.initialInvoice;
    _amountController = TextEditingController(
      text: _invoice.balanceDue > 0
          ? _invoice.balanceDue.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _recordPayment() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) return;

    setState(() => _isSavingPayment = true);
    try {
      final api = ref.read(adminDashboardApiProvider);
      final res = await api.recordInvoicePayment(
        _invoice.id,
        amount: amount,
        method: _selectedMethod,
        reference: _referenceController.text.trim(),
      );

      final updatedInvoice = res['invoice'] is Map<String, dynamic>
          ? AdminInvoice.fromJson(res['invoice'] as Map<String, dynamic>)
          : _invoice;

      final isDuplicate = res['duplicate'] == true;
      final msg = isDuplicate
          ? 'Reference was already recorded on ${_invoice.invoiceNumber}; nothing charged twice.'
          : '₹${amount.toStringAsFixed(2)} recorded against ${_invoice.invoiceNumber}.';

      if (mounted) {
        Navigator.of(context).pop();
        widget.onPaid(updatedInvoice, msg);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment record failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(adminInvoiceDetailProvider(_invoice.id));
    final inv = detailAsync.valueOrNull ?? _invoice;
    final outstanding = inv.balanceDue;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Sheet Drag Handle & Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inv.invoiceNumber,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              inv.billToName,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Line Items Breakdown
                  if (inv.items.isNotEmpty) ...[
                    Text(
                      'LINE ITEMS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...inv.items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.name} × ${item.quantity} ${item.unit}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Text(
                                '₹${item.totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 12),
                  ],

                  // Commercial Totals
                  _DetailRow(label: 'Total', value: '₹${inv.totalAmount.toStringAsFixed(2)}', isBold: true),
                  if (inv.balanceAmount > 0) ...[
                    _DetailRow(
                        label: 'Advance (${inv.advancePercent?.toStringAsFixed(0) ?? 0}%)',
                        value: '₹${inv.advanceAmount.toStringAsFixed(2)}'),
                    _DetailRow(
                        label: 'Balance on completion',
                        value: '₹${inv.balanceAmount.toStringAsFixed(2)}'),
                  ],
                  _DetailRow(label: 'Paid', value: '₹${inv.amountPaid.toStringAsFixed(2)}'),
                  _DetailRow(
                    label: 'Outstanding',
                    value: '₹${inv.balanceDue.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: inv.balanceDue > 0 ? const Color(0xFFB45309) : null,
                  ),

                  // Payments History
                  if (inv.payments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'PAYMENTS HISTORY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...inv.payments.map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.method,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (p.reference.isNotEmpty)
                                    Text(
                                      'Ref: ${p.reference}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                '₹${p.amount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],

                  // Record Payment Section
                  if (outstanding > 0 && !inv.isCancelled) ...[
                    const SizedBox(height: 16),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 14),
                    Text(
                      'Record a payment',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Amount (₹)',
                              border: OutlineInputBorder(),
                              prefixText: '₹ ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedMethod,
                            decoration: const InputDecoration(
                              labelText: 'Method',
                              border: OutlineInputBorder(),
                            ),
                            items: _paymentMethods.map((m) {
                              return DropdownMenuItem(value: m, child: Text(m));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedMethod = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Transaction Reference (optional)',
                        hintText: 'e.g. UPI Ref / Bank UTR / Cash receipt',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A reference makes this safe to repeat: recording the same reference twice will not charge twice.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _isSavingPayment ? null : _recordPayment,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isSavingPayment
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('Record ₹${_amountController.text.trim()}'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}