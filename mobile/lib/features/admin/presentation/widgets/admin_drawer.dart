import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/sevo_brand_mark.dart';
import '../../../../shared/widgets/workforce_avatar.dart';
import '../../../auth/presentation/auth_controller.dart';

/// The official Admin Navigation Drawer for Workforce Mobile.
/// Provides role-aware, grouped, collapsible navigation matching the SEVO web portal structure:
///
/// Super Admin / Platform Admin:
/// - SEVO Platform / Superadmin Console Header
/// - Platform Dashboard
/// - PLATFORM GOVERNANCE: Vendor Directory, Workforce Roster, Applications Approval, Service Providers
/// - OPERATIONS HUB: AC Estimations, Field Jobs, Dispatch Radar, Skills Master, Scorecards
/// - FINANCE & TREASURY: Platform Treasury, Transactions, Withdrawals, Payout Accounts
/// - TELEMETRY & AUDITS: Database & Egress, Reports & Audits
/// - BOTTOM: System Settings, Log Out
///
/// Vendor Admin / Manager:
/// - SEVO / WORKFORCE ADMIN Header
/// - Home
/// - WORKFORCE: Employees, Applications, Services, Skills
/// - OPERATIONS: Jobs, Dispatch, Live Workforce
/// - FINANCE: Wallets, Transactions, Withdrawals, Bank Accounts
/// - MONITORING: Database & Egress
/// - REPORTS: Reports
/// - SETTINGS: Settings
/// - BOTTOM: Log Out
class AdminDrawer extends ConsumerStatefulWidget {
  const AdminDrawer({super.key});

