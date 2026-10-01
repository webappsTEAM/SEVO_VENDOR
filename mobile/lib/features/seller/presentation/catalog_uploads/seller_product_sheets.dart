import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/photo_source_sheet.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Product status labels / colours (Web `STATUS_CONFIG`).
const sellerProductStatuses = <(String, String)>[
  ('ALL', 'All Statuses'),
  ('DRAFT', 'Draft'),
  ('SUBMITTED', 'Awaiting approval'),
  ('UNDER_REVIEW', 'Under review'),
  ('CHANGES_REQUESTED', 'Changes requested'),
  ('APPROVED', 'Approved'),
  ('REJECTED', 'Rejected'),
  ('PAUSED', 'Paused'),
];

class SellerProductStatusBadge extends StatelessWidget {
  const SellerProductStatusBadge(this.status, {super.key});

  final String status;

  static Color colorFor(String status) => switch (status) {
    'APPROVED' => const Color(0xFF059669),
    'SUBMITTED' || 'UNDER_REVIEW' => const Color(0xFF2563EB),
    'CHANGES_REQUESTED' => const Color(0xFFEA580C),
    'REJECTED' => const Color(0xFFE11D48),
    'PAUSED' => const Color(0xFFD97706),
    _ => const Color(0xFF475569),
  };

  @override
  Widget build(BuildContext context) {
    final label = sellerProductStatuses
        .firstWhere((s) => s.$1 == status, orElse: () => (status, status))
        .$2;
    return SellerPill(label: label, color: colorFor(status));
  }
}

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
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

