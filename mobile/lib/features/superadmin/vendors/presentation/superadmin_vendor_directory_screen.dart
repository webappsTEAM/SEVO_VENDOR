import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';

import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';
import '../../../../shared/widgets/sevo/sevo_module_scaffold.dart';
import '../../../../shared/widgets/sevo/sevo_search_field.dart';
import '../../../../shared/widgets/sevo/sevo_skeleton.dart';
import '../../../../shared/widgets/sevo/sevo_state_views.dart';
import '../../../../shared/widgets/sevo/sevo_typography.dart';
import '../domain/platform_vendor.dart';
import 'superadmin_vendor_providers.dart';
import 'widgets/vendor_card.dart';
import 'widgets/vendor_directory_metrics.dart';

/// Super Admin Platform Governance: Vendor Companies Management.
///
/// Premium layout: a light app bar (SEVO wordmark + menu), the page title at
/// the top-left of the content, a short branded module transition on open, and
/// skeleton / empty / error states.
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

    return SevoModuleScaffold(
      module: SevoModule.vendorDirectory,
      title: 'Vendor Directory',
      subtitle: 'Manage registered vendors',
      ready: !vendorsAsync.isLoading,
      onRefresh: () async {
        ref.invalidate(platformVendorsDataProvider);
        await ref.read(platformVendorsDataProvider.future);
      },
      heroTrailing: IconButton.filled(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
        tooltip: 'Refresh Vendors',
        onPressed: () => ref.invalidate(platformVendorsDataProvider),
      ),
      heroBottom: SevoSearchField(
        controller: _searchController,
        hint: 'Search vendor, owner, email or city',
        onChanged: _onSearchChanged,
      ),
      children: _body(vendorsAsync, filteredVendors, metrics),
    );
  }

  List<Widget> _body(
    AsyncValue<PlatformVendorsResponse> async,
    List<PlatformVendor> filtered,
    VendorDirectoryMetrics metrics,
  ) {
    if (async.hasError && !async.hasValue) {
      return [
        SevoErrorState(
          message: 'Unable to load platform vendor businesses',
          onRetry: () => ref.invalidate(platformVendorsDataProvider),
        ),
      ];
    }
    if (!async.hasValue) {
      return const [SevoListSkeleton(count: 3)];
    }

    final total = async.requireValue.vendors.length;
    return [
      VendorDirectoryMetricsCards(
        metrics: metrics,
        onManageWorkforce: () => _navigateToWorkforce(),
      ),
      const SizedBox(height: AppSpacing.lg),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          'Showing ${filtered.length} of $total vendors',
          style: SevoText.caption,
        ),
      ),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        SevoEmptyState(
          module: SevoModule.vendorDirectory,
          title: _searchController.text.isNotEmpty
              ? 'No vendor businesses found'
              : 'No Vendors Registered',
          message: _searchController.text.isNotEmpty
              ? 'No vendors match your search criteria.'
              : 'No service vendor organizations have registered on the platform yet.',
        )
      else
        for (var i = 0; i < filtered.length; i++)
          VendorCard(
            index: i,
            vendor: filtered[i],
            onViewWorkers: () => _navigateToWorkforce(filtered[i].id),
          ),
    ];
  }
}
