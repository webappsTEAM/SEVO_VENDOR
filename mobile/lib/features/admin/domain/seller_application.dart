import '../../../core/utils/json_parsing.dart';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Owner / primary manager of a seller store (`owner` on the application payload).
class SellerApplicationOwner {
  const SellerApplicationOwner({
    this.firstName,
    this.lastName,
    this.mobile,
    this.email,
  });

  factory SellerApplicationOwner.fromJson(Map<String, dynamic> json) =>
      SellerApplicationOwner(
        firstName: parseString(json['first_name']),
        lastName: parseString(json['last_name']),
        mobile: parseString(json['mobile_number']),
        email: parseString(json['email']),
      );

  final String? firstName;
  final String? lastName;
  final String? mobile;
  final String? email;

  bool get hasName => (firstName ?? '').isNotEmpty;
  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();
}

class SellerApplicationCategory {
  const SellerApplicationCategory({
    required this.id,
    required this.name,
    required this.status,
  });

  factory SellerApplicationCategory.fromJson(Map<String, dynamic> json) =>
      SellerApplicationCategory(
        id: parseString(json['id']) ?? parseString(json['name']) ?? '',
        name: parseString(json['name']) ?? parseString(json['id']) ?? '',
        status: (parseString(json['status']) ?? 'pending').toLowerCase(),
      );

  final String id;
  final String name;
  final String status;
}

class SellerApplicationDocument {
  const SellerApplicationDocument({
    required this.key,
    required this.title,
    required this.status,
    this.documentNumber,
    this.fileUrl,
    this.rejectionReason,
  });

  factory SellerApplicationDocument.fromJson(
    String key,
    Map<String, dynamic> json,
  ) => SellerApplicationDocument(
    key: key,
    title: parseString(json['title']) ?? key,
    status: (parseString(json['status']) ?? 'pending').toLowerCase(),
    documentNumber: parseString(json['document_number']),
    fileUrl: parseString(json['file_url']),
    rejectionReason: parseString(json['rejection_reason']),
  );

  final String key;
  final String title;
  final String status;
  final String? documentNumber;
  final String? fileUrl;
  final String? rejectionReason;

  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

/// One row of `GET /workforce/admin/seller-applications/` and the header of
/// the detail dossier (`.../seller-applications/{id}/`).
class SellerApplication {
  const SellerApplication({
    required this.id,
    required this.storeName,
    required this.companyName,
    required this.registrationStatus,
    required this.owner,
    this.fssaiNumber,
    this.gstNumber,
    this.storeAddress,
    this.createdAt,
    this.isCompanyActive = false,
    this.isAcceptingOrders = false,
    this.documentStatuses = const {},
    this.categories = const [],
    this.documents = const [],
    this.approvedAt,
    this.correctionNotes,
    this.rejectionReason,
  });

  factory SellerApplication.fromJson(Map<String, dynamic> json) {
    final onboarding = _map(json['onboarding_data']);
    final docsMap = _map(onboarding['documents']);
    final docStatus = _map(json['documents_status']);
    final onboardingCats = onboarding['categories'];
    final listCats = json['categories_status'];
    final catSource = onboardingCats is List
        ? onboardingCats
        : (listCats is List ? listCats : const []);
    return SellerApplication(
      id: parseInt(json['id']) ?? 0,
      storeName: parseString(json['store_name']) ?? 'Store',
      companyName: parseString(json['company_name']) ?? '',
      registrationStatus:
          (parseString(json['registration_status']) ?? 'not_started')
              .toLowerCase(),
      owner: SellerApplicationOwner.fromJson(_map(json['owner'])),
      fssaiNumber: parseString(json['fssai_license_number']),
      gstNumber: parseString(json['gst_number']),
      storeAddress: parseString(json['store_address']),
      createdAt: parseDateTime(json['created_at']),
      isCompanyActive: json['is_company_active'] == true,
      isAcceptingOrders: json['is_accepting_orders'] == true,
      documentStatuses: {
        for (final e in docStatus.entries)
          e.key: (parseString(_map(e.value)['status']) ?? '').toLowerCase(),
      },
      categories: [
        for (final c in catSource)
          if (c is Map)
            SellerApplicationCategory.fromJson(Map<String, dynamic>.from(c)),
      ],
      documents: [
        for (final e in docsMap.entries)
          if (e.value is Map)
            SellerApplicationDocument.fromJson(
              e.key,
              Map<String, dynamic>.from(e.value as Map),
            ),
      ],
      approvedAt: parseDateTime(onboarding['approved_at']),
      correctionNotes: parseString(onboarding['correction_notes']),
      rejectionReason: parseString(onboarding['rejection_reason']),
    );
  }

  final int id;
  final String storeName;
  final String companyName;
  final String registrationStatus;
  final SellerApplicationOwner owner;
  final String? fssaiNumber;
  final String? gstNumber;
  final String? storeAddress;
  final DateTime? createdAt;
  final bool isCompanyActive;
  final bool isAcceptingOrders;

  /// List payload: `documents_status` (key → status). Detail payload uses [documents].
  final Map<String, String> documentStatuses;
  final List<SellerApplicationCategory> categories;
  final List<SellerApplicationDocument> documents;
  final DateTime? approvedAt;
  final String? correctionNotes;
  final String? rejectionReason;

  int get docCount =>
      documents.isNotEmpty ? documents.length : documentStatuses.length;
  int get approvedDocCount => documents.isNotEmpty
      ? documents.where((d) => d.isApproved).length
      : documentStatuses.values.where((s) => s == 'approved').length;
  bool get isApproved => registrationStatus == 'approved';

  /// Web counts `submitted`, `under_review` and `pending` as "Under Review".
  bool get isPending =>
      registrationStatus == 'submitted' ||
      registrationStatus == 'under_review' ||
      registrationStatus == 'pending';
  bool get needsCorrection => registrationStatus == 'correction_required';
  bool get isRejected => registrationStatus == 'rejected';
}

/// Chip label for a registration / document / category status.
String sellerStatusLabel(String status) {
  final s = status.toLowerCase();
  return switch (s) {
    'submitted' || 'under_review' || 'pending' => 'Under Review',
    'correction_required' => 'Correction Required',
    'not_started' => 'Not Started',
    _ =>
      s.isEmpty
          ? 'Pending'
          : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}',
  };
}
