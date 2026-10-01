import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../seller/presentation/widgets/seller_hub_widgets.dart';
import '../../data/vendor_estimation_repository.dart';
import '../../domain/vendor_estimation.dart';

/// Status pill colours of the Web `STATUS_BADGES` map.
Color estimationStatusColor(String status) => switch (status) {
  'REQUESTED' => const Color(0xFF2563EB),
  'VENDOR_CONFIRMED' => const Color(0xFF4F46E5),
  'TECHNICIAN_ASSIGNED' => const Color(0xFF7C3AED),
  'TECHNICIAN_ON_THE_WAY' => const Color(0xFFD97706),
  'TECHNICIAN_ARRIVED' => const Color(0xFFEA580C),
  'INSPECTION_IN_PROGRESS' => const Color(0xFF0D9488),
  'INSPECTION_COMPLETED' => const Color(0xFF0891B2),
  'QUOTATION_SENT' => const Color(0xFF0284C7),
  'CUSTOMER_APPROVED' || 'COMPLETED' => AppColors.emerald,
  'CUSTOMER_REJECTED' => const Color(0xFFE11D48),
  'CANCELLED' => const Color(0xFF71717A),
  _ => const Color(0xFF2563EB),
};

Color estimationFeeColor(String feeStatus) => switch (feeStatus) {
  'COLLECTED' => AppColors.emerald,
  'WAIVED' => const Color(0xFF7C3AED),
  _ => const Color(0xFFD97706),
};

/// Web `VendorEstimationsPage` (`/workforce/admin/estimations`) — AC Inspection
/// & Quotation Manager: lead metrics, status tabs, search, date filter, leads.
class AdminEstimationsScreen extends ConsumerStatefulWidget {
  const AdminEstimationsScreen({super.key});

  @override
  ConsumerState<AdminEstimationsScreen> createState() =>
      _AdminEstimationsScreenState();
}

class _AdminEstimationsScreenState
    extends ConsumerState<AdminEstimationsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _tab = 'all';
  DateTime? _date;
  VendorEstimationList? _data;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(vendorEstimationRepositoryProvider)
          .list(
            status: _tab,
            date: _date == null ? null : _iso(_date!),
            search: _search.text.trim(),
          );
      if (mounted && seq == _seq) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Failed to load estimation leads.';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  Future<void> _open(VendorEstimation lead) async {
    await context.push('${AppRoutes.adminEstimations}/${lead.id}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final leads = _data?.leads ?? const <VendorEstimation>[];
    final metrics = _data?.metrics;
    return SevoModuleFrame(
      module: SevoModule.estimations,
      title: 'AC Inspection & Quotation Manager',
      subtitle: 'Manage AC diagnostic leads, on-site technician inspections, and formal versioned quotations.',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.air_rounded,
                iconColor: const Color(0xFF0284C7),
                title: 'AC Inspection & Quotation Manager',
                badge: 'Vendor Portal',
                description: 'Manage AC diagnostic leads, on-site technician inspections, and formal versioned quotations.',
                actions: [
                  SellerHeaderAction(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
              if (metrics != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _MetricsRow(metrics: metrics),
              ],
              const SizedBox(height: AppSpacing.md),
              SellerFilterChips(
                options: estimationFilterTabs,
                selected: _tab,
                onSelected: (v) {
                  if (v == _tab) return;
                  setState(() => _tab = v);
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerSearchField(
                controller: _search,
                hint: 'Search customer, ID, brand...',
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _load);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(
                      _date == null
                          ? 'dd/mm/yyyy'
                          : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}',
                    ),
                  ),
                  if (_date != null)
                    IconButton(
                      tooltip: 'Clear date',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        setState(() => _date = null);
                        _load();
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Request failed',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (_loading && _data == null)
                const SellerLoading(message: 'Loading estimation leads...')
              else if (leads.isEmpty)
                const SellerStateMessage(
                  icon: Icons.air_rounded,
                  title: 'No Estimation Leads Found',
                  message: 'No matching AC inspection requests found for current filter criteria.',
                )
              else ...[
                for (final lead in leads) ...[
                  _LeadCard(lead: lead, onTap: () => _open(lead)),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics});

  final Map<String, int> metrics;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, Color)>[
      ('Total Leads', 'all', AppColors.textPrimary),
      ('New Requests', 'requested', const Color(0xFF2563EB)),
      ('Assigned', 'assigned', const Color(0xFF7C3AED)),
      ('In Progress', 'in_progress', const Color(0xFFD97706)),
      ('Quotes Sent', 'quotation_sent', const Color(0xFF0284C7)),
      ('Completed', 'completed', AppColors.emerald),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 6 : 3;
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, key, color) in items)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${metrics[key] ?? 0}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
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

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, required this.onTap});

  final VendorEstimation lead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = estimationStatusColor(lead.status);
    final feeStatus = lead.feeStatusOrPending;
    final fee = lead.feeAmount ?? 199;
    final feeText = fee == fee.roundToDouble()
        ? fee.toInt().toString()
        : fee.toStringAsFixed(2);
    final brandType = '${lead.acBrand ?? ''} ${lead.acType ?? ''}'.trim();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          lead.reference,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SellerPill(
                          label: lead.acType ?? 'AC',
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  SellerPill(
                    label: estimationStatusLabel(lead.status),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brandType.isEmpty ? 'AC' : brandType,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Capacity: ${lead.capacityLabel} • Qty: ${lead.acQuantity ?? 1}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Visit Fee',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      SellerPill(
                        label: '₹$feeText $feeStatus',
                        color: estimationFeeColor(feeStatus),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '"${lead.symptom ?? 'General cooling inspection and checkup'}"',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _line(
                Icons.location_on_outlined,
                lead.address ?? 'Address on file',
              ),
              _line(
                Icons.calendar_today_outlined,
                '${_dateLabel(lead.preferredDate)} • ${lead.preferredTime ?? 'Morning'}',
              ),
              if ((lead.technicianName ?? '').isNotEmpty)
                _line(
                  Icons.how_to_reg_outlined,
                  'Tech: ${lead.technicianName}',
                ),
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Customer: ',
                        children: [
                          TextSpan(
                            text: lead.customerName ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Text(
                    'Manage Job',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateLabel(String? raw) {
    final d = raw == null ? null : DateTime.tryParse(raw);
    if (d == null) return 'Today';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}
