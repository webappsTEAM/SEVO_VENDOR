import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile/core/network/api_error.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/presentation/finance/admin_finance_providers.dart';
import 'package:mobile/features/admin/presentation/finance/widgets/admin_wallet_card.dart';
import 'package:mobile/features/admin/presentation/widgets/admin_drawer.dart';
import 'package:mobile/routing/app_routes.dart';
import 'package:mobile/shared/widgets/empty_state.dart';
import 'package:mobile/shared/widgets/workforce_app_bar.dart';

/// Super Admin / Platform Treasury Screen: Technician Wallets & Financial Oversight.
///
/// Monitors technician earnings (60% commission share), pending T+7 settlements,
/// and payout disbursements across all active technician wallets.
class AdminWalletsScreen extends ConsumerStatefulWidget {
  const AdminWalletsScreen({super.key});

  @override
  ConsumerState<AdminWalletsScreen> createState() => _AdminWalletsScreenState();
}

class _AdminWalletsScreenState extends ConsumerState<AdminWalletsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(adminWalletsProvider);
    ref.invalidate(adminWithdrawalsProvider);
    await ref.read(adminWalletsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final walletsAsync = ref.watch(adminWalletsProvider);
    final summary = ref.watch(adminWalletSummaryProvider);
    final filteredWallets = ref.watch(filteredAdminWalletsProvider);
    final currentStatusFilter = ref.watch(adminWalletStatusFilterProvider);
    final pendingPayoutsCount = ref.watch(adminPendingWithdrawalsCountProvider);
    final displayedCount = filteredWallets.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WorkforceAppBar(
        titleText: 'Vendor Wallets',
        showStatusSubBar: false,
        showDrawerMenu: true,
      ),
      drawer: const AdminDrawer(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // ── 1. Page Header ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x040F172A),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Context Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Text(
                        'Wallets & Finance',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Title & Subtitle Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF005965), Color(0xFF0284C7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Technician Wallets & Financial Oversight',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Monitor technician earnings (60% commission share), pending T+7 settlements, and payout disbursements.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 10),

                    // Actions Row: Refresh & Manage Payouts (X)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: BorderSide(color: AppColors.border),
                            visualDensity: VisualDensity.compact,
                            textStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              context.push(AppRoutes.adminFinanceWithdrawals),
                          icon: const Icon(Icons.payments_rounded, size: 15),
                          label: Text('Manage Payouts ($pendingPayoutsCount)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF005965),
                            visualDensity: VisualDensity.compact,
                            textStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── 2. Financial Metrics (4 Cards) ───────────────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final card1 = _FinancialMetricCard(
                    label: 'Technicians',
                    value: (summary?.totalWallets ?? 0).toString(),
                    description: 'Total active technician wallets',
                    icon: Icons.people_alt_rounded,
                    iconColor: AppColors.infoText,
                    iconBgColor: AppColors.infoBg,
                  );
                  final card2 = _FinancialMetricCard(
                    label: 'Total Available',
                    value:
                        '₹${(summary?.totalAvailableBalance ?? 0.0).toStringAsFixed(2)}',
                    description: 'Withdrawable technician balances',
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: AppColors.successText,
                    iconBgColor: AppColors.successBg,
                  );
                  final card3 = _FinancialMetricCard(
                    label: 'In T+7 Hold',
                    value:
                        '₹${(summary?.totalPendingBalance ?? 0.0).toStringAsFixed(2)}',
                    description: 'Pending settlement release',
                    icon: Icons.hourglass_top_rounded,
                    iconColor: AppColors.warningText,
                    iconBgColor: AppColors.warningBg,
                  );
                  final card4 = _FinancialMetricCard(
                    label: 'Total Disbursed',
                    value:
                        '₹${(summary?.totalDisbursed ?? 0.0).toStringAsFixed(2)}',
                    description: 'Lifetime payouts to technicians',
                    icon: Icons.check_circle_rounded,
                    iconColor: AppColors.isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                    iconBgColor: AppColors.isDark ? const Color(0xFF4C1D95).withValues(alpha: 0.3) : const Color(0xFFF5F3FF),
                  );

                  if (constraints.maxWidth >= 600) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: card1),
                            const SizedBox(width: 8),
                            Expanded(child: card2),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: card3),
                            const SizedBox(width: 8),
                            Expanded(child: card4),
                          ],
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      card1,
                      const SizedBox(height: 8),
                      card2,
                      const SizedBox(height: 8),
                      card3,
                      const SizedBox(height: 8),
                      card4,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // ── 3. Main Section Header & Action Link ──────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Active Technician Wallets ($displayedCount)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        context.push(AppRoutes.adminFinanceTransactions),
                    icon: Text(
                      'View All Transactions →',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF005965),
                      ),
                    ),
                    label: const SizedBox.shrink(),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── 4. Search & Filter Bar ────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    ref.read(adminWalletSearchQueryProvider.notifier).state =
                        val;
                  },
                  style: TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search technician by name or employee ID...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: AppColors.textMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(
                                      adminWalletSearchQueryProvider.notifier)
                                  .state = '';
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Horizontally Scrollable Status Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    {'id': 'ALL', 'label': 'All Statuses'},
                    {'id': 'ACTIVE', 'label': 'Active'},
                    {'id': 'LOCKED', 'label': 'Locked'},
                    {'id': 'SUSPENDED', 'label': 'Suspended'},
                  ].map((st) {
                    final isSelected = currentStatusFilter == st['id'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          st['label']!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            ref
                                .read(adminWalletStatusFilterProvider.notifier)
                                .state = st['id']!;
                          }
                        },
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        backgroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── 5. Technician Wallets List ────────────────────────────────
              walletsAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child:
                        CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (error, stack) {
                  debugPrint('AdminWalletsScreen error: $error\n$stack');
                  final message = error is DioException
                      ? describeDioError(error,
                          fallback: 'Failed to load technician wallet data.')
                      : error.toString();

                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECDD3)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 36, color: Color(0xFFDC2626)),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load technician wallet data',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text('Retry'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
                data: (_) {
                  if (filteredWallets.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 40, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title:
                            'No technician wallets matched current search criteria.',
                        message:
                            'Try clearing search or changing status filter.',
                      ),
                    );
                  }

                  return Column(
                    children: filteredWallets.map((wallet) {
                      return AdminWalletCard(
                        key: ValueKey(wallet.id),
                        wallet: wallet,
                        onViewTransactions: () {
                          ref
                              .read(adminSelectedTechnicianProvider.notifier)
                              .state = wallet;
                          context.push(AppRoutes.adminFinanceTransactions);
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive Financial Metric Card
class _FinancialMetricCard extends StatelessWidget {
  const _FinancialMetricCard({
    required this.label,
    required this.value,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
  });

  final String label;
  final String value;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x040F172A),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}