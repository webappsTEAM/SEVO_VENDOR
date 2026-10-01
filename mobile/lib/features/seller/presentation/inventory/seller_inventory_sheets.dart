import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

Future<bool?> _showSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (_) => child,
  );
}

/// Form sheet body with a title, scrollable fields and keyboard padding.
class _FormSheet extends StatelessWidget {
  const _FormSheet({
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input(
    this.controller,
    this.label, {
    this.hint,
    this.decimal = false,
    this.onChanged,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool decimal;
  final ValueChanged<String>? onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: decimal
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          isDense: true,
        ),
      ),
    );
  }
}

/// Date field that opens a picker and stores `YYYY-MM-DD`.
class _DateInput extends StatelessWidget {
  const _DateInput(this.controller, this.label);

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
        ),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 10),
          );
          if (picked != null) {
            controller.text =
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          }
        },
      ),
    );
  }
}

class _SubmitRow extends StatelessWidget {
  const _SubmitRow({
    required this.label,
    required this.busy,
    required this.onSubmit,
    this.color,
  });

  final String label;
  final bool busy;
  final VoidCallback? onSubmit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: color ?? AppColors.emerald,
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ),
      ],
    );
  }
}

bool _positive(String v) => (double.tryParse(v.trim()) ?? 0) > 0;

/// Stock In / Adjust (+/-) / Damage — the Web's three movement modals.
class SellerStockMovementSheet extends ConsumerStatefulWidget {
  const SellerStockMovementSheet({
    super.key,
    required this.item,
    required this.initialType,
  });

  final SellerHubInventoryItem item;

  /// `STOCK_IN`, `ADJUSTMENT_INCREASE` (adjust sheet) or `DAMAGE`.
  final String initialType;

  static Future<bool?> show(
    BuildContext context,
    SellerHubInventoryItem item,
    String type,
  ) => _showSheet(
    context,
    SellerStockMovementSheet(item: item, initialType: type),
  );

  @override
  ConsumerState<SellerStockMovementSheet> createState() =>
      _SellerStockMovementSheetState();
}

