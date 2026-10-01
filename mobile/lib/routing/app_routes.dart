/// Route path constants shared between the router and (later) any widget
/// that needs to know a path, e.g. for testing.
class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const createAccount = '/create-account';
  static const providerRegister = '/provider/register';
  static const onboardingWizard = '/onboarding/wizard';
  static const pendingReview = '/pending-review';
  static const correctionRequired = '/correction-required';
  static const rejected = '/rejected';
  static const registrationIncomplete = '/registration-incomplete';
  static const employeeOnly = '/employee-only';
  static const home = '/home';
  static const jobs = '/jobs';
  static const performance = '/performance';
  static const estimates = '/estimates';
  static const invitations = '/invitations';
  static const notifications = '/notifications';
  static const more = '/more';
  static const moreProfile = '/more/profile';
  static const morePerformance = '/more/performance';
  static const moreEstimates = '/more/estimates';
  static const moreInvitations = '/more/invitations';
  static const moreDocuments = '/more/documents';
  static const moreServices = '/more/services';
  static const moreLocations = '/more/locations';
  static const moreSettings = '/more/settings';
  static const moreSettingsSecurity = '/more/settings/security';
  static const moreSettingsAppearance = '/more/settings/appearance';
  static const moreSettingsNotifications = '/more/settings/notifications';
  static const moreSettingsPrivacy = '/more/settings/privacy';

  // Employee Earnings routes
  static const earnings = '/earnings';
  static const earningsWallet = '/earnings/wallet';
  static const earningsTransactions = '/earnings/transactions';
  static const earningsWithdrawals = '/earnings/withdrawals';
  static const earningsBankAccount = '/earnings/bank-account';

  // Super Admin routes
  static const superAdminDashboard = '/superadmin/dashboard';
  static const superAdminWorkforce = '/superadmin/workforce';
  static const superAdminServiceProviders = '/workforce/platform/providers';
  static const superAdminVendors = '/superadmin/vendors';
  static const superAdminApplications = '/superadmin/applications';

  // Admin / Workforce Operations Center routes
  static const adminHome = '/admin/home';
  static const adminTiedTechnicians = '/admin/technician-network';
  static const adminVendorInvitations = '/admin/vendor-invitations';
  static const adminEmployees = '/admin/employees';
  static const adminApplications = '/admin/applications';
  static const adminApplicationDetail = '/admin/applications/:id';
  static const adminServices = '/admin/services';
  static const adminSkills = '/admin/skills';
  static const adminJobs = '/admin/jobs';
  static const adminDispatch = '/admin/dispatch';
  static const adminLiveWorkforce = '/admin/live-workforce';
  static const adminProviderProfile = '/admin/provider-profile';
  static const adminQuotationApprovals = '/admin/quotations';
  static const adminEstimations = '/admin/estimations';
  static const adminSellerApplications = '/admin/seller-applications';
  static const adminStock = '/admin/stock';
  static const adminInvoices = '/admin/invoices';
  static const adminPricingApprovals = '/admin/pricing-approvals';
  static const adminScorecards = '/admin/scorecards';
  static const adminSocialSecurity = '/admin/social-security';
  static const adminReports = '/admin/reports';
  static const adminSettings = '/admin/settings';

  // Admin Finance routes
  static const adminFinanceWallets = '/admin/finance/wallets';
  static const adminFinanceTransactions = '/admin/finance/transactions';
  static const adminFinanceWithdrawals = '/admin/finance/withdrawals';
  static const adminFinanceBankAccounts = '/admin/finance/bank-accounts';

  // Admin Monitoring routes
  static const adminMonitoringDatabaseEgress =
      '/admin/monitoring/database-egress';

  // Seller Hub routes
  static const sellerHome = '/admin/seller/home';
  static const sellerOrders = '/admin/seller/orders';
  static const sellerReturns = '/admin/seller/returns';
  static const sellerClaims = '/admin/seller/claims';
  static const sellerInventory = '/admin/seller/inventory';
  static const sellerCatalogUploads = '/admin/seller/catalog-uploads';
  static const sellerCategories = '/admin/seller/categories';
  static const sellerCategoriesApproval = '/admin/seller/categories-approval';
  static const sellerCategoriesApprovalDetail =
      '/admin/seller/categories-approval/:sellerId';
  static const sellerWarehouse = '/admin/seller/warehouse';
  static const sellerCoupons = '/admin/seller/coupons';
  static const sellerReportsQuality = '/admin/seller/reports-quality';
  static const sellerStoreProfile = '/admin/seller/store-profile';
}
