import '../../../../core/utils/json_parsing.dart';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// The primary administrator of a service provider organisation.
class ServiceProviderAdmin {
  const ServiceProviderAdmin({
    this.fullName,
    this.username,
    this.email,
    this.phone,
  });

  factory ServiceProviderAdmin.fromJson(Map<String, dynamic> j) =>
      ServiceProviderAdmin(
        fullName: parseString(j['full_name']),
        username: parseString(j['username']),
        email: parseString(j['email']),
        phone: parseString(j['phone']),
      );

  final String? fullName;
  final String? username;
  final String? email;
  final String? phone;

  String get displayName =>
      (fullName ?? '').isNotEmpty ? fullName! : (username ?? '—');
}

/// One row of `GET /workforce/superadmin/service-providers/` (Web
/// `AdminServiceProvidersPage`).
class ServiceProvider {
  const ServiceProvider({
    required this.id,
    required this.companyName,
    required this.isActive,
    this.displayId,
    this.industry,
    this.address,
    this.website,
    this.employeeCount = 0,
    this.createdAt,
    this.primaryAdmin,
  });

  factory ServiceProvider.fromJson(Map<String, dynamic> j) {
    final admin = j['primary_admin'];
    return ServiceProvider(
      id: parseInt(j['id']) ?? 0,
      companyName: parseString(j['company_name']) ?? 'Service Provider',
      isActive: j['is_active'] != false,
      displayId: parseString(j['display_id']),
      industry: parseString(j['industry']),
      address: parseString(j['address']),
      website: parseString(j['website']),
      employeeCount: parseInt(j['employee_count']) ?? 0,
      createdAt: parseDateTime(j['created_at']),
      primaryAdmin: admin is Map
          ? ServiceProviderAdmin.fromJson(_map(admin))
          : null,
    );
  }

  final int id;
  final String companyName;
  final bool isActive;
  final String? displayId;
  final String? industry;
  final String? address;
  final String? website;
  final int employeeCount;
  final DateTime? createdAt;
  final ServiceProviderAdmin? primaryAdmin;

  /// The Web shows the display code, or `ID: {id}` when there is none.
  String get identifier =>
      (displayId ?? '').isNotEmpty ? displayId! : 'ID: $id';
}

/// The create-provider form (Web `formData`).
class NewServiceProvider {
  const NewServiceProvider({
    required this.companyName,
    required this.adminUsername,
    required this.adminEmail,
    required this.adminPassword,
    this.displayId = '',
    this.address = '',
    this.industry = '',
    this.website = '',
    this.adminFirstName = '',
    this.adminLastName = '',
    this.adminPhone = '',
  });

  final String companyName;
  final String displayId;
  final String address;
  final String industry;
  final String website;
  final String adminUsername;
  final String adminEmail;
  final String adminPassword;
  final String adminFirstName;
  final String adminLastName;
  final String adminPhone;

  Map<String, dynamic> toJson() => {
    'company_name': companyName,
    'display_id': displayId,
    'address': address,
    'industry': industry,
    'website': website,
    'admin_username': adminUsername,
    'admin_email': adminEmail,
    'admin_password': adminPassword,
    'admin_first_name': adminFirstName,
    'admin_last_name': adminLastName,
    'admin_phone': adminPhone,
  };
}
