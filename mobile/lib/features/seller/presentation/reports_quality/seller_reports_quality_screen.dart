import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Seller Reports & Quality Controls (Web parity: `SellerReportsPage.jsx`,
/// route `/workforce/seller-hub/reports`).
class SellerReportsQualityScreen extends ConsumerStatefulWidget {
  const SellerReportsQualityScreen({super.key});

  static const periods = <(String, String)>[
    ('7', '7 Days'),
    ('30', '30 Days'),
    ('90', '90 Days'),
    ('all', 'All Time'),
  ];

  @override
  ConsumerState<SellerReportsQualityScreen> createState() =>
      _SellerReportsQualityScreenState();
}

class _SellerReportsQualityScreenState
    extends ConsumerState<SellerReportsQualityScreen> {
  String _days = '30';
  String _tab = 'overview';
  SellerReportsSummary? _summary;
  SellerReportsPerformance? _performance;
  SellerQualityAudit? _audit;
  bool _loading = true;
  String? _error;
  String? _exporting;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  /// Summary, performance and audit in parallel; like the Web, only the
  /// summary failing is an error for the page.
  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait<Object?>([
      _repo
          .getReportsSummary(_days)
          .then<Object?>((v) => v, onError: (Object e) => e),
      _repo
          .getReportsPerformance(_days)
          .then<Object?>((v) => v, onError: (Object _) => null),
      _repo.getQualityAudit().then<Object?>(
        (v) => v,
        onError: (Object _) => null,
      ),
    ]);
    if (!mounted || seq != _seq) return;
    setState(() {
      final summary = results[0];
      if (summary is SellerReportsSummary) {
        _summary = summary;
      } else {
        _error = summary is SellerHubException
            ? summary.message
            : 'Error loading summary KPIs';
      }
      _performance = results[1] as SellerReportsPerformance?;
      _audit = results[2] as SellerQualityAudit?;
      _loading = false;
    });
  }

  Future<void> _export(String type) async {
    setState(() => _exporting = type);
    try {
      final bytes = await _repo.exportReportCsv(type, _days);
      final dir = await getTemporaryDirectory();
      final date = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/sevo_seller_${type}_report_$date.csv');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'SEVO Seller ${type.toUpperCase()} Report',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              'Export error: ${e is SellerHubException ? e.message : 'Failed to export $type report'}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  static String _pct(double v) => '${v.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return SevoModuleFrame(
      module: SevoModule.reportsQuality,
      title: 'Seller Reports & Quality Controls',
      subtitle:
          'Authoritative scorecard, inventory health, order fulfillment rates, returns diagnostics, '
          'and data exports.',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.bar_chart_rounded,
                title: 'Seller Reports & Quality Controls',
                badge: 'Real DB Feed',
                iconColor: const Color(0xFF2563EB),
                description:
                    'Authoritative scorecard, inventory health, order fulfillment rates, returns diagnostics, '
                    'and data exports.',
                actions: [
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _reload,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Period:',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              SellerFilterChips(
                options: SellerReportsQualityScreen.periods,
                selected: _days,
                onSelected: (v) {
                  if (v == _days) return;
                  setState(() => _days = v);
                  _reload();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading && s == null)
                const SellerLoading(message: 'Loading seller reports...')
              else if (_error != null && s == null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Unable to load reports',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _reload,
                )
              else if (s != null) ...[
                _kpis(s),
                const SizedBox(height: AppSpacing.md),
                SellerFilterChips(
                  options: [
                    ('overview', 'Executive Scorecard'),
                    (
                      'audit',
                      'Quality Audit Checklist${_audit == null ? '' : ' (${_audit!.totalIssues})'}',
                    ),
                    ('fulfilment', 'Fulfilment & Revenue'),
                    ('inventory', 'Inventory Health'),
                    ('returns_claims', 'Returns & Claims'),
                    ('exports', 'Export Center (CSV)'),
                  ],
                  selected: _tab,
                  onSelected: (v) => setState(() => _tab = v),
                ),
                const SizedBox(height: AppSpacing.md),
                ...switch (_tab) {
                  'audit' => _auditTab(),
                  'fulfilment' => _fulfilmentTab(),
                  'inventory' => _inventoryTab(),
                  'returns_claims' => _returnsClaimsTab(),
                  'exports' => _exportsTab(),
                  _ => _overviewTab(s),
                },
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpis(SellerReportsSummary s) {
    return SellerTileGrid(
      minTileWidth: 150,
      children: [
        SellerMetricTile(
          label: 'Catalog Quality · ${s.catalogQualityBand}',
          value: _pct(s.catalogQualityScore),
          caption:
              '${s.approvedProducts} approved • ${s.pendingProducts} in review • Missing Images: ${s.missingImages}',
          icon: Icons.verified_outlined,
          color: s.catalogQualityScore >= 80
              ? AppColors.emerald
              : (s.catalogQualityScore >= 50
                    ? const Color(0xFFD97706)
                    : const Color(0xFFDC2626)),
          onTap: () => setState(() => _tab = 'audit'),
        ),
        SellerMetricTile(
          label: 'Fulfilled Order Value · Gross',
          value: formatRupeesCompact(s.fulfilledGrossValue),
          caption:
              '${s.deliveredOrders} delivered • ${s.totalOrders} total • Success Rate: ${_pct(s.fulfilmentSuccessRate)}',
          icon: Icons.shopping_bag_outlined,
          color: const Color(0xFF2563EB),
          onTap: () => context.go(AppRoutes.sellerOrders),
        ),
        SellerMetricTile(
          label:
              'Inventory Health · ${s.outOfStock == 0 ? 'Fully Stocked' : '${s.outOfStock} Out of Stock'}',
          value: _pct(s.inventoryHealthIndex),
          caption:
              '${s.totalInventoryItems} SKUs tracked • ${s.lowStock} low stock • Expiring <30d: ${s.expiringBatches}',
          icon: Icons.inventory_2_outlined,
          color: AppColors.emerald,
          onTap: () => context.go(AppRoutes.sellerInventory),
        ),
        SellerMetricTile(
          label: 'Return & Claim Rates · Disputes',
          value: _pct(s.returnRate),
          caption:
              '${s.totalReturns} returns • ${s.totalClaims} claims • Action Needed: ${s.claimsRequiringResponse} claims',
          icon: Icons.replay_rounded,
          color: const Color(0xFFEA580C),
          onTap: () => context.go(AppRoutes.sellerClaims),
        ),
      ],
    );
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _overviewTab(SellerReportsSummary s) {
    return [
      SellerPanel(
        title: 'Catalog Quality Breakdown',
        subtitle: 'Listing completeness and admin review status',
        child: Column(
          children: [
            _statRow('Total Products', '${s.totalProducts}'),
            _statRow(
              'Approved & Active',
              '${s.approvedProducts}',
              color: AppColors.emerald,
            ),
            _statRow(
              'Pending Review',
              '${s.pendingProducts}',
              color: const Color(0xFF2563EB),
            ),
            _statRow(
              'Rejected / Action Needed',
              '${s.rejectedProducts}',
              color: const Color(0xFFE11D48),
            ),
            _statRow('Missing Primary Image', '${s.missingImages}'),
            _statRow(
              'Missing Detailed Description',
              '${s.missingDescriptions}',
            ),
            _link('Manage Catalog Listings', AppRoutes.sellerCatalogUploads),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Inventory Health & Valuation',
        subtitle: 'Warehouse stock valuation and shelf life',
        child: Column(
          children: [
            _statRow(
              'Total On-Hand Quantity',
              '${s.totalOnHandQuantity.toStringAsFixed(3)} units',
            ),
            _statRow(
              'Estimated Inventory Value',
              formatRupeesCompact(s.inventoryValuation),
            ),
            _statRow(
              'Low Stock Threshold Alert',
              '${s.lowStock} SKUs',
              color: const Color(0xFFD97706),
            ),
            _statRow(
              'Out-of-Stock SKUs',
              '${s.outOfStock} SKUs',
              color: const Color(0xFFDC2626),
            ),
            _statRow(
              'Expiring Batches (< 30 Days)',
              '${s.expiringBatches} batches',
            ),
            _link('Adjust & Restock Inventory', AppRoutes.sellerInventory),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Order & Reverse Operations',
        subtitle: 'Pick-pack velocity and reverse dispute pipeline',
        child: Column(
          children: [
            _statRow('Pending Orders', '${s.pendingOrders}'),
            _statRow('In Preparation / Picking', '${s.inPrepOrders}'),
            _statRow(
              'Delivered / Completed',
              '${s.deliveredOrders}',
              color: AppColors.emerald,
            ),
            _statRow('Returns Pending Review', '${s.pendingReturns}'),
            _statRow(
              'Claims Requiring Response',
              '${s.claimsRequiringResponse}',
              color: const Color(0xFFE11D48),
            ),
            Row(
              children: [
                Expanded(child: _link('Orders', AppRoutes.sellerOrders)),
                Expanded(child: _link('Claims', AppRoutes.sellerClaims)),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _link(String label, String route) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.go(route),
        icon: const Icon(Icons.arrow_forward_rounded, size: 15),
        label: Text(label),
      ),
    );
  }

  List<Widget> _auditTab() {
    final a = _audit;
    if (a == null) {
      return const [
        SellerStateMessage(
          icon: Icons.fact_check_outlined,
          title: 'Quality audit unavailable',
          message: 'The quality audit checklist could not be loaded. Pull to refresh.',
        ),
      ];
    }
    Widget item(
      String title,
      int count,
      String body,
      String action,
      String route,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SellerPanel(
        tint: count > 0 ? const Color(0xFFD97706) : AppColors.emerald,
        title: '$title ($count)',
        subtitle: body,
        child: _link(action, route),
      ),
    );
    return [
      Text(
        'Automated audit findings derived directly from live database tables requiring merchant attention.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 6),
      Text(
        '${a.totalIssues} Action Items',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      item(
        'Approved Products with Zero Stock',
        a.outOfStockApproved,
        'Approved products with zero inventory on hand will not appear in customer storefront search.',
        'Restock Now',
        AppRoutes.sellerInventory,
      ),
      item(
        'Expiring Batches within 30 Days',
        a.expiringBatches,
        'Perishable or dated stock approaching expiry must be prioritized or marked down to prevent loss.',
        'View Batches',
        AppRoutes.sellerInventory,
      ),
      item(
        'Products Missing Primary Images',
        a.missingImages,
        'Upload high-resolution image assets to pass platform quality compliance checks.',
        'Upload Media',
        AppRoutes.sellerCatalogUploads,
      ),
      item(
        'Open Claims Awaiting Merchant Response',
        a.claimsRequiringResponse,
        'Provide dispute comments or supporting proof of dispatch before claims are auto-escalated.',
        'Respond to Claims',
        AppRoutes.sellerClaims,
      ),
      item(
        'Returns Pending Intake / Quality Inspection',
        a.returnsPendingQc,
        'Items received at warehouse must be inspected for restock or scrap classification.',
        'Perform QC',
        AppRoutes.sellerReturns,
      ),
    ];
  }

  List<Widget> _fulfilmentTab() {
    final trends = _performance?.dailyTrends ?? const [];
    return [
      SellerPanel(
        title: 'Daily Fulfilment Trends',
        subtitle: 'Real-time daily order volume and fulfilled gross value',
        child: trends.isEmpty
            ? Text(
                'No order activity recorded in selected date range.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            : Column(
                children: [
                  for (final t in trends)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.date,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Placed ${t.orders} · Delivered ${t.delivered} · Cancelled ${t.cancelled}',
                      ),
                      trailing: Text(
                        formatRupeesCompact(t.value),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
      ),
    ];
  }

  List<Widget> _inventoryTab() {
    final rows = _performance?.movementBreakdown ?? const [];
    return [
      SellerPanel(
        title: 'Inventory Movement Ledger by Type',
        subtitle: 'Breakdown of warehouse receipts, dispatches, restocks, and adjustments',
        child: Column(
          children: [
            if (rows.isEmpty)
              Text(
                'No inventory movements recorded in selected period.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              for (final r in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    r.type,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${r.events} events'),
                  trailing: Text(
                    r.quantity.toStringAsFixed(3),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            _link('Full Ledger', AppRoutes.sellerInventory),
          ],
        ),
      ),
    ];
  }

  List<Widget> _returnsClaimsTab() {
    final p = _performance;
    Widget list(List<({String label, int count})> rows, String empty) =>
        rows.isEmpty
        ? Text(empty, style: TextStyle(color: AppColors.textSecondary))
        : Column(
            children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.label),
                  trailing: Text(
                    '${r.count}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          );
    return [
      SellerPanel(
        title: 'Returns by Customer Reason',
        subtitle: 'Root-cause classification of reverse logistics',
        child: list(
          p?.returnReasons ?? const [],
          'No returns recorded in selected period.',
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Claims by Dispute Type',
        subtitle: 'Damage, transit loss, and merchant disputes',
        child: list(
          p?.claimTypes ?? const [],
          'No claims or disputes recorded in selected period.',
        ),
      ),
    ];
  }

  List<Widget> _exportsTab() {
    const exports = [
      ('orders', 'Order Fulfilment Ledger', Icons.shopping_bag_outlined),
      ('inventory', 'Inventory Stock & Batches', Icons.inventory_2_outlined),
      ('returns', 'Returns & QC Log', Icons.replay_rounded),
      ('claims', 'Claims & Operational Disputes', Icons.shield_outlined),
      ('quality', 'Catalog Quality Audit', Icons.verified_outlined),
    ];
    return [
      for (final (type, label, icon) in exports)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(icon, color: AppColors.primary),
            title: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'CSV · period: ${SellerReportsQualityScreen.periods.firstWhere((p) => p.$1 == _days).$2}',
            ),
            trailing: _exporting == type
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            onTap: _exporting == null ? () => _export(type) : null,
          ),
        ),
    ];
  }
}
