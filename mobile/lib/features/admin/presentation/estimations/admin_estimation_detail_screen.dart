import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../seller/presentation/widgets/seller_hub_widgets.dart';
import '../../data/vendor_estimation_repository.dart';
import '../../domain/vendor_estimation.dart';
import 'admin_estimations_screen.dart'
    show estimationFeeColor, estimationStatusColor;
import 'estimation_inspection_screen.dart';
import 'estimation_quotation_screen.dart';

Map<String, dynamic>? latestQuotation(VendorEstimation e) {
  final raw = e.raw;
  if (raw['latest_quotation'] is Map)
    return Map<String, dynamic>.from(raw['latest_quotation'] as Map);
  final list = raw['quotations'];
  if (list is List && list.isNotEmpty && list.first is Map)
    return Map<String, dynamic>.from(list.first as Map);
  return null;
}

String money(num v) {
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  // Indian digit grouping: last 3, then groups of 2.
  if (digits.length <= 3) {
    buf.write(digits);
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    buf.write('${groups.join(',')},$last3');
  }
  return '₹$buf.${parts[1]}';
}

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Web detail console of `VendorEstimationsPage`: stage banner with the next
/// action, customer + AC cards, rate card, quotation / decision / repair panel,
/// visit fee and inspection findings.
class AdminEstimationDetailScreen extends ConsumerStatefulWidget {
  const AdminEstimationDetailScreen({super.key, required this.leadId});

  final int leadId;

  @override
  ConsumerState<AdminEstimationDetailScreen> createState() =>
      _AdminEstimationDetailScreenState();
}