Widget _sheetHeader(BuildContext context, String title, {String? subtitle}) {
  return Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
      IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit product: step 1 category picker, step 2 details (Web modal).
// ─────────────────────────────────────────────────────────────────────────────

class SellerProductEditorSheet extends ConsumerStatefulWidget {
  const SellerProductEditorSheet({super.key, this.product});

  /// Null = add a new product (opens on category selection).
  final SellerHubProduct? product;

  /// Returns the server message when saved.
  static Future<String?> show(
    BuildContext context, {
    SellerHubProduct? product,
  }) => _sheet<String>(context, SellerProductEditorSheet(product: product));

  static const units = <(String, String)>[
    ('piece', 'piece'),
    ('pack', 'pack'),
    ('g', 'g (Grams)'),
    ('kg', 'kg (Kilograms)'),
    ('ml', 'ml (Millilitres)'),
    ('litre', 'litre (Litres)'),
    ('box', 'box'),
    ('bottle', 'bottle'),
    ('can', 'can'),
    ('bunch', 'bunch'),
  ];

  @override
  ConsumerState<SellerProductEditorSheet> createState() =>
      _SellerProductEditorSheetState();
}

class _SellerProductEditorSheetState
    extends ConsumerState<SellerProductEditorSheet> {
  late int _step = widget.product == null ? 1 : 2;

  // Category picker (step 1).
  final List<SellerCatalogPickerCategory> _path = [];
  List<SellerCatalogPickerCategory>? _column;
  String? _columnError;
  final _pickerSearch = TextEditingController();
  Timer? _searchDebounce;
  List<SellerCatalogPickerCategory>? _searchResults;
  int? _categoryId;
  String? _categoryLabel;

  // Details (step 2).
  final _title = TextEditingController();
  final _sku = TextEditingController();
  final _brand = TextEditingController();
  final _barcode = TextEditingController();
  final _mrp = TextEditingController();
  final _price = TextEditingController();
  final _tax = TextEditingController(text: '0.00');
  final _hsn = TextEditingController();
  final _packSize = TextEditingController(text: '1');
  final _storage = TextEditingController();
  final _expiry = TextEditingController();
  final _imageUrl = TextEditingController();
  final _description = TextEditingController();
  String _unit = 'piece';
  Map<String, String> _errors = {};
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _categoryId = p.categoryId;
      _categoryLabel =
          p.categoryPath ??
          p.categoryName ??
          (p.categoryId == null ? null : 'Category #${p.categoryId}');
      _title.text = p.title;
      _sku.text = p.sku;
      _brand.text = p.brand ?? '';
      _barcode.text = p.barcode ?? '';
      _mrp.text = p.mrp > 0 ? p.mrp.toStringAsFixed(2) : '';
      _price.text = p.sellingPrice > 0 ? p.sellingPrice.toStringAsFixed(2) : '';
      _tax.text = p.taxRate.toStringAsFixed(2);
      _hsn.text = p.hsnCode ?? '';
      _packSize.text = p.packSize ?? '1';
      _storage.text = p.storageInfo ?? '';
      _expiry.text = p.expiryInfo ?? '';
      _imageUrl.text = p.primaryImage ?? '';
      _description.text = p.description ?? '';
      final unit = p.unit ?? 'piece';
      _unit = SellerProductEditorSheet.units.any((u) => u.$1 == unit)
          ? unit
          : 'piece';
    } else {
      _loadColumn(null);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    for (final c in [
      _pickerSearch,
      _title,
      _sku,
      _brand,
      _barcode,
      _mrp,
      _price,
      _tax,
      _hsn,
      _packSize,
      _storage,
      _expiry,
      _imageUrl,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  Future<void> _loadColumn(int? parentId) async {
    setState(() {
      _column = null;
      _columnError = null;
    });
    try {
      final list = await _repo.getCatalogPickerCategories(parentId: parentId);
      if (mounted) setState(() => _column = list);
    } catch (e) {
      if (mounted)
        setState(
          () => _columnError = e is SellerHubException
              ? e.message
              : 'Network connection failed',
        );
    }
  }

  void _onPickerSearch(String text) {
    _searchDebounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() => _searchResults = null);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await _repo.getCatalogPickerCategories(query: q);
        if (mounted && _pickerSearch.text.trim() == q)
          setState(() => _searchResults = results);
      } catch (_) {
        if (mounted) setState(() => _searchResults = const []);
      }
    });
  }

  void _openCategory(SellerCatalogPickerCategory c) {
    if (c.hasChildren) {
      setState(() {
        _path.add(c);
        _categoryId = null;
        _categoryLabel = null;
      });
      _loadColumn(c.id);
    } else {
      setState(() {
        _categoryId = c.id;
        _categoryLabel =
            c.pathString ?? [..._path.map((p) => p.name), c.name].join(' > ');
      });
    }
  }

  void _goUp(int depth) {
    setState(() {
      _path.removeRange(depth, _path.length);
      _categoryId = null;
      _categoryLabel = null;
    });
    _loadColumn(depth == 0 ? null : _path[depth - 1].id);
  }

  Future<void> _uploadPhoto() async {
    final path = await pickJobPhoto(context);
    if (path == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _repo.uploadProductImage(path);
      if (mounted) setState(() => _imageUrl.text = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              e is SellerHubException ? e.message : 'Image upload failed',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Map<String, String> _validate(bool submitNow) {
    final errors = <String, String>{};
    final mrp = double.tryParse(_mrp.text.trim()) ?? 0;
    final price = double.tryParse(_price.text.trim()) ?? 0;
    if (_title.text.trim().isEmpty)
      errors['title'] = 'Product title is required';
    if (_sku.text.trim().isEmpty) errors['sku'] = 'SKU is required';
    if (_categoryId == null) errors['category'] = 'Category is required';
    if (mrp <= 0) errors['mrp'] = 'Valid MRP is required';
    if (price <= 0) errors['selling_price'] = 'Valid selling price is required';
    if (price > mrp)
      errors['selling_price'] = 'Selling price cannot exceed MRP';
    if (submitNow && _imageUrl.text.trim().isEmpty) {
      errors['images'] =
          'At least one product image is required to submit for review';
    }
    return errors;
  }

  Future<void> _save(bool submitNow) async {
    final errors = _validate(submitNow);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final existing = widget.product;
    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'brand': _brand.text.trim(),
      'sku': _sku.text.trim(),
      'barcode': _barcode.text.trim(),
      'category': _categoryId,
      'unit': _unit,
      'pack_size': _packSize.text.trim(),
      'mrp': _mrp.text.trim(),
      'selling_price': _price.text.trim(),
      'tax_rate': _tax.text.trim().isEmpty ? '0.00' : _tax.text.trim(),
      'hsn_code': _hsn.text.trim(),
      'storage_info': _storage.text.trim(),
      'expiry_info': _expiry.text.trim(),
      'description': _description.text.trim(),
      'images': [if (_imageUrl.text.trim().isNotEmpty) _imageUrl.text.trim()],
      'status': submitNow ? 'SUBMITTED' : (existing?.status ?? 'DRAFT'),
    };
    setState(() => _busy = true);
    try {
      final message = await _repo.saveProduct(payload, productId: existing?.id);
      if (mounted)
        Navigator.of(context).pop(message ?? 'Product saved successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text(
            e is SellerHubException ? e.message : 'Failed to save product',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _sheetHeader(
              context,
              widget.product == null ? 'Add Single Product' : 'Edit Product',
              subtitle: _step == 1
                  ? 'Step 1 of 2 · Select Category'
                  : 'Step 2 of 2 · Add Product Details',
            ),
            const SizedBox(height: 10),
            if (_step == 1) ..._buildPicker() else ..._buildDetails(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPicker() {
    final results = _searchResults;
    return [
      TextField(
        controller: _pickerSearch,
        onChanged: _onPickerSearch,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, size: 18),
          hintText: 'Search Category (Try Milk, Rice, Oil, Vegetables, Biscuits and more...)',
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      if (results != null) ...[
        if (results.isEmpty)
          Text(
            'No categories matched your search.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        for (final c in results)
          ListTile(
            dense: true,
            enabled: c.isLeaf,
            leading: Icon(
              c.isLeaf ? Icons.label_outline_rounded : Icons.folder_outlined,
              size: 18,
            ),
            title: Text(c.name),
            subtitle: c.pathString == null
                ? null
                : Text(c.pathString!, style: const TextStyle(fontSize: 11)),
            trailing: c.isLeaf
                ? null
                : const Text(
                    'Has Subcategories',
                    style: TextStyle(fontSize: 10.5),
                  ),
            selected: _categoryId == c.id,
            onTap: () => setState(() {
              _categoryId = c.id;
              _categoryLabel = c.pathString ?? c.name;
              _pickerSearch.clear();
              _searchResults = null;
            }),
          ),
      ] else ...[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ActionChip(
              label: const Text('All Departments'),
              onPressed: _path.isEmpty ? null : () => _goUp(0),
            ),
            for (var i = 0; i < _path.length; i++) ...[
              const Icon(Icons.chevron_right_rounded, size: 16),
              ActionChip(
                label: Text(_path[i].name),
                onPressed: i == _path.length - 1 ? null : () => _goUp(i + 1),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (_columnError != null)
          SellerStateMessage(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFDC2626),
            title: 'Failed to load categories',
            message: _columnError!,
            actionLabel: 'Refresh categories',
            onAction: () => _loadColumn(_path.isEmpty ? null : _path.last.id),
          )
        else if (_column == null)
          SellerLoading(
            message: _path.isEmpty
                ? 'Loading categories...'
                : 'Loading subcategories...',
          )
        else if (_column!.isEmpty)
          Text(
            _path.isEmpty ? 'No active categories found.' : 'No sub-categories',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          for (final c in _column!)
            ListTile(
              dense: true,
              leading: Icon(
                c.hasChildren
                    ? Icons.folder_outlined
                    : Icons.label_outline_rounded,
                size: 18,
              ),
              title: Text(c.name),
              trailing: c.hasChildren
                  ? const Icon(Icons.chevron_right_rounded)
                  : (_categoryId == c.id
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.emerald,
                          )
                        : null),
              selected: _categoryId == c.id,
              onTap: () => _openCategory(c),
            ),
      ],
      const SizedBox(height: 12),
      if (_categoryLabel != null)
        SellerPanel(
          tint: AppColors.emerald,
          child: Text(
            'Selected: $_categoryLabel',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: _categoryId == null ? null : () => setState(() => _step = 2),
        child: const Text('Continue to Product Details'),
      ),
    ];
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? errorKey,
    bool decimal = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: decimal
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: _errors[errorKey],
          isDense: true,
        ),
      ),
    );
  }

  List<Widget> _buildDetails() {
    final image = AppConfig.resolveMediaUrl(
      _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
    );
    return [
      SellerPanel(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Category: ${_categoryLabel ?? 'Not selected'}',
                style: TextStyle(
                  fontSize: 12,
                  color: _errors['category'] != null
                      ? const Color(0xFFDC2626)
                      : null,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _step = 1);
                if (_column == null)
                  _loadColumn(_path.isEmpty ? null : _path.last.id);
              },
              child: const Text('Change category'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _field(
        _title,
        'Product Title *',
        hint: 'e.g. Fortune Sunlite Refined Sunflower Oil 1L',
        errorKey: 'title',
      ),
      _field(_sku, 'SKU *', hint: 'e.g. FORT-SUN-1L', errorKey: 'sku'),
      _field(_brand, 'Brand Name', hint: 'e.g. Fortune, Tata, Aashirvaad'),
      _field(_barcode, 'Barcode (EAN / UPC)', hint: 'e.g. 8901234567890'),
      Row(
        children: [
          Expanded(
            child: _field(
              _mrp,
              'MRP (₹) *',
              hint: '180.00',
              errorKey: 'mrp',
              decimal: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _field(
              _price,
              'Selling Price (₹) *',
              hint: '165.00',
              errorKey: 'selling_price',
              decimal: true,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _field(
              _tax,
              'GST Tax Rate (%)',
              hint: '5.00',
              decimal: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _field(_hsn, 'HSN Code', hint: '1512')),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  isDense: true,
                ),
                items: [
                  for (final (v, l) in SellerProductEditorSheet.units)
                    DropdownMenuItem(value: v, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _field(
              _packSize,
              'Pack Size / Value',
              hint: 'e.g. 1L, 500g, Pack of 3',
            ),
          ),
        ],
      ),
      _field(
        _storage,
        'Storage Instructions',
        hint: 'e.g. Store in a cool and dry place away from heat',
      ),
      _field(
        _expiry,
        'Expiry / Shelf Life Info',
        hint: 'e.g. Best before 9 months from date of packaging',
      ),
      Text(
        'Product Image',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: _uploading ? null : _uploadPhoto,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded, size: 16),
            label: const Text('Upload Photo File'),
          ),
          const SizedBox(width: 10),
          if (image != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    image,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(Icons.broken_image),
                    ),
                  ),
                ),
                Positioned(
                  right: -8,
                  top: -8,
                  child: IconButton(
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    onPressed: () => setState(() => _imageUrl.clear()),
                  ),
                ),
              ],
            ),
        ],
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _imageUrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'or paste a direct web image URL',
            hintText: 'https://example.com/product-image.jpg',
            errorText: _errors['images'],
            isDense: true,
          ),
        ),
      ),
      _field(
        _description,
        'Detailed Product Description',
        hint: 'Enter detailed description, ingredients, benefits...',
        maxLines: 3,
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          if (widget.product == null)
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Back to Categories'),
            ),
          const Spacer(),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(false),
            child: const Text('Save as Draft'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : () => _save(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit for Review'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product detail & audit history
// ─────────────────────────────────────────────────────────────────────────────

class SellerProductDetailSheet extends ConsumerWidget {
  const SellerProductDetailSheet({super.key, required this.productId});

  final int productId;

  static Future<void> show(BuildContext context, int productId) =>
      _sheet<void>(context, SellerProductDetailSheet(productId: productId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => FutureBuilder<SellerProductDetail>(
        future: ref
            .read(sellerHubRepositoryProvider)
            .getProductDetail(productId),
        builder: (context, snap) {
          final children = <Widget>[
            _sheetHeader(context, 'Product Detail & Audit History'),
          ];
          if (snap.connectionState != ConnectionState.done) {
            children.add(const SellerLoading(message: 'Loading product...'));
          } else if (snap.hasError) {
            final err = snap.error;
            children.add(
              SellerStateMessage(
                icon: Icons.error_outline_rounded,
                color: const Color(0xFFDC2626),
                title: 'Unable to load product',
                message: err is SellerHubException
                    ? err.message
                    : 'Please try again.',
              ),
            );
          } else {
            final d = snap.data!;
            final p = d.product;
            final img = AppConfig.resolveMediaUrl(
              d.imageUrls.isNotEmpty ? d.imageUrls.first : p.primaryImage,
            );
            children.addAll([
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 72,
                      height: 72,
                      color: AppColors.surfaceMuted,
                      child: img == null
                          ? const Icon(Icons.image_outlined)
                          : Image.network(
                              img,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.image_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'SKU: ${p.sku}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '₹${p.sellingPrice.toStringAsFixed(2)}  ·  MRP ₹${p.mrp.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (p.categoryPath != null)
                          Text(
                            p.categoryPath!,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (p.barcode != null)
                          Text(
                            'Scannable Barcode: ${p.barcode}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        const SizedBox(height: 4),
                        SellerProductStatusBadge(p.status),
                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Platform catalog review (admins)
// ─────────────────────────────────────────────────────────────────────────────

class SellerProductReviewSheet extends ConsumerStatefulWidget {
  const SellerProductReviewSheet({super.key, required this.product});

  final SellerHubProduct product;

  /// Returns the server message on success.
  static Future<String?> show(BuildContext context, SellerHubProduct product) =>
      _sheet<String>(context, SellerProductReviewSheet(product: product));

  static const actions = <(String, String)>[
    ('approve', 'Approve & Publish'),
    ('request_changes', 'Request Changes'),
    ('reject', 'Reject Item'),
    ('pause', 'Pause Product'),
  ];

  @override
  ConsumerState<SellerProductReviewSheet> createState() =>
      _SellerProductReviewSheetState();
}

class _SellerProductReviewSheetState
    extends ConsumerState<SellerProductReviewSheet> {
  String _action = 'approve';
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _noteRequired => _action != 'approve';

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final message = await ref
          .read(sellerHubRepositoryProvider)
          .reviewProduct(widget.product.id, _action, _note.text);
      if (mounted)
        Navigator.of(context).pop(message ?? 'Review decision recorded.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text(
            e is SellerHubException
                ? e.message
                : 'Failed to execute review decision',
          ),
        ),
      );
    }
  }

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
            _sheetHeader(
              context,
              'Platform Catalog Review',
              subtitle: widget.product.title,
            ),
            const SizedBox(height: 10),
            const Text(
              'Select Review Decision',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (id, label) in SellerProductReviewSheet.actions)
                  ChoiceChip(
                    label: Text(label),
                    selected: _action == id,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _action = id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _noteRequired
                    ? 'Feedback note *'
                    : 'Feedback note (optional)',
                hintText: 'Explain clearly what changes are needed or why this item was rejected...',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || (_noteRequired && _note.text.trim().isEmpty)
                    ? null
                    : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm Decision'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
