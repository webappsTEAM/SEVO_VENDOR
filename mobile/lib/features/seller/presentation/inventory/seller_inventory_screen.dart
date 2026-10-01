import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';
import 'seller_inventory_sheets.dart';

/// Store Stock & Inventory — Live Stock Engine (Web parity:
/// `SellerInventoryPage.jsx`, route `/workforce/seller-hub/inventory`).
class SellerInventoryScreen extends ConsumerStatefulWidget {
  const SellerInventoryScreen({super.key});

  @override
  ConsumerState<SellerInventoryScreen> createState() =>
      _SellerInventoryScreenState();
}

class _SellerInventoryScreenState extends ConsumerState<SellerInventoryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _tab = 'ALL';
  String _search = '';
  int? _categoryId;

  List<SellerHubInventoryItem> _items = const [];
  List<SellerActiveCategory> _categories = const [];
  bool _loading = true;
  String? _error;
  int _requestSeq = 0;

  /// Approved products count, only checked when inventory is empty (Web).
  int? _approvedCount;

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _loadCategories();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  Future<void> _loadCategories() async {
    try {
      final cats = await _repo.getActiveCategories(leafOnly: true);
      if (mounted) setState(() => _categories = cats);
    } catch (_) {
      // Category filter is optional; the Web ignores this failure too.
    }
  }

  Future<void> _loadInventory() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.getInventory(
        status: _tab,
        search: _search,
        categoryId: _categoryId,
      );
      int? approved;
      if (items.isEmpty &&
          _search.isEmpty &&
          _categoryId == null &&
          _tab == 'ALL') {
        try {
          approved = (await _repo.getProducts(status: 'APPROVED')).length;
        } catch (_) {
          approved = 0;
        }
      }
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items = items;
        _approvedCount = approved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items = const [];
        _loading = false;
        _error = e is SellerHubException
            ? e.message
            : 'Error fetching store inventory.';
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value == _search) return;
      _search = value;
      _loadInventory();
    });
  }

  Future<void> _afterAction(bool? done) async {
    if (done == true) await _loadInventory();
  }

  Future<void> _openInitialize() async {
    final done = await SellerInitializeStockSheet.show(
      context,
      existingProductIds: {for (final i in _items) i.productId},
    );
    await _afterAction(done);
  }

  @override
  Widget build(BuildContext context) {
    final s = SellerInventorySummary.of(_items);
    final tabs = <(String, String)>[
      ('ALL', 'All Items (${s.total})'),
      ('IN_STOCK', 'In Stock (${s.inStock})'),
      ('LOW_STOCK', 'Low Stock Alert (${s.lowStock})'),
      ('OUT_OF_STOCK', 'Out of Stock (${s.outOfStock})'),
      ('EXPIRING_SOON', 'Expiring Soon (${s.expiring})'),
      ('EXPIRED', 'Expired'),
      ('PAUSED', 'Paused Products'),
    ];

    return SevoModuleFrame(
      module: SevoModule.sellerInventory,
      title: 'Store Stock & Inventory',
      subtitle:
          'Physical warehouse balance, grocery batch expiration tracking, stock adjustments, and '
          'ledger movements',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadInventory,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.inventory_2_rounded,
                title: 'Store Stock & Inventory',
                badge: 'Live Stock Engine',
                description:
                    'Physical warehouse balance, grocery batch expiration tracking, stock adjustments, and '
                    'ledger movements',
                actions: [
                  SellerHeaderAction(
                    label: 'Initialize Product Stock',
                    icon: Icons.add_rounded,
                    primary: true,
                    onPressed: _openInitialize,
                  ),
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _loadInventory,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerTileGrid(
                minTileWidth: 140,
                children: [
                  SellerMetricTile(
                    label: 'Tracked SKUs',
                    value: '${s.total}',
                    caption: 'Active catalog items',
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                  SellerMetricTile(
                    label: 'In Stock',
                    value: '${s.inStock}',
                    caption: 'Above reorder point',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.emerald,
                  ),
                  SellerMetricTile(
                    label: 'Low Stock',
                    value: '${s.lowStock}',
                    caption: 'Needs replenishment',
                    icon: Icons.warning_amber_rounded,
                    color: const Color(0xFFD97706),
                  ),
                  SellerMetricTile(
                    label: 'Out of Stock',
                    value: '${s.outOfStock}',
                    caption: 'Zero physical balance',
                    icon: Icons.highlight_off_rounded,
                    color: const Color(0xFFDC2626),
                  ),
                  SellerMetricTile(
                    label: 'Expiring Soon',
                    value: '${s.expiring}',
                    caption: 'Within 30 days',
                    icon: Icons.event_busy_outlined,
                    color: const Color(0xFFEA580C),
                  ),
                  SellerMetricTile(
                    label: 'Total Value',
                    value: formatRupeesCompact(s.totalValue),
                    caption: 'At selling price',
                    icon: Icons.currency_rupee_rounded,
                    color: const Color(0xFF4F46E5),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerSearchField(
                controller: _searchController,
                hint: 'Search by Product Title, SKU, Brand, Barcode...',
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerDropdownFilter(
                value: _categoryId?.toString() ?? '',
                options: [
                  ('', 'All Leaf Categories'),
                  for (final c in _categories) ('${c.id}', c.path),
                ],
                onChanged: (v) {
                  final id = int.tryParse(v);
                  if (id == _categoryId) return;
                  setState(() => _categoryId = id);
                  _loadInventory();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerFilterChips(
                options: tabs,
                selected: _tab,
                selectedColor: AppColors.emerald,
                onSelected: (v) {
                  if (v == _tab) return;
                  setState(() => _tab = v);
                  _loadInventory();
                },
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
      return const [SellerLoading(message: 'Loading store stock balances...')];
    if (_error != null) {
      return [
        SellerStateMessage(
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFDC2626),
          title: 'Error Loading Inventory',
          message: _error!,
          actionLabel: 'Retry',
          onAction: _loadInventory,
        ),
      ];
    }
    if (_items.isEmpty) {
      if (_search.isNotEmpty || _categoryId != null || _tab != 'ALL') {
        return const [
          SellerStateMessage(
            icon: Icons.search_off_rounded,
            title: 'No Matching Inventory Found',
            message: 'No inventory records match your current filter or search criteria.',
          ),
        ];
      }
      if ((_approvedCount ?? 0) == 0) {
        return [
          SellerStateMessage(
            icon: Icons.inventory_2_outlined,
            title: 'No Approved Products in Inventory',
            message:
                'Products appear here after admin approval. Upload your products and submit them for review '
                'in Catalog Uploads.',
            actionLabel: 'Go to Catalog Uploads',
            onAction: () => context.go(AppRoutes.sellerCatalogUploads),
          ),
        ];
      }
      return [
        SellerStateMessage(
          icon: Icons.playlist_add_rounded,
          title: 'No Stock Initialized Yet',
          message:
              'You have approved catalog products ready. Initialize opening stock to start managing and '
              'tracking inventory.',
          actionLabel: 'Initialize Stock',
          onAction: _openInitialize,
        ),
      ];
    }
    return [
      for (final item in _items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SellerInventoryCard(
            item: item,
            onStockIn: () async => _afterAction(
              await SellerStockMovementSheet.show(context, item, 'STOCK_IN'),
            ),
            onAdjust: () async => _afterAction(
              await SellerStockMovementSheet.show(
                context,
                item,
                'ADJUSTMENT_INCREASE',
              ),
            ),
            onDamage: () async => _afterAction(
              await SellerStockMovementSheet.show(context, item, 'DAMAGE'),
            ),
            onThreshold: () async =>
                _afterAction(await SellerThresholdSheet.show(context, item)),
            onLedger: () => SellerInventoryLedgerSheet.show(context, item),
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }
}

/// One inventory row from the Web table, as a mobile card.
class SellerInventoryCard extends StatelessWidget {
  const SellerInventoryCard({
    super.key,
    required this.item,
    required this.onStockIn,
    required this.onAdjust,
    required this.onDamage,
    required this.onThreshold,
    required this.onLedger,
  });

  final SellerHubInventoryItem item;
  final VoidCallback onStockIn;
  final VoidCallback onAdjust;
  final VoidCallback onDamage;
  final VoidCallback onThreshold;
  final VoidCallback onLedger;

  static (String, Color) statusStyle(String status) => switch (status) {
    'OUT_OF_STOCK' => ('Out of Stock', const Color(0xFFDC2626)),
    'LOW_STOCK' => ('Low Stock', const Color(0xFFD97706)),
    _ => ('In Stock', const Color(0xFF059669)),
  };

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = statusStyle(item.stockStatus);
    final image = AppConfig.resolveMediaUrl(item.productImage);
    final meta = [
      item.productSku,
      if (item.productBrand != null) item.productBrand!,
      [
        item.productPackSize,
        item.productUnit,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onLedger,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: AppColors.surfaceMuted,
                    child: image == null
                        ? Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.textMuted,
                          )
                        : Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.inventory_2_outlined,
                              color: AppColors.textMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (item.productBarcode != null)
                        Text(
                          item.productBarcode!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      if (item.productCategoryName != null)
                        Text(
                          item.productCategoryName!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                    ],
                  ),
                ),
                SellerPill(label: statusLabel, color: statusColor),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _QtyCell(
                label: 'On Hand',
                value:
                    '${item.onHandQty.toStringAsFixed(3)} ${item.productUnit}',
              ),
              _QtyCell(
                label: 'Reserved',
                value: item.reservedQty.toStringAsFixed(3),
              ),
              _QtyCell(
                label: 'Available',
                value: item.availableQty.toStringAsFixed(3),
                strong: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (item.hasExpiringBatches)
                const SellerPill(
                  label: 'Expiring Soon',
                  color: Color(0xFFEA580C),
                )
              else if (item.batchesCount > 0)
                SellerPill(
                  label:
                      '${item.batchesCount} ${item.batchesCount == 1 ? 'batch' : 'batches'}',
                  color: const Color(0xFF475569),
                )
              else
                Text(
                  'Batches: —',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: onThreshold,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.tune_rounded, size: 14),
                label: Text('≤ ${item.lowStockThreshold.toStringAsFixed(1)}'),
              ),
            ],
          ),
          Divider(height: 12, color: AppColors.border),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton(
                onPressed: onStockIn,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Stock In'),
              ),
              OutlinedButton(
                onPressed: onAdjust,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Adjust'),
              ),
              IconButton(
                tooltip: 'Record damaged / broken stock',
                onPressed: onDamage,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: Color(0xFFDC2626),
                ),
              ),
              IconButton(
                tooltip: 'View Movement Ledger',
                onPressed: onLedger,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyCell extends StatelessWidget {
  const _QtyCell({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              color: strong ? AppColors.emerald : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
