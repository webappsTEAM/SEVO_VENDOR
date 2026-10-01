import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../seller_hub_providers.dart';
import '../widgets/seller_hub_widgets.dart';

/// Seller Hub Home — Merchant Center (Web parity: `SellerDashboardPage.jsx`,
/// route `/workforce/seller/dashboard`).
class SellerHomeScreen extends ConsumerWidget {
  const SellerHomeScreen({super.key});

  static const _blue = Color(0xFF2563EB);
  static const _amber = Color(0xFFD97706);
  static const _purple = Color(0xFF7C3AED);
  static const _red = Color(0xFFDC2626);
  static const _orange = Color(0xFFEA580C);
  static const _indigo = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final isAdmin = user?.isAdmin == true;
    final storeName = (user?.companyName?.trim().isNotEmpty ?? false)
        ? user!.companyName!.trim()
        : null;
    final summaryAsync = ref.watch(sellerHomeSummaryProvider);

    return SevoModuleFrame(
      module: SevoModule.sellerHome,
      title: storeName ?? 'Seller Hub',
      subtitle: 'Central command dashboard for your catalog, orders, inventory, and promotions',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(sellerHomeSummaryProvider);
            try {
              await ref.read(sellerHomeSummaryProvider.future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SellerHubHeader(
                icon: Icons.storefront_rounded,
                title: storeName ?? 'Seller Hub',
                badge: 'Merchant Center',
                description: 'Central command dashboard for your catalog, orders, inventory, and promotions',
                actions: [
                  if (isAdmin)
                    SellerHeaderAction(
                      label: 'Categories',
                      icon: Icons.layers_rounded,
                      onPressed: () => context.go(AppRoutes.sellerCategories),
                    )
                  else
                    SellerHeaderAction(
                      label: 'Add Products',
                      icon: Icons.cloud_upload_rounded,
                      onPressed: () =>
                          context.go(AppRoutes.sellerCatalogUploads),
                    ),
                  SellerHeaderAction(
                    label: 'New Coupon',
                    icon: Icons.add_rounded,
                    primary: true,
                    onPressed: () => context.go(AppRoutes.sellerCoupons),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _FoundationBanner(),
              ...summaryAsync.when<List<Widget>>(
                loading: () => const [
                  SellerLoading(message: 'Loading live store metrics...'),
                ],
                error: (err, _) => [
                  SellerStateMessage(
                    icon: Icons.error_outline_rounded,
                    color: _red,
                    title: 'Unable to load Seller Hub metrics',
                    message: err is SellerHubException
                        ? err.message
                        : 'Please try again.',
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(sellerHomeSummaryProvider),
                  ),
                ],
                data: (summary) => _buildDashboard(
                  context,
                  summary,
                  isAdmin: isAdmin,
                  storeName: storeName,
                ),
              ),
              const SellerSectionLabel('Seller Hub Modules Directory'),
              _ModulesDirectory(
                isAdmin: isAdmin,
                summary: summaryAsync.valueOrNull,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDashboard(
    BuildContext context,
    SellerHomeSummary summary, {
    required bool isAdmin,
    required String? storeName,
  }) {
    final m = summary.metrics;
    void go(String route) => context.go(route);

    return [
      const SellerSectionLabel('Live Store Configurations'),
      _ConfigCard(
        icon: Icons.layers_rounded,
        color: AppColors.emerald,
        badge: 'Live Data',
        value: '${summary.categoriesCount}',
        title: 'Catalog Categories',
        subtitle: 'Hierarchical grocery department classifications',
        linkLabel: isAdmin ? 'Manage Categories' : 'View Products',
        onTap: () => go(
          isAdmin ? AppRoutes.sellerCategories : AppRoutes.sellerCatalogUploads,
        ),
      ),
      const SizedBox(height: 10),
      _ConfigCard(
        icon: Icons.local_offer_rounded,
        color: _indigo,
        badge: 'Live Data',
        value: '${summary.couponsCount}',
        title: 'Active Store Coupons',
        subtitle: 'Marketing vouchers, flat & % discounts',
        linkLabel: 'Manage Coupons',
        onTap: () => go(AppRoutes.sellerCoupons),
      ),
      const SizedBox(height: 10),
      _ConfigCard(
        icon: Icons.store_rounded,
        color: _blue,
        badge: 'Active',
        valueText: storeName ?? 'Verified Merchant Store',
        title: 'Merchant Store Status',
        subtitle: 'Ready for catalog listings & fulfillment',
        linkLabel: 'Store Inventory',
        onTap: () => go(AppRoutes.sellerInventory),
      ),
      const SellerSectionLabel('Store Operational Pipelines'),
      SellerTileGrid(
        children: [
          SellerMetricTile(
            label: "Today's Orders",
            value: '${m.todayOrders}',
            caption: 'Incoming queue',
            icon: Icons.shopping_bag_outlined,
            color: _blue,
            onTap: () => go(AppRoutes.sellerOrders),
          ),
          SellerMetricTile(
            label: 'Action Required',
            value: '${m.pendingOrders}',
            caption: 'New orders',
            icon: Icons.inventory_2_outlined,
            color: _amber,
            onTap: () => go(AppRoutes.sellerOrders),
          ),
          SellerMetricTile(
            label: 'In Preparation',
            value: '${m.inPrepOrders}',
            caption: 'Picking / Packed',
            icon: Icons.local_shipping_outlined,
            color: _purple,
            onTap: () => go(AppRoutes.sellerOrders),
          ),
          SellerMetricTile(
            label: 'Completed Orders',
            value: '${m.completedOrders}',
            caption: 'Fulfilled',
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.emerald,
            onTap: () => go(AppRoutes.sellerOrders),
          ),
          SellerMetricTile(
            label: 'Return Requests',
            value: '${m.pendingReturns}',
            caption: '${m.totalReturns} total cases',
            icon: Icons.replay_rounded,
            color: _orange,
            onTap: () => go(AppRoutes.sellerReturns),
          ),
          SellerMetricTile(
            label: 'Open Claims',
            value: '${m.openClaims}',
            caption: m.claimsRequiringResponse > 0
                ? '${m.claimsRequiringResponse} need response'
                : '${m.totalClaims} total cases',
            icon: Icons.shield_outlined,
            color: _red,
            onTap: () => go(AppRoutes.sellerClaims),
          ),
          SellerMetricTile(
            label: 'Low Stock Items',
            value: '${m.lowStockItems}',
            caption: 'Reorder alert',
            icon: Icons.warning_amber_rounded,
            color: _amber,
            onTap: () => go(AppRoutes.sellerInventory),
          ),
          SellerMetricTile(
            label: 'Out of Stock',
            value: '${m.outOfStockItems}',
            caption: 'Zero inventory',
            icon: Icons.highlight_off_rounded,
            color: _red,
            onTap: () => go(AppRoutes.sellerInventory),
          ),
          SellerMetricTile(
            label: 'Pending Catalogs',
            value: '${m.catalogsAwaitingApproval}',
            caption: 'Items in review',
            icon: Icons.cloud_upload_outlined,
            color: _indigo,
            onTap: () => go(AppRoutes.sellerCatalogUploads),
          ),
          // The metrics API does not report sales, and the Web card is a
          // hard-coded ₹0.00; mobile shows no figure rather than a fake one.
          const SellerMetricTile(
            label: "Today's Sales",
            value: '—',
            caption: 'Not reported by API',
            icon: Icons.trending_up_rounded,
            color: AppColors.emerald,
          ),
        ],
      ),
    ];
  }
}

class _FoundationBanner extends StatelessWidget {
  const _FoundationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.successBg, AppColors.surface],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.emerald,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seller Hub Foundation & Catalog Engine',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Catalog categories and store coupons are powered by live records. Orders, inventory sync, '
                  'returns, claims and catalog feeds are managed from this hub.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.icon,
    required this.color,
    required this.badge,
    this.value,
    this.valueText,
    required this.title,
    required this.subtitle,
    required this.linkLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String badge;
  final String? value;
  final String? valueText;
  final String title;
  final String subtitle;
  final String linkLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Icon(icon, size: 19, color: color),
                  ),
                  const Spacer(),
                  SellerPill(label: badge, color: color),
                ],
              ),
              const SizedBox(height: 12),
              if (value != null)
                Text(
                  value!,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                )
              else
                Text(
                  valueText ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    linkLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModulesDirectory extends StatelessWidget {
  const _ModulesDirectory({required this.isAdmin, required this.summary});

  final bool isAdmin;
  final SellerHomeSummary? summary;

  @override
  Widget build(BuildContext context) {
    final categories = summary?.categoriesCount;
    final coupons = summary?.couponsCount;
    final modules = <_Module>[
      const _Module(
        '1. Home',
        'Merchant command center overview and store health telemetry.',
        'Current Page',
        Icons.storefront_rounded,
        AppColors.emerald,
        null,
      ),
      const _Module(
        '2. Orders',
        'Customer order routing, packing slips, and delivery rider handoffs.',
        'Open Orders',
        Icons.shopping_bag_rounded,
        Color(0xFF2563EB),
        AppRoutes.sellerOrders,
      ),
      const _Module(
        '3. Returns',
        'Customer return requests, inspection decisions, and reverse pickup.',
        'Open Returns',
        Icons.replay_rounded,
        Color(0xFFEA580C),
        AppRoutes.sellerReturns,
      ),
      const _Module(
        '4. Claims',
        'In-transit damage claims, delivery losses, and merchant protections.',
        'Open Claims',
        Icons.shield_rounded,
        Color(0xFFDC2626),
        AppRoutes.sellerClaims,
      ),
      const _Module(
        '5. Inventory',
        'Stock levels, warehouse allocation, and low-stock reorder thresholds.',
        'Open Inventory',
        Icons.inventory_2_rounded,
        AppColors.emerald,
        AppRoutes.sellerInventory,
      ),
      const _Module(
        '6. Catalog Uploads',
        'Bulk Excel/CSV item ingestion feeds and image archive uploads.',
        'Open Feeds',
        Icons.cloud_upload_rounded,
        Color(0xFF4F46E5),
        AppRoutes.sellerCatalogUploads,
      ),
      _Module(
        '7. Catalog Categories',
        isAdmin
            ? 'Multi-level expandable folder tree for merchandise organization.'
            : 'Hierarchical department structure. Picked during single & bulk product cataloging.',
        isAdmin
            ? (categories == null ? 'Manage' : 'Manage ($categories)')
            : 'Browse Catalog',
        Icons.layers_rounded,
        AppColors.primaryAccent,
        isAdmin ? AppRoutes.sellerCategories : AppRoutes.sellerCatalogUploads,
      ),
      _Module(
        '8. Coupons',
        'Discount vouchers, promotional rules, thresholds, and limits.',
        coupons == null ? 'Manage' : 'Manage ($coupons)',
        Icons.local_offer_rounded,
        const Color(0xFF7C3AED),
        AppRoutes.sellerCoupons,
      ),
      const _Module(
        '9. Reports & Quality',
        'Quality scorecards, inventory velocity, returns/claims audits, and CSV data exports.',
        'Open Reports',
        Icons.bar_chart_rounded,
        Color(0xFF2563EB),
        AppRoutes.sellerReportsQuality,
      ),
    ];

    return SellerTileGrid(
      minTileWidth: 160,
      children: [for (final m in modules) _ModuleCard(module: m)],
    );
  }
}

class _Module {
  const _Module(
    this.title,
    this.description,
    this.linkLabel,
    this.icon,
    this.color,
    this.route,
  );

  final String title;
  final String description;
  final String linkLabel;
  final IconData icon;
  final Color color;
  final String? route;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final _Module module;

  @override
  Widget build(BuildContext context) {
    final route = module.route;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: route == null ? null : () => context.go(route),
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(module.icon, size: 16, color: module.color),
              ),
              const SizedBox(height: 8),
              Text(
                module.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Text(
                  module.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      module.linkLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: module.color,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 13,
                    color: module.color,
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
