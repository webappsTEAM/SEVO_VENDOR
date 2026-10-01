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
import 'seller_order_actions.dart';
import 'seller_order_detail_sheet.dart';

/// Seller Hub Orders — Real Fulfilment Engine (Web parity:
/// `SellerOrdersPage.jsx`, route `/workforce/seller-hub/orders`).
class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  static const statusTabs = <(String, String)>[
    ('ALL', 'All Orders'),
    ('NEW', 'New / Action Required'),
    ('IN_PREPARATION', 'In Preparation'),
    ('READY_FOR_PICKUP', 'Ready for Pickup'),
    ('COMPLETED', 'Completed'),
    ('CANCELLED', 'Cancelled'),
  ];

  static const fulfillmentOptions = <(String, String)>[
    ('ALL', 'All Fulfilment Types'),
    ('DELIVERY', 'Delivery'),
    ('STORE_PICKUP', 'Store Pickup'),
  ];

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _status = 'ALL';
  String _fulfillment = 'ALL';
  String _search = '';

  final List<SellerHubOrder> _orders = [];
  int _totalCount = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestSeq = 0;
  final Set<int> _busyOrderIds = {};

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Loads page 1 (or appends the next page). A sequence number discards
  /// responses that arrive after the filters changed.
  Future<void> _loadOrders({bool append = false}) async {
    final seq = ++_requestSeq;
    final nextPage = append ? _page + 1 : 1;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await ref
          .read(sellerHubRepositoryProvider)
          .getOrders(
            page: nextPage,
            status: _status,
            fulfillmentType: _fulfillment,
            search: _search,
          );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        if (!append) _orders.clear();
        _orders.addAll(page.results);
        _totalCount = page.count;
        _page = nextPage;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) {
          _orders.clear();
          _error = e is SellerHubException
              ? e.message
              : 'Error loading orders.';
        }
      });
      if (append && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SellerHubException
                  ? e.message
                  : 'Error loading more orders.',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _refreshAll() async {
    ref.invalidate(sellerHubMetricsProvider);
    await _loadOrders();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value == _search) return;
      _search = value;
      _loadOrders();
    });
  }

  SellerOrderActions _actionsFor() => SellerOrderActions(
    context: context,
    ref: ref,
    onChanged: (_) => _refreshAll(),
  );

  Future<void> _runOnOrder(int orderId, Future<void> Function() action) async {
    if (_busyOrderIds.contains(orderId)) return;
    setState(() => _busyOrderIds.add(orderId));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(orderId));
    }
  }

  void _openDetail(SellerHubOrder order) {
    SellerOrderDetailSheet.show(
      context,
      orderId: order.id,
      onOrderChanged: _refreshAll,
    );
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(sellerHubMetricsProvider);
    final m = metricsAsync.valueOrNull;
    String metric(int Function(SellerHubMetrics) pick) =>
        m == null ? (metricsAsync.hasError ? '—' : '…') : '${pick(m)}';
    final hasMore = _orders.length < _totalCount;

    return SevoModuleFrame(
      module: SevoModule.sellerOrders,
      title: 'Seller Hub Orders',
      subtitle: 'Manage incoming orders, item picking, packing, delivery handoffs, and packing slips',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.shopping_bag_rounded,
                title: 'Seller Hub Orders',
                badge: 'Real Fulfilment Engine',
                iconColor: const Color(0xFF2563EB),
                description: 'Manage incoming orders, item picking, packing, delivery handoffs, and packing slips',
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
                  SellerHeaderAction(
                    label: 'Inventory Balance',
                    onPressed: () => context.go(AppRoutes.sellerInventory),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerTileGrid(
                children: [
                  SellerMetricTile(
                    label: "Today's Orders",
                    value: metric((m) => m.todayOrders),
                    caption: 'Incoming queue',
                    icon: Icons.schedule_rounded,
                    color: const Color(0xFF2563EB),
                  ),
                  SellerMetricTile(
                    label: 'Action Required (New)',
                    value: metric((m) => m.pendingOrders),
                    caption: 'Awaiting acceptance',
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFFD97706),
                  ),
                  SellerMetricTile(
                    label: 'In Preparation',
                    value: metric((m) => m.inPrepOrders),
                    caption: 'Picking / Packed / Ready',
                    icon: Icons.local_shipping_outlined,
                    color: const Color(0xFF7C3AED),
                  ),
                  SellerMetricTile(
                    label: 'Fulfilled & Completed',
                    value: metric((m) => m.completedOrders),
                    caption: 'Handed over or delivered',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.emerald,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerFilterChips(
                options: SellerOrdersScreen.statusTabs,
                selected: _status,
                selectedColor: const Color(0xFF2563EB),
                onSelected: (v) {
                  if (v == _status) return;
                  setState(() => _status = v);
                  _loadOrders();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerSearchField(
                controller: _searchController,
                hint: 'Search by Order #, Customer Name, SKU...',
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              _FulfillmentDropdown(
                value: _fulfillment,
                onChanged: (v) {
                  if (v == _fulfillment) return;
                  setState(() => _fulfillment = v);
                  _loadOrders();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              ..._buildList(hasMore),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildList(bool hasMore) {
    if (_loading)
      return const [SellerLoading(message: 'Loading orders from database...')];
    if (_error != null) {
      return [
        SellerStateMessage(
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFDC2626),
          title: 'Error Loading Orders',
          message: _error!,
          actionLabel: 'Retry',
          onAction: _loadOrders,
        ),
      ];
    }
    if (_orders.isEmpty) {
      return [
        const SellerStateMessage(
          icon: Icons.shopping_bag_outlined,
          title: 'No Orders in Queue',
          message:
              'Real marketplace customer bookings will arrive here automatically when customers check out '
              'from your approved product catalog.',
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            SellerHeaderAction(
              label: 'Check Inventory Stock',
              icon: Icons.inventory_2_outlined,
              onPressed: () => context.go(AppRoutes.sellerInventory),
            ),
            SellerHeaderAction(
              label: 'Manage Catalog',
              icon: Icons.layers_outlined,
              onPressed: () => context.go(AppRoutes.sellerCatalogUploads),
            ),
          ],
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          'Showing ${_orders.length} of $_totalCount orders',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ),
      for (final order in _orders)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SellerOrderCard(
            order: order,
            busy: _busyOrderIds.contains(order.id),
            onOpen: () => _openDetail(order),
            onAction: (action) => _runOnOrder(order.id, () async {
              final actions = _actionsFor();
              switch (action) {
                case 'cancel':
                  await actions.cancel(order);
                case 'retry':
                  await actions.retryDispatch(order);
                case 'riders':
                  await actions.showRiders(order);
                case 'track':
                  await actions.trackRider(order);
                case 'slip':
                  await actions.previewPackingSlip(order);
                case 'label':
                  await actions.downloadShippingLabel(order);
                default:
                  await actions.transition(order, action);
              }
            }),
          ),
        ),
      if (hasMore)
        Center(
          child: _loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              : OutlinedButton(
                  onPressed: () => _loadOrders(append: true),
                  child: const Text('Load more orders'),
                ),
        ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }
}

class _FulfillmentDropdown extends StatelessWidget {
  const _FulfillmentDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.filter_list_rounded, size: 18),
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (final (v, label) in SellerOrdersScreen.fulfillmentOptions)
              DropdownMenuItem(value: v, child: Text(label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// One order row from the Web table, as a mobile card.
class SellerOrderCard extends StatelessWidget {
  const SellerOrderCard({
    super.key,
    required this.order,
    required this.busy,
    required this.onOpen,
    required this.onAction,
  });

  final SellerHubOrder order;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final primary = primaryOrderAction(order.status);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onOpen,
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
                          order.orderNumber,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (order.sourceOrderId != null)
                          Text(
                            'Src: ${order.sourceOrderId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        Text(
                          formatSellerDateTime(order.createdAt),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SellerOrderStatusBadge(order.status),
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
                          order.customerName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (order.customerPhone != null)
                          Text(
                            order.customerPhone!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (order.deliverySlot != null)
                          Text(
                            'Slot: ${order.deliverySlot}',
                            style: TextStyle(
                              fontSize: 11,
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
                        formatRupees(order.totalAmount),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${order.paymentMethod} (${order.paymentStatus})',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${order.itemsCount} item(s)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (order.itemsSummary.isNotEmpty)
                Text(
                  order.itemsSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Type: ${order.fulfillmentLabel}',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (primary != null)
                    FilledButton(
                      onPressed: busy ? null : () => onAction(primary.$1),
                      style: FilledButton.styleFrom(
                        backgroundColor: order.status == 'NEW'
                            ? AppColors.emerald
                            : const Color(0xFF2563EB),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(primary.$2),
                    ),
                  if (order.status == 'NEW')
                    OutlinedButton(
                      onPressed: busy ? null : () => onAction('cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Cancel'),
                    ),
                  if (order.awaitingRider)
                    if (order.handlingTechnicianName != null)
                      SellerPill(
                        label: order.handlingTechnicianName!,
                        color: const Color(0xFF0D9488),
                        icon: Icons.local_shipping_rounded,
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: () => onAction('riders'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.hourglass_top_rounded, size: 14),
                        label: const Text('Assigning Rider...'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => onAction('retry'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Retry'),
                      ),
                    ],
                  if (order.inRiderPhase && order.dispatchJobId != null)
                    OutlinedButton.icon(
                      onPressed: () => onAction('track'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.navigation_rounded, size: 14),
                      label: const Text('Track Rider'),
                    ),
                  _IconAction(
                    icon: Icons.visibility_outlined,
                    tooltip: 'Order Details & Picking List',
                    onTap: onOpen,
                  ),
                  _IconAction(
                    icon: Icons.print_outlined,
                    tooltip: 'Preview Packing Slip',
                    onTap: () => onAction('slip'),
                  ),
                  _IconAction(
                    icon: Icons.qr_code_2_rounded,
                    tooltip: 'Download Shipping Label (PDF, scannable barcode)',
                    onTap: busy ? null : () => onAction('label'),
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

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(backgroundColor: AppColors.surfaceMuted),
      icon: Icon(icon, size: 18, color: AppColors.textSecondary),
    );
  }
}
