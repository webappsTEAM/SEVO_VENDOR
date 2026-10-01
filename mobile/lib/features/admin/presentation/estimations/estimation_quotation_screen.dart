import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../seller/presentation/widgets/seller_hub_widgets.dart';
import '../../data/vendor_estimation_repository.dart';
import '../../domain/vendor_estimation.dart';
import 'admin_estimation_detail_screen.dart' show latestQuotation, money;

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class _Line {
  _Line({
    this.rateItemId,
    this.category = '',
    required this.title,
    this.type = 'LABOR',
    this.quantity = 1,
    this.unit = 'unit',
    this.unitPrice = 0,
  });

  Object? rateItemId;
  String category;
  String title;
  String type;
  double quantity;
  String unit;
  double unitPrice;

  double get total => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
    'rate_item_id': rateItemId,
    'category_name_snapshot': category,
    'item_name_snapshot': title,
    'title': title,
    'item_type': type,
    'quantity': quantity < 0.1 ? 0.1 : quantity,
    'unit': unit.isEmpty ? 'unit' : unit,
    'unit_price': unitPrice < 0 ? 0 : unitPrice,
  };
}

/// Web `VendorQuotationBuilder` — pick items from the booking's rate-card
/// snapshot, add custom lines, set GST / discount / validity, then save the
/// draft or submit it for admin review. Pops `true` after a successful save.
class EstimationQuotationScreen extends ConsumerStatefulWidget {
  const EstimationQuotationScreen({super.key, required this.lead});

  final VendorEstimation lead;

  @override
  ConsumerState<EstimationQuotationScreen> createState() =>
      _EstimationQuotationScreenState();
}

