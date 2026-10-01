import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../seller_hub_providers.dart';
import '../widgets/seller_hub_widgets.dart';
import 'seller_return_detail_sheet.dart';

/// Returns & Reverse Logistics (Web parity: `SellerReturnsPage.jsx`, route
/// `/workforce/seller-hub/returns`).
class SellerReturnsScreen extends ConsumerStatefulWidget {
  const SellerReturnsScreen({super.key});

  static const statusTabs = <(String, String)>[
    ('ALL', 'All Returns'),
    ('PENDING', 'Pending Review'),
    ('APPROVED', 'Approved'),
    ('PICKUP_SCHEDULED', 'Pickup Scheduled'),
    ('RECEIVED', 'Received'),
    ('QUALITY_CHECK', 'Quality Check'),
    ('RESTOCKED', 'Restocked'),
    ('CLOSED', 'Closed'),
    ('REJECTED', 'Rejected'),
  ];

  @override
  ConsumerState<SellerReturnsScreen> createState() =>
      _SellerReturnsScreenState();
}

class _SellerReturnsScreenState extends ConsumerState<SellerReturnsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _status = 'ALL';
  String _search = '';

  List<SellerHubReturn> _returns = const [];
  bool _loading = true;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadReturns();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReturns() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(sellerHubRepositoryProvider)
          .getReturns(status: _status, search: _search);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _returns = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _returns = const [];
        _loading = false;
        _error = e is SellerHubException ? e.message : 'Error loading returns';
      });
    }
  }

  Future<void> _refreshAll() async {
    ref.invalidate(sellerHubMetricsProvider);
    await _loadReturns();
  }

  void _setStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _loadReturns();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value == _search) return;
      _search = value;
      _loadReturns();
    });
  }

  void _openDetail(SellerHubReturn ret) {
    SellerReturnDetailSheet.show(
      context,
      returnId: ret.id,
      onChanged: _refreshAll,
    );
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(sellerHubMetricsProvider);
    final m = metricsAsync.valueOrNull;
    String metric(int Function(SellerHubMetrics) pick) =>
        m == null ? (metricsAsync.hasError ? '—' : '…') : '${pick(m)}';

    return SevoModuleFrame(
      module: SevoModule.sellerReturns,
      title: 'Returns & Reverse Logistics',
      subtitle: 'Process customer returns, parcel receipts, physical quality inspections, and stock-in adjustments',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.replay_rounded,
                title: 'Returns & Reverse Logistics',
                badge: 'Seller Hub',
                iconColor: const Color(0xFFEA580C),
                description: 'Process customer returns, parcel receipts, physical quality inspections, and stock-in adjustments',
                actions: [
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _refreshAll,
                  ),
                  SellerHeaderAction(
                    label: 'Seller Home',
                    onPressed: () => context.go(AppRoutes.sellerHome),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerTileGrid(
                children: [
                  SellerMetricTile(
                    label: 'Pending Review',
                    value: metric((m) => m.pendingReturns),
                    caption: 'Action required',
                    icon: Icons.pending_actions_rounded,
                    color: const Color(0xFFD97706),
                    selected: _status == 'PENDING',
                    onTap: () => _setStatus('PENDING'),
                  ),
                  SellerMetricTile(
                    label: 'Under Inspection',
                    value: metric((m) => m.underInspectionReturns),
                    caption: 'Pickup / Store QC',
                    icon: Icons.fact_check_outlined,
                    color: const Color(0xFF7C3AED),
                    selected: _status == 'IN_INSPECTION',
                    onTap: () => _setStatus('IN_INSPECTION'),
                  ),
                  SellerMetricTile(
                    label: 'Resolved / Restocked',
                    value: metric((m) => m.resolvedReturns),
                    caption: 'Closed & restocked',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.emerald,
                    selected: _status == 'RESOLVED',
                    onTap: () => _setStatus('RESOLVED'),
                  ),
                  SellerMetricTile(
                    label: 'Total Returns',
                    value: metric((m) => m.totalReturns),
                    caption: 'All time cases',
                    icon: Icons.all_inbox_rounded,
                    color: const Color(0xFF2563EB),
                    selected: _status == 'ALL',
                    onTap: () => _setStatus('ALL'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerFilterChips(
                options: SellerReturnsScreen.statusTabs,
                selected: _status,
                selectedColor: const Color(0xFF0F172A),
                onSelected: _setStatus,
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerSearchField(
                controller: _searchController,
                hint: 'Search Return #, Order #, customer...',
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.md),
              ..._buildList(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildList() {
    if (_loading)
      return const [SellerLoading(message: 'Loading return cases...')];
    if (_error != null) {
      return [
        SellerStateMessage(
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFDC2626),
          title: 'Error Loading Returns',
          message: _error!,
          actionLabel: 'Retry',
          onAction: _loadReturns,
        ),
      ];
    }
    if (_returns.isEmpty) {
      return [
        SellerStateMessage(
          icon: Icons.assignment_return_outlined,
          title: 'No Return Cases Found',
          message: _search.isNotEmpty || _status != 'ALL'
              ? 'No returns matching your search criteria. Try adjusting your filter parameters.'
              : 'There are currently no active customer return requests for your store. When customers initiate '
                    'return requests, they will appear here.',
        ),
      ];
    }
    return [
      for (final ret in _returns)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SellerReturnCard(ret: ret, onManage: () => _openDetail(ret)),
        ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }
}

/// One return row from the Web table, as a mobile card.
class SellerReturnCard extends StatelessWidget {
  const SellerReturnCard({
    super.key,
    required this.ret,
    required this.onManage,
  });

  final SellerHubReturn ret;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final qc = ret.qualityCheckStatus;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onManage,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ret.returnNumber,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (ret.sourceReturnId != null)
                          Text(
                            'Src: ${ret.sourceReturnId}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        Text(
                          '#${ret.orderNumber ?? 'N/A'}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SellerReturnStatusBadge(ret.status),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ret.customerName ?? 'Customer',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          ret.customerPhone ?? 'No phone',
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
                        'QC Result',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        qc ?? 'Pending QC',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: qc == null
                              ? AppColors.textMuted
                              : (qc == 'PASSED'
                                    ? AppColors.emerald
                                    : const Color(0xFFD97706)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ret.itemsSummary ?? '${ret.itemsCount} items',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Reason: ',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    TextSpan(
                      text: ret.reason,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatSellerDate(ret.createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onManage,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 15),
                    label: const Text('Manage'),
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
