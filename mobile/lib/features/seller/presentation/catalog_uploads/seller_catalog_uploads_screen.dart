import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../seller_hub_providers.dart';
import '../widgets/seller_hub_widgets.dart';
import 'seller_product_sheets.dart';

/// Catalog Uploads & Products (Web parity: `SellerCatalogUploadsPage.jsx`,
/// route `/workforce/seller-hub/catalog-uploads`).
class SellerCatalogUploadsScreen extends ConsumerStatefulWidget {
  const SellerCatalogUploadsScreen({super.key});

  @override
  ConsumerState<SellerCatalogUploadsScreen> createState() =>
      _SellerCatalogUploadsScreenState();
}

enum _CatalogTab { catalog, bulk, batches }

class _SellerCatalogUploadsScreenState
    extends ConsumerState<SellerCatalogUploadsScreen> {
  _CatalogTab _tab = _CatalogTab.catalog;
  String _status = 'ALL';
  String _category = '';
  final _searchController = TextEditingController();

  List<SellerHubProduct> _products = const [];
  List<SellerActiveCategory> _categories = const [];
  List<SellerCatalogUploadBatch> _batches = const [];
  bool _loading = true;
  String? _error;

  // Bulk feed.
  PlatformFile? _file;
  Uint8List? _fileBytes;
  SellerBulkPreview? _preview;
  bool _previewing = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _fetchData(refreshMetrics: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  /// Products, categories, metrics and batches in parallel (as the Web does).
  /// Metrics come from the watched provider; it is only invalidated on
  /// refresh (the first watch already fetches it).
  Future<void> _fetchData({bool refreshMetrics = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (refreshMetrics) ref.invalidate(sellerHubMetricsProvider);
    try {
      final results = await Future.wait<Object>([
        _repo.getProducts(),
        _repo.getActiveCategories().catchError((_) => <SellerActiveCategory>[]),
        _repo.getProductBatches().catchError(
          (_) => <SellerCatalogUploadBatch>[],
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<SellerHubProduct>;
        _categories = results[1] as List<SellerActiveCategory>;
        _batches = results[2] as List<SellerCatalogUploadBatch>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SellerHubException
            ? e.message
            : 'Failed to load catalog records';
      });
    }
  }

  void _toast(String? message, {bool error = false}) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(
    Future<String?> Function() action, {
    String? fallbackError,
  }) async {
    try {
      final message = await action();
      _toast(message);
      await _fetchData();
    } catch (e) {
      _toast(
        e is SellerHubException
            ? e.message
            : (fallbackError ?? 'Action failed.'),
        error: true,
      );
    }
  }

  Future<void> _openEditor([SellerHubProduct? product]) async {
    final message = await SellerProductEditorSheet.show(
      context,
      product: product,
    );
    if (message != null) {
      _toast(message);
      await _fetchData();
    }
  }

  Future<void> _submitProduct(SellerHubProduct p) async {
    if (!await _confirm(
      'Are you sure you want to submit this product for catalog review?',
    ))
      return;
    await _run(
      () => _repo.submitProduct(p.id),
      fallbackError: 'Failed to submit product',
    );
  }

  Future<void> _deleteProduct(SellerHubProduct p) async {
    if (!await _confirm(
      "Are you sure you want to delete '${p.title}'? This action cannot be undone.",
    ))
      return;
    await _run(
      () => _repo.deleteProduct(p.id),
      fallbackError: 'Failed to delete product',
    );
  }

  Future<void> _review(SellerHubProduct p) async {
    final message = await SellerProductReviewSheet.show(context, p);
    if (message != null) {
      _toast(message);
      await _fetchData();
    }
  }

  // ── Bulk feed ──────────────────────────────────────────────────────────────

  Future<void> _downloadTemplate() async {
    try {
      final bytes = await _repo.downloadProductTemplate();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/seller_catalog_template.csv');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Seller Hub Catalog Template',
        ),
      );
    } catch (e) {
      _toast(
        e is SellerHubException ? e.message : 'Failed to download template.',
        error: true,
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx', 'xls'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _file = file;
        _fileBytes = bytes;
        _preview = null;
      });
    } catch (e) {
      _toast('Unable to read the selected file.', error: true);
    }
  }

  Future<void> _validatePreview() async {
    final bytes = _fileBytes;
    final file = _file;
    if (bytes == null || file == null) return;
    setState(() => _previewing = true);
    try {
      final preview = await _repo.previewBulkUpload(bytes, file.name);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      _toast(
        e is SellerHubException ? e.message : 'Failed to parse file',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _confirmImport() async {
    final bytes = _fileBytes;
    final file = _file;
    if (bytes == null || file == null) return;
    setState(() => _importing = true);
    try {
      final message = await _repo.importBulkUpload(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _file = null;
        _fileBytes = null;
        _preview = null;
        _tab = _CatalogTab.catalog;
      });
      _toast(message ?? 'Bulk import completed.');
      await _fetchData();
    } catch (e) {
      _toast(
        e is SellerHubException ? e.message : 'Bulk import failed',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  List<SellerHubProduct> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    return _products.where((p) {
      if (_status != 'ALL' && p.status != _status) return false;
      if (_category.isNotEmpty && '${p.categoryId}' != _category) return false;
      if (q.isNotEmpty) {
        final hay = [
          p.title,
          p.sku,
          p.brand ?? '',
          p.barcode ?? '',
        ].map((s) => s.toLowerCase());
        if (!hay.any((s) => s.contains(q))) return false;
      }
      return true;
    }).toList();
  }

  void _showStatus(String status) => setState(() {
    _status = status;
    _tab = _CatalogTab.catalog;
  });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final isAdmin = user?.isAdmin == true;
    final m = ref.watch(sellerHubMetricsProvider).valueOrNull;
    String metric(int Function(SellerHubMetrics) pick) =>
        m == null ? '…' : '${pick(m)}';

    return SevoModuleFrame(
      module: SevoModule.catalogUploads,
      title: 'Catalog Uploads & Products',
      subtitle: 'Single item creator, bulk CSV/Excel feeds, leaf category tagging, and admin verification workflow',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _fetchData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.cloud_upload_rounded,
                title: 'Catalog Uploads & Products',
                iconColor: const Color(0xFF4F46E5),
                description: 'Single item creator, bulk CSV/Excel feeds, leaf category tagging, and admin verification workflow',
                actions: [
                  SellerHeaderAction(
                    label: 'Add Single Product',
                    icon: Icons.add_rounded,
                    primary: true,
                    onPressed: () => _openEditor(),
                  ),
                  SellerHeaderAction(
                    label: 'Bulk Feed',
                    icon: Icons.upload_file_rounded,
                    onPressed: () => setState(() => _tab = _CatalogTab.bulk),
                  ),
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _fetchData,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerTileGrid(
                minTileWidth: 140,
                children: [
                  _tile(
                    'Total Items',
                    metric((m) => m.totalProducts),
                    'All registered',
                    Icons.inventory_2_outlined,
                    const Color(0xFF0F172A),
                    'ALL',
                  ),
                  _tile(
                    'Approved',
                    metric((m) => m.approvedProducts),
                    'Verified & Active',
                    Icons.check_circle_outline_rounded,
                    AppColors.emerald,
                    'APPROVED',
                  ),
                  _tile(
                    'Awaiting Review',
                    metric((m) => m.catalogsAwaitingApproval),
                    'Submitted Queue',
                    Icons.hourglass_top_rounded,
                    const Color(0xFF2563EB),
                    'SUBMITTED',
                  ),
                  _tile(
                    'Action Required',
                    metric((m) => m.changesRequested),
                    'Changes Requested',
                    Icons.edit_note_rounded,
                    const Color(0xFFEA580C),
                    'CHANGES_REQUESTED',
                  ),
                  _tile(
                    'Drafts',
                    metric((m) => m.draftProducts),
                    'Unsubmitted items',
                    Icons.drafts_outlined,
                    const Color(0xFF475569),
                    'DRAFT',
                  ),
                  _tile(
                    'Rejected',
                    metric((m) => m.rejectedProducts),
                    'Format / Compliance',
                    Icons.cancel_outlined,
                    const Color(0xFFE11D48),
                    'REJECTED',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerFilterChips(
                options: [
                  ('catalog', 'Product Catalog (${_products.length})'),
                  ('bulk', 'Bulk CSV / Excel Ingestion'),
                  ('batches', 'Upload Batches (${_batches.length})'),
                ],
                selected: _tab.name,
                selectedColor: const Color(0xFF0F172A),
                onSelected: (v) =>
                    setState(() => _tab = _CatalogTab.values.byName(v)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: isAdmin
                      ? () => context.go(AppRoutes.sellerCategories)
                      : null,
                  icon: const Icon(Icons.layers_outlined, size: 16),
                  label: Text(
                    'Seller Hub Categories (${_categories.length} Leaf Available)',
                  ),
                ),
              ),
              if (_loading)
                const SellerLoading(message: 'Loading store products...')
              else if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Unable to load catalog',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _fetchData,
                )
              else
                ...switch (_tab) {
                  _CatalogTab.catalog => _buildCatalog(isAdmin),
                  _CatalogTab.bulk => _buildBulk(),
                  _CatalogTab.batches => _buildBatches(),
                },
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    String label,
    String value,
    String caption,
    IconData icon,
    Color color,
    String status,
  ) {
    return SellerMetricTile(
      label: label,
      value: value,
      caption: caption,
      icon: icon,
      color: color,
      selected: _status == status && _tab == _CatalogTab.catalog,
      onTap: () => _showStatus(status),
    );
  }

  List<Widget> _buildCatalog(bool isAdmin) {
    final products = _filtered;
    final filtered =
        _searchController.text.trim().isNotEmpty ||
        _status != 'ALL' ||
        _category.isNotEmpty;
    return [
      SellerPanel(
        tint: const Color(0xFF2563EB),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Catalog Approval Notice: Only approved products appear in Inventory. Submitted products require '
                'admin review before opening stock can be managed.',
                style: TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.sellerInventory),
              child: const Text('Inventory →'),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      SellerSearchField(
        controller: _searchController,
        hint: 'Search by Title, SKU, Brand, Barcode...',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: AppSpacing.sm),
      SellerDropdownFilter(
        value: _category,
        options: [
          ('', 'All Categories'),
          for (final c in _categories) ('${c.id}', c.path),
        ],
        onChanged: (v) => setState(() => _category = v),
      ),
      const SizedBox(height: AppSpacing.sm),
      SellerDropdownFilter(
        value: _status,
        options: sellerProductStatuses,
        onChanged: (v) => setState(() => _status = v),
      ),
      const SizedBox(height: AppSpacing.md),
      if (products.isEmpty) ...[
        SellerStateMessage(
          icon: Icons.inventory_2_outlined,
          title: 'No products found',
          message: filtered
              ? 'No products matched your search or status filter criteria.'
              : 'Your store catalog is currently empty. Click below to add your first product or use bulk CSV '
                    'ingestion.',
        ),
        if (!filtered)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              SellerHeaderAction(
                label: 'Add First Product',
                primary: true,
                onPressed: () => _openEditor(),
              ),
              SellerHeaderAction(
                label: 'Upload Bulk File',
                onPressed: () => setState(() => _tab = _CatalogTab.bulk),
              ),
            ],
          ),
      ] else
        for (final p in products)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SellerProductCard(
              product: p,
              isAdmin: isAdmin,
              onDetail: () => SellerProductDetailSheet.show(context, p.id),
              onEdit: () => _openEditor(p),
              onSubmit: () => _submitProduct(p),
              onDelete: () => _deleteProduct(p),
              onReview: () => _review(p),
            ),
          ),
    ];
  }

  List<Widget> _buildBulk() {
    final preview = _preview;
    final file = _file;
    return [
      SellerPanel(
        tint: const Color(0xFF4F46E5),
        title: 'Bulk Catalog Spreadsheet Ingestion',
        subtitle:
            'Download the standardized template, fill in your product catalog items with their leaf category '
            'slugs, pricing, and image URLs, then upload below. Use the preview validator to test for SKU conflicts '
            'or missing leaf categories before importing.',
        child: OutlinedButton.icon(
          onPressed: _downloadTemplate,
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Download CSV Template'),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      SellerPanel(
        child: file == null
            ? Column(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    size: 40,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _pickFile,
                    child: const Text('Choose Catalog File'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Supports CSV, XLSX up to 500 rows per batch',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${file.name}  (${((_fileBytes?.length ?? 0) / 1024).round()} KB)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _previewing ? null : _validatePreview,
                        child: Text(
                          _previewing
                              ? 'Validating File...'
                              : 'Validate & Preview',
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _file = null;
                          _fileBytes = null;
                          _preview = null;
                        }),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      if (preview != null) ...[
        const SellerSectionLabel('Batch Validation Results'),
        Text(
          'Total Rows: ${preview.totalRows} • Valid: ${preview.validRows} • Errors: ${preview.invalidRows}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: !preview.canImport || _importing ? null : _confirmImport,
          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
          child: Text(
            _importing
                ? 'Importing Products...'
                : 'Confirm & Import Valid Rows',
          ),
        ),
        if (preview.errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          SellerPanel(
            tint: const Color(0xFFE11D48),
            title: 'Validation Errors Detected (${preview.errors.length} rows)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in preview.errors)
                  Text(
                    'Row ${e.row} (${e.sku}): ${e.errors.join(', ')}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        for (final item in preview.items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 14,
              child: Text(
                '${item.rowNumber}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            title: Text(item.title),
            subtitle: Text(
              '${item.sku} · ${item.categoryName ?? '—'} · ₹${item.sellingPrice} / ₹${item.mrp}',
            ),
            trailing: SellerPill(
              label: item.hasErrors ? 'Error' : 'Valid',
              color: item.hasErrors
                  ? const Color(0xFFE11D48)
                  : AppColors.emerald,
            ),
          ),
      ],
    ];
  }

  List<Widget> _buildBatches() {
    if (_batches.isEmpty) {
      return const [
        SellerStateMessage(
          icon: Icons.history_rounded,
          title: 'No batch history recorded yet',
          message: 'Uploaded CSV and Excel batches will appear here.',
        ),
      ];
    }
    return [
      const SellerSectionLabel('Bulk Catalog Feed History'),
      for (final b in _batches)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${b.id} • ${b.fileName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${b.uploadedByName ?? '—'} · ${b.totalRows} rows · ${b.importedRows} imported · '
                      '${formatSellerDate(b.createdAt)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SellerPill(
                label: b.status,
                color: switch (b.status) {
                  'COMPLETED' => AppColors.emerald,
                  'FAILED' => const Color(0xFFE11D48),
                  _ => const Color(0xFFD97706),
                },
              ),
            ],
          ),
        ),
    ];
  }
}

/// One product row from the Web catalog table, as a mobile card.
class SellerProductCard extends StatelessWidget {
  const SellerProductCard({
    super.key,
    required this.product,
    required this.isAdmin,
    required this.onDetail,
    required this.onEdit,
    required this.onSubmit,
    required this.onDelete,
    required this.onReview,
  });

  final SellerHubProduct product;
  final bool isAdmin;
  final VoidCallback onDetail;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;
  final VoidCallback onDelete;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final image = AppConfig.resolveMediaUrl(p.primaryImage);
    final discount = p.discountPercent;
    final feedback = p.rejectionReason ?? p.adminReviewNote;
    final needsFix = p.status == 'REJECTED' || p.status == 'CHANGES_REQUESTED';
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 48,
                  height: 48,
                  color: AppColors.surfaceMuted,
                  child: image == null
                      ? Icon(Icons.image_outlined, color: AppColors.textMuted)
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.image_outlined,
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
                    if (p.barcode != null)
                      Text(
                        p.barcode!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    Text(
                      p.categoryPath ?? p.categoryName ?? 'Leaf Category',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
              SellerProductStatusBadge(p.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '₹${p.sellingPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (discount != null) ...[
                const SizedBox(width: 6),
                Text(
                  '₹${p.mrp.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
                SellerPill(label: '$discount% OFF', color: AppColors.emerald),
              ],
              const Spacer(),
              Text(
                '${p.packLabel}  ·  GST: ${p.taxRate.toStringAsFixed(2)}%${p.hsnCode != null ? ' • HSN: ${p.hsnCode}' : ''}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (needsFix && feedback != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${p.status == 'REJECTED' ? 'Rejection Reason:' : 'Changes Needed:'} $feedback',
                style: TextStyle(fontSize: 11.5, color: AppColors.errorText),
              ),
            ),
          ],
          Divider(height: 16, color: AppColors.border),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (needsFix)
                FilledButton(
                  onPressed: onEdit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Edit & Resubmit'),
                ),
              if (p.status == 'DRAFT' || p.status == 'PAUSED')
                FilledButton(
                  onPressed: onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Submit'),
                ),
              if (isAdmin)
                OutlinedButton(
                  onPressed: onReview,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Review'),
                ),
              IconButton(
                tooltip: 'View Audit Timeline & Details',
                onPressed: onDetail,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.history_rounded, size: 18),
              ),
              IconButton(
                tooltip: 'Edit Product Details',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              if (p.status == 'DRAFT' || p.status == 'REJECTED')
                IconButton(
                  tooltip: 'Delete Product',
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFDC2626),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