class _EstimationQuotationScreenState
    extends ConsumerState<EstimationQuotationScreen> {
  final List<_Line> _lines = [];
  bool _applyGst = true;
  final _gst = TextEditingController(text: '18');
  final _discount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  late DateTime _validUntil = DateTime.now().add(const Duration(days: 7));
  String _category = 'ALL';
  bool _saving = false;
  String? _error;
  int? _quoteId;

  @override
  void initState() {
    super.initState();
    final latest = latestQuotation(widget.lead);
    if (latest != null) {
      _quoteId = latest['id'] is num
          ? (latest['id'] as num).toInt()
          : int.tryParse('${latest['id']}');
      final items = latest['items'] is List
          ? latest['items'] as List
          : const [];
      for (final it in items.whereType<Map>()) {
        _lines.add(
          _Line(
            rateItemId: it['rate_item_id'],
            category: '${it['category_name_snapshot'] ?? it['category'] ?? ''}',
            title:
                '${it['service_name'] ?? it['title'] ?? it['item_name_snapshot'] ?? ''}',
            type: '${it['item_type'] ?? 'LABOR'}',
            quantity: _d(it['quantity']) == 0 ? 1 : _d(it['quantity']),
            unit: '${it['unit'] ?? 'unit'}',
            unitPrice: _d(it['unit_price'] ?? it['unit_price_snapshot']),
          ),
        );
      }
      final tax = _d(latest['tax_amount']);
      _applyGst = tax > 0;
      _discount.text = '${_d(latest['discount_amount'])}';
      _notes.text = '${latest['notes'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _gst.dispose();
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _subtotal => _lines.fold(0, (s, l) => s + l.total);
  double get _tax =>
      !_applyGst ? 0 : (_subtotal * (_d(_gst.text) / 100) * 100).round() / 100;
  double get _grand {
    final t = _subtotal + _tax - _d(_discount.text);
    return t < 0 ? 0 : (t * 100).round() / 100;
  }

  void _addRate(EstimationRateItem r) {
    final i = _lines.indexWhere((l) => l.title == r.name);
    setState(() {
      if (i >= 0) {
        _lines[i].quantity += 1;
      } else {
        _lines.add(
          _Line(
            category: r.category ?? 'General',
            title: r.name,
            type: r.name.toLowerCase().contains('gas') ? 'GAS' : 'LABOR',
            unit: r.unit ?? 'unit',
            unitPrice: r.price ?? 0,
          ),
        );
      }
    });
  }

  Future<int?> _saveDraft() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'Please add at least one line item.');
      return null;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final lead = await ref
          .read(vendorEstimationRepositoryProvider)
          .saveQuotation(widget.lead.id, {
            'valid_until':
                '${_validUntil.year.toString().padLeft(4, '0')}-${_validUntil.month.toString().padLeft(2, '0')}-${_validUntil.day.toString().padLeft(2, '0')}',
            'tax_rate_percent': _applyGst ? _d(_gst.text) : 0,
            'discount_amount': _d(_discount.text),
            'notes': _notes.text,
            'items': [for (final l in _lines) l.toJson()],
          });
      final q = latestQuotation(lead);
      final id = q == null
          ? null
          : (q['id'] is num
                ? (q['id'] as num).toInt()
                : int.tryParse('${q['id']}'));
      if (mounted) setState(() => _quoteId = id ?? _quoteId);
      return id ?? _quoteId;
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is VendorEstimationException
              ? e.message
              : 'Failed to save quotation draft.',
        );
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final id = await _saveDraft();
    if (id != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quotation draft saved.')));
    }
  }

  Future<void> _submitForReview() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for admin review?'),
        content: Text(
          'Total ${money(_grand)} will be sent to the admin for approval before release to the customer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = await _saveDraft();
    if (id == null) {
      if (mounted && _error == null)
        setState(
          () => _error = 'Unable to resolve quotation ID for submission.',
        );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(vendorEstimationRepositoryProvider)
          .submitQuotationForReview(widget.lead.id, id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Failed to submit quotation for admin review.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.lead.rateCard;
    final cats = <String>{
      for (final r in rate) r.category ?? 'Standard Repairs',
    }.toList();
    final shown = _category == 'ALL'
        ? rate
        : rate
              .where((r) => (r.category ?? 'Standard Repairs') == _category)
              .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Quotation Builder')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  'Job #${widget.lead.reference} • ${widget.lead.customerName ?? ''} • ${widget.lead.acBrand ?? ''} (${widget.lead.capacityLabel})',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                SellerSectionLabel(
                  'Authorized Service Rate Card (snapshot for this booking)',
                ),
                const SizedBox(height: 6),
                if (rate.isEmpty)
                  Text(
                    'No pre-approved rate card items for this booking. Add custom lines below.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                else ...[
                  SellerFilterChips(
                    options: [
                      ('ALL', 'All Items (${rate.length})'),
                      for (final c in cats) (c, c),
                    ],
                    selected: _category,
                    onSelected: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 6),
                  for (final r in shown)
                    Builder(
                      builder: (context) {
                        final added = _lines.any((l) => l.title == r.name);
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          tileColor: added
                              ? AppColors.emerald.withValues(alpha: 0.08)
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: added
                                  ? AppColors.emerald
                                  : AppColors.border,
                            ),
                          ),
                          title: Text(
                            r.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '${r.category ?? ''} • ${r.unit ?? 'unit'} • ${r.price == null ? '—' : money(r.price!)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Icon(
                            added
                                ? Icons.add_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: added
                                ? AppColors.emerald
                                : AppColors.textMuted,
                          ),
                          onTap: () => _addRate(r),
                        );
                      },
                    ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: SellerSectionLabel(
                        'Quotation Line Items (${_lines.length})',
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Add custom line',
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onSelected: (t) => setState(
                        () => _lines.add(
                          _Line(
                            category: 'Custom',
                            title: t == 'GAS'
                                ? 'Refrigerant Gas'
                                : t == 'PART'
                                ? 'Spare Component'
                                : 'Labor Service',
                            type: t,
                          ),
                        ),
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'LABOR',
                          child: Text('Add Custom Labor'),
                        ),
                        PopupMenuItem(
                          value: 'PART',
                          child: Text('Add Custom Part'),
                        ),
                        PopupMenuItem(value: 'GAS', child: Text('Add Gas')),
                      ],
                    ),
                  ],
                ),
                if (_lines.isEmpty)
                  Text(
                    'No repair items selected. Tap rate-card items above or add a custom line.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                else
                  for (var i = 0; i < _lines.length; i++)
                    _LineEditor(
                      key: ObjectKey(_lines[i]),
                      line: _lines[i],
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => _lines.removeAt(i)),
                    ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: _validUntil,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (p != null) setState(() => _validUntil = p);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    'Valid until ${_validUntil.day.toString().padLeft(2, '0')}/${_validUntil.month.toString().padLeft(2, '0')}/${_validUntil.year}',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Customer guarantee & warranty terms',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Apply GST'),
                        value: _applyGst,
                        onChanged: (v) => setState(() => _applyGst = v),
                      ),
                    ),
                    if (_applyGst)
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _gst,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'GST %'),
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Discount (₹)'),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _row('Subtotal', money(_subtotal)),
                      if (_applyGst) _row('GST (${_gst.text}%)', money(_tax)),
                      if (_d(_discount.text) > 0)
                        _row('Discount', '- ${money(_d(_discount.text))}'),
                      const Divider(),
                      _row('Grand Total', money(_grand), bold: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Working...' : 'Save Draft'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _submitForReview,
                      child: const Text('Submit for Review'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            l,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final _Line line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _title = TextEditingController(text: widget.line.title);
  late final _qty = TextEditingController(text: '${widget.line.quantity}');
  late final _unit = TextEditingController(text: widget.line.unit);
  late final _price = TextEditingController(text: '${widget.line.unitPrice}');

  @override
  void dispose() {
    _title.dispose();
    _qty.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              DropdownButton<String>(
                value: const ['LABOR', 'PART', 'GAS', 'OTHER'].contains(l.type)
                    ? l.type
                    : 'LABOR',
                items: [
                  for (final t in const ['LABOR', 'PART', 'GAS', 'OTHER'])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) {
                  l.type = v ?? l.type;
                  widget.onChanged();
                },
              ),
              const Spacer(),
              Text(
                money(l.total),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          TextField(
            controller: _title,
            onChanged: (v) => l.title = v,
            decoration: const InputDecoration(
              labelText: 'Service / Component title',
            ),
          ),
          if (l.category.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Category: ${l.category}',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    l.quantity = double.tryParse(v) ?? 0;
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _unit,
                  onChanged: (v) => l.unit = v,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    l.unitPrice = double.tryParse(v) ?? 0;
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'Unit ₹'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
