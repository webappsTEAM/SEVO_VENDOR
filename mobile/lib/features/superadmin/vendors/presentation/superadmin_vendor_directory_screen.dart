import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/workforce_app_bar.dart';
import '../../../admin/presentation/widgets/admin_drawer.dart';
import '../domain/platform_vendor.dart';
import 'superadmin_vendor_providers.dart';
import 'widgets/vendor_card.dart';
import 'widgets/vendor_directory_metrics.dart';

/// Super Admin Platform Governance: Vendor Companies Management.
class SuperAdminVendorDirectoryScreen extends ConsumerStatefulWidget {
  const SuperAdminVendorDirectoryScreen({super.key});

  @override
  ConsumerState<SuperAdminVendorDirectoryScreen> createState() =>
      _SuperAdminVendorDirectoryScreenState();
}

class _SuperAdminVendorDirectoryScreenState
    extends ConsumerState<SuperAdminVendorDirectoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {});
    ref.read(vendorSearchQueryProvider.notifier).state = query.trim();
  }

  void _navigateToWorkforce([int? vendorId]) {
    if (vendorId != null && vendorId > 0) {
      context.go('${AppRoutes.superAdminWorkforce}?vendor_id=$vendorId');
    } else {
      context.go(AppRoutes.superAdminWorkforce);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(platformVendorsDataProvider);
    final filteredVendors = ref.watch(filteredPlatformVendorsProvider);
    final metrics = ref.watch(vendorDirectoryMetricsProvider);

    return Scaffold(
      appBar: const WorkforceAppBar(
        titleText: 'Vendor Directory',
        showStatusSubBar: false,
        showDrawerMenu: true,
      ),
      drawer: const AdminDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(platformVendorsDataProvider);
          await ref.read(platformVendorsDataProvider.future);
        },
        child: AsyncValueView<PlatformVendorsResponse>(
          value: vendorsAsync,
          errorMessage: 'Unable to load platform vendor businesses',
          onRetry: () => ref.invalidate(platformVendorsDataProvider),
          builder: (context, response) {
            final totalCount = response.vendors.length;
            final showingCount = filteredVendors.length;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                // ── 1. Screen Header ─────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF005965)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFF005965)
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  'PLATFORM GOVERNANCE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF005965),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Vendor Companies Management',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SEVO Platform Admin: Complete oversight of service vendor organizations and their tied workforce.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: const Color(0xFF005965),
                      tooltip: 'Refresh Vendors',
                      onPressed: () =>
                          ref.invalidate(platformVendorsDataProvider),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── 2. Summary Metrics & Manage All Workforce Action ─────────
                VendorDirectoryMetricsCards(
                  metrics: metrics,
                  onManageWorkforce: () => _navigateToWorkforce(),
                ),
                const SizedBox(height: 14),

                // ── 3. Search Bar & Count Toolbar ───────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Search by vendor name, owner, email, or city...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          color: AppColors.textMuted,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Showing X of Y vendors label
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'Showing $showingCount of $totalCount vendors',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── 4. Vendor Cards List ────────────────────────────────────
                if (filteredVendors.isEmpty)
                  _EmptyVendorsView(
                    isSearching: _searchController.text.isNotEmpty,
                  )
                else
                  ...filteredVendors.map(
                    (vendor) => VendorCard(
                      vendor: vendor,
                      onViewWorkers: () => _navigateToWorkforce(vendor.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyVendorsView extends StatelessWidget {
  const _EmptyVendorsView({required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.business_outlined,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            isSearching ? 'No vendor businesses found' : 'No Vendors Registered',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            isSearching
                ? 'No vendors match your search criteria.'
                : 'No service vendor organizations have registered on the platform yet.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}