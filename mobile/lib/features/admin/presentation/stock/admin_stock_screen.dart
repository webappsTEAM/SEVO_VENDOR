import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../seller/presentation/widgets/seller_hub_widgets.dart';
import '../../data/vendor_stock_repository.dart';
import '../../domain/vendor_stock.dart';

enum _StockPanel { restock, markOut, edit, history }

/// Web `AdminStockManagementPage` (`/workforce/admin/stock`) — the vendor's own
/// Daily Essentials stock: restock, mark out of stock, edit price, history.
class AdminStockScreen extends ConsumerStatefulWidget {
  const AdminStockScreen({super.key});

  @override
  ConsumerState<AdminStockScreen> createState() => _AdminStockScreenState();
}

class _AdminStockScreenState extends ConsumerState<AdminStockScreen> {
  List<VendorStockProduct> _products = const [];
  bool _loading = true;
  String? _error;
  String? _flash;
  Timer? _flashTimer;
  int? _openProductId;
  _StockPanel? _openPanel;

  VendorStockRepository get _repo => ref.read(vendorStockRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _repo.list();
      if (!mounted) return;
      setState(() {
        _products = rows;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is VendorStockException
            ? e.message
            : 'Could not load your stock.';
        _loading = false;
      });
    }
  }

  void _showFlash(String message) {
    _flashTimer?.cancel();
    setState(() => _flash = message);
    _flashTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _togglePanel(int productId, _StockPanel panel) {
    setState(() {
      final same = _openProductId == productId && _openPanel == panel;
      _openProductId = same ? null : productId;
      _openPanel = same ? null : panel;
    });
  }

  void _closePanel() => setState(() {
    _openProductId = null;
    _openPanel = null;
  });

  void _onError(Object err) {
    setState(
      () => _error = err is VendorStockException ? err.message : err.toString(),
    );
  }

  /// Web `onSuccess`: flash, clear the error and patch the card in place, or
  /// reload the list when the response carried no `data`.
  void _onSuccess(
    int productId,
    VendorStockWriteResult result,
    String fallbackMessage,
  ) {
    _showFlash(result.message ?? fallbackMessage);
    setState(() => _error = null);
    final patch = result.data;
    if (patch == null) {
      _load();
      return;
    }
    setState(() {
      _products = [
        for (final p in _products)
          p.productId == productId ? p.merge(patch) : p,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return SevoModuleFrame(
      module: SevoModule.stock,
      title: 'Stock management',
      subtitle: 'Restock, mark items out of stock, and update prices for your Daily Essentials products. Changes here only affect stock you own — a product another vendor already manages shows as read-only.',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.eco_rounded,
                title: 'Stock management',
                description: 'Restock, mark items out of stock, and update prices for your Daily Essentials products. Changes here only affect stock you own — a product another vendor already manages shows as read-only.',
                actions: [
                  SellerHeaderAction(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_flash != null)
                _banner(Icons.check_circle_rounded, _flash!, AppColors.emerald),
              if (_error != null)
                _banner(
                  Icons.warning_amber_rounded,
                  _error!,
                  const Color(0xFFDC2626),
                  actionLabel: 'Try again',
                  onAction: _load,
                ),
              if (_loading && _products.isEmpty)
                const SellerLoading(message: 'Loading your stock...')
              else if (_products.isEmpty && _error == null)
                const SellerStateMessage(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products',
                  message: 'No Daily Essentials products found.',
                )
              else
                for (final p in _products) ...[
                  _StockCard(
                    key: ValueKey(p.productId),
                    product: p,
                    openPanel: _openProductId == p.productId
                        ? _openPanel
                        : null,
                    onToggle: (panel) => _togglePanel(p.productId, panel),
                    onClose: _closePanel,
                    repo: _repo,
                    onError: _onError,
                    onSuccess: (result, fallback) =>
                        _onSuccess(p.productId, result, fallback),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(
    IconData icon,
    String text,
    Color color, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (actionLabel != null)
                  GestureDetector(
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        actionLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    super.key,
    required this.product,
    required this.openPanel,
    required this.onToggle,
    required this.onClose,
    required this.repo,
    required this.onError,
    required this.onSuccess,
  });

  final VendorStockProduct product;
  final _StockPanel? openPanel;
  final ValueChanged<_StockPanel> onToggle;
  final VoidCallback onClose;
  final VendorStockRepository repo;
  final ValueChanged<Object> onError;
  final void Function(VendorStockWriteResult result, String fallbackMessage)
  onSuccess;

  Color get _stateColor => switch (product.state) {
    'in_stock' => AppColors.emerald,
    'out_of_stock' => const Color(0xFFE11D48),
    _ => AppColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final p = product;
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
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: (p.image ?? '').isNotEmpty
                      ? Image.network(
                          p.image!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if ((p.vegetableGram ?? '').isNotEmpty)
                      Text(
                        p.vegetableGram!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              SellerPill(label: p.stateLabel, color: _stateColor),
            ],
          ),
          if (p.locked) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: Color(0xFFB45309),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Managed by another vendor — you can view this product but not change it.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SellerTileGrid(
            minTileWidth: 130,
            children: [
              _stat('Available today', p.todayAvailableDisplay ?? '—'),
              _stat('Price', '₹${p.price ?? '—'}', sub: p.mrpNote),
              _stat('Reorder level', p.reorderLevelDisplay ?? '—'),
              _stat('Restock level', p.restockLevelDisplay ?? '—'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action(
                Icons.add_box_rounded,
                'Restock',
                _StockPanel.restock,
                disabled: p.locked,
              ),
              _action(
                Icons.remove_shopping_cart_rounded,
                'Mark out of stock',
                _StockPanel.markOut,
                disabled: p.locked,
              ),
              _action(
                Icons.edit_rounded,
                'Edit price',
                _StockPanel.edit,
                disabled: p.locked,
              ),
              _action(Icons.history_rounded, 'History', _StockPanel.history),
            ],
          ),
          if (openPanel != null) ...[
            const SizedBox(height: 10),
            switch (openPanel!) {
              _StockPanel.restock => _RestockPanel(
                product: p,
                repo: repo,
                onClose: onClose,
                onError: onError,
                onSuccess: onSuccess,
              ),
              _StockPanel.markOut => _MarkOutPanel(
                product: p,
                repo: repo,
                onClose: onClose,
                onError: onError,
                onSuccess: onSuccess,
              ),
              _StockPanel.edit => _EditPanel(
                product: p,
                repo: repo,
                onClose: onClose,
                onError: onError,
                onSuccess: onSuccess,
              ),
              _StockPanel.history => _HistoryPanel(
                product: p,
                repo: repo,
                onClose: onClose,
                onError: onError,
              ),
            },
          ],
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceMuted,
    child: Icon(Icons.eco_outlined, color: AppColors.textMuted),
  );

  Widget _stat(String label, String value, {String? sub}) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (sub != null)
          Text(
            sub,
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
      ],
    ),
  );

  Widget _action(
    IconData icon,
    String label,
    _StockPanel panel, {
    bool disabled = false,
  }) {
    final active = openPanel == panel;
    return OutlinedButton.icon(
      onPressed: disabled ? null : () => onToggle(panel),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: active ? Colors.white : AppColors.textPrimary,
        backgroundColor: active ? AppColors.textPrimary : null,
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
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
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close',
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

typedef _OnSuccess = void Function(
  VendorStockWriteResult result,
  String fallbackMessage,
);

class _RestockPanel extends StatefulWidget {
  const _RestockPanel({
    required this.product,
    required this.repo,
    required this.onClose,
    required this.onError,
    required this.onSuccess,
  });

  final VendorStockProduct product;
  final VendorStockRepository repo;
  final VoidCallback onClose;
  final ValueChanged<Object> onError;
  final _OnSuccess onSuccess;

  @override
  State<_RestockPanel> createState() => _RestockPanelState();
}

class _RestockPanelState extends State<_RestockPanel> {
  final _qty = TextEditingController();
  String _unit = 'kg';
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final q = double.tryParse(_qty.text.trim());
    if (q == null || q <= 0) {
      widget.onError(
        const VendorStockException('Enter a quantity greater than zero.'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await widget.repo.restock(
        widget.product.productId,
        quantity: q,
        unit: _unit,
      );
      widget.onSuccess(res, 'Restocked.');
      widget.onClose();
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Restock',
      onClose: widget.onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantity to add',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _unit,
                items: const [
                  DropdownMenuItem(value: 'kg', child: Text('kg')),
                  DropdownMenuItem(value: 'g', child: Text('g')),
                ],
                onChanged: (v) => setState(() => _unit = v ?? 'kg'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Saving...' : 'Add stock'),
          ),
        ],
      ),
    );
  }
}

class _MarkOutPanel extends StatefulWidget {
  const _MarkOutPanel({
    required this.product,
    required this.repo,
    required this.onClose,
    required this.onError,
    required this.onSuccess,
  });

  final VendorStockProduct product;
  final VendorStockRepository repo;
  final VoidCallback onClose;
  final ValueChanged<Object> onError;
  final _OnSuccess onSuccess;

  @override
  State<_MarkOutPanel> createState() => _MarkOutPanelState();
}

class _MarkOutPanelState extends State<_MarkOutPanel> {
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final res = await widget.repo.markOutOfStock(widget.product.productId);
      widget.onSuccess(res, 'Marked ${widget.product.name} as out of stock.');
      widget.onClose();
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Mark out of stock',
      onClose: widget.onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This sets live stock to zero immediately — customers won't be able to add ${widget.product.name} to their cart until you restock it.",
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _confirm,
            icon: const Icon(Icons.remove_shopping_cart_rounded, size: 16),
            label: const Text('Confirm — mark out of stock'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditPanel extends StatefulWidget {
  const _EditPanel({
    required this.product,
    required this.repo,
    required this.onClose,
    required this.onError,
    required this.onSuccess,
  });

  final VendorStockProduct product;
  final VendorStockRepository repo;
  final VoidCallback onClose;
  final ValueChanged<Object> onError;
  final _OnSuccess onSuccess;

  @override
  State<_EditPanel> createState() => _EditPanelState();
}

class _EditPanelState extends State<_EditPanel> {
  late final _price = TextEditingController(text: widget.product.price ?? '');
  late final _offer = TextEditingController(
    text:
        (widget.product.mrp ?? '').isNotEmpty &&
            widget.product.mrp != widget.product.price
        ? widget.product.mrp!
        : '',
  );
  final _reorder = TextEditingController();
  final _restock = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    _offer.dispose();
    _reorder.dispose();
    _restock.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Web sends only the fields that were filled in.
    final payload = <String, dynamic>{};
    if (_price.text.trim().isNotEmpty) payload['price'] = _price.text.trim();
    if (_offer.text.trim().isNotEmpty)
      payload['offer_price'] = _offer.text.trim();
    final reorder = double.tryParse(_reorder.text.trim());
    if (_reorder.text.trim().isNotEmpty && reorder != null) {
      payload['reorder_level_quantity'] = reorder;
      payload['reorder_level_unit'] = 'kg';
    }
    final restock = double.tryParse(_restock.text.trim());
    if (_restock.text.trim().isNotEmpty && restock != null) {
      payload['restock_level_quantity'] = restock;
      payload['restock_level_unit'] = 'kg';
    }
    setState(() => _saving = true);
    try {
      final res = await widget.repo.updateDetails(
        widget.product.productId,
        payload,
      );
      widget.onSuccess(res, 'Details updated.');
      widget.onClose();
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, helperText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Edit price & levels',
      onClose: widget.onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_price, 'Selling price (₹)'),
          _field(
            _offer,
            'MRP / offer price (₹)',
            hint: 'Leave blank for no strike-through price.',
          ),
          _field(
            _reorder,
            'Reorder level (kg)',
            hint: 'Leave blank to keep current.',
          ),
          _field(
            _restock,
            'Restock level (kg)',
            hint: 'Leave blank to keep current.',
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Saving...' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatefulWidget {
  const _HistoryPanel({
    required this.product,
    required this.repo,
    required this.onClose,
    required this.onError,
  });

  final VendorStockProduct product;
  final VendorStockRepository repo;
  final VoidCallback onClose;
  final ValueChanged<Object> onError;

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  List<VendorStockHistoryRow>? _rows;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final rows = await widget.repo.history(widget.product.productId);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) widget.onError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return _PanelShell(
      title: 'Last 7 days',
      onClose: widget.onClose,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : rows == null || rows.isEmpty
          ? Text(
              'No activity in this window.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 32,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 36,
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Opening')),
                  DataColumn(label: Text('Restocked')),
                  DataColumn(label: Text('Sold')),
                  DataColumn(label: Text('Closing')),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(r.date)),
                        DataCell(Text(r.openingDisplay ?? '—')),
                        DataCell(Text(r.restockedLabel)),
                        DataCell(Text(r.soldLabel)),
                        DataCell(Text(r.closingDisplay ?? '—')),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}
