import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../seller_hub_providers.dart';
import '../widgets/seller_hub_widgets.dart';
import 'seller_claim_sheets.dart';

/// Claims & Dispute Management (Web parity: `SellerClaimsPage.jsx`, route
/// `/workforce/seller-hub/claims`).
class SellerClaimsScreen extends ConsumerStatefulWidget {
  const SellerClaimsScreen({super.key});

  static const statusTabs = <(String, String)>[
    ('ALL', 'All Claims'),
    ('OPEN', 'Open'),
    ('NEEDS_RESPONSE', 'Needs Response'),
    ('UNDER_REVIEW', 'Under Review'),
    ('ESCALATED', 'Escalated'),
    ('APPROVED', 'Approved'),
    ('REJECTED', 'Rejected'),
    ('SETTLED', 'Settled'),
    ('CLOSED', 'Closed'),
  ];

  @override
  ConsumerState<SellerClaimsScreen> createState() => _SellerClaimsScreenState();
}

class _SellerClaimsScreenState extends ConsumerState<SellerClaimsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _status = 'ALL';
  String _type = '';
  String _search = '';

  List<SellerHubClaim> _claims = const [];
  bool _loading = true;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClaims() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(sellerHubRepositoryProvider)
          .getClaims(status: _status, claimType: _type, search: _search);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _claims = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _claims = const [];
        _loading = false;
        _error = e is SellerHubException ? e.message : 'Error loading claims';
      });
    }
  }

  Future<void> _refreshAll() async {
    ref.invalidate(sellerHubMetricsProvider);
    await _loadClaims();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value == _search) return;
      _search = value;
      _loadClaims();
    });
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _status = 'ALL';
      _type = '';
      _search = '';
    });
    _loadClaims();
  }

  Future<void> _openCreate() async {
    final created = await SellerCreateClaimSheet.show(context);
    if (created == true) _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(sellerHubMetricsProvider);
    final m = metricsAsync.valueOrNull;
    String metric(int Function(SellerHubMetrics) pick) =>
        m == null ? (metricsAsync.hasError ? '—' : '…') : '${pick(m)}';

    return SevoModuleFrame(
      module: SevoModule.sellerClaims,
      title: 'Claims & Dispute Management',
      subtitle:
          'Merchant protections, in-transit damage claims, delivery losses, and operational '
          'dispute arbitration',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.shield_rounded,
                title: 'Claims & Dispute Management',
                iconColor: const Color(0xFFDC2626),
                description:
                    'Merchant protections, in-transit damage claims, delivery losses, and operational '
                    'dispute arbitration',
                actions: [
                  SellerHeaderAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _refreshAll,
                  ),
                  SellerHeaderAction(
                    label: 'File Dispute / Claim',
                    icon: Icons.add_rounded,
                    primary: true,
                    onPressed: _openCreate,
                  ),
                  SellerHeaderAction(
                    label: 'Seller Home',
                    onPressed: () => context.go(AppRoutes.sellerHome),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerTileGrid(
                minTileWidth: 140,
                children: [
                  SellerMetricTile(
                    label: 'Open Claims',
                    value: metric((m) => m.openClaims),
                    caption: 'Active under review',
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                  SellerMetricTile(
                    label: 'Needs Response',
                    value: metric((m) => m.claimsRequiringResponse),
                    caption: 'Awaiting seller reply',
                    icon: Icons.mark_chat_unread_outlined,
                    color: const Color(0xFFD97706),
                  ),
                  SellerMetricTile(
                    label: 'Escalated',
                    value: metric((m) => m.escalatedClaims),
                    caption: 'Admin arbitration',
                    icon: Icons.gavel_rounded,
                    color: const Color(0xFFE11D48),
                  ),
                  SellerMetricTile(
                    label: 'Resolved',
                    value: metric((m) => m.resolvedClaims),
                    caption: 'Approved & settled',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.emerald,
                  ),
                  SellerMetricTile(
                    label: 'Total Claims',
                    value: metric((m) => m.totalClaims),
                    caption: 'All logged tickets',
                    icon: Icons.all_inbox_rounded,
                    color: const Color(0xFF475569),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SellerFilterChips(
                options: SellerClaimsScreen.statusTabs,
                selected: _status,
                selectedColor: const Color(0xFF0F172A),
                onSelected: (v) {
                  if (v == _status) return;
                  setState(() => _status = v);
                  _loadClaims();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerSearchField(
                controller: _searchController,
                hint: 'Search by Claim #, Order #, Return #, Customer, or Description...',
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              SellerDropdownFilter(
                value: _type,
                options: [('', 'All Claim Types'), ...sellerClaimTypes],
                onChanged: (v) {
                  if (v == _type) return;
                  setState(() => _type = v);
                  _loadClaims();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              ..._buildList(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildList() {
    if (_loading)
      return const [
        SellerLoading(message: 'Loading claims records from database...'),
      ];
    if (_error != null) {
      return [
        SellerStateMessage(
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFDC2626),
          title: 'Error Loading Claims',
          message: _error!,
          actionLabel: 'Retry',
          onAction: _loadClaims,
        ),
      ];
    }
    if (_claims.isEmpty) {
      final filtered =
          _search.isNotEmpty || _type.isNotEmpty || _status != 'ALL';
      return [
        SellerStateMessage(
          icon: Icons.shield_outlined,
          title: 'No Claims Found',
          message: filtered
              ? 'No claims matched your filter criteria. Try adjusting the search query or status tab.'
              : 'Your store currently has zero operational claims or dispute filings logged in the system.',
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            SellerHeaderAction(
              label: 'File a New Dispute',
              primary: true,
              onPressed: _openCreate,
            ),
            if (filtered)
              SellerHeaderAction(
                label: 'Reset Filters',
                onPressed: _resetFilters,
              ),
          ],
        ),
      ];
    }
    return [
      for (final claim in _claims)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: SellerClaimCard(
            claim: claim,
            onView: () => SellerClaimDetailSheet.show(
              context,
              claimId: claim.id,
              onChanged: _refreshAll,
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }
}

/// One claim row from the Web table, as a mobile card.
class SellerClaimCard extends StatelessWidget {
  const SellerClaimCard({super.key, required this.claim, required this.onView});

  final SellerHubClaim claim;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onView,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '#${claim.claimNumber}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SellerClaimStatusBadge(claim.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                claim.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  SellerPill(
                    label: claim.typeLabel,
                    color: SellerClaimStatusBadge.typeColor(claim.claimType),
                  ),
                  if (claim.orderNumber != null)
                    SellerPill(
                      label: 'Ord: #${claim.orderNumber}',
                      color: const Color(0xFF2563EB),
                    )
                  else
                    SellerPill(
                      label: 'No order linked',
                      color: const Color(0xFF94A3B8),
                    ),
                  if (claim.returnNumber != null)
                    SellerPill(
                      label: 'Ret: #${claim.returnNumber}',
                      color: const Color(0xFFEA580C),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    claim.claimedAmount > 0
                        ? '₹${claim.claimedAmount.toStringAsFixed(2)}'
                        : '—',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatSellerLongDate(claim.createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onView,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 15),
                    label: const Text('View'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