class _SellerStockMovementSheetState
    extends ConsumerState<SellerStockMovementSheet> {
  late String _type = widget.initialType;
  final _qty = TextEditingController();
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _cost = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isStockIn => widget.initialType == 'STOCK_IN';
  bool get _isDamage => widget.initialType == 'DAMAGE';
  bool get _isAdjust => !_isStockIn && !_isDamage;

  @override
  void dispose() {
    for (final c in [_qty, _batch, _expiry, _cost, _reference, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    if (!_positive(_qty.text)) return false;
    if (_isDamage &&
        (double.tryParse(_qty.text) ?? 0) > widget.item.availableQty)
      return false;
    if ((_isAdjust || _isDamage) && _reason.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final item = widget.item;
    try {
      await ref
          .read(sellerHubRepositoryProvider)
          .adjustInventory(
            item.id,
            movementType: _type,
            quantity: _qty.text.trim(),
            reason: _isStockIn && _reason.text.trim().isEmpty
                ? 'Warehouse stock-in / replenishment.'
                : _reason.text.trim(),
            referenceId: _reference.text.trim(),
            batchNumber: _batch.text.trim(),
            expiryDate: _expiry.text.trim(),
            costPrice: _cost.text.trim(),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      final qty = _qty.text.trim();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text(switch (_type) {
            'STOCK_IN' =>
              'Successfully added $qty ${item.productUnit} to stock!',
            'DAMAGE' => 'Recorded $qty ${item.productUnit} as damaged/broken.',
            _ =>
              'Stock adjustment of $qty ${item.productUnit} recorded successfully.',
          }),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to record stock movement.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final unit = item.productUnit;
    return _FormSheet(
      title: _isStockIn
          ? 'Stock In / Replenish'
          : _isDamage
          ? 'Record Damaged / Broken Stock'
          : 'Stock Count Adjustment',
      subtitle: item.productTitle,
      children: [
        if (_isAdjust) ...[
          const Text(
            'Adjustment Direction *',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'ADJUSTMENT_INCREASE',
                label: Text('Increase (+)'),
                icon: Icon(Icons.add),
              ),
              ButtonSegment(
                value: 'ADJUSTMENT_DECREASE',
                label: Text('Decrease (-)'),
                icon: Icon(Icons.remove),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
        ],
        _Input(
          _qty,
          _isStockIn
              ? 'Quantity to Add ($unit) *'
              : _isDamage
              ? 'Damaged Quantity ($unit) *'
              : 'Adjustment Quantity ($unit) *',
          hint: _isDamage
              ? 'Max ${formatQuantity(item.availableQty)}'
              : 'e.g. 50.000',
          helper: _isDamage
              ? 'Available to write off: ${formatQuantity(item.availableQty)} $unit'
              : null,
          decimal: true,
          onChanged: (_) => setState(() {}),
        ),
        if (_isStockIn) ...[
          _Input(_batch, 'Batch / Lot # (Optional)', hint: 'e.g. LOT-2026-09'),
          _DateInput(_expiry, 'Expiry Date (Optional)'),
          _Input(
            _cost,
            'Cost Price (₹, Optional)',
            hint: 'e.g. 140.00',
            decimal: true,
          ),
          _Input(_reference, 'PO / Invoice # (Optional)', hint: 'e.g. PO-9821'),
          _Input(
            _reason,
            'Notes / Reason',
            hint: 'e.g. Fresh wholesale stock received from vendor.',
          ),
        ] else ...[
          _Input(
            _reason,
            _isDamage ? 'Damage Reason *' : 'Mandatory Audit Reason *',
            hint: _isDamage
                ? 'e.g. Packaging seal breached during transit, oil bottle cracked.'
                : 'e.g. Physical inventory count discrepancy correction.',
            onChanged: (_) => setState(() {}),
          ),
          _Input(
            _reference,
            'Audit Reference / Note (Optional)',
            hint: 'e.g. AUDIT-2026-Q3',
          ),
        ],
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        _SubmitRow(
          label: _isStockIn
              ? 'Confirm Stock In'
              : _isDamage
              ? 'Record Damage'
              : 'Confirm Adjustment',
          color: _isDamage ? const Color(0xFFDC2626) : null,
          busy: _busy,
          onSubmit: _valid ? _submit : null,
        ),
      ],
    );
  }
}

/// Stock Alert Thresholds (PATCH low_stock_threshold / reorder_level).
class SellerThresholdSheet extends ConsumerStatefulWidget {
  const SellerThresholdSheet({super.key, required this.item});

  final SellerHubInventoryItem item;

  static Future<bool?> show(
    BuildContext context,
    SellerHubInventoryItem item,
  ) => _showSheet(context, SellerThresholdSheet(item: item));

  @override
  ConsumerState<SellerThresholdSheet> createState() =>
      _SellerThresholdSheetState();
}

class _SellerThresholdSheetState extends ConsumerState<SellerThresholdSheet> {
  late final _low = TextEditingController(
    text: widget.item.lowStockThreshold.toStringAsFixed(3),
  );
  late final _reorder = TextEditingController(
    text: widget.item.reorderLevel.toStringAsFixed(3),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _low.dispose();
    _reorder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sellerHubRepositoryProvider)
          .updateInventoryThresholds(
            widget.item.id,
            lowStockThreshold: _low.text.trim(),
            reorderLevel: _reorder.text.trim(),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text('Inventory thresholds updated successfully.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to update thresholds.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.item.productUnit;
    return _FormSheet(
      title: 'Stock Alert Thresholds',
      subtitle: widget.item.productTitle,
      children: [
        _Input(
          _low,
          'Low Stock Alert Level ($unit) *',
          decimal: true,
          helper: 'Triggers amber warning when stock reaches or drops below this point.',
          onChanged: (_) => setState(() {}),
        ),
        _Input(
          _reorder,
          'Suggested Reorder Level ($unit) *',
          decimal: true,
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        _SubmitRow(
          label: 'Save Levels',
          busy: _busy,
          onSubmit:
              _low.text.trim().isNotEmpty && _reorder.text.trim().isNotEmpty
              ? _submit
              : null,
        ),
      ],
    );
  }
}

/// Initialize Product Inventory for an approved product without stock.
class SellerInitializeStockSheet extends ConsumerStatefulWidget {
  const SellerInitializeStockSheet({
    super.key,
    required this.existingProductIds,
  });

  final Set<int> existingProductIds;

  static Future<bool?> show(
    BuildContext context, {
    required Set<int> existingProductIds,
  }) => _showSheet(
    context,
    SellerInitializeStockSheet(existingProductIds: existingProductIds),
  );

  @override
  ConsumerState<SellerInitializeStockSheet> createState() =>
      _SellerInitializeStockSheetState();
}

class _SellerInitializeStockSheetState
    extends ConsumerState<SellerInitializeStockSheet> {
  List<SellerHubProduct>? _products;
  String? _loadError;
  int? _productId;
  final _onHand = TextEditingController(text: '0.000');
  final _low = TextEditingController(text: '10.000');
  final _reorder = TextEditingController(text: '20.000');
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _cost = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    for (final c in [_onHand, _low, _reorder, _batch, _expiry, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final all = await ref
          .read(sellerHubRepositoryProvider)
          .getProducts(status: 'APPROVED');
      final pending = all
          .where((p) => !widget.existingProductIds.contains(p.id))
          .toList();
      if (!mounted) return;
      setState(() {
        _products = pending;
        _productId = pending.isEmpty ? null : pending.first.id;
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _loadError = e is SellerHubException
              ? e.message
              : 'Failed to load products.',
        );
    }
  }

  Future<void> _submit() async {
    final productId = _productId;
    if (productId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sellerHubRepositoryProvider)
          .initializeInventory(
            productId: productId,
            onHandQty: _onHand.text.trim(),
            lowStockThreshold: _low.text.trim(),
            reorderLevel: _reorder.text.trim(),
            batchNumber: _batch.text.trim(),
            expiryDate: _expiry.text.trim(),
            costPrice: _cost.text.trim(),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.emerald,
          content: Text(
            'Product inventory initialized with initial stock levels.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to initialize inventory.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return _FormSheet(
      title: 'Initialize Product Inventory',
      subtitle: 'Add an approved catalog item to active warehouse stock',
      children: [
        if (_loadError != null)
          Text(_loadError!, style: const TextStyle(color: Color(0xFFDC2626)))
        else if (products == null)
          const SellerLoading(message: 'Checking approved catalog products...')
        else if (products.isEmpty)
          const SellerStateMessage(
            icon: Icons.check_circle_outline_rounded,
            title: 'No Uninitialized Approved Products',
            message: 'Every approved product already has an inventory record.',
          )
        else ...[
          DropdownButtonFormField<int>(
            initialValue: _productId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Select Approved Product *',
              isDense: true,
            ),
            items: [
              for (final p in products)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.title} (${p.sku})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _productId = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Input(_onHand, 'Opening Stock', decimal: true)),
              const SizedBox(width: 8),
              Expanded(child: _Input(_low, 'Low Threshold', decimal: true)),
              const SizedBox(width: 8),
              Expanded(child: _Input(_reorder, 'Reorder Point', decimal: true)),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _Input(
                  _batch,
                  'Batch # (Optional)',
                  hint: 'e.g. BATCH-01',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _DateInput(_expiry, 'Expiry Date (Optional)')),
            ],
          ),
          _Input(_cost, 'Cost Price (₹, Optional)', decimal: true),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          _SubmitRow(
            label: 'Initialize Inventory',
            busy: _busy,
            onSubmit: _productId == null ? null : _submit,
          ),
        ],
      ],
    );
  }
}

/// Movement ledger & batches drawer for one inventory record.
class SellerInventoryLedgerSheet extends ConsumerStatefulWidget {
  const SellerInventoryLedgerSheet({super.key, required this.item});

  final SellerHubInventoryItem item;

  static Future<void> show(BuildContext context, SellerHubInventoryItem item) =>
      _showSheet(context, SellerInventoryLedgerSheet(item: item));

  static const movementTypes = <(String, String)>[
    ('', 'All Movement Types'),
    ('OPENING_STOCK', 'Opening Stock'),
    ('STOCK_IN', 'Stock In'),
    ('ADJUSTMENT_INCREASE', 'Adjustment (+)'),
    ('ADJUSTMENT_DECREASE', 'Adjustment (-)'),
    ('DAMAGE', 'Damaged Stock'),
    ('EXPIRED', 'Expired Stock'),
  ];

  @override
  ConsumerState<SellerInventoryLedgerSheet> createState() =>
      _SellerInventoryLedgerSheetState();
}

class _SellerInventoryLedgerSheetState
    extends ConsumerState<SellerInventoryLedgerSheet> {
  bool _showBatches = false;
  String _movementType = '';
  late Future<List<SellerInventoryMovement>> _movements = _fetchMovements();
  Future<List<SellerInventoryBatch>>? _batches;

  Future<List<SellerInventoryMovement>> _fetchMovements() => ref
      .read(sellerHubRepositoryProvider)
      .getInventoryMovements(widget.item.id, movementType: _movementType);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => ListView(
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
                      item.productTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'SKU: ${item.productSku}${item.productCategoryName != null ? ' • ${item.productCategoryName}' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (item.productBarcode != null)
                      Text(
                        'Barcode: ${item.productBarcode}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
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
          const SizedBox(height: 10),
          SellerTileGrid(
            minTileWidth: 100,
            children: [
              _Stat('On Hand', item.onHandQty.toStringAsFixed(3)),
              _Stat('Reserved', item.reservedQty.toStringAsFixed(3)),
              _Stat('Available', item.availableQty.toStringAsFixed(3)),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Movement Ledger')),
              ButtonSegment(value: true, label: Text('Batches & Expiry')),
            ],
            selected: {_showBatches},
            onSelectionChanged: (s) => setState(() {
              _showBatches = s.first;
              if (_showBatches) {
                _batches ??= ref
                    .read(sellerHubRepositoryProvider)
                    .getInventoryBatches(item.id);
              }
            }),
          ),
          const SizedBox(height: 12),
          if (!_showBatches) ...[
            SellerDropdownFilter(
              value: _movementType,
              options: SellerInventoryLedgerSheet.movementTypes,
              onChanged: (v) => setState(() {
                _movementType = v;
                _movements = _fetchMovements();
              }),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<SellerInventoryMovement>>(
              future: _movements,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SellerLoading(
                    message: 'Loading movement history...',
                  );
                }
                if (snap.hasError) {
                  return Text(
                    snap.error is SellerHubException
                        ? (snap.error as SellerHubException).message
                        : 'Failed to load.',
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  );
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return Text(
                    'No stock movements recorded.',
                    style: TextStyle(color: AppColors.textSecondary),
                  );
                }
                return Column(
                  children: [for (final m in list) _MovementRow(m)],
                );
              },
            ),
          ] else
            FutureBuilder<List<SellerInventoryBatch>>(
              future: _batches,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SellerLoading(message: 'Loading batches...');
                }
                final list = snap.data ?? const [];
                if (snap.hasError || list.isEmpty) {
                  return Text(
                    'No specific grocery lot / batches registered for this product.',
                    style: TextStyle(color: AppColors.textSecondary),
                  );
                }
                return Column(children: [for (final b in list) _BatchRow(b)]);
              },
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow(this.m);

  final SellerInventoryMovement m;

  @override
  Widget build(BuildContext context) {
    final positive = m.quantityChange > 0;
    final color = switch (m.movementType) {
      'STOCK_IN' || 'OPENING_STOCK' => AppColors.emerald,
      'DAMAGE' || 'EXPIRED' => const Color(0xFFDC2626),
      _ => const Color(0xFFD97706),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SellerPill(
                label: m.movementTypeDisplay ?? m.movementType,
                color: color,
              ),
              const Spacer(),
              Text(
                '${positive ? '+' : ''}${m.quantityChange.toStringAsFixed(3)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: positive ? AppColors.emerald : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Balance: ${m.balanceBefore.toStringAsFixed(3)} → ${m.balanceAfter.toStringAsFixed(3)}  ·  '
            '${formatSellerTimestamp(m.createdAt)}',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (m.reason != null)
            Text(m.reason!, style: const TextStyle(fontSize: 12)),
          Text(
            [
              'Actor: ${m.actorName ?? 'System'}',
              if (m.referenceId != null) 'Ref: ${m.referenceId}',
            ].join('  ·  '),
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow(this.b);

  final SellerInventoryBatch b;

  @override
  Widget build(BuildContext context) {
    final color = switch (b.status) {
      'ACTIVE' => AppColors.emerald,
      'EXPIRING_SOON' => const Color(0xFFD97706),
      'EXPIRED' => const Color(0xFFDC2626),
      _ => const Color(0xFF64748B),
    };
    final days = b.daysUntilExpiry;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${b.batchNumber}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              SellerPill(label: b.status, color: color),
            ],
          ),
          const SizedBox(height: 4),
          SellerKeyValue('Current Qty', b.currentQuantity.toStringAsFixed(3)),
          SellerKeyValue('Initial Qty', b.initialQuantity.toStringAsFixed(3)),
          SellerKeyValue('Received', b.receivedDate ?? '—'),
          SellerKeyValue('Expiry', b.expiryDate ?? 'N/A'),
          if (days != null)
            Text(
              days < 0
                  ? 'Expired ${days.abs()} days ago'
                  : 'Expires in $days days',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}
