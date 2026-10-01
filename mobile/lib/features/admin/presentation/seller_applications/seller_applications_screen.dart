import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';
import '../../../../shared/widgets/sevo/sevo_module_scaffold.dart';
import '../../../../shared/widgets/sevo/sevo_search_field.dart';
import '../../../../shared/widgets/sevo/sevo_skeleton.dart';
import '../../../../shared/widgets/sevo/sevo_state_views.dart';
import '../../../../shared/widgets/sevo/sevo_typography.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/seller_applications_repository.dart';
import '../../domain/seller_application.dart';

/// Technician Applications route for the signed-in role (platform vs vendor admin).
String _technicianApplicationsRoute(WidgetRef ref) =>
    ref.read(authControllerProvider).user?.isSuperAdmin == true
    ? AppRoutes.superAdminApplications
    : AppRoutes.adminApplications;

/// Status → badge tone (shared by the list and the dossier).
SevoTone sellerStatusTone(String status) => switch (status) {
  'approved' => SevoTone.success,
  'rejected' => SevoTone.error,
  'correction_required' => SevoTone.error,
  'submitted' || 'under_review' || 'pending' => SevoTone.warning,
  _ => SevoTone.neutral,
};

/// Status → solid colour (kept for callers that need a raw colour).
Color sellerStatusColor(String status) =>
    SevoToneColors.of(sellerStatusTone(status)).fg;

/// Web `AdminSellerApplicationsPage` — the Grocery Seller Applications queue.
class SellerApplicationsScreen extends ConsumerStatefulWidget {
  const SellerApplicationsScreen({super.key, this.initialStatus = 'all'});

  final String initialStatus;

  @override
  ConsumerState<SellerApplicationsScreen> createState() =>
      _SellerApplicationsScreenState();
}