class _AdminEstimationDetailScreenState
    extends ConsumerState<AdminEstimationDetailScreen> {
  VendorEstimation? _lead;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  VendorEstimationRepository get _repo =>
      ref.read(vendorEstimationRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner) setState(() => _loading = true);
    try {
      final l = await _repo.detail(widget.leadId);
      if (mounted) {
        setState(() {
          _lead = l;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Could not fetch full lead details.';
        });
      }
    }
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
      ),
    );
  }

  /// Runs a workflow call that returns the refreshed lead.
  Future<void> _act(Future<VendorEstimation> Function() call) async {
    setState(() => _busy = true);
    try {
      final l = await call();
      if (mounted) setState(() => _lead = l);
    } catch (e) {
      _toast(
        e is VendorEstimationException
            ? e.message
            : 'Action failed. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok) _toast('Could not open link.', error: true);
  }

  Future<void> _assign(VendorEstimation l) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => _AssignSheet(lead: l, repo: _repo),
    );
    if (ok == true) await _load(spinner: false);
  }

  Future<void> _otp(VendorEstimation l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _OtpDialog(lead: l, repo: _repo),
    );
    if (ok == true) await _load(spinner: false);
  }

  Future<void> _fee(VendorEstimation l) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => _FeeSheet(lead: l, repo: _repo),
    );
    if (ok == true) await _load(spinner: false);
  }

  Future<void> _inspection(VendorEstimation l) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EstimationInspectionScreen(lead: l)),
    );
    if (ok == true) await _load(spinner: false);
  }

  Future<void> _quotation(VendorEstimation l) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EstimationQuotationScreen(lead: l)),
    );
    if (ok == true) await _load(spinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final l = _lead;
    return SevoModuleFrame(
      module: SevoModule.estimations,
      title: l == null ? 'Estimation Lead' : 'Lead #${l.reference}',
      body: SafeArea(child: _body(l)),
    );
  }

  Widget _body(VendorEstimation? l) {
    if (_loading && l == null)
      return const SellerLoading(message: 'Loading lead...');
    if (l == null) {
      return ListView(
        children: [
          SellerStateMessage(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFDC2626),
            title: 'Lead not available',
            message: _error ?? 'Could not fetch full lead details.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ],
      );
    }
    final quote = latestQuotation(l);
    return RefreshIndicator(
      onRefresh: () => _load(spinner: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _stageBanner(l),
          const SizedBox(height: AppSpacing.sm),
          _customerCard(l),
          const SizedBox(height: AppSpacing.sm),
          _acCard(l),
          if (l.rateCard.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _rateCard(l),
          ],
          if (quote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _QuoteCard(
              lead: l,
              quote: quote,
              busy: _busy,
              onAct: _act,
              onEdit: () => _quotation(l),
              repo: _repo,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _RepairAndFee(
            lead: l,
            quote: quote,
            busy: _busy,
            onAct: _act,
            onFee: () => _fee(l),
            repo: _repo,
          ),
          if (l.findings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _findings(l),
          ],
          const SizedBox(height: AppSpacing.md),
          if (l.createdAt != null)
            Text(
              'Lead Created: ${l.createdAt!.toLocal().toString().split('.').first}',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  // ── Stage banner + next action ───────────────────────────────────────────
  Widget _stageBanner(VendorEstimation l) {
    final color = estimationStatusColor(l.status);
    final Widget cta = switch (l.status) {
      'REQUESTED' => _ctaBtn(
        Icons.check_circle_rounded,
        'Accept Lead',
        () => _act(() => _repo.confirm(l.id)),
      ),
      'VENDOR_CONFIRMED' => _ctaBtn(
        Icons.how_to_reg_rounded,
        'Assign Technician',
        () => _assign(l),
      ),
      'TECHNICIAN_ASSIGNED' => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : () => _assign(l),
            child: const Text('Reassign'),
          ),
          _ctaBtn(
            Icons.navigation_rounded,
            'Start Trip',
            () => _act(() => _repo.startJourney(l.id)),
          ),
        ],
      ),
      'TECHNICIAN_ON_THE_WAY' => _ctaBtn(
        Icons.location_on_rounded,
        'Mark Arrived',
        () => _act(() => _repo.markArrived(l.id)),
      ),
      'TECHNICIAN_ARRIVED' => _ctaBtn(
        Icons.check_circle_rounded,
        'Enter Customer Start OTP',
        () => _otp(l),
      ),
      'INSPECTION_IN_PROGRESS' => _ctaBtn(
        Icons.build_rounded,
        'Open Inspection Sheet',
        () => _inspection(l),
      ),
      'INSPECTION_COMPLETED' => _ctaBtn(
        Icons.request_quote_rounded,
        'Create Quotation',
        () => _quotation(l),
      ),
      'QUOTATION_SENT' || 'CUSTOMER_APPROVED' || 'CUSTOMER_REJECTED' => _ctaBtn(
        Icons.request_quote_rounded,
        'View / Edit Quote',
        () => _quotation(l),
      ),
      _ => const SizedBox.shrink(),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CURRENT OPERATIONAL STAGE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SellerPill(label: estimationStatusLabel(l.status), color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            estimationStageTitle(l),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          cta,
        ],
      ),
    );
  }

  Widget _ctaBtn(IconData icon, String label, VoidCallback onTap) =>
      FilledButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
      );

  Widget _card(String title, Widget child, {Widget? trailing}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _customerCard(VendorEstimation l) => _card(
    'Customer Contact Information',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.customerName ?? '—',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          '${l.phone ?? '—'} • ${(l.email ?? '').isEmpty ? 'No email' : l.email}',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if ((l.address ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.address!,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if ((l.phone ?? '').isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _openUrl('tel:${l.phone}'),
                icon: const Icon(Icons.phone_rounded, size: 16),
                label: const Text('Call Customer'),
              ),
            if ((l.address ?? '').isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _openUrl(
                  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(l.address!)}',
                ),
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: const Text('Google Maps'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _acCard(VendorEstimation l) => _card(
    'Air Conditioner Specifications',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SellerKeyValue('Brand', l.acBrand ?? '—'),
        SellerKeyValue('Type', l.acType ?? '—'),
        SellerKeyValue('Capacity', (l.acCapacity ?? '—').replaceAll('_', ' ')),
        SellerKeyValue('Units', '${l.acQuantity ?? 1}'),
        if ((l.symptom ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '"${l.symptom}"',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _rateCard(VendorEstimation l) => _card(
    'Authorized Rate Card Snapshot (${l.rateCard.length} Pre-approved Items)',
    Column(
      children: [
        for (final r in l.rateCard)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${r.category ?? ''} • ${r.unit ?? 'unit'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  r.price == null ? '—' : money(r.price!),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _findings(VendorEstimation l) => _card(
    'Inspection Findings (${l.findings.length})',
    Column(
      children: [
        for (final f in l.findings)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (f.severity != null)
                      SellerPill(
                        label: f.severity!,
                        color: severityColor(f.severity!),
                      ),
                  ],
                ),
                if ((f.description ?? '').isNotEmpty)
                  Text(
                    f.description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if ((f.recommendedAction ?? '').isNotEmpty)
                  Text(
                    'Fix: ${f.recommendedAction}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D9488),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
    trailing: (l.status == 'INSPECTION_IN_PROGRESS')
        ? TextButton(
            onPressed: _busy ? null : () => _inspection(l),
            child: const Text('Edit Findings'),
          )
        : null,
  );
}

Color severityColor(String s) => switch (s.toUpperCase()) {
  'LOW' => AppColors.emerald,
  'MEDIUM' => const Color(0xFFD97706),
  'HIGH' => const Color(0xFFEA580C),
  'CRITICAL' => const Color(0xFFE11D48),
  _ => AppColors.textMuted,
};

// ═════════════════════════════════════════════════════════════════════════════
// Quotation card + admin review / customer decision
// ═════════════════════════════════════════════════════════════════════════════

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.lead,
    required this.quote,
    required this.busy,
    required this.onAct,
    required this.onEdit,
    required this.repo,
  });

  final VendorEstimation lead;
  final Map<String, dynamic> quote;
  final bool busy;
  final Future<void> Function(Future<VendorEstimation> Function()) onAct;
  final VoidCallback onEdit;
  final VendorEstimationRepository repo;

  int? get _quoteId => quote['id'] is num
      ? (quote['id'] as num).toInt()
      : int.tryParse('${quote['id']}');
  String get _status => '${quote['status'] ?? ''}'.toUpperCase();

  Future<void> _adminReview(
    BuildContext context,
    String action,
    bool autoConvert,
  ) async {
    final id = _quoteId;
    if (id == null) return;
    final notes = TextEditingController(
      text: action == 'SEND_BACK'
          ? ''
          : autoConvert
          ? 'Approved and converted directly to active service booking.'
          : 'Approved based on on-site inspection findings.',
    );
    var convert = autoConvert;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(
            action == 'SEND_BACK'
                ? 'Send Back to Technician'
                : 'Approve Quotation',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quotation: #${quote['quote_ref'] ?? ''} • ${money(_num(quote['total_amount']))}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (action == 'APPROVE')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: convert,
                  onChanged: (v) => set(() => convert = v ?? false),
                  title: const Text(
                    'Directly convert to active Service Booking',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Admin notes'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                action == 'SEND_BACK' ? 'Send Back' : 'Confirm Approval',
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await onAct(
        () => repo.adminReviewQuotation(
          lead.id,
          id,
          action: action,
          notes: notes.text.trim(),
          autoConvert: convert,
        ),
      );
    }
  }

  Future<void> _customerApprove(BuildContext context) async {
    var date = DateTime.now();
    var slot = '10:00 AM - 01:00 PM';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Accept Quotation & Book Job'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quotation: #${quote['quote_ref'] ?? ''} • ${money(_num(quote['total_amount']))}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                ),
                onPressed: () async {
                  final p = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) set(() => date = p);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: slot,
                decoration: const InputDecoration(labelText: 'Time slot'),
                items: const [
                  DropdownMenuItem(
                    value: '10:00 AM - 01:00 PM',
                    child: Text('10:00 AM - 01:00 PM (Morning)'),
                  ),
                  DropdownMenuItem(
                    value: '02:00 PM - 05:00 PM',
                    child: Text('02:00 PM - 05:00 PM (Afternoon)'),
                  ),
                  DropdownMenuItem(
                    value: '05:00 PM - 08:00 PM',
                    child: Text('05:00 PM - 08:00 PM (Evening)'),
                  ),
                ],
                onChanged: (v) => set(() => slot = v ?? slot),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm & Book Job'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final iso =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await onAct(
        () => repo.approveQuotationForCustomer(lead.id, date: iso, time: slot),
      );
    }
  }

  Future<void> _customerReject(BuildContext context) async {
    var reason = 'PRICE_TOO_HIGH';
    var method = 'UPI';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Cancel Estimation & Collect Visit Fee'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: const [
                    DropdownMenuItem(
                      value: 'PRICE_TOO_HIGH',
                      child: Text('Quotation Price Too High'),
                    ),
                    DropdownMenuItem(
                      value: 'WILL_DO_LATER',
                      child: Text('Customer Postponed Work'),
                    ),
                    DropdownMenuItem(
                      value: 'LOCAL_TECH_FOUND',
                      child: Text('Customer Found Alternative'),
                    ),
                    DropdownMenuItem(
                      value: 'NO_REPAIR_NEEDED',
                      child: Text('No Repair Needed'),
                    ),
                    DropdownMenuItem(
                      value: 'OTHER',
                      child: Text('Other Reason'),
                    ),
                  ],
                  onChanged: (v) => set(() => reason = v ?? reason),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Customer notes / feedback',
                    hintText: 'Optional note explaining customer decision...',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Payment method',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const ['UPI', 'CASH', 'ONLINE'])
                      ChoiceChip(
                        label: Text(m),
                        selected: method == m,
                        onSelected: (_) => set(() => method = m),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: const Text('Confirm Rejection'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await onAct(
        () => repo.rejectQuotationForCustomer(
          lead.id,
          reason: reason,
          note: note.text.trim(),
          paymentMethod: method,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (quote['items'] is List ? quote['items'] as List : const [])
        .whereType<Map>()
        .toList();
    final tax = _num(quote['tax_amount']);
    final discount = _num(quote['discount_amount']);
    final status = _status;
    final subtotal = items.isEmpty
        ? null
        : items.fold<double>(
            0,
            (s, it) =>
                s +
                (_num(it['quantity']) == 0 ? 1 : _num(it['quantity'])) *
                    _num(it['unit_price']),
          );
    final color = switch (status) {
      'SUBMITTED_FOR_ADMIN_REVIEW' => const Color(0xFF4F46E5),
      'APPROVED' || 'CUSTOMER_APPROVED' => AppColors.emerald,
      'SENT' || 'QUOTATION_SENT' => const Color(0xFF2563EB),
      'SENT_BACK_TO_TECHNICIAN' => const Color(0xFFD97706),
      _ => AppColors.textSecondary,
    };
    final sentToCustomer =
        status == 'SENT' ||
        status == 'ADMIN_APPROVED' ||
        lead.status == 'QUOTATION_SENT';
    final rejected =
        status == 'REJECTED' ||
        const [
          'CUSTOMER_REJECTED',
          'CANCELLED',
          'CLOSED_INSPECTION_ONLY',
        ].contains(lead.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quotation #${quote['quote_ref'] ?? ''} (v${quote['version'] ?? 1})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SellerPill(label: status.replaceAll('_', ' '), color: color),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'Quotation total: ${money(_num(quote['total_amount']))} (${quote['items_count'] ?? 0} line items)',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            )
          else
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${it['service_name'] ?? it['title'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${it['item_type'] ?? 'PART'} • ${it['quantity'] ?? 1} ${it['unit'] ?? 'unit'} × ${money(_num(it['unit_price']))}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(
                        (_num(it['quantity']) == 0 ? 1 : _num(it['quantity'])) *
                            _num(it['unit_price']),
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          const Divider(height: 16),
          if (subtotal != null) _sum('Subtotal', money(subtotal)),
          if (tax > 0) _sum('GST', money(tax)),
          if (discount > 0) _sum('Discount', '- ${money(discount)}'),
          _sum('Grand Total', money(_num(quote['total_amount'])), bold: true),
          if ('${quote['notes'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Terms: ${quote['notes']}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (status == 'SUBMITTED_FOR_ADMIN_REVIEW')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => _adminReview(context, 'APPROVE', false),
                  child: const Text('Approve & Release to Customer'),
                ),
                FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () => _adminReview(context, 'APPROVE', true),
                  child: const Text('Approve & Convert to Booking'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _adminReview(context, 'SEND_BACK', false),
                  child: const Text('Send Back to Tech'),
                ),
              ],
            ),
          if (status == 'SENT_BACK_TO_TECHNICIAN') ...[
            if ('${quote['admin_notes'] ?? ''}'.isNotEmpty)
              Text(
                'Admin notes: ${quote['admin_notes']}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : _revise,
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Revise Quotation'),
            ),
          ],
          if (sentToCustomer &&
              status != 'SUBMITTED_FOR_ADMIN_REVIEW' &&
              !rejected)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => _customerApprove(context),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Customer Accepts'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _customerReject(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Customer Rejects'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          if (rejected) ...[
            const Text(
              'Customer rejected / estimation closed.',
              style: TextStyle(fontSize: 12, color: Color(0xFFE11D48)),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: busy ? null : _revise,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Revise & Resend Quote'),
            ),
          ],
          if (status == 'DRAFT' || status.isEmpty)
            OutlinedButton.icon(
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit Quote'),
            ),
        ],
      ),
    );
  }

  Future<void> _revise() async {
    final id = _quoteId;
    if (id == null) return;
    await onAct(() => repo.reviseQuotation(lead.id, id));
    onEdit();
  }

  Widget _sum(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            l,
            style: TextStyle(
              fontSize: bold ? 13.5 : 12.5,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: bold ? 15 : 12.5,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Repair progress + visit fee
// ═════════════════════════════════════════════════════════════════════════════

class _RepairAndFee extends StatelessWidget {
  const _RepairAndFee({
    required this.lead,
    required this.quote,
    required this.busy,
    required this.onAct,
    required this.onFee,
    required this.repo,
  });

  final VendorEstimation lead;
  final Map<String, dynamic>? quote;
  final bool busy;
  final Future<void> Function(Future<VendorEstimation> Function()) onAct;
  final VoidCallback onFee;
  final VendorEstimationRepository repo;

  @override
  Widget build(BuildContext context) {
    final st = lead.status.toUpperCase();
    final qs = '${quote?['status'] ?? ''}'.toUpperCase();
    final repairVisible =
        qs == 'APPROVED' ||
        const [
          'CUSTOMER_APPROVED',
          'CONVERTED_TO_JOB',
          'REPAIR_IN_PROGRESS',
          'REPAIR_COMPLETED',
          'TESTING_AC',
          'COMPLETED',
        ].contains(st);
    final fee = lead.raw['fee'] is Map
        ? Map<String, dynamic>.from(lead.raw['fee'] as Map)
        : const <String, dynamic>{};
    final feeStatus = '${fee['status'] ?? 'PENDING'}';
    final feeAmount = fee['amount'] == null ? 199 : _num(fee['amount']);

    // (label, stage, enabled-when, done-when)
    final stages = <(String, String, bool, bool)>[
      (
        'Start Repair',
        'START_REPAIR',
        st == 'CUSTOMER_APPROVED' || st == 'CONVERTED_TO_JOB',
        const [
          'REPAIR_IN_PROGRESS',
          'REPAIR_COMPLETED',
          'TESTING_AC',
          'COMPLETED',
        ].contains(st),
      ),
      (
        'Complete Repair',
        'COMPLETE_REPAIR',
        st == 'REPAIR_IN_PROGRESS',
        const ['REPAIR_COMPLETED', 'TESTING_AC', 'COMPLETED'].contains(st),
      ),
      (
        'Test AC & Cooling',
        'TEST_AC',
        st == 'REPAIR_COMPLETED',
        const ['TESTING_AC', 'COMPLETED'].contains(st),
      ),
      (
        'Customer Sign-Off',
        'CUSTOMER_CONFIRM',
        st == 'TESTING_AC',
        st == 'COMPLETED',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (repairVisible)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customer Accepted Quotation #${quote?['quote_ref'] ?? ''} — Approved for AC Repair',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    SellerPill(
                      label: st == 'COMPLETED'
                          ? 'JOB COMPLETED'
                          : 'REPAIR ACTIVE',
                      color: AppColors.emerald,
                    ),
                  ],
                ),
                if (quote != null)
                  Text(
                    'Authorized repair total: ${money(_num(quote!['total_amount']))}. The diagnostic fee is waived / credited.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 8),
                for (var i = 0; i < stages.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          stages[i].$4
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: stages[i].$4
                              ? AppColors.emerald
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Step ${i + 1} • ${stages[i].$1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (stages[i].$3)
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => onAct(
                                    () => repo.progressRepair(
                                      lead.id,
                                      stages[i].$2,
                                    ),
                                  ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(stages[i].$1),
                          )
                        else if (!stages[i].$4)
                          Text(
                            'Pending',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inspection Visit Fee: ₹${feeAmount == feeAmount.roundToDouble() ? feeAmount.toInt() : feeAmount}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SellerPill(
                      label: feeStatus,
                      color: estimationFeeColor(feeStatus),
                    ),
                  ],
                ),
              ),
              if (feeStatus == 'PENDING')
                FilledButton.tonal(
                  onPressed: busy ? null : onFee,
                  child: const Text('Collect / Waive Fee'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sheets / dialogs
// ═════════════════════════════════════════════════════════════════════════════

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.lead, required this.repo});

  final VendorEstimation lead;
  final VendorEstimationRepository repo;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  late final _name = TextEditingController(
    text: widget.lead.technicianName ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.lead.technicianPhone ?? '',
  );
  List<VendorTechnician> _techs = const [];
  String? _techId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repo
        .technicians()
        .then((t) {
          if (mounted) setState(() => _techs = t);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Technician name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.assignTechnician(
        widget.lead.id,
        technicianId: _techId,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Failed to assign technician.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign Technician',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Lead #${widget.lead.reference}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12.5,
                  ),
                ),
              ),
            if (_techs.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _techId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select from Available Team',
                ),
                items: [
                  for (final t in _techs)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        '${t.name} (${t.title ?? 'Technician'})${(t.phone ?? '').isEmpty ? '' : ' - ${t.phone}'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _techId = v);
                  final m = _techs.where((t) => t.id == v);
                  if (m.isNotEmpty) {
                    _name.text = m.first.name;
                    _phone.text = m.first.phone ?? '';
                  }
                },
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Technician Full Name *',
                hintText: 'e.g. Suresh Kumar',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Contact Number',
                hintText: 'e.g. +91 98765 43210',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(
                      _saving ? 'Assigning...' : 'Confirm Assignment',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpDialog extends StatefulWidget {
  const _OtpDialog({required this.lead, required this.repo});

  final VendorEstimation lead;
  final VendorEstimationRepository repo;

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _otp = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.verifyOtp(widget.lead.id, _otp.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Invalid OTP. Please verify with the customer.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Customer OTP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Please ask customer ${widget.lead.customerName ?? 'Customer'} for the 6-digit arrival start OTP shown on their app or SMS to commence inspection.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 12.5,
                ),
              ),
            ),
          TextField(
            controller: _otp,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 8,
              fontWeight: FontWeight.w800,
            ),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Enter 6-Digit Start OTP',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _otp.text.trim().length < 4 ? null : _verify,
          child: Text(_busy ? 'Verifying...' : 'Verify & Start Inspection'),
        ),
      ],
    );
  }
}

class _FeeSheet extends StatefulWidget {
  const _FeeSheet({required this.lead, required this.repo});

  final VendorEstimation lead;
  final VendorEstimationRepository repo;

  @override
  State<_FeeSheet> createState() => _FeeSheetState();
}

class _FeeSheetState extends State<_FeeSheet> {
  bool _collect = true;
  String _method = 'CASH';
  final _ref = TextEditingController();
  final _reason = TextEditingController(
    text: 'Customer approved major repair work quotation.',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_collect) {
        await widget.repo.collectFee(
          widget.lead.id,
          paymentMethod: _method,
          reference: _ref.text,
        );
      } else {
        await widget.repo.waiveFee(widget.lead.id, reason: _reason.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Failed to update fee record.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.lead.feeAmount ?? 199;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inspection Fee: ₹${fee == fee.roundToDouble() ? fee.toInt() : fee}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Job #${widget.lead.reference}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Collect Payment')),
                ButtonSegment(value: false, label: Text('Waive Fee')),
              ],
              selected: {_collect},
              onSelectionChanged: (s) => setState(() => _collect = s.first),
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12.5,
                  ),
                ),
              ),
            if (_collect) ...[
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('💵 Cash'),
                    selected: _method == 'CASH',
                    onSelected: (_) => setState(() => _method = 'CASH'),
                  ),
                  ChoiceChip(
                    label: const Text('📱 UPI / QR'),
                    selected: _method == 'UPI',
                    onSelected: (_) => setState(() => _method = 'UPI'),
                  ),
                ],
              ),
              if (_method == 'UPI') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _ref,
                  decoration: const InputDecoration(
                    labelText: 'UPI Transaction ID / Ref',
                  ),
                ),
              ],
            ] else
              TextField(
                controller: _reason,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for waiving',
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? 'Saving...'
                          : (_collect
                                ? 'Confirm Collection'
                                : 'Confirm Waiver'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
