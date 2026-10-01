import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_invoice.dart';
import 'admin_invoices_providers.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sept',
  'Oct',
  'Nov',
  'Dec',
];

/// `29 Sept 2026` (Web `formatDate`).
String _date(DateTime? d) =>
    d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// `₹1,86,426.88` — Indian grouping with paise (Web `formatMoney`).
String formatInr(double amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final whole = fixed.split('.').first;
  final paise = fixed.split('.').last;
  var grouped = whole;
  if (whole.length > 3) {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}₹$grouped.$paise';
}

/// Customer Invoices & Billing (Web parity: `InvoicesPage.jsx`, route
/// `/workforce/admin/invoices`).
class AdminInvoicesScreen extends ConsumerStatefulWidget {
  const AdminInvoicesScreen({super.key});

  /// Web status tabs: (status, label).
  static const statusTabs = <(String, String)>[
    ('', 'All Invoices'),
    ('PAID', 'Paid'),
    ('ISSUED', 'Issued / Pending'),
    ('PARTIALLY_PAID', 'Partial'),
    ('CANCELLED', 'Cancelled'),
  ];

  @override
  ConsumerState<AdminInvoicesScreen> createState() =>
      _AdminInvoicesScreenState();
}

class _AdminInvoicesScreenState extends ConsumerState<AdminInvoicesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(adminInvoicesListProvider);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFFDC2626)
            : const Color(0xFF059669),
      ),
    );
  }

  /// Web "Export CSV": the filtered rows with the same columns.
  Future<void> _exportCsv(List<AdminInvoice> rows) async {
    if (rows.isEmpty) return;
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final lines = [
      'Invoice Number,Status,Job ID,Customer Name,Customer Phone,Service,Issued Date,Total Amount (INR),Amount Paid (INR),Balance Due (INR)',
      for (final i in rows)
        [
          i.invoiceNumber,
          i.status,
          '${i.jobId ?? 'N/A'}',
          q(i.billToName),
          i.billToPhone,
          q(i.serviceName.isNotEmpty ? i.serviceName : i.serviceCategory),
          q(_date(i.issuedAt)),
          i.totalAmount.toStringAsFixed(2),
          i.amountPaid.toStringAsFixed(2),
          i.balanceDue.toStringAsFixed(2),
        ].join(','),
    ];
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/invoices_export_$stamp.csv');
      await file.writeAsString(lines.join('\n'));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'SEVO Invoices Export',
        ),
      );
    } catch (e) {
      _snack('Export failed: $e', error: true);
    }
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
          _snack(message);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(adminInvoicesSearchQueryProvider);
    final statusFilter = ref.watch(adminInvoicesStatusFilterProvider);
    final invoicesAsync = ref.watch(adminInvoicesListProvider);
    final all = invoicesAsync.valueOrNull ?? const <AdminInvoice>[];
    final filtered = filterInvoices(all, search: search, status: statusFilter);

    int count(String status) => status.isEmpty
        ? all.length
        : all.where((i) => i.status == status).length;

    return SevoModuleFrame(
      module: SevoModule.invoices,
      title: 'Invoices',
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _header(filtered),
              const SizedBox(height: AppSpacing.md),
              if (invoicesAsync.hasValue) ...[
                _Kpis(invoices: all),
                const SizedBox(height: AppSpacing.md),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (id, label) in AdminInvoicesScreen.statusTabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '$label (${count(id)})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: statusFilter == id
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: statusFilter == id
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                          selected: statusFilter == id,
                          showCheckmark: false,
                          onSelected: (_) =>
                              ref
                                      .read(
                                        adminInvoicesStatusFilterProvider
                                            .notifier,
                                      )
                                      .state =
                                  id,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: statusFilter == id
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) =>
                      ref
                              .read(adminInvoicesSearchQueryProvider.notifier)
                              .state =
                          val,
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search invoice, customer, job...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    suffixIcon: search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                      .read(
                                        adminInvoicesSearchQueryProvider
                                            .notifier,
                                      )
                                      .state =
                                  '';
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
              const SizedBox(height: AppSpacing.md),
              invoicesAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 10),
                        Text(
                          'Loading invoices...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
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
                        label: const Text('Try again'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                data: (_) => filtered.isEmpty
                    ? AppCard(
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 16,
                        ),
                        child: const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No invoices found',
                          message:
                              'No invoices match the selected filter criteria.',
                        ),
                      )
                    : Column(
                        children: [
                          for (final inv in filtered)
                            _InvoiceCard(
                              invoice: inv,
                              onTap: () => _openInvoiceDetail(inv),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(List<AdminInvoice> filtered) {
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
                      'Customer Invoices & Billing',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Tax invoices generated automatically for completed service requests and approved quotations.',
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
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered),
                icon: const Icon(Icons.download_rounded, size: 15),
                label: const Text('Export CSV'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Web financial KPI cards, computed from the loaded invoices.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.invoices});

  final List<AdminInvoice> invoices;

  @override
  Widget build(BuildContext context) {
    var billed = 0.0, collected = 0.0, outstanding = 0.0;
    var paid = 0, pending = 0;
    for (final i in invoices) {
      billed += i.totalAmount;
      collected += i.amountPaid;
      outstanding += i.balanceDue;
      if (i.status == 'PAID') {
        paid++;
      } else if (i.status == 'ISSUED' || i.status == 'PARTIALLY_PAID') {
        pending++;
      }
    }
    final cards = [
      (
        'Total Invoiced',
        formatInr(billed),
        '${invoices.length} invoices generated',
        Icons.receipt_rounded,
        const Color(0xFF4F46E5),
      ),
      (
        'Collected Amount',
        formatInr(collected),
        '$paid fully paid invoices',
        Icons.verified_rounded,
        const Color(0xFF059669),
      ),
      (
        'Pending / Outstanding',
        formatInr(outstanding),
        '$pending awaiting payment',
        Icons.schedule_rounded,
        const Color(0xFFB45309),
      ),
      (
        'Total Invoices',
        '${invoices.length}',
        '$paid Paid · $pending Unpaid',
        Icons.description_rounded,
        const Color(0xFF0284C7),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value, sub, icon, color) in cards)
              Container(
                width: w,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Icon(icon, size: 16, color: color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One invoice row from the Web table, as a mobile card.
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.onTap});

  final AdminInvoice invoice;
  final VoidCallback onTap;

  (Color, Color) _statusColors() => switch (invoice.status) {
    'ISSUED' => (AppColors.infoBg, AppColors.infoText),
    'PARTIALLY_PAID' => (AppColors.warningBg, AppColors.warningText),
    'PAID' => (AppColors.successBg, AppColors.successText),
    'CANCELLED' || 'REFUNDED' => (AppColors.errorBg, AppColors.errorText),
    _ => (AppColors.surfaceMuted, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors();
    final service = invoice.serviceName.isNotEmpty
        ? invoice.serviceName
        : invoice.serviceCategory;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        if (invoice.bookingReference != null)
                          Text(
                            'Booking: ${invoice.bookingReference}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      invoice.statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.surfaceMuted,
                    child: Text(
                      invoice.billToName.isEmpty
                          ? 'C'
                          : invoice.billToName[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.billToName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (invoice.billToPhone.isNotEmpty)
                          Text(
                            invoice.billToPhone,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          service,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (invoice.serviceCategory.isNotEmpty &&
                            invoice.serviceCategory != invoice.serviceName)
                          Text(
                            invoice.serviceCategory.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatInr(invoice.totalAmount),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        invoice.balanceDue > 0
                            ? '${formatInr(invoice.balanceDue)} due'
                            : 'Settled',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: invoice.balanceDue > 0
                              ? const Color(0xFFB45309)
                              : const Color(0xFF059669),
                        ),
                      ),
                      Text(
                        _date(invoice.issuedAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
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
  bool _isDownloadingPdf = false;

  /// Official tax invoice PDF, handed to the share sheet (print / save).
  Future<void> _downloadPdf() async {
    setState(() => _isDownloadingPdf = true);
    try {
      final bytes = await ref
          .read(adminDashboardApiProvider)
          .downloadInvoicePdf(_invoice.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_invoice.invoiceNumber}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: _invoice.invoiceNumber,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate PDF.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingPdf = false);
    }
  }

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
                              '${inv.statusLabel} · ${inv.billToName}',
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
                  // Booking, dates and technician (Web tax invoice header)
                  if (inv.bookingReference != null)
                    _DetailRow(
                      label: 'Booking Reference',
                      value: inv.bookingReference!,
                    ),
                  _DetailRow(label: 'Invoice Date', value: _date(inv.issuedAt)),
                  _DetailRow(
                    label: 'Payment Due Date',
                    value: _date(inv.dueDate),
                  ),
                  if (inv.technicianName != null || inv.technicianId != null)
                    _DetailRow(
                      label: 'Assigned Technician',
                      value:
                          inv.technicianName ??
                          'Technician #${inv.technicianId}',
                    ),
                  if (inv.billToPhone.isNotEmpty)
                    _DetailRow(label: 'Customer Phone', value: inv.billToPhone),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isDownloadingPdf ? null : _downloadPdf,
                    icon: _isDownloadingPdf
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('Download PDF'),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 12),

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
                    ...inv.items.map(
                      (item) => Padding(
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
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 12),
                  ],

                  // Commercial Totals
                  _DetailRow(
                    label: 'Total',
                    value: '₹${inv.totalAmount.toStringAsFixed(2)}',
                    isBold: true,
                  ),
                  if (inv.balanceAmount > 0) ...[
                    _DetailRow(
                      label:
                          'Advance (${inv.advancePercent?.toStringAsFixed(0) ?? 0}%)',
                      value: '₹${inv.advanceAmount.toStringAsFixed(2)}',
                    ),
                    _DetailRow(
                      label: 'Balance on completion',
                      value: '₹${inv.balanceAmount.toStringAsFixed(2)}',
                    ),
                  ],
                  _DetailRow(
                    label: 'Paid',
                    value: '₹${inv.amountPaid.toStringAsFixed(2)}',
                  ),
                  _DetailRow(
                    label: 'Outstanding',
                    value: '₹${inv.balanceDue.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: inv.balanceDue > 0
                        ? const Color(0xFFB45309)
                        : null,
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
                    ...inv.payments.map(
                      (p) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.5,
                          ),
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
                      ),
                    ),
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
                              decimal: true,
                            ),
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
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
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
