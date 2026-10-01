import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Promotional Coupons (Web parity: `AdminSellerCouponsPage.jsx`, route
/// `/workforce/admin/seller-hub/coupons`).
class SellerCouponsScreen extends ConsumerStatefulWidget {
  const SellerCouponsScreen({super.key});

  @override
  ConsumerState<SellerCouponsScreen> createState() =>
      _SellerCouponsScreenState();
}

class _SellerCouponsScreenState extends ConsumerState<SellerCouponsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _status = 'all';
  String _type = 'all';
  List<SellerHubCoupon> _coupons = const [];
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

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.getCoupons(
        search: _search.text,
        status: _status,
        discountType: _type,
      );
      if (mounted && seq == _seq) {
        setState(() {
          _coupons = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to load coupons';
        });
      }
    }
  }

  Future<void> _openForm([SellerHubCoupon? editing]) async {
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
      builder: (_) => _CouponFormSheet(editing: editing),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggle(SellerHubCoupon c) async {
    try {
      await _repo.saveCoupon({'is_active': !c.isActive}, id: c.id);
      await _load();
    } catch (e) {
      _snack(
        e is SellerHubException ? e.message : 'Failed to update coupon status',
        error: true,
      );
    }
  }

  Future<void> _delete(SellerHubCoupon c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Coupon'),
        content: Text('Delete coupon ${c.code}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteCoupon(c.id);
      await _load();
    } catch (e) {
      _snack(
        e is SellerHubException ? e.message : 'Failed to delete coupon',
        error: true,
      );
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SevoModuleFrame(
      module: SevoModule.coupons,
      title: 'Promotional Coupons',
      subtitle: 'Create and manage discount codes, percentage vouchers, and customer incentives.',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.local_offer_rounded,
                title: 'Promotional Coupons',
                badge: 'Seller Hub / Coupons & Promotions',
                iconColor: const Color(0xFF4F46E5),
                description: 'Create and manage discount codes, percentage vouchers, and customer incentives.',
                actions: [
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _load,
                  ),
                  SellerHeaderAction(
                    label: 'Create Coupon',
                    icon: Icons.add_rounded,
                    primary: true,
                    onPressed: () => _openForm(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerSearchField(
                controller: _search,
                hint: 'Search coupon code, description...',
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), _load);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerFilterChips(
                options: const [
                  ('all', 'All Status'),
                  ('active', 'Active'),
                  ('expired', 'Expired'),
                  ('inactive', 'Disabled'),
                ],
                selected: _status,
                onSelected: (v) {
                  setState(() => _status = v);
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerDropdownFilter(
                value: _type,
                options: const [
                  ('all', 'All Discount Types'),
                  ('percent', 'Percentage (%)'),
                  ('flat', 'Flat Amount (₹)'),
                ],
                onChanged: (v) {
                  setState(() => _type = v);
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const SellerLoading(
                  message: 'Loading coupons and promotions...',
                )
              else if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Error loading coupons',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (_coupons.isEmpty)
                SellerStateMessage(
                  icon: Icons.local_offer_outlined,
                  title: 'No coupons found',
                  message: 'Create a discount code to reward customers.',
                  actionLabel: 'Create Coupon',
                  onAction: () => _openForm(),
                )
              else
                for (final c in _coupons) _card(c),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(SellerHubCoupon c) {
    final status = c.statusAt(DateTime.now());
    final statusColor = switch (status) {
      'Active' => AppColors.emerald,
      'Expired' => const Color(0xFFE11D48),
      _ => const Color(0xFF64748B),
    };
    String money(double v) => '₹${v.toStringAsFixed(2)}';
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
          Row(
            children: [
              Text(
                c.code,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                tooltip: 'Copy code',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: c.code));
                  _snack('Copied ${c.code}');
                },
              ),
              const Spacer(),
              SellerPill(label: status, color: statusColor),
            ],
          ),
          if (c.description != null)
            Text(
              c.description!,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          Text(
            c.companyName ?? 'Platform Universal',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              SellerPill(
                label: c.isPercent
                    ? '${c.discountValue.toStringAsFixed(2)}% OFF'
                    : '${money(c.discountValue)} FLAT',
                color: const Color(0xFF4F46E5),
              ),
              if (c.maxDiscountAmount != null)
                SellerPill(
                  label: 'Capped at ${money(c.maxDiscountAmount!)}',
                  color: const Color(0xFF475569),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SellerKeyValue('Min Order', money(c.minOrderAmount)),
          SellerKeyValue('Per User', '${c.usageLimitPerUser}x'),
          SellerKeyValue(
            'Usage',
            '${c.timesUsed} / ${c.usageLimitTotal?.toString() ?? '∞'}',
          ),
          SellerKeyValue(
            'Validity',
            c.validUntil == null
                ? 'No Expiry Date'
                : 'Until ${formatSellerTimestamp(c.validUntil)}',
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Switch(value: c.isActive, onChanged: (_) => _toggle(c)),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _openForm(c),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Color(0xFFDC2626),
                ),
                onPressed: () => _delete(c),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CouponFormSheet extends ConsumerStatefulWidget {
  const _CouponFormSheet({this.editing});

  final SellerHubCoupon? editing;

  @override
  ConsumerState<_CouponFormSheet> createState() => _CouponFormSheetState();
}

class _CouponFormSheetState extends ConsumerState<_CouponFormSheet> {
  late final _code = TextEditingController(text: widget.editing?.code ?? '');
  late final _description = TextEditingController(
    text: widget.editing?.description ?? '',
  );
  late String _type = widget.editing?.discountType ?? 'percent';
  late final _value = TextEditingController(
    text: widget.editing == null ? '10' : _fmt(widget.editing!.discountValue),
  );
  late final _minOrder = TextEditingController(
    text: _fmt(widget.editing?.minOrderAmount ?? 0),
  );
  late final _maxDiscount = TextEditingController(
    text: widget.editing?.maxDiscountAmount == null
        ? ''
        : _fmt(widget.editing!.maxDiscountAmount!),
  );
  late final _limitTotal = TextEditingController(
    text: widget.editing?.usageLimitTotal?.toString() ?? '',
  );
  late final _limitPerUser = TextEditingController(
    text: '${widget.editing?.usageLimitPerUser ?? 1}',
  );
  late DateTime? _validFrom = widget.editing?.validFrom;
  late DateTime? _validUntil = widget.editing?.validUntil;
  late bool _active = widget.editing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  static String _fmt(double v) => v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [
      _code,
      _description,
      _value,
      _minOrder,
      _maxDiscount,
      _limitTotal,
      _limitPerUser,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
  }

  Future<void> _save() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Coupon code is required.');
      return;
    }
    final value = double.tryParse(_value.text.trim()) ?? 0;
    if (value <= 0) {
      setState(() => _error = 'A valid positive discount value is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      'code': _code.text.trim().toUpperCase(),
      'description': _description.text.trim(),
      'discount_type': _type,
      'discount_value': value,
      'min_order_amount': double.tryParse(_minOrder.text.trim()) ?? 0,
      'max_discount_amount': double.tryParse(_maxDiscount.text.trim()),
      'usage_limit_total': int.tryParse(_limitTotal.text.trim()),
      'usage_limit_per_user': int.tryParse(_limitPerUser.text.trim()) ?? 1,
      'valid_from': _validFrom?.toUtc().toIso8601String(),
      'valid_until': _validUntil?.toUtc().toIso8601String(),
      'is_active': _active,
    };
    try {
      await ref
          .read(sellerHubRepositoryProvider)
          .saveCoupon(payload, id: widget.editing?.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to save coupon';
        });
      }
    }
  }

  Widget _num(
    TextEditingController c,
    String label,
    String hint, {
    bool decimal = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(decimal ? r'[0-9.]' : r'[0-9]'),
          ),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateButton(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await _pickDateTime(value);
        if (picked != null) onChanged(picked);
      },
      onLongPress: () => onChanged(null),
      child: Text(
        '$label: ${value == null ? 'None' : formatSellerDateTime(value)}',
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  child: Text(
                    widget.editing == null ? 'Create Coupon' : 'Edit Coupon',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Coupon Code *',
                hintText: 'e.g. WELCOME20, FESTIVE100',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description / Customer Note',
                hintText: 'e.g. 20% discount on orders above ₹500',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Discount Type',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text('Percentage (%)'),
                      ),
                      DropdownMenuItem(
                        value: 'flat',
                        child: Text('Flat Amount (₹)'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _num(
                    _value,
                    _type == 'percent' ? 'Discount (%) *' : 'Discount (₹) *',
                    '10',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _num(_minOrder, 'Min Order Amount (₹)', '0.00'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _num(
                    _maxDiscount,
                    'Max Discount Cap (₹)',
                    'Leave blank for no upper limit',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _num(
                    _limitTotal,
                    'Total Usage Limit',
                    'Unlimited (Leave blank)',
                    decimal: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _num(
                    _limitPerUser,
                    'Limit Per Customer',
                    '1',
                    decimal: false,
                  ),
                ),
              ],
            ),
            _dateButton(
              'Valid From',
              _validFrom,
              (v) => setState(() => _validFrom = v),
            ),
            const SizedBox(height: 6),
            _dateButton(
              'Valid Until (Expiry)',
              _validUntil,
              (v) => setState(() => _validUntil = v),
            ),
            Text(
              'Long-press a date to clear it.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Coupon Active and Redeemable'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving...'
                    : (widget.editing == null
                          ? 'Create Coupon'
                          : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