class _SellerApplicationsScreenState
    extends ConsumerState<SellerApplicationsScreen> {
  static const _pageSize = 10;

  final _search = TextEditingController();
  late String _status = widget.initialStatus;
  int _page = 1;
  List<SellerApplication> _apps = const [];
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
      final rows = await ref
          .read(sellerApplicationsRepositoryProvider)
          .list(status: _status == 'all' ? null : _status);
      if (mounted && seq == _seq) {
        setState(() {
          _apps = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e is SellerApplicationsException
              ? e.message
              : 'Failed to load seller applications.';
        });
      }
    }
  }

  void _setStatus(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _page = 1;
    });
    _load();
  }

  /// Web search: store, company, owner, email, phone, FSSAI and GST.
  List<SellerApplication> get _filtered {
    final term = _search.text.toLowerCase().trim();
    if (term.isEmpty) return _apps;
    bool has(String? v) => (v ?? '').toLowerCase().contains(term);
    return _apps
        .where(
          (a) =>
              has(a.storeName) ||
              has(a.companyName) ||
              has(a.owner.fullName) ||
              has(a.owner.email) ||
              has(a.owner.mobile) ||
              has(a.fssaiNumber) ||
              has(a.gstNumber),
        )
        .toList();
  }

  Future<void> _open(SellerApplication app) async {
    await context.push('${AppRoutes.adminSellerApplications}/${app.id}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return SevoModuleScaffold(
      module: SevoModule.sellerApplications,
      title: 'Seller Applications',
      subtitle: 'Review merchant dossiers',
      ready: !_loading,
      onRefresh: _load,
      heroTrailing: IconButton.filled(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
        tooltip: 'Refresh Applications',
        onPressed: _loading ? null : _load,
      ),
      heroBottom: SevoSearchField(
        controller: _search,
        hint: 'Search store, owner, FSSAI...',
        onChanged: (_) => setState(() => _page = 1),
      ),
      children: _body(),
    );
  }

  List<Widget> _body() {
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, totalPages);
    final pageRows = filtered
        .skip((page - 1) * _pageSize)
        .take(_pageSize)
        .toList();
    final pending = _apps.where((a) => a.isPending).length;
    final approved = _apps.where((a) => a.isApproved).length;
    final corrections = _apps.where((a) => a.needsCorrection).length;

    return [
      // Sibling application queues (Web: three tabs).
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _navChip(
            'Technician Applications',
            Icons.person_rounded,
            () => context.go(_technicianApplicationsRoute(ref)),
          ),
          SevoFilterChip(
            label: 'Seller Hub Applications (${_apps.length})',
            selected: true,
            onTap: () {},
          ),
          _navChip(
            'Profile Change Requests',
            Icons.description_outlined,
            () => context.go(
              '${_technicianApplicationsRoute(ref)}?tab=change_requests',
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SevoTileGrid(
        tiles: [
          SevoStatTile(
            index: 0,
            label: 'TOTAL SELLERS',
            caption: 'All applications',
            value: _apps.length,
            icon: Icons.storefront_rounded,
            accent: const Color(0xFF0D9488),
            selected: _status == 'all',
            onTap: () => _setStatus('all'),
          ),
          SevoStatTile(
            index: 1,
            label: 'UNDER REVIEW',
            caption: 'Awaiting review',
            value: pending,
            icon: Icons.schedule_rounded,
            accent: const Color(0xFFD97706),
            selected: _status == 'pending',
            onTap: () => _setStatus('pending'),
          ),
          SevoStatTile(
            index: 2,
            label: 'APPROVED ACTIVE',
            caption: 'Live storefronts',
            value: approved,
            icon: Icons.check_circle_rounded,
            accent: const Color(0xFF059669),
            selected: _status == 'approved',
            onTap: () => _setStatus('approved'),
          ),
          SevoStatTile(
            index: 3,
            label: 'CORRECTION NEEDED',
            caption: 'Sent back to seller',
            value: corrections,
            icon: Icons.warning_amber_rounded,
            accent: const Color(0xFFE11D48),
            selected: _status == 'correction_required',
            onTap: () => _setStatus('correction_required'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SevoFilterRow(
        chips: [
          for (final f in const [
            ('all', 'All Statuses'),
            ('pending', 'Under Review'),
            ('approved', 'Approved'),
            ('correction_required', 'Correction Required'),
            ('rejected', 'Rejected'),
          ])
            SevoFilterChip(
              label: f.$2,
              selected: _status == f.$1,
              onTap: () => _setStatus(f.$1),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (_loading)
        const SevoListSkeleton(count: 3)
      else if (_error != null)
        SevoErrorState(message: _error!, onRetry: _load)
      else if (filtered.isEmpty)
        SevoEmptyState(
          module: SevoModule.sellerApplications,
          title: 'No Seller Applications Found',
          message: _search.text.isNotEmpty || _status != 'all'
              ? 'No seller applications match your current filters. Try resetting search criteria.'
              : 'There are currently zero seller applications lodged on the platform.',
        )
      else ...[
        for (var i = 0; i < pageRows.length; i++)
          _ApplicationCard(
            index: i,
            app: pageRows[i],
            onOpen: () => _open(pageRows[i]),
          ),
        _Pager(
          page: page,
          totalPages: totalPages,
          onPage: (p) => setState(() => _page = p),
        ),
      ],
    ];
  }

  Widget _navChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.bodyText),
      label: Text(
        label,
        style: SevoText.badge.copyWith(fontSize: 12, color: AppColors.bodyText),
      ),
      backgroundColor: AppColors.surface,
      side: BorderSide(color: AppColors.border),
      shape: const StadiumBorder(),
      onPressed: onTap,
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onPage,
  });

  final int page;
  final int totalPages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
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
          child: Text('Page $page of $totalPages', style: SevoText.bodyStrong),
        ),
        OutlinedButton(
          onPressed: page < totalPages ? () => onPage(page + 1) : null,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.index,
    required this.app,
    required this.onOpen,
  });

  final int index;
  final SellerApplication app;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final owner = app.owner;
    final cats = app.categories;
    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onOpen,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.storeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#SEL-${app.id} • ${app.companyName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.meta,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SevoBadge(
              label: sellerStatusLabel(app.registrationStatus),
              tone: sellerStatusTone(app.registrationStatus),
            ),
          ),
          const SizedBox(height: 6),
          _line(
            Icons.person_outline_rounded,
            owner.hasName ? owner.fullName : 'Store Manager',
          ),
          _line(Icons.phone_outlined, owner.mobile ?? 'No phone'),
          _line(
            Icons.verified_user_outlined,
            'FSSAI: ${app.fssaiNumber ?? 'Pending'}',
          ),
          _line(
            Icons.description_outlined,
            app.docCount > 0
                ? '${app.approvedDocCount}/${app.docCount} Docs Approved'
                : 'No files lodged',
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: cats.isEmpty
                    ? Text('General', style: SevoText.caption)
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in cats.take(2))
                            SevoBadge(label: c.name),
                          if (cats.length > 2)
                            SevoBadge(label: '+${cats.length - 2}'),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.selectedOnTint,
                  backgroundColor: AppColors.selectedTint,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('Review', style: SevoText.button),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SevoText.caption.copyWith(color: AppColors.bodyText),
          ),
        ),
      ],
    ),
  );
}