  @override
  ConsumerState<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends ConsumerState<AdminDrawer> {
  // Super Admin Collapsible Group States
  bool _governanceExpanded = true;
  bool _superAdminSellerHubExpanded = true;
  bool _operationsHubExpanded = true;
  bool _financeTreasuryExpanded = true;
  bool _telemetryAuditsExpanded = true;

  // Vendor Admin Collapsible Group States
  bool _sellerHubExpanded = true;
  bool _workforceExpanded = true;
  bool _operationsExpanded = true;
  bool _financeExpanded = true;
  bool _telemetryExpanded = true;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final isSuperAdmin = user?.isSuperAdmin == true;
    final displayName =
        user?.displayName ?? (isSuperAdmin ? 'Platform Admin' : 'Admin');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';
    final email = user?.email ?? '';
    final photoUrl = user?.avatar;

    // Active route detection
    String currentLocation = '';
    try {
      currentLocation = GoRouterState.of(context).matchedLocation;
    } catch (_) {}

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            // ── Drawer Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                22,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF003B46), // Deep rich teal
                    Color(0xFF005965), // Teal Primary
                    Color(0xFF028090), // Cyan Accent
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SevoBrandMark(size: 44),
                      const SizedBox(width: 12),
                      const SevoHeaderTitle(
                        fontSize: 41,
                      ), // ≈ the previous 24.7px-tall logo
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        WorkforceAvatar(
                          imageUrl: photoUrl,
                          name: displayName,
                          initial: initial,
                          radius: 24,
                          fontSize: 18,
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          foregroundColor: Colors.white,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: const TextStyle(
                                    color: Color(0xFFCFEDEA),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16A34A),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isSuperAdmin ? 'SUPERADMIN' : 'ADMIN',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable Menu ────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                children: [
                  if (isSuperAdmin) ...[
                    // ==========================================
                    // SUPER ADMIN NAVIGATION
                    // ==========================================

                    // TOP: Platform Dashboard
                    _DrawerNavItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Platform Dashboard',
                      route: AppRoutes.superAdminDashboard,
                      isActive:
                          currentLocation == AppRoutes.superAdminDashboard ||
                          currentLocation == '/superadmin' ||
                          currentLocation == '/superadmin/home' ||
                          currentLocation == '/superadmin/dashboard' ||
                          currentLocation == '/workforce/admin',
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(AppRoutes.superAdminDashboard);
                      },
                    ),

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 1. PLATFORM GOVERNANCE
                    _DrawerGroupHeader(
                      title: 'PLATFORM GOVERNANCE',
                      isExpanded: _governanceExpanded,
                      onToggle: () => setState(
                        () => _governanceExpanded = !_governanceExpanded,
                      ),
                    ),
                    if (_governanceExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.business_rounded,
                        label: 'Vendor Directory',
                        route: AppRoutes.superAdminVendors,
                        isActive:
                            currentLocation.startsWith('/superadmin/vendors') ||
                            currentLocation.startsWith(
                              '/workforce/platform/vendors',
                            ) ||
                            currentLocation.startsWith('/platform/vendors'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.superAdminVendors);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.groups_rounded,
                        iconColor: AppColors.primaryLight,
                        label: 'Workforce Roster',
                        route: AppRoutes.superAdminWorkforce,
                        isActive:
                            currentLocation.startsWith(
                              '/superadmin/workforce',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/platform/workforce',
                            ) ||
                            currentLocation.startsWith('/platform/workforce'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.superAdminWorkforce);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.assignment_ind_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: 'Technician Applications',
                        route: AppRoutes.superAdminApplications,
                        isActive:
                            currentLocation.startsWith(
                              '/superadmin/applications',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/platform/applications',
                            ) ||
                            currentLocation.startsWith(
                              '/platform/applications',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.superAdminApplications);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.storefront_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: 'Seller Applications',
                        route: AppRoutes.adminSellerApplications,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/seller-applications',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/seller-applications',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminSellerApplications);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.domain_verification_rounded,
                        label: 'Service Providers',
                        route: AppRoutes.superAdminServiceProviders,
                        isActive: currentLocation.startsWith(
                          '/workforce/platform/providers',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.superAdminServiceProviders);
                        },
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 2. SELLER HUB
                    _DrawerGroupHeader(
                      title: 'SELLER HUB',
                      isExpanded: _superAdminSellerHubExpanded,
                      onToggle: () => setState(
                        () => _superAdminSellerHubExpanded =
                            !_superAdminSellerHubExpanded,
                      ),
                    ),
                    if (_superAdminSellerHubExpanded) ...[
                      ..._buildSellerHubItems(
                        context,
                        currentLocation,
                        platformAdmin: true,
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 3. OPERATIONS HUB
                    _DrawerGroupHeader(
                      title: 'OPERATIONS HUB',
                      isExpanded: _operationsHubExpanded,
                      onToggle: () => setState(
                        () => _operationsHubExpanded = !_operationsHubExpanded,
                      ),
                    ),
                    if (_operationsHubExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.calculate_rounded,
                        iconColor: AppColors.primaryLight,
                        label: 'AC Estimations',
                        route: AppRoutes.adminEstimations,
                        isActive:
                            currentLocation.startsWith('/admin/estimations') ||
                            currentLocation.startsWith(
                              '/workforce/admin/estimations',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminEstimations);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.fact_check_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: 'Quotation Approvals',
                        route: AppRoutes.adminQuotationApprovals,
                        isActive:
                            currentLocation.startsWith('/admin/quotations') ||
                            currentLocation.startsWith(
                              '/workforce/admin/quotations',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminQuotationApprovals);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.receipt_long_rounded,
                        iconColor: const Color(0xFF0D9488),
                        label: 'Invoices',
                        route: AppRoutes.adminInvoices,
                        isActive:
                            currentLocation.startsWith('/admin/invoices') ||
                            currentLocation.startsWith(
                              '/workforce/admin/invoices',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminInvoices);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.work_rounded,
                        label: 'Field Jobs',
                        route: AppRoutes.adminJobs,
                        isActive:
                            currentLocation.startsWith('/admin/jobs') ||
                            currentLocation.startsWith('/workforce/admin/jobs'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminJobs);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.radar_rounded,
                        iconColor: const Color(0xFF059669),
                        label: 'Dispatch Radar',
                        route: AppRoutes.adminDispatch,
                        isActive:
                            currentLocation.startsWith('/admin/dispatch') ||
                            currentLocation.startsWith(
                              '/admin/live-workforce',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/dispatch',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminDispatch);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.military_tech_rounded,
                        label: 'Skills Master',
                        route: AppRoutes.adminSkills,
                        isActive:
                            currentLocation.startsWith('/admin/skills') ||
                            currentLocation.startsWith(
                              '/workforce/admin/skills',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminSkills);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.price_change_rounded,
                        iconColor: const Color(0xFF7C3AED),
                        label: 'Pricing & Approvals',
                        route: AppRoutes.adminPricingApprovals,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/pricing-approvals',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/pricing-approvals',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminPricingApprovals);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.eco_rounded,
                        iconColor: const Color(0xFF16A34A),
                        label: 'Stock Management',
                        route: AppRoutes.adminStock,
                        isActive:
                            currentLocation.startsWith('/admin/stock') ||
                            currentLocation.startsWith(
                              '/workforce/admin/stock',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminStock);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.score_rounded,
                        iconColor: const Color(0xFFD97706),
                        label: 'Scorecards',
                        route: AppRoutes.adminScorecards,
                        isActive:
                            currentLocation.startsWith('/admin/scorecards') ||
                            currentLocation.startsWith(
                              '/workforce/admin/scorecards',
                            ) ||
                            currentLocation.startsWith('/performance') ||
                            currentLocation.startsWith('/more/performance'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminScorecards);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.health_and_safety_rounded,
                        iconColor: const Color(0xFF059669),
                        label: 'Social Security',
                        route: AppRoutes.adminSocialSecurity,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/social-security',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/social-security',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminSocialSecurity);
                        },
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 3. FINANCE & TREASURY
                    _DrawerGroupHeader(
                      title: 'FINANCE & TREASURY',
                      isExpanded: _financeTreasuryExpanded,
                      onToggle: () => setState(
                        () => _financeTreasuryExpanded =
                            !_financeTreasuryExpanded,
                      ),
                    ),
                    if (_financeTreasuryExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: AppColors.primaryLight,
                        label: 'Platform Treasury',
                        route: AppRoutes.adminFinanceWallets,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/wallets',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/wallets',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceWallets);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.receipt_long_rounded,
                        iconColor: const Color(0xFF0D9488),
                        label: 'Transactions',
                        route: AppRoutes.adminFinanceTransactions,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/transactions',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/transactions',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceTransactions);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.payments_rounded,
                        iconColor: const Color(0xFF059669),
                        label: 'Withdrawals',
                        route: AppRoutes.adminFinanceWithdrawals,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/withdrawals',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/withdrawals',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceWithdrawals);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.account_balance_rounded,
                        iconColor: const Color(0xFF6366F1),
                        label: 'Payout Accounts',
                        route: AppRoutes.adminFinanceBankAccounts,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/bank-accounts',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/bank-accounts',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceBankAccounts);
                        },
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 4. TELEMETRY & AUDITS
                    _DrawerGroupHeader(
                      title: 'TELEMETRY & AUDITS',
                      isExpanded: _telemetryAuditsExpanded,
                      onToggle: () => setState(
                        () => _telemetryAuditsExpanded =
                            !_telemetryAuditsExpanded,
                      ),
                    ),
                    if (_telemetryAuditsExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.data_usage_rounded,
                        iconColor: const Color(0xFF0284C7),
                        label: 'Database & Egress',
                        route: AppRoutes.adminMonitoringDatabaseEgress,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/monitoring/database-egress',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/monitoring/database-egress',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminMonitoringDatabaseEgress);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.bar_chart_rounded,
                        label: 'Reports & Audits',
                        route: AppRoutes.adminReports,
                        isActive:
                            currentLocation.startsWith('/admin/reports') ||
                            currentLocation.startsWith(
                              '/workforce/admin/reports',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminReports);
                        },
                      ),
                    ],
                  ] else ...[
                    // ==========================================
                    // VENDOR ADMIN NAVIGATION
                    // ==========================================

                    // 0. COMPANY HEADER CARD
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.isDark
                            ? AppColors.surfaceMuted
                            : const Color(0xFFE6F4F1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.companyName ?? 'Vendor Business',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Company Portal',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 1. COMPANY HOME
                    _DrawerNavItem(
                      icon: Icons.home_rounded,
                      label: 'Company Home',
                      route: AppRoutes.adminHome,
                      isActive:
                          currentLocation == '/admin/home' ||
                          currentLocation == '/workforce/admin' ||
                          currentLocation == AppRoutes.adminHome,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(AppRoutes.adminHome);
                      },
                    ),

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 2. SELLER HUB GROUP
                    _DrawerGroupHeader(
                      title: 'SELLER HUB',
                      isExpanded: _sellerHubExpanded,
                      onToggle: () => setState(
                        () => _sellerHubExpanded = !_sellerHubExpanded,
                      ),
                    ),
                    if (_sellerHubExpanded) ...[
                      ..._buildSellerHubItems(
                        context,
                        currentLocation,
                        platformAdmin: false,
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 3. MY WORKFORCE GROUP
                    _DrawerGroupHeader(
                      title: 'MY WORKFORCE',
                      isExpanded: _workforceExpanded,
                      onToggle: () => setState(
                        () => _workforceExpanded = !_workforceExpanded,
                      ),
                    ),
                    if (_workforceExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.people_alt_rounded,
                        label: 'Tied Technicians',
                        route: AppRoutes.adminTiedTechnicians,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/technician-network',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/technician-network',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminTiedTechnicians);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.mail_outline_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: 'Send Invitations',
                        route: AppRoutes.adminVendorInvitations,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/vendor-invitations',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/vendor-invitations',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminVendorInvitations);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.how_to_reg_rounded,
                        iconColor: AppColors.primaryLight,
                        label: 'Employee Roster',
                        route: AppRoutes.adminEmployees,
                        isActive:
                            currentLocation.startsWith('/admin/employees') ||
                            currentLocation.startsWith(
                              '/workforce/admin/employees',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminEmployees);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.assignment_ind_rounded,
                        iconColor: const Color(0xFF0D9488),
                        label: 'Applications',
                        route: AppRoutes.adminApplications,
                        isActive:
                            currentLocation.startsWith('/admin/applications') ||
                            currentLocation.startsWith(
                              '/workforce/admin/applications',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminApplications);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.storefront_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: 'Seller Applications',
                        route: AppRoutes.adminSellerApplications,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/seller-applications',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/seller-applications',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminSellerApplications);
                        },
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 3. OPERATIONS GROUP
                    _DrawerGroupHeader(
                      title: 'OPERATIONS',
                      isExpanded: _operationsExpanded,
                      onToggle: () => setState(
                        () => _operationsExpanded = !_operationsExpanded,
                      ),
                    ),
                    if (_operationsExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.work_rounded,
                        label: 'Field Jobs',
                        route: AppRoutes.adminJobs,
                        isActive:
                            currentLocation.startsWith('/admin/jobs') ||
                            currentLocation.startsWith('/workforce/admin/jobs'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminJobs);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.send_rounded,
                        iconColor: const Color(0xFF059669),
                        label: 'Dispatch Radar',
                        route: AppRoutes.adminDispatch,
                        isActive:
                            currentLocation.startsWith('/admin/dispatch') ||
                            currentLocation.startsWith(
                              '/admin/live-workforce',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/dispatch',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminDispatch);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.apartment_rounded,
                        iconColor: const Color(0xFF7C3AED),
                        label: 'Company Profile',
                        route: AppRoutes.adminProviderProfile,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/provider-profile',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/provider-profile',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/provider/profile',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminProviderProfile);
                        },
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 4. FINANCE & LEDGER GROUP
                    _DrawerGroupHeader(
                      title: 'FINANCE & LEDGER',
                      isExpanded: _financeExpanded,
                      onToggle: () =>
                          setState(() => _financeExpanded = !_financeExpanded),
                    ),
                    if (_financeExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: AppColors.primaryLight,
                        label: 'Company Wallet',
                        route: AppRoutes.adminFinanceWallets,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/wallets',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/wallets',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceWallets);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.receipt_long_rounded,
                        iconColor: const Color(0xFF0D9488),
                        label: 'Transactions',
                        route: AppRoutes.adminFinanceTransactions,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/transactions',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/transactions',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceTransactions);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.payments_rounded,
                        iconColor: const Color(0xFF059669),
                        label: 'Withdrawals',
                        route: AppRoutes.adminFinanceWithdrawals,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/withdrawals',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/withdrawals',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceWithdrawals);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.account_balance_rounded,
                        iconColor: const Color(0xFF6366F1),
                        label: 'Payout Accounts',
                        route: AppRoutes.adminFinanceBankAccounts,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/finance/bank-accounts',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/finance/bank-accounts',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminFinanceBankAccounts);
                        },
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),

                    // 5. TELEMETRY GROUP
                    _DrawerGroupHeader(
                      title: 'TELEMETRY',
                      isExpanded: _telemetryExpanded,
                      onToggle: () => setState(
                        () => _telemetryExpanded = !_telemetryExpanded,
                      ),
                    ),
                    if (_telemetryExpanded) ...[
                      _DrawerNavItem(
                        icon: Icons.data_usage_rounded,
                        iconColor: const Color(0xFF0284C7),
                        label: 'Database & Egress',
                        route: AppRoutes.adminMonitoringDatabaseEgress,
                        isActive:
                            currentLocation.startsWith(
                              '/admin/monitoring/database-egress',
                            ) ||
                            currentLocation.startsWith(
                              '/workforce/admin/monitoring/database-egress',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminMonitoringDatabaseEgress);
                        },
                      ),
                      _DrawerNavItem(
                        icon: Icons.bar_chart_rounded,
                        iconColor: AppColors.primaryLight,
                        label: 'Reports & Audits',
                        route: AppRoutes.adminReports,
                        isActive:
                            currentLocation.startsWith('/admin/reports') ||
                            currentLocation.startsWith(
                              '/workforce/admin/reports',
                            ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(AppRoutes.adminReports);
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),

            // ── Drawer Footer: System Settings & Log Out ───────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DrawerNavItem(
                    icon: Icons.settings_rounded,
                    iconColor: AppColors.textSecondary,
                    label: 'System Settings',
                    route: isSuperAdmin
                        ? AppRoutes.adminSettings
                        : AppRoutes.adminHome,
                    isActive: isSuperAdmin
                        ? (currentLocation == AppRoutes.adminSettings ||
                              currentLocation.startsWith('/admin/settings') ||
                              currentLocation.startsWith(
                                '/workforce/admin/settings',
                              ))
                        : false,
                    onTap: () {
                      Navigator.of(context).pop();
                      if (isSuperAdmin) {
                        context.go(AppRoutes.adminSettings);
                      } else {
                        context.go(AppRoutes.adminHome);
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Material(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.logout_rounded,
                              color: Color(0xFFDC2626),
                              size: 22,
                            ),
                            const SizedBox(width: 14),
                            const Text(
                              'Log Out',
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Log Out'),
                            content: Text(
                              'Are you sure you want to log out of Workforce?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: Text('Log Out'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref
                              .read(authControllerProvider.notifier)
                              .logout();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Seller Hub entries. Categories, Categories Approval and Warehouses are
  /// platform-admin only, matching the Web vendor-admin sidebar.
  List<Widget> _buildSellerHubItems(
    BuildContext context,
    String currentLocation, {
    required bool platformAdmin,
  }) {
    return [
      _DrawerNavItem(
        icon: Icons.storefront_rounded,
        iconColor: const Color(0xFF0D9488),
        label: 'Home',
        route: AppRoutes.sellerHome,
        isActive:
            currentLocation == AppRoutes.sellerHome ||
            currentLocation.startsWith('/admin/seller/home') ||
            currentLocation.startsWith('/workforce/admin/seller/home'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerHome);
        },
      ),
      _DrawerNavItem(
        icon: Icons.shopping_bag_rounded,
        iconColor: const Color(0xFF2563EB),
        label: 'Orders',
        route: AppRoutes.sellerOrders,
        isActive:
            currentLocation == AppRoutes.sellerOrders ||
            currentLocation.startsWith('/admin/seller/orders') ||
            currentLocation.startsWith('/workforce/admin/seller/orders') ||
            currentLocation.startsWith('/workforce/admin/grocery-orders') ||
            currentLocation.startsWith('/admin/grocery-orders'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerOrders);
        },
      ),
      _DrawerNavItem(
        icon: Icons.assignment_return_rounded,
        iconColor: const Color(0xFFDC2626),
        label: 'Returns',
        route: AppRoutes.sellerReturns,
        isActive:
            currentLocation == AppRoutes.sellerReturns ||
            currentLocation.startsWith('/admin/seller/returns') ||
            currentLocation.startsWith('/workforce/admin/seller/returns'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerReturns);
        },
      ),
      _DrawerNavItem(
        icon: Icons.gavel_rounded,
        iconColor: const Color(0xFFD97706),
        label: 'Claims',
        route: AppRoutes.sellerClaims,
        isActive:
            currentLocation == AppRoutes.sellerClaims ||
            currentLocation.startsWith('/admin/seller/claims') ||
            currentLocation.startsWith('/workforce/admin/seller/claims'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerClaims);
        },
      ),
      _DrawerNavItem(
        icon: Icons.inventory_2_rounded,
        iconColor: const Color(0xFF059669),
        label: 'Inventory',
        route: AppRoutes.sellerInventory,
        isActive:
            currentLocation == AppRoutes.sellerInventory ||
            currentLocation.startsWith('/admin/seller/inventory') ||
            currentLocation.startsWith('/workforce/admin/seller/inventory') ||
            currentLocation.startsWith('/workforce/admin/inventory') ||
            currentLocation.startsWith('/admin/inventory'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerInventory);
        },
      ),
      _DrawerNavItem(
        icon: Icons.cloud_upload_rounded,
        iconColor: const Color(0xFF6366F1),
        label: 'Catalog Uploads',
        route: AppRoutes.sellerCatalogUploads,
        isActive:
            currentLocation == AppRoutes.sellerCatalogUploads ||
            currentLocation.startsWith('/admin/seller/catalog-uploads') ||
            currentLocation.startsWith(
              '/workforce/admin/seller/catalog-uploads',
            ),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerCatalogUploads);
        },
      ),
      if (platformAdmin) ...[
        _DrawerNavItem(
          icon: Icons.category_rounded,
          iconColor: const Color(0xFF8B5CF6),
          label: 'Categories',
          route: AppRoutes.sellerCategories,
          isActive:
              currentLocation == AppRoutes.sellerCategories ||
              (currentLocation.startsWith('/admin/seller/categories') &&
                  !currentLocation.startsWith(
                    AppRoutes.sellerCategoriesApproval,
                  )),
          onTap: () {
            Navigator.of(context).pop();
            context.go(AppRoutes.sellerCategories);
          },
        ),
        _DrawerNavItem(
          icon: Icons.fact_check_rounded,
          iconColor: const Color(0xFF0284C7),
          label: 'Categories Approval',
          route: AppRoutes.sellerCategoriesApproval,
          isActive:
              currentLocation == AppRoutes.sellerCategoriesApproval ||
              currentLocation.startsWith('/admin/seller/categories-approval') ||
              currentLocation.startsWith(
                '/workforce/admin/seller/categories-approval',
              ),
          onTap: () {
            Navigator.of(context).pop();
            context.go(AppRoutes.sellerCategoriesApproval);
          },
        ),
        _DrawerNavItem(
          icon: Icons.warehouse_rounded,
          iconColor: const Color(0xFFEA580C),
          label: 'Warehouses',
          route: AppRoutes.sellerWarehouse,
          isActive:
              currentLocation == AppRoutes.sellerWarehouse ||
              currentLocation.startsWith('/admin/seller/warehouse') ||
              currentLocation.startsWith('/workforce/admin/seller/warehouse') ||
              currentLocation.startsWith('/workforce/admin/warehouse') ||
              currentLocation.startsWith('/admin/warehouse'),
          onTap: () {
            Navigator.of(context).pop();
            context.go(AppRoutes.sellerWarehouse);
          },
        ),
      ],
      _DrawerNavItem(
        icon: Icons.local_offer_rounded,
        iconColor: const Color(0xFFEC4899),
        label: 'Coupons',
        route: AppRoutes.sellerCoupons,
        isActive:
            currentLocation == AppRoutes.sellerCoupons ||
            currentLocation.startsWith('/admin/seller/coupons') ||
            currentLocation.startsWith('/workforce/admin/seller/coupons') ||
            currentLocation.startsWith('/workforce/admin/promotions') ||
            currentLocation.startsWith('/admin/promotions'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerCoupons);
        },
      ),
      _DrawerNavItem(
        icon: Icons.insights_rounded,
        iconColor: const Color(0xFF10B981),
        label: 'Reports & Quality',
        route: AppRoutes.sellerReportsQuality,
        isActive:
            currentLocation == AppRoutes.sellerReportsQuality ||
            currentLocation.startsWith('/admin/seller/reports-quality') ||
            currentLocation.startsWith(
              '/workforce/admin/seller/reports-quality',
            ),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerReportsQuality);
        },
      ),
      _DrawerNavItem(
        icon: Icons.store_rounded,
        iconColor: const Color(0xFF0D9488),
        label: 'Store Profile',
        route: AppRoutes.sellerStoreProfile,
        isActive:
            currentLocation == AppRoutes.sellerStoreProfile ||
            currentLocation.startsWith('/admin/seller/store-profile') ||
            currentLocation.startsWith(
              '/workforce/admin/seller/store-profile',
            ) ||
            currentLocation.startsWith('/workforce/admin/store-profile') ||
            currentLocation.startsWith('/admin/store-profile'),
        onTap: () {
          Navigator.of(context).pop();
          context.go(AppRoutes.sellerStoreProfile);
        },
      ),
    ];
  }
}

class _DrawerGroupHeader extends StatelessWidget {
  const _DrawerGroupHeader({
    required this.title,
    required this.isExpanded,
    required this.onToggle,
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0 : -0.25,
              duration: AppMotion.resolve(AppMotion.normal),
              curve: AppMotion.curve,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A menu row: tinted rounded icon tile, label and chevron. The active route
/// gets a soft teal wash.
class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.route,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String route;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = iconColor ?? AppColors.primaryAccent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isActive ? AppColors.selectedTint : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: base.withValues(alpha: isActive ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: base, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                      color: isActive
                          ? AppColors.selectedOnTint
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: isActive
                      ? AppColors.selectedOnTint
                      : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
