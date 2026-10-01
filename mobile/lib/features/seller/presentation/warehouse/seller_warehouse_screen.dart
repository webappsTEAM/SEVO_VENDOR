import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../locations/presentation/widgets/location_picker_map.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Fulfillment Warehouses (Web parity: `AdminWarehousesPage.jsx`, route
/// `/workforce/admin/seller-hub/warehouses`).
class SellerWarehouseScreen extends ConsumerStatefulWidget {
  const SellerWarehouseScreen({super.key});

  @override
  ConsumerState<SellerWarehouseScreen> createState() =>
      _SellerWarehouseScreenState();
}

class _SellerWarehouseScreenState extends ConsumerState<SellerWarehouseScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _status = 'all';
  String _city = 'all';
  List<SellerWarehouse> _warehouses = const [];

  /// Cities seen across loads, so the filter keeps its options while filtered.
  final Set<String> _cities = {};
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
      final list = await _repo.getWarehouses(
        search: _search.text,
        city: _city == 'all' ? null : _city,
        isActive: _status == 'all' ? null : _status == 'active',
      );
      if (mounted && seq == _seq) {
        setState(() {
          _warehouses = list;
          _cities.addAll(
            list
                .map((w) => w.city)
                .whereType<String>()
                .where((c) => c.isNotEmpty),
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to fetch warehouse facilities.';
        });
      }
    }
  }

  Future<void> _openForm([SellerWarehouse? editing]) async {
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
      builder: (_) => _WarehouseFormSheet(editing: editing),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggleActive(SellerWarehouse wh) async {
    if (wh.isActive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            'Are you sure you want to deactivate "${wh.name}"? Merchants assigned to this facility '
            "won't be able to dispatch orders until reassigned.",
          ),
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
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      if (wh.isActive) {
        await _repo.deactivateWarehouse(wh.id);
      } else {
        await _repo.saveWarehouse({'is_active': true}, id: wh.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              e is SellerHubException
                  ? e.message
                  : 'Failed to toggle warehouse active state.',
            ),
          ),
        );
      }
    }
  }

  void _openDetail(SellerWarehouse wh) {
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
      builder: (_) => _WarehouseDetailSheet(warehouseId: wh.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _warehouses.where((w) => w.isActive).length;
    final merchants = _warehouses.fold<int>(
      0,
      (sum, w) => sum + w.assignedSellersCount,
    );
    final cities = _cities.toList()..sort();
    return SevoModuleFrame(
      module: SevoModule.warehouses,
      title: 'Fulfillment Warehouses',
      subtitle: 'Platform Regional Hubs & Dispatch Pickup Coordinates Master',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.warehouse_rounded,
                title: 'Fulfillment Warehouses',
                iconColor: const Color(0xFF4F46E5),
                description: 'Platform Regional Hubs & Dispatch Pickup Coordinates Master',
                actions: [
                  SellerHeaderAction(
                    label: 'Add Warehouse',
                    icon: Icons.add_rounded,
                    primary: true,
                    onPressed: () => _openForm(),
                  ),
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerTileGrid(
                minTileWidth: 110,
                children: [
                  SellerMetricTile(
                    label: 'Total Facilities',
                    value: '${_warehouses.length}',
                    caption: 'Registered hubs',
                    icon: Icons.apartment_rounded,
                    color: const Color(0xFF4F46E5),
                  ),
                  SellerMetricTile(
                    label: 'Active Facilities',
                    value: '$active',
                    caption: 'Dispatch enabled',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.emerald,
                  ),
                  SellerMetricTile(
                    label: 'Assigned Merchants',
                    value: '$merchants',
                    caption: 'Linked stores',
                    icon: Icons.storefront_outlined,
                    color: const Color(0xFFD97706),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerSearchField(
                controller: _search,
                hint: 'Search warehouse by name, code, address, city...',
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), _load);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: SellerDropdownFilter(
                      value: _city,
                      options: [
                        ('all', 'All Cities'),
                        for (final c in cities) (c, c),
                      ],
                      onChanged: (v) {
                        setState(() => _city = v);
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SellerDropdownFilter(
                      value: _status,
                      options: const [
                        ('all', 'All Statuses'),
                        ('active', 'Active Only'),
                        ('inactive', 'Inactive Only'),
                      ],
                      onChanged: (v) {
                        setState(() => _status = v);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const SellerLoading(message: 'Loading warehouse facilities...')
              else if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Unable to load warehouses',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (_warehouses.isEmpty)
                const SellerStateMessage(
                  icon: Icons.warehouse_outlined,
                  title: 'No Warehouses Found',
                  message:
                      'No fulfillment facilities match the current filters.',
                )
              else
                for (final wh in _warehouses) _card(wh),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(SellerWarehouse wh) {
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
          InkWell(
            onTap: () => _openDetail(wh),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wh.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        [
                          wh.code,
                          wh.contactPhone,
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                SellerPill(
                  label: wh.isActive ? 'Active' : 'Inactive',
                  color: wh.isActive
                      ? AppColors.emerald
                      : const Color(0xFF64748B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SellerKeyValue(
            'City / Region',
            [wh.city ?? '—', wh.region ?? '—'].join(' · '),
          ),
          SellerKeyValue('Address', wh.address ?? '—'),
          SellerKeyValue(
            'GPS',
            wh.hasGps
                ? '${wh.latitude!.toStringAsFixed(4)}, ${wh.longitude!.toStringAsFixed(4)}'
                : 'Missing GPS Pin',
          ),
          SellerKeyValue('Merchants', '${wh.assignedSellersCount}'),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _openDetail(wh),
                child: const Text('Details'),
              ),
              TextButton(
                onPressed: () => _openForm(wh),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () => _toggleActive(wh),
                style: TextButton.styleFrom(
                  foregroundColor: wh.isActive
                      ? const Color(0xFFDC2626)
                      : AppColors.emerald,
                ),
                child: Text(wh.isActive ? 'Deactivate' : 'Activate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarehouseDetailSheet extends ConsumerWidget {
  const _WarehouseDetailSheet({required this.warehouseId});

  final int warehouseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => FutureBuilder<SellerWarehouse>(
        future: ref
            .read(sellerHubRepositoryProvider)
            .getWarehouseDetail(warehouseId),
        builder: (context, snap) {
          final children = <Widget>[];
          if (snap.connectionState != ConnectionState.done) {
            children.add(const SellerLoading(message: 'Loading details...'));
          } else if (snap.hasError) {
            children.add(
              const Text(
                'Failed to load warehouse details.',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
            );
          } else {
            final wh = snap.data!;
            children.addAll([
              Row(
                children: [
                  Expanded(
                    child: Text(
                      wh.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SellerPill(
                    label: wh.isActive ? 'Active' : 'Inactive',
                    color: wh.isActive
                        ? AppColors.emerald
                        : const Color(0xFF64748B),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SellerKeyValue('Address', wh.address ?? '—'),
              SellerKeyValue('City', wh.city ?? '—'),
              SellerKeyValue('Region', wh.region ?? '—'),
              SellerKeyValue(
                'GPS',
                wh.hasGps
                    ? '${wh.latitude!.toStringAsFixed(6)}, ${wh.longitude!.toStringAsFixed(6)}'
                    : 'Missing GPS Pin',
              ),
              SellerSectionLabel('Assigned Merchants (${wh.sellers.length})'),
              if (wh.sellers.isEmpty)
                Text(
                  'No merchants are currently assigned to this warehouse.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                for (final s in wh.sellers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(s.name),
                    subtitle: Text(
                      [
                        if (s.slug != null) s.slug!,
                        if (s.address != null) s.address!,
                        if (s.assignedAt != null)
                          'Assigned ${formatSellerDate(s.assignedAt)}',
                      ].join(' · '),
                    ),
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

class _WarehouseFormSheet extends ConsumerStatefulWidget {
  const _WarehouseFormSheet({this.editing});

  final SellerWarehouse? editing;

  @override
  ConsumerState<_WarehouseFormSheet> createState() =>
      _WarehouseFormSheetState();
}

class _WarehouseFormSheetState extends ConsumerState<_WarehouseFormSheet> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _code = TextEditingController(text: widget.editing?.code ?? '');
  late final _address = TextEditingController(
    text: widget.editing?.address ?? '',
  );
  late final _city = TextEditingController(
    text: widget.editing?.city ?? (widget.editing == null ? 'Bangalore' : ''),
  );
  late final _region = TextEditingController(
    text: widget.editing?.region ?? (widget.editing == null ? 'Karnataka' : ''),
  );
  late final _phone = TextEditingController(
    text: widget.editing?.contactPhone ?? '',
  );
  // Web defaults the pin to Bangalore centre.
  late double _lat = widget.editing?.latitude ?? 12.9716;
  late double _lng = widget.editing?.longitude ?? 77.5946;
  late bool _active = widget.editing?.isActive ?? true;
  final Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _code, _address, _city, _region, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    _errors.clear();
    if (_name.text.trim().isEmpty)
      _errors['name'] = 'Warehouse facility name is required.';
    if (_address.text.trim().isEmpty)
      _errors['address'] = 'Street address is required.';
    if (_errors.isNotEmpty) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(sellerHubRepositoryProvider).saveWarehouse({
        'name': _name.text.trim(),
        'code': _code.text.trim().isEmpty ? null : _code.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'region': _region.text.trim(),
        'contact_phone': _phone.text.trim(),
        'latitude': double.parse(_lat.toStringAsFixed(7)),
        'longitude': double.parse(_lng.toStringAsFixed(7)),
        'is_active': _active,
      }, id: widget.editing?.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errors['general'] = e is SellerHubException
              ? e.message
              : 'Failed to save warehouse facility.';
        });
      }
    }
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    String? errorKey,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: _errors[errorKey],
          isDense: true,
        ),
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
                    widget.editing == null ? 'Add Warehouse' : 'Edit Warehouse',
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
            _field(
              _name,
              'Warehouse Facility *',
              'e.g. Central Bangalore Hub',
              errorKey: 'name',
            ),
            _field(_code, 'Code', 'e.g. WH-BLR-01'),
            _field(
              _address,
              'Physical Street Address *',
              'Full street address and landmark for rider navigation',
              errorKey: 'address',
              maxLines: 2,
            ),
            Row(
              children: [
                Expanded(child: _field(_city, 'City', 'e.g. Bangalore')),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(_region, 'Region / State', 'e.g. Karnataka'),
                ),
              ],
            ),
            _field(_phone, 'Contact Phone', 'e.g. +91 98765 43210'),
            const Text(
              'GPS Pickup Coordinates',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            LocationPickerMap(
              latitude: _lat,
              longitude: _lng,
              height: 220,
              onPositionChange: (lat, lng) => setState(() {
                _lat = lat;
                _lng = lng;
              }),
            ),
            const SizedBox(height: 6),
            Text(
              '${_lat.toStringAsFixed(6)}, ${_lng.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Active for rider dispatch and seller order pickups',
                style: TextStyle(fontSize: 13),
              ),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_errors['general'] != null) ...[
              Text(
                _errors['general']!,
                style: const TextStyle(color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving...'
                    : (widget.editing == null
                          ? 'Create Warehouse'
                          : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
