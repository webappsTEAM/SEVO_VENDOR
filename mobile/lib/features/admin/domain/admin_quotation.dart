import '../../../core/utils/json_parsing.dart';

/// Represents a quotation in the SEVO back office approval and pre-send review queues.
///
/// Backed by `/api/workforce/quotes/pending-approval/` and `/api/workforce/quotes/pending-review/`.
class AdminQuotation {
  const AdminQuotation({
    required this.id,
    required this.quoteNumber,
    this.quoteVersion = 1,
    required this.title,
    this.description = '',
    required this.status,
    required this.statusDisplay,
    required this.serviceCategory,
    required this.serviceName,
    required this.jobId,
    this.workJobId,
    this.technicianId,
    this.companyId,
    this.customerId,
    this.customerName = 'Customer',
    this.estimatedLaborCost = 0.0,
    this.estimatedMaterialsCost = 0.0,
    this.subtotalAmount = 0.0,
    this.discountAmount = 0.0,
    this.taxAmount = 0.0,
    this.totalAmount = 0.0,
    this.inspectionFee = 0.0,
    this.inspectionFeeAdjusted = 0.0,
    this.netPayable = 0.0,
    this.requiresStructuralClearance = false,
    this.isStructurallyCleared = false,
    this.customerDecision,
    this.customerDeclineReason,
    this.customerNotes,
    this.submittedForApprovalAt,
    this.validUntil,
    this.createdAt,
    this.updatedAt,
    this.customerDecidedAt,
    this.advanceAmount,
    this.balanceAmount,
    this.items = const [],
    this.measurements = const [],
  });

  factory AdminQuotation.fromJson(Map<String, dynamic> json) {
    return AdminQuotation(
      id: parseInt(json['id']) ?? 0,
      quoteNumber: parseString(json['quote_number']) ?? 'QT-${json['id']}',
      quoteVersion: parseInt(json['quote_version']) ?? 1,
      title: parseString(json['title']) ?? '',
      description: parseString(json['description']) ?? '',
      status: parseString(json['status'])?.toUpperCase() ?? 'DRAFT',
      statusDisplay:
          parseString(json['status_display']) ??
          parseString(json['status']) ??
          'Draft',
      serviceCategory: parseString(json['service_category']) ?? 'Service',
      serviceName:
          parseString(json['service_name']) ??
          parseString(json['title']) ??
          'Quotation',
      jobId: parseInt(json['job_id']) ?? 0,
      workJobId: parseInt(json['work_job_id']),
      technicianId: parseInt(json['technician_id']),
      companyId: parseInt(json['company_id']),
      customerId: parseInt(json['customer_id']),
      customerName: parseString(json['customer_name']) ?? 'Customer',
      estimatedLaborCost: parseDouble(json['estimated_labor_cost']) ?? 0.0,
      estimatedMaterialsCost:
          parseDouble(json['estimated_materials_cost']) ?? 0.0,
      subtotalAmount: parseDouble(json['subtotal_amount']) ?? 0.0,
      discountAmount: parseDouble(json['discount_amount']) ?? 0.0,
      taxAmount: parseDouble(json['tax_amount']) ?? 0.0,
      totalAmount: parseDouble(json['total_amount']) ?? 0.0,
      inspectionFee: parseDouble(json['inspection_fee']) ?? 0.0,
      inspectionFeeAdjusted:
          parseDouble(json['inspection_fee_adjusted']) ?? 0.0,
      netPayable:
          parseDouble(json['net_payable']) ??
          parseDouble(json['total_amount']) ??
          0.0,
      requiresStructuralClearance: parseBool(
        json['requires_structural_clearance'],
      ),
      isStructurallyCleared: parseBool(json['is_structurally_cleared']),
      customerDecision: parseString(json['customer_decision']),
      customerDeclineReason: parseString(json['customer_decline_reason']),
      customerNotes: parseString(json['customer_notes']),
      submittedForApprovalAt: parseDateTime(json['submitted_for_approval_at']),
      validUntil: parseDateTime(json['valid_until']),
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
      customerDecidedAt: parseDateTime(json['customer_decided_at']),
      advanceAmount: parseDouble(json['advance_amount']),
      balanceAmount: parseDouble(json['balance_amount']),
      items: [
        for (final i
            in (json['items'] is List ? json['items'] as List : const []))
          if (i is Map) AdminQuoteItem.fromJson(Map<String, dynamic>.from(i)),
      ],
      measurements: [
        for (final m
            in (json['measurements'] is List
                ? json['measurements'] as List
                : const []))
          if (m is Map)
            AdminQuoteMeasurement.fromJson(Map<String, dynamic>.from(m)),
      ],
    );
  }

