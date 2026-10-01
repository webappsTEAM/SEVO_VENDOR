import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Catalog Categories — multi-level folder tree (Web parity:
/// `AdminSellerCategoriesPage.jsx`, route `/workforce/admin/seller-hub/categories`).
/// Create / edit / delete / toggle are platform-admin only, as on the Web.
class SellerCategoriesScreen extends ConsumerStatefulWidget {
  const SellerCategoriesScreen({super.key});

  static const orderings = <(String, String)>[
    ('sort_order', 'Sort Order (Asc)'),
    ('-sort_order', 'Sort Order (Desc)'),
    ('name', 'Name (A-Z)'),
    ('-name', 'Name (Z-A)'),
    ('-id', 'Recently Added'),
  ];

  @override
  ConsumerState<SellerCategoriesScreen> createState() =>
      _SellerCategoriesScreenState();
}

/// A visible row of the flattened tree.
class _Row {
  const _Row(
    this.cat,
    this.depth,
    this.childCount,
    this.expanded,
    this.parentPath,
  );

  final SellerHubCategory cat;
  final int depth;
  final int childCount;
  final bool expanded;
  final List<String> parentPath;
}

class _SellerCategoriesScreenState
    extends ConsumerState<SellerCategoriesScreen> {
  List<SellerHubCategory> _all = const [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  String _status = 'all';
  String _ordering = 'sort_order';
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await _repo.getCategories();
      if (mounted) {
        setState(() {
          _all = cats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to load catalog categories';
        });
      }
    }
  }

  Map<int, SellerHubCategory> get _byId => {for (final c in _all) c.id: c};

  Map<int, List<SellerHubCategory>> get _children {
    final byId = _byId;
    final map = <int, List<SellerHubCategory>>{};
    for (final c in _all) {
      if (c.parentId != null && byId.containsKey(c.parentId)) {
        map.putIfAbsent(c.parentId!, () => []).add(c);
      }
    }
    return map;
  }

  List<SellerHubCategory> _sorted(List<SellerHubCategory> items) {
    final list = [...items];
    int bySort(SellerHubCategory a, SellerHubCategory b) =>
        a.sortOrder.compareTo(b.sortOrder);
    list.sort(switch (_ordering) {
      '-sort_order' => (a, b) => b.sortOrder.compareTo(a.sortOrder),
      'name' => (a, b) => a.name.compareTo(b.name),
      '-name' => (a, b) => b.name.compareTo(a.name),
      '-id' => (a, b) => b.id.compareTo(a.id),
      _ => bySort,
    });
    return list;
  }

  /// The inactive ancestor that hides an active category from sellers.
  String? _inactiveAncestor(SellerHubCategory cat) {
    final byId = _byId;
    final seen = <int>{};
    var parentId = cat.parentId;
    while (parentId != null && seen.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      if (!parent.isActive) return parent.name;
      parentId = parent.parentId;
    }
    return null;
  }

  List<_Row> _visibleRows() {
    final byId = _byId;
    final children = _children;
    final q = _search.text.trim().toLowerCase();
    Set<int>? matches;
    final ancestors = <int>{};
    if (q.isNotEmpty) {
      matches = {};
      for (final c in _all) {
        final hit =
            c.name.toLowerCase().contains(q) ||
            c.slug.toLowerCase().contains(q) ||
            (c.description ?? '').toLowerCase().contains(q);
        if (!hit) continue;
        matches.add(c.id);
        var cur = c;
        while (cur.parentId != null &&
            byId[cur.parentId] != null &&
            ancestors.add(cur.parentId!)) {
          cur = byId[cur.parentId]!;
        }
      }
    }
    bool statusMatch(SellerHubCategory c) => _status == 'active'
        ? c.isActive
        : (_status == 'inactive' ? !c.isActive : true);

    final rows = <_Row>[];
    void walk(List<SellerHubCategory> items, int depth, List<String> path) {
      for (final c in _sorted(items)) {
        final kids = children[c.id] ?? const [];
        final isAncestor = ancestors.contains(c.id);
        final expanded = _expanded.contains(c.id) || isAncestor;
        final include = matches == null || matches.contains(c.id) || isAncestor;
        if (include && (statusMatch(c) || isAncestor)) {
          rows.add(_Row(c, depth, kids.length, expanded, path));
        }
        if (kids.isNotEmpty && expanded)
          walk(kids, depth + 1, [...path, c.name]);
      }
    }

    walk(
      _all
          .where((c) => c.parentId == null || !byId.containsKey(c.parentId))
          .toList(),
      0,
      const [],
    );
    return rows;
  }

  Future<void> _openEditor({SellerHubCategory? editing, int? parentId}) async {
    final saved = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) =>
          _CategoryEditorSheet(all: _all, editing: editing, parentId: parentId),
    );
    if (saved == null) return;
    if (saved > 0) setState(() => _expanded.add(saved));
    await _load();
  }

  Future<void> _toggleActive(SellerHubCategory cat) async {
    try {
      await _repo.updateCategory(cat.id, {'is_active': !cat.isActive});
      if (mounted) {
        setState(
          () => _all = [
            for (final c in _all)
              c.id == cat.id ? c.copyWith(isActive: !c.isActive) : c,
          ],
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              e is SellerHubException
                  ? e.message
                  : 'Failed to update category status.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _delete(SellerHubCategory cat, int childCount) async {
    final subCount = cat.childrenCount ?? childCount;
    String? error;
    var deleting = false;
    final deleted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            'Delete "${cat.name}"?',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Safe deletion checks apply',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (subCount > 0 || cat.productsCount > 0)
                Text(
                  '${[if (subCount > 0) '$subCount subcategories', if (cat.productsCount > 0) '${cat.productsCount} linked products'].join(' and ')} are attached; the server will block deletion until they are moved.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFB45309),
                  ),
                )
              else
                const Text(
                  'This category has no subcategories or products.',
                  style: TextStyle(fontSize: 12.5),
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: deleting
                  ? null
                  : () async {
                      setDialog(() {
                        deleting = true;
                        error = null;
                      });
                      try {
                        await _repo.deleteCategory(cat.id);
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setDialog(() {
                          deleting = false;
                          error = e is SellerHubException
                              ? e.message
                              : 'Failed to delete category.';
                        });
                      }
                    },
              child: const Text('Confirm Delete'),
            ),
          ],
        ),
      ),
    );
    if (deleted == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final isSuperAdmin = user?.isSuperAdmin == true;
    final rows = _loading || _error != null ? const <_Row>[] : _visibleRows();
    final children = _children;

    return SevoModuleFrame(
      module: SevoModule.categories,
      title: 'Catalog Categories',
      subtitle: 'Organize products and services in a multi-level folder tree',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.layers_rounded,
                title: 'Catalog Categories',
                description: 'Organize products and services in a multi-level folder tree',
                actions: [
                  if (isSuperAdmin)
                    SellerHeaderAction(
                      label: 'Add Category',
                      icon: Icons.add_rounded,
                      primary: true,
                      onPressed: () => _openEditor(),
                    ),
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerSearchField(
                controller: _search,
                hint: 'Search categories across hierarchy...',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _expanded
                        ..clear()
                        ..addAll(children.keys);
                    }),
                    icon: const Icon(Icons.unfold_more_rounded, size: 16),
                    label: const Text('Expand All'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(_expanded.clear),
                    icon: const Icon(Icons.unfold_less_rounded, size: 16),
                    label: const Text('Collapse All'),
                  ),
                ],
              ),
              SellerFilterChips(
                options: const [
                  ('all', 'All'),
                  ('active', 'Active'),
                  ('inactive', 'Inactive'),
                ],
                selected: _status,
                onSelected: (v) => setState(() => _status = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerDropdownFilter(
                value: _ordering,
                options: SellerCategoriesScreen.orderings,
                onChanged: (v) => setState(() => _ordering = v),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const SellerLoading(
                  message: 'Loading catalog categories tree...',
                )
              else if (_error != null)
                SellerStateMessage(
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFDC2626),
                  title: 'Error',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              else if (_all.isEmpty)
                SellerStateMessage(
                  icon: Icons.layers_outlined,
                  title: 'No categories yet',
                  message: 'Create the first catalog category to start organizing products.',
                  actionLabel: isSuperAdmin ? 'Create First Category' : null,
                  onAction: isSuperAdmin ? () => _openEditor() : null,
                )
              else if (rows.isEmpty)
                const SellerStateMessage(
                  icon: Icons.search_off_rounded,
                  title: 'No matching categories',
                  message: 'Try a different search or status filter.',
                )
              else
                for (final r in rows) _rowCard(r, isSuperAdmin),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowCard(_Row r, bool isSuperAdmin) {
    final c = r.cat;
    final hiddenBy = c.isActive ? _inactiveAncestor(c) : null;
    final subCount = c.childrenCount ?? r.childCount;
    return Padding(
      padding: EdgeInsets.only(left: (r.depth * 16).toDouble(), bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 34,
                  child: r.childCount > 0
                      ? IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip:
                              '${r.expanded ? 'Collapse' : 'Expand'} subcategories',
                          icon: Icon(
                            r.expanded
                                ? Icons.expand_more_rounded
                                : Icons.chevron_right_rounded,
                          ),
                          onPressed: () => setState(() {
                            if (!_expanded.remove(c.id)) _expanded.add(c.id);
                          }),
                        )
                      : Icon(
                          Icons.label_outline_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        r.childCount > 0
                            ? '${r.childCount} ${r.childCount == 1 ? 'subcategory' : 'subcategories'}'
                            : 'Leaf Category',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: isSuperAdmin ? () => _toggleActive(c) : null,
                  child: SellerPill(
                    label: c.isActive ? 'Active' : 'Inactive',
                    color: c.isActive
                        ? AppColors.emerald
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slug: ${c.slug}  ·  ${c.productsCount} products  ·  $subCount subcategories  ·  Sort ${c.sortOrder}',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  if (!c.isActive)
                    Text(
                      'Hidden from sellers',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    )
                  else if (hiddenBy != null)
                    Text(
                      "Hidden from sellers: parent '$hiddenBy' is inactive",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  if (isSuperAdmin)
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openEditor(parentId: c.id),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Subcategory'),
                        ),
                        IconButton(
                          tooltip: 'Edit category',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _openEditor(editing: c),
                        ),
                        IconButton(
                          tooltip: 'Delete category',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Color(0xFFDC2626),
                          ),
                          onPressed: () => _delete(c, r.childCount),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create / edit category form. Pops with the parent id to expand (0 when
/// none) on success.
class _CategoryEditorSheet extends ConsumerStatefulWidget {
  const _CategoryEditorSheet({required this.all, this.editing, this.parentId});

  final List<SellerHubCategory> all;
  final SellerHubCategory? editing;
  final int? parentId;

  static const icons = [
    'Store',
    'Package',
    'ShoppingBag',
    'Carrot',
    'Sparkles',
    'Wrench',
    'Tag',
    'Layers',
  ];

  @override
  ConsumerState<_CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<_CategoryEditorSheet> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _slug = TextEditingController(text: widget.editing?.slug ?? '');
  late final _description = TextEditingController(
    text: widget.editing?.description ?? '',
  );
  late final _sort = TextEditingController(
    text:
        '${widget.editing?.sortOrder ?? (widget.all.isEmpty ? 1 : widget.all.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1)}',
  );
  late String _icon = _CategoryEditorSheet.icons.contains(widget.editing?.icon)
      ? widget.editing!.icon!
      : 'Store';
  late int? _parent = widget.editing?.parentId ?? widget.parentId;
  late bool _active = widget.editing?.isActive ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _slug, _description, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parents cannot be the category itself or one of its descendants.
  List<SellerHubCategory> get _eligibleParents {
    final editing = widget.editing;
    if (editing == null) return widget.all;
    final exclude = {editing.id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in widget.all) {
        if (c.parentId != null &&
            exclude.contains(c.parentId) &&
            exclude.add(c.id))
          grew = true;
      }
    }
    return widget.all.where((c) => !exclude.contains(c.id)).toList();
  }

  void _onNameChanged(String v) {
    if (widget.editing != null) return;
    _slug.text = v
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Category name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {
      'name': _name.text.trim(),
      'slug': _slug.text.trim(),
      'description': _description.text.trim(),
      'icon': _icon,
      'parent': _parent,
      'sort_order': int.tryParse(_sort.text.trim()) ?? 0,
      'is_active': _active,
    };
    try {
      final repo = ref.read(sellerHubRepositoryProvider);
      if (widget.editing != null) {
        await repo.updateCategory(widget.editing!.id, payload);
      } else {
        await repo.createCategory(payload);
      }
      if (mounted)
        Navigator.of(context).pop(widget.editing == null ? (_parent ?? 0) : 0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is SellerHubException
              ? e.message
              : 'Failed to save category.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parents = _eligibleParents;
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
                    widget.editing == null ? 'Add Category' : 'Edit Category',
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
              controller: _name,
              onChanged: _onNameChanged,
              decoration: const InputDecoration(
                labelText: 'Category Name *',
                hintText: 'e.g. Sunflower Oil, Dhals, Exotic Fruits',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _slug,
              decoration: const InputDecoration(
                labelText: 'Slug',
                hintText: 'e.g. sunflower-oil',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              initialValue: parents.any((p) => p.id == _parent)
                  ? _parent
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Parent Category',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('None (Top-Level Root Category)'),
                ),
                for (final p in parents)
                  DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _parent = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText:
                    'Brief summary of items or services under this category...',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _icon,
                    decoration: const InputDecoration(
                      labelText: 'Icon',
                      isDense: true,
                    ),
                    items: [
                      for (final i in _CategoryEditorSheet.icons)
                        DropdownMenuItem(value: i, child: Text(i)),
                    ],
                    onChanged: (v) => setState(() => _icon = v ?? _icon),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sort Order',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active (Visible in Catalog)'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.editing == null
                          ? 'Create Category'
                          : 'Save Changes',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
