import '../../../core/utils/json_parsing.dart';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// Lead tabs of the Web AC Inspection & Quotation Manager (`id` is the API value).
const estimationFilterTabs = <(String, String)>[
  ('all', 'All Leads'),
  ('requested', 'New Requests'),
  ('assigned', 'Assigned'),
  ('in_progress', 'In Progress'),
  ('quotation_sent', 'Quotation Sent'),
  ('completed', 'Completed'),
];

/// `TECHNICIAN_ON_THE_WAY` → `TECHNICIAN ON THE WAY`.
String estimationStatusLabel(String status) => status.replaceAll('_', ' ');

/// Stage banner text of the Web detail console.
String estimationStageTitle(VendorEstimation e) => switch (e.status) {
  'REQUESTED' => 'New Lead Unconfirmed — Vendor Acceptance Required',
  'VENDOR_CONFIRMED' => 'Confirmed — Assign On-site Field Technician',
  'TECHNICIAN_ASSIGNED' =>
    'Technician ${e.technicianName ?? ''} Assigned — Ready for Journey',
  'TECHNICIAN_ON_THE_WAY' => 'Technician In Transit to Customer Location',
  'TECHNICIAN_ARRIVED' =>
    'Technician Arrived at Site — Customer Start OTP Required',
  'INSPECTION_IN_PROGRESS' =>
    'Inspection In Progress — Record Structured Defect Findings',
  'INSPECTION_COMPLETED' =>
    'Inspection Completed — Draft and Send Formal Quotation',
  'QUOTATION_SENT' => 'Formal Quotation Sent — Awaiting Customer Approval',
  'CUSTOMER_APPROVED' =>
    'Customer Approved — Collect Visit Fee & Commencing Work',
  'CUSTOMER_REJECTED' => 'Customer Rejected Quote — Revise Pricing & Resend',
  _ => 'Job Lifecycle Active',
};

class EstimationRateItem {
  const EstimationRateItem({
    required this.name,
    this.category,
    this.unit,
    this.price,
  });

  factory EstimationRateItem.fromJson(Map<String, dynamic> j) =>
      EstimationRateItem(
        name: parseString(j['item_name']) ?? '',
        category: parseString(j['category']),
        unit: parseString(j['unit']),
        price: parseDouble(j['price']),
      );

  final String name;
  final String? category;
  final String? unit;
  final double? price;
}

class EstimationFinding {
  const EstimationFinding({
    required this.title,
    this.severity,
    this.description,
    this.recommendedAction,
  });

  factory EstimationFinding.fromJson(Map<String, dynamic> j) =>
      EstimationFinding(
        title: parseString(j['title']) ?? '',
        severity: parseString(j['severity']),
        description: parseString(j['description']),
        recommendedAction: parseString(j['recommended_action']),
      );

  final String title;
  final String? severity;
  final String? description;
  final String? recommendedAction;
}

/// One lead from `GET /vendor/estimations/` (and its detail).
class VendorEstimation {
  const VendorEstimation({
    required this.id,
    required this.status,
    this.requestId,
    this.srStatus,
    this.customerName,
    this.phone,
    this.email,
    this.address,
    this.preferredDate,
    this.preferredTime,
    this.createdAt,
    this.acBrand,
    this.acType,
    this.acCapacity,
    this.acQuantity,
    this.symptom,
    this.feeStatus,
    this.feeAmount,
    this.technicianName,
    this.technicianPhone,
    this.rateCard = const [],
    this.findings = const [],
    this.raw = const {},
  });

  factory VendorEstimation.fromJson(Map<String, dynamic> j) {
    final ac = _map(j['ac_details']);
    final fee = _map(j['fee']);
    final tech = _map(j['technician']);
    return VendorEstimation(
      id: parseInt(j['id']) ?? 0,
      status: parseString(j['status']) ?? 'REQUESTED',
      requestId: parseString(j['request_id']),
      srStatus: parseString(j['sr_status']),
      customerName: parseString(j['customer_name']),
      phone: parseString(j['phone']),
      email: parseString(j['email']),
      address: parseString(j['address']),
      preferredDate: parseString(j['preferred_date']),
      preferredTime: parseString(j['preferred_time']),
      createdAt: parseDateTime(j['created_at']),
      acBrand: parseString(ac['ac_brand']),
      acType: parseString(ac['ac_type']),
      acCapacity: parseString(ac['ac_capacity']),
      acQuantity: parseInt(ac['ac_quantity']),
      symptom: parseString(ac['customer_symptom']),
      feeStatus: parseString(fee['status']),
      feeAmount: parseDouble(fee['amount']),
      technicianName: parseString(tech['name']),
      technicianPhone: parseString(tech['phone']),
      rateCard: [
        for (final r in _maps(j['rate_card_snapshot']))
          EstimationRateItem.fromJson(r),
      ],
      findings: [
        for (final f in _maps(j['findings'])) EstimationFinding.fromJson(f),
      ],
      raw: j,
    );
  }

  final int id;
  final String status;
  final String? requestId;
  final String? srStatus;
  final String? customerName;
  final String? phone;
  final String? email;
  final String? address;
  final String? preferredDate;
  final String? preferredTime;
  final DateTime? createdAt;
  final String? acBrand;
  final String? acType;
  final String? acCapacity;
  final int? acQuantity;
  final String? symptom;
  final String? feeStatus;
  final double? feeAmount;
  final String? technicianName;
  final String? technicianPhone;
  final List<EstimationRateItem> rateCard;
  final List<EstimationFinding> findings;

  /// The untouched API payload (quotations, decision data, …).
  final Map<String, dynamic> raw;

  String get reference => requestId ?? '#$id';
  String get capacityLabel => (acCapacity ?? '1.5 Ton').replaceAll('_', ' ');
  String get feeStatusOrPending => feeStatus ?? 'PENDING';
}

class VendorEstimationList {
  const VendorEstimationList({required this.leads, this.metrics});

  factory VendorEstimationList.fromJson(dynamic body) {
    if (body is List) {
      return VendorEstimationList(
        leads: [
          for (final r in body)
            if (r is Map)
              VendorEstimation.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
    }
    final m = _map(body);
    final metrics = m['metrics'] is Map
        ? Map<String, dynamic>.from(m['metrics'] as Map)
        : null;
    return VendorEstimationList(
      leads: [
        for (final r in _maps(m['results'])) VendorEstimation.fromJson(r),
      ],
      metrics: metrics == null
          ? null
          : {for (final e in metrics.entries) e.key: parseInt(e.value) ?? 0},
    );
  }

  final List<VendorEstimation> leads;

  /// `all`, `requested`, `assigned`, `in_progress`, `quotation_sent`, `completed`.
  final Map<String, int>? metrics;
}

class VendorTechnician {
  const VendorTechnician({
    required this.id,
    required this.name,
    this.title,
    this.phone,
  });

  factory VendorTechnician.fromJson(Map<String, dynamic> j) => VendorTechnician(
    id: parseString(j['id']) ?? '',
    name: parseString(j['name']) ?? '',
    title: parseString(j['title']),
    phone: parseString(j['phone']),
  );

  final String id;
  final String name;
  final String? title;
  final String? phone;
}
