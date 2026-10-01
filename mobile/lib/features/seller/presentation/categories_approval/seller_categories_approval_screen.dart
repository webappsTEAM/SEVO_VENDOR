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

void _toast(BuildContext context, String? message, {bool error = false}) {
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
    ),
  );
}

Widget _pager({
  required int page,
  required int totalPages,
  required ValueChanged<int> onPage,
}) {
  if (totalPages <= 1) return const SizedBox.shrink();
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      OutlinedButton(
        onPressed: page > 1 ? () => onPage(page - 1) : null,
        child: const Text('Previous'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'Page $page of $totalPages',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      OutlinedButton(
        onPressed: page < totalPages ? () => onPage(page + 1) : null,
        child: const Text('Next'),
      ),
    ],
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Screen 1 — merchant stores (Web `/workforce/admin/seller-hub/categories-approval`)
// ═════════════════════════════════════════════════════════════════════════════

class SellerCategoriesApprovalScreen extends ConsumerStatefulWidget {
  const SellerCategoriesApprovalScreen({super.key});

  @override
  ConsumerState<SellerCategoriesApprovalScreen> createState() =>
      _SellerCategoriesApprovalScreenState();
}

class _SellerCategoriesApprovalScreenState
    extends ConsumerState<SellerCategoriesApprovalScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _hasPending = false;
  int _page = 1;
  SellerPage<SellerApprovalStore>? _data;
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

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(sellerHubRepositoryProvider)
          .getApprovalSellers(
            search: _search.text,
            hasPending: _hasPending,
            page: _page,
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
          _error = e is SellerHubException
              ? e.message
              : 'Failed to fetch sellers list.';
        });
      }
    }
  }

  Future<void> _assignWarehouse(SellerApprovalStore store) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => _AssignWarehouseSheet(store: store),
    );
    if (saved == true) {
      if (mounted) _toast(context, 'Warehouse assigned to ${store.name}.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return SevoModuleFrame(
      module: SevoModule.categoriesApproval,
      title: 'Categories Approval',
      subtitle: 'Manage and verify merchant catalog category submissions across registered stores',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SellerHubHeader(
                icon: Icons.fact_check_rounded,
                title: 'Categories Approval',
                description: 'Manage and verify merchant catalog category submissions across registered stores',
              ),
              const SizedBox(height: AppSpacing.md),
              SellerSearchField(
                controller: _search,
                hint: 'Search store name, merchant slug...',
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    _page = 1;
                    _load();
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Has Pending Submissions',
                  style: TextStyle(fontSize: 13),
                ),
                value: _hasPending,
                onChanged: (v) {
                  setState(() {
                    _hasPending = v;
                    _page = 1;
                  });
                  _load();
                },
              ),
              if (_loading)
                const SellerLoading(message: 'Loading merchant stores...')
              else if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Unable to load stores',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (data == null || data.results.isEmpty)
                const SellerStateMessage(
                  icon: Icons.storefront_outlined,
                  title: 'No stores found',
                  message: 'No merchant stores match the current filters.',
                )
              else ...[
                for (final s in data.results) _storeCard(s),
                Text(
                  'Showing ${data.results.length} of ${data.count} merchants',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                _pager(
                  page: _page,
                  totalPages: data.totalPages,
                  onPage: (p) {
                    setState(() => _page = p);
                    _load();
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storeCard(SellerApprovalStore s) {
    Widget count(String label, int value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          if (s.slug != null)
            Text(
              s.slug!,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.warehouse_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.warehouseName ?? 'No fulfillment warehouse',
                  style: TextStyle(
                    fontSize: 12,
                    color: s.warehouseName == null ? AppColors.textMuted : null,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _assignWarehouse(s),
                child: Text(
                  s.warehouseName == null ? 'Assign Warehouse' : 'Change',
                ),
              ),
            ],
          ),
          Row(
            children: [
              count('Pending', s.pendingCount, const Color(0xFFD97706)),
              count('Approved', s.approvedCount, AppColors.emerald),
              count('Rejected', s.rejectedCount, const Color(0xFFE11D48)),
              count('Total', s.totalCount, AppColors.textPrimary),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Last Submitted: ${s.latestSubmittedAt == null ? '—' : formatSellerDate(s.latestSubmittedAt)}',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.push(
                  '${AppRoutes.sellerCategoriesApproval}/${s.id}',
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Review Products'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignWarehouseSheet extends ConsumerStatefulWidget {
  const _AssignWarehouseSheet({required this.store});

  final SellerApprovalStore store;

  @override
  ConsumerState<_AssignWarehouseSheet> createState() =>
      _AssignWarehouseSheetState();
}

class _AssignWarehouseSheetState extends ConsumerState<_AssignWarehouseSheet> {
  List<SellerWarehouse>? _warehouses;
  String? _loadError;
  late int? _warehouseId = widget.store.warehouseId;
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(sellerHubRepositoryProvider)
        .getWarehouses(isActive: true)
        .then((list) {
          if (mounted) setState(() => _warehouses = list);
        })
        .catchError((Object e) {
          if (mounted)
            setState(
              () => _loadError = e is SellerHubException
                  ? e.message
                  : 'Failed to load warehouses.',
            );
        });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _warehouseId;
    if (id == null) {
      setState(
        () => _error = 'Please select a fulfillment warehouse facility.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(sellerHubRepositoryProvider)
          .assignSellerWarehouse(
            widget.store.id,
            id,
            notes: _notes.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to assign warehouse.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _warehouses;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assign Warehouse',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.store.name,
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
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadError != null)
              Text(
                _loadError!,
                style: const TextStyle(color: Color(0xFFDC2626)),
              )
            else if (list == null)
              const SellerLoading(message: 'Loading warehouses...')
            else if (list.isEmpty)
              const Text('No active warehouses found')
            else
              DropdownButtonFormField<int>(
                initialValue: list.any((w) => w.id == _warehouseId)
                    ? _warehouseId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Fulfillment Warehouse',
                  hintText: '-- Choose Warehouse --',
                ),
                items: [
                  for (final w in list)
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(
                        '${w.name}${w.code != null ? ' (${w.code})' : ''}${w.city != null ? ' – ${w.city}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Assignment Notes (Optional)',
                hintText: 'e.g. Bangalore South regional zone assignment',
              ),
            ),
            const SizedBox(height: 10),
            const SellerPanel(
              tint: Color(0xFF2563EB),
              title: 'How dispatch routing works',
              subtitle:
                  "When this store's orders transition to Ready for Pickup, delivery riders will be routed to "
                  'pick up stock directly from the selected warehouse.',
              child: SizedBox.shrink(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving || list == null || list.isEmpty ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save Assignment'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Screen 2 — one seller's products (Web `/categories-approval/:sellerId`)
// ═════════════════════════════════════════════════════════════════════════════

class SellerApprovalProductsScreen extends ConsumerStatefulWidget {
  const SellerApprovalProductsScreen({super.key, required this.sellerId});

  final int sellerId;

  @override
  ConsumerState<SellerApprovalProductsScreen> createState() =>
      _SellerApprovalProductsScreenState();
}

class _SellerApprovalProductsScreenState
    extends ConsumerState<SellerApprovalProductsScreen> {
  String _tab = 'PENDING';
  final _search = TextEditingController();
  Timer? _debounce;
  int? _categoryId;
  int _page = 1;
  List<({int id, String path})> _categories = const [];
  SellerApprovalProductsPage? _data;
  bool _loading = true;
  String? _error;
  final Set<int> _selected = {};
  bool _busy = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
    ref
        .read(sellerHubRepositoryProvider)
        .getCategoryTreePaths()
        .then((c) {
          if (mounted) setState(() => _categories = c);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      final data = await _repo.getApprovalProducts(
        widget.sellerId,
        status: _tab,
        search: _search.text,
        categoryId: _categoryId,
        page: _page,
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
          _error = e is SellerHubException
              ? e.message
              : 'Failed to fetch seller products.';
        });
      }
    }
  }

  Future<void> _act(Future<String?> Function() action, String fallback) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) _toast(context, message ?? fallback);
      await _load();
    } catch (e) {
      if (mounted)
        _toast(
          context,
          e is SellerHubException ? e.message : 'Action failed.',
          error: true,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(SellerHubProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Product Catalog'),
        content: Text("Approve '${p.title}' and publish it to the catalog?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok == true)
      await _act(
        () => _repo.approveProduct(p.id),
        "Product '${p.title}' approved successfully.",
      );
  }

  Future<void> _reject(SellerHubProduct p) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(title: p.title),
    );
    if (reason != null)
      await _act(
        () => _repo.rejectProduct(p.id, reason),
        "Product '${p.title}' rejected.",
      );
  }

  Future<void> _bulkApprove() async {
    final ids = _selected.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Approve Products'),
        content: Text('Approve ${ids.length} selected product(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async {
      final done = await _repo.bulkApproveProducts(ids);
      return 'Bulk approved $done of ${ids.length} product(s) successfully.';
    }, '');
  }

  void _openDetail(SellerHubProduct p) {
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
      builder: (_) => _ApprovalProductDetailSheet(
        productId: p.id,
        onApprove: () {
          Navigator.of(context).pop();
          _approve(p);
        },
        onReject: () {
          Navigator.of(context).pop();
          _reject(p);
        },
      ),
    );
  }

  static (String, Color) _statusStyle(String status) => switch (status) {
    'APPROVED' => ('Approved', const Color(0xFF059669)),
    'REJECTED' => ('Rejected', const Color(0xFFE11D48)),
    'SUBMITTED' ||
    'UNDER_REVIEW' ||
    'CHANGES_REQUESTED' => ('Pending Review', const Color(0xFFD97706)),
    'PAUSED' => ('Paused', const Color(0xFF52525B)),
    _ => (status.isEmpty ? 'Draft' : status, const Color(0xFF475569)),
  };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final seller = data?.seller;
    final products = data?.page.results ?? const <SellerHubProduct>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(seller?.name ?? 'Seller Catalog Review')),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.fact_check_rounded,
                title: seller?.name ?? 'Seller Catalog Review',
                badge: 'ID #${widget.sellerId}',
                description: 'Review and approve product category assignments for this merchant',
              ),
              const SizedBox(height: AppSpacing.md),
              SellerFilterChips(
                options: [
                  (
                    'PENDING',
                    'Pending Review${seller == null ? '' : ' (${seller.pendingCount})'}',
                  ),
                  (
                    'APPROVED',
                    'Approved${seller == null ? '' : ' (${seller.approvedCount})'}',
                  ),
                  (
                    'REJECTED',
                    'Rejected${seller == null ? '' : ' (${seller.rejectedCount})'}',
                  ),
                  (
                    'ALL',
                    'All Products${seller == null ? '' : ' (${seller.totalCount})'}',
                  ),
                ],
                selected: _tab,
                onSelected: (v) {
                  setState(() {
                    _tab = v;
                    _page = 1;
                  });
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerSearchField(
                controller: _search,
                hint: 'Search Title, SKU, Barcode...',
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    _page = 1;
                    _load();
                  });
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerDropdownFilter(
                value: _categoryId?.toString() ?? '',
                options: [
                  ('', 'All Categories (Tree)'),
                  for (final c in _categories) ('${c.id}', c.path),
                ],
                onChanged: (v) {
                  setState(() {
                    _categoryId = int.tryParse(v);
                    _page = 1;
                  });
                  _load();
                },
              ),
              if (products.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Checkbox(
                      value: _selected.length == products.length,
                      onChanged: (_) => setState(() {
                        if (_selected.length == products.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(products.map((p) => p.id));
                        }
                      }),
                    ),
                    const Text('Select all'),
                    const Spacer(),
                    FilledButton(
                      onPressed: _selected.isEmpty || _busy
                          ? null
                          : _bulkApprove,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                      ),
                      child: Text('Bulk Approve (${_selected.length})'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                const SellerLoading(message: 'Loading products for review...')
              else if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Unable to load products',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (products.isEmpty)
                const SellerStateMessage(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products found',
                  message: 'No products in this status for this merchant.',
                )
              else ...[
                for (final p in products) _productCard(p),
                _pager(
                  page: _page,
                  totalPages: data!.page.totalPages,
                  onPage: (pg) {
                    setState(() => _page = pg);
                    _load();
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productCard(SellerHubProduct p) {
    final (label, color) = _statusStyle(p.status);
    final image = AppConfig.resolveMediaUrl(p.primaryImage);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: _selected.contains(p.id)
              ? AppColors.primary
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selected.contains(p.id),
                onChanged: (_) => setState(() {
                  if (!_selected.remove(p.id)) _selected.add(p.id);
                }),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 44,
                  height: 44,
                  color: AppColors.surfaceMuted,
                  child: image == null
                      ? const Icon(Icons.image_outlined)
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.image_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      [p.sku, if (p.brand != null) p.brand!].join(' • '),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      p.categoryPath ?? p.categoryName ?? '—',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    Text(
                      '₹${p.sellingPrice.toStringAsFixed(2)} / ₹${p.mrp.toStringAsFixed(2)}  ·  '
                      'Submitted ${p.submittedAt == null ? '—' : formatSellerDate(p.submittedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (p.status == 'REJECTED' && p.rejectionReason != null)
                      Text(
                        'Rejection Feedback: ${p.rejectionReason}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.errorText,
                        ),
                      ),
                  ],
                ),
              ),
              SellerPill(label: label, color: color),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _openDetail(p),
                child: const Text('Details'),
              ),
              if (p.status != 'APPROVED')
                TextButton(
                  onPressed: _busy ? null : () => _approve(p),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.emerald,
                  ),
                  child: const Text('Approve'),
                ),
              if (p.status != 'REJECTED')
                TextButton(
                  onPressed: _busy ? null : () => _reject(p),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE11D48),
                  ),
                  child: const Text('Reject'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.title});

  final String title;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _reason.text.trim().length >= 5;
    return AlertDialog(
      title: const Text('Reject Product Catalog'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Rejection reason (min 5 characters)',
              hintText: 'e.g. Inappropriate category selection, image resolution too low, or incorrect brand description...',
              hintMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE11D48),
          ),
          onPressed: valid
              ? () => Navigator.of(context).pop(_reason.text.trim())
              : null,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

class _ApprovalProductDetailSheet extends ConsumerWidget {
  const _ApprovalProductDetailSheet({
    required this.productId,
    required this.onApprove,
    required this.onReject,
  });

  final int productId;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => FutureBuilder<SellerProductDetail>(
        future: ref
            .read(sellerHubRepositoryProvider)
            .getApprovalProductDetail(productId),
        builder: (context, snap) {
          final children = <Widget>[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Product Catalog Review',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ];
          if (snap.connectionState != ConnectionState.done) {
            children.add(
              const SellerLoading(message: 'Loading specifications...'),
            );
          } else if (snap.hasError) {
            children.add(
              const Text(
                'Failed to load product full details.',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
            );
          } else {
            final d = snap.data!;
            final p = d.product;
            children.addAll([
              if (d.imageUrls.isNotEmpty)
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final url in d.imageUrls)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              AppConfig.resolveMediaUrl(url) ?? url,
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                p.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              SellerPanel(
                title: 'Product Details',
                child: Column(
                  children: [
                    SellerKeyValue('SKU', p.sku),
                    SellerKeyValue('Brand', p.brand ?? '—'),
                    SellerKeyValue(
                      'Category',
                      p.categoryPath ?? p.categoryName ?? '—',
                    ),
                    SellerKeyValue(
                      'Price / MRP',
                      '₹${p.sellingPrice.toStringAsFixed(2)} / ₹${p.mrp.toStringAsFixed(2)}',
                    ),
                    SellerKeyValue(
                      'Tax / HSN',
                      '${p.taxRate.toStringAsFixed(2)}% / ${p.hsnCode ?? '—'}',
                    ),
                    SellerKeyValue(
                      'Unit & Pack',
                      p.packLabel.isEmpty ? '—' : p.packLabel,
                    ),
                    if (p.barcode != null)
                      SellerKeyValue('Barcode / EAN', p.barcode!),
                    if (p.rejectionReason != null)
                      SellerKeyValue('Rejection', p.rejectionReason!),
                  ],
                ),
              ),
              if (p.description != null) ...[
                const SizedBox(height: 8),
                Text(p.description!, style: const TextStyle(fontSize: 12.5)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (p.status != 'APPROVED')
                    Expanded(
                      child: FilledButton(
                        onPressed: onApprove,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  if (p.status != 'APPROVED' && p.status != 'REJECTED')
                    const SizedBox(width: 8),
                  if (p.status != 'REJECTED')
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE11D48),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                ],
              ),
              const SellerSectionLabel('Audit History'),
              if (d.auditLogs.isEmpty)
                Text(
                  'No audit events recorded.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                for (final log in d.auditLogs)
                  SellerAuditRow(
                    title: log.action,
                    subtitle: 'By ${log.actorName ?? 'System'}',
                    note: log.notes,
                    timestamp: formatSellerTimestamp(log.createdAt),
                  ),
            ]);
          }
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: children,
          );
        },
      ),
    );
  }
}