  final int id;
  final String quoteNumber;
  final int quoteVersion;
  final String title;
  final String description;
  final String status;
  final String statusDisplay;
  final String serviceCategory;
  final String serviceName;
  final int jobId;
  final int? workJobId;
  final int? technicianId;
  final int? companyId;
  final int? customerId;
  final String customerName;
  final double estimatedLaborCost;
  final double estimatedMaterialsCost;
  final double subtotalAmount;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final double inspectionFee;
  final double inspectionFeeAdjusted;
  final double netPayable;
  final bool requiresStructuralClearance;
  final bool isStructurallyCleared;
  final String? customerDecision;
  final String? customerDeclineReason;
  final String? customerNotes;
  final DateTime? submittedForApprovalAt;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? customerDecidedAt;
  final double? advanceAmount;
  final double? balanceAmount;
  final List<AdminQuoteItem> items;
  final List<AdminQuoteMeasurement> measurements;

  double _round(double v) => (v * 100).roundToDouble() / 100;

  /// 50% advance milestone; the Web falls back to half the net payable.
  double get advance => advanceAmount ?? _round(netPayable * 0.5);

  /// 50% completion balance.
  double get balance => balanceAmount ?? _round(netPayable - advance);

  double get totalArea => measurements.fold(0.0, (sum, m) => sum + m.area);

  bool get isHeldForReview => status == 'PENDING_REVIEW';
  bool get isAwaitingApproval =>
      status == 'CUSTOMER_ACCEPTED' || status == 'PENDING_ADMIN_APPROVAL';

  /// Status label as the Web badge prints it.
  String get statusLabel => isHeldForReview
      ? 'HELD FOR CRM REVIEW'
      : (statusDisplay.isNotEmpty
            ? statusDisplay
            : status.replaceAll('_', ' '));
}

class AdminQuoteItem {
  const AdminQuoteItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.taxRate,
    this.section,
    required this.total,
  });

  factory AdminQuoteItem.fromJson(Map<String, dynamic> json) {
    return AdminQuoteItem(
      name:
          parseString(json['name']) ??
          parseString(json['description']) ??
          'Quotation Item',
      quantity: parseDouble(json['quantity']) ?? 0,
      unit: parseString(json['unit']) ?? 'sqft',
      unitPrice:
          parseDouble(json['unit_price']) ?? parseDouble(json['rate']) ?? 0,
      taxRate: parseDouble(json['tax_rate']) ?? 0,
      section: parseString(json['section']),
      total:
          parseDouble(json['total_amount']) ??
          parseDouble(json['line_total']) ??
          0,
    );
  }

  final String name;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double taxRate;
  final String? section;
  final double total;
}

class AdminQuoteMeasurement {
  const AdminQuoteMeasurement({
    required this.name,
    this.length,
    this.width,
    this.height,
    required this.area,
  });

  factory AdminQuoteMeasurement.fromJson(Map<String, dynamic> json) {
    return AdminQuoteMeasurement(
      name: parseString(json['name']) ?? '',
      length: parseDouble(json['length']),
      width: parseDouble(json['width']),
      height: parseDouble(json['height']),
      area:
          parseDouble(json['area']) ??
          parseDouble(json['calculated_area']) ??
          0,
    );
  }

  final String name;
  final double? length;
  final double? width;
  final double? height;
  final double area;
}
