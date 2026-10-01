import '../../../core/config/app_config.dart';

/// Mirrors the user object returned by `/auth/login/` and `/auth/me/`.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.companyId,
    required this.companyName,
    required this.isSuperuser,
    required this.employeeId,
    required this.registrationStatus,
    this.avatar,
    this.isPlatformAdmin = false,
    this.isVendorAdmin = false,
    this.isTechnician = false,
    this.userType,
    this.businessType,
    this.industry,
    this.selectedModules = const [],
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawAvatar =
        (json['avatar'] as String?) ?? (json['avatar_url'] as String?);
    final role = (json['role'] as String? ?? 'employee').toLowerCase();
    final isSuper = json['is_superuser'] as bool? ?? false;
    final companyJson = json['company'] is Map<String, dynamic>
        ? json['company'] as Map<String, dynamic>
        : (json['company_details'] is Map<String, dynamic>
              ? json['company_details'] as Map<String, dynamic>
              : null);
    final companyId =
        (json['company'] as num?)?.toInt() ??
        (companyJson?['id'] as num?)?.toInt();
    final businessType =
        (json['business_type'] as String?) ??
        (companyJson?['business_type'] as String?);
    final industry =
        (json['industry'] as String?) ?? (companyJson?['industry'] as String?);
    final rawModules =
        (json['selected_modules'] as List<dynamic>?) ??
        (companyJson?['selected_modules'] as List<dynamic>?);
    final selectedModules = rawModules != null
        ? rawModules.map((m) => m.toString()).toList()
        : const <String>[];
    final userType = json['user_type'] as String?;
    final isPlatformRole =
        role == 'superadmin' ||
        role == 'platform_admin' ||
        userType == 'platform_admin' ||
        isSuper;
    final isPlatformAdmin =
        (json['is_platform_admin'] == true) ||
        isPlatformRole ||
        ((role == 'admin' || role == 'manager') &&
            (companyId == 1 || companyId == null));
    final isVendorRole =
        role == 'admin' ||
        role == 'manager' ||
        role == 'vendor_admin' ||
        role == 'company_admin';
    final isVendorAdmin =
        !isPlatformAdmin && ((json['is_vendor_admin'] == true) || isVendorRole);
    final isTech =
        (json['is_technician'] as bool?) ??
        (!isPlatformAdmin && !isVendorAdmin);

    return AuthUser(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      role: role,
      companyId: companyId,
      companyName:
          (json['company_name'] as String?) ??
          (companyJson?['company_name'] as String?),
      isSuperuser: isSuper,
      isPlatformAdmin: isPlatformAdmin,
      isVendorAdmin: isVendorAdmin,
      isTechnician: isTech,
      userType: userType,
      businessType: businessType,
      industry: industry,
      selectedModules: selectedModules,
      employeeId: json['employee_id'] as String?,
      registrationStatus:
          (json['registration_status'] as String?) ?? 'not_started',
      avatar: AppConfig.resolveMediaUrl(rawAvatar),
    );
  }

  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final int? companyId;
  final String? companyName;
  final bool isSuperuser;
  final bool isPlatformAdmin;
  final bool isVendorAdmin;
  final bool isTechnician;
  final String? userType;
  final String? businessType;
  final String? industry;
  final List<String> selectedModules;
  final String? employeeId;
  final String registrationStatus;
  final String? avatar;

  /// True for Platform Super Admins.
  bool get isSuperAdmin =>
      isPlatformAdmin ||
      isSuperuser ||
      role == 'superadmin' ||
      role == 'platform_admin' ||
      userType == 'platform_admin';

  /// True for Platform Admins (superuser/staff) and Vendor Admins/Managers.
  bool get isAdmin =>
      isSuperAdmin ||
      isVendorAdmin ||
      isPlatformAdmin ||
      isSuperuser ||
      role == 'admin' ||
      role == 'manager' ||
      role == 'company_admin' ||
      role == 'vendor_admin' ||
      role == 'superadmin' ||
      role == 'platform_admin' ||
      userType == 'platform_admin';

  /// True for Employees / Technicians (mutually exclusive with Admin).
  bool get isEmployee => !isAdmin && (role == 'employee' || isTechnician);

  /// True if the user or company is configured as a Grocery / Multi-Vendor Store supplier,
  /// or is a Platform Superadmin / Company ID 1.
  bool get isGrocerySupplier {
    if (isSuperAdmin || isPlatformAdmin || isSuperuser || companyId == 1) {
      return true;
    }
    final bType = businessType?.toLowerCase() ?? '';
    if (bType == 'grocery_supplier' || bType == 'hybrid') {
      return true;
    }
    final ind = industry?.toLowerCase() ?? '';
    if (ind.contains('grocery') ||
        ind.contains('vegetable') ||
        ind.contains('produce') ||
        ind.contains('farm') ||
        ind.contains('supermarket')) {
      return true;
    }
    for (final m in selectedModules) {
      final lower = m.toLowerCase();
      if (lower == 'grocery_supplier' ||
          lower == 'grocery_inventory' ||
          lower == 'groceries' ||
          lower == 'grocery' ||
          lower == 'produce' ||
          lower == 'store' ||
          lower == 'inventory') {
        return true;
      }
    }
    return false;
  }

  String get displayName {
    final full = '$firstName $lastName'.trim();
    if (full.isNotEmpty) return full;
    return username;
  }
}
