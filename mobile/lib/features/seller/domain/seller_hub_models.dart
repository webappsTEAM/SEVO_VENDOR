/// Domain models for the Seller Hub fulfilment engine
/// (`/api/workforce/seller-hub/*`), mirroring the payloads consumed by the
/// Web pages `SellerDashboardPage`, `SellerOrdersPage` and `SellerReturnsPage`.
library;

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
  return 0;
}

int? _intOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString();
  return s.isEmpty ? fallback : s;
}

String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

bool _bool(dynamic v) => v == true || v == 'true' || v == 1;

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

List<Map<String, dynamic>> _maps(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

/// Formats a decimal quantity like the backend's `"4.000"` as `4`, keeping
/// real fractions (e.g. `1.5`).
String formatQuantity(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics — GET /workforce/seller-hub/metrics/
// ─────────────────────────────────────────────────────────────────────────────

class SellerHubMetrics {
  const SellerHubMetrics({
    required this.catalogsAwaitingApproval,
    required this.approvedProducts,
    required this.activeCategories,
    required this.activeCoupons,
    required this.totalInventoryProducts,
    required this.lowStockItems,
    required this.outOfStockItems,
    required this.todayOrders,
    required this.pendingOrders,
    required this.inPrepOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.totalReturns,
    required this.pendingReturns,
    required this.underInspectionReturns,
    required this.resolvedReturns,
    required this.totalClaims,
    required this.openClaims,
    required this.claimsRequiringResponse,
    this.escalatedClaims = 0,
    this.resolvedClaims = 0,
    this.inStockItems = 0,
    this.expiringSoonItems = 0,
    this.totalInventoryValue = 0,
    this.totalProducts = 0,
    this.draftProducts = 0,
    this.changesRequested = 0,
    this.rejectedProducts = 0,
  });

  factory SellerHubMetrics.fromJson(Map<String, dynamic> json) {
    return SellerHubMetrics(
      catalogsAwaitingApproval: _int(json['catalogs_awaiting_approval']),
      approvedProducts: _int(json['approved_products']),
      activeCategories: _intOrNull(json['active_categories']),
      activeCoupons: _intOrNull(json['active_coupons']),
      totalInventoryProducts: _int(json['total_inventory_products']),
      lowStockItems: _int(json['low_stock_items_count']),
      outOfStockItems: _int(json['out_of_stock_items_count']),
      todayOrders: _int(json['today_orders_count']),
      pendingOrders: _int(json['pending_orders_count']),
      inPrepOrders: _int(json['in_prep_orders_count']),
      completedOrders: _int(json['completed_orders_count']),
      cancelledOrders: _int(json['cancelled_orders_count']),
      totalReturns: _int(json['total_returns_count']),
      pendingReturns: _int(json['pending_returns_count']),
      underInspectionReturns: _int(json['under_inspection_returns_count']),
      resolvedReturns: _int(json['resolved_returns_count']),
      totalClaims: _int(json['total_claims_count']),
      openClaims: _int(json['open_claims_count']),
      claimsRequiringResponse: _int(json['claims_requiring_response_count']),
      escalatedClaims: _int(json['escalated_claims_count']),
      resolvedClaims: _int(json['resolved_claims_count']),
      inStockItems: _int(json['in_stock_items_count']),
      expiringSoonItems: _int(json['expiring_soon_items_count']),
      totalInventoryValue: _double(json['total_inventory_value']),
      totalProducts: _int(json['total_products']),
      draftProducts: _int(json['draft_products']),
      changesRequested: _int(json['changes_requested']),
      rejectedProducts: _int(json['rejected_products']),
    );
  }

  final int catalogsAwaitingApproval;
  final int approvedProducts;

  /// Null when the backend omits the field (the Web then falls back to
  /// counting the category / coupon lists).
  final int? activeCategories;
  final int? activeCoupons;
  final int totalInventoryProducts;
  final int lowStockItems;
  final int outOfStockItems;
  final int todayOrders;
  final int pendingOrders;
  final int inPrepOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int totalReturns;
  final int pendingReturns;
  final int underInspectionReturns;
  final int resolvedReturns;
  final int totalClaims;
  final int openClaims;
  final int claimsRequiringResponse;
  final int escalatedClaims;
  final int resolvedClaims;
  final int inStockItems;
  final int expiringSoonItems;
  final double totalInventoryValue;
  final int totalProducts;
  final int draftProducts;
  final int changesRequested;
  final int rejectedProducts;
}

/// Metrics plus the category / coupon counts shown on Seller Home.
class SellerHomeSummary {
  const SellerHomeSummary({
    required this.metrics,
    required this.categoriesCount,
    required this.couponsCount,
  });

  final SellerHubMetrics metrics;
  final int categoriesCount;
  final int couponsCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// Orders — /workforce/seller-hub/orders/
// ─────────────────────────────────────────────────────────────────────────────

class SellerHubOrderItem {
  const SellerHubOrderItem({
    required this.id,
    required this.productTitle,
    required this.sku,
    this.unit,
    this.packSize,
    required this.orderedQuantity,
    required this.lineTotal,
    required this.isPicked,
    required this.isPacked,
    this.availableStock,
  });

  factory SellerHubOrderItem.fromJson(Map<String, dynamic> json) {
    return SellerHubOrderItem(
      id: _int(json['id']),
      productTitle: _str(json['product_title'], 'Item'),
      sku: _str(json['sku']),
      unit: _strOrNull(json['unit']),
      packSize: _strOrNull(json['pack_size']),
      orderedQuantity: _double(json['ordered_quantity']),
      lineTotal: _double(json['line_total']),
      isPicked: _bool(json['is_picked']),
      isPacked: _bool(json['is_packed']),
      availableStock: json['available_stock'] == null
          ? null
          : _double(json['available_stock']),
    );
  }

  final int id;
  final String productTitle;
  final String sku;
  final String? unit;
  final String? packSize;
  final double orderedQuantity;
  final double lineTotal;
  final bool isPicked;
  final bool isPacked;
  final double? availableStock;

  SellerHubOrderItem copyWithPick({bool? isPicked, bool? isPacked}) {
    return SellerHubOrderItem(
      id: id,
      productTitle: productTitle,
      sku: sku,
      unit: unit,
      packSize: packSize,
      orderedQuantity: orderedQuantity,
      lineTotal: lineTotal,
      isPicked: isPicked ?? this.isPicked,
      isPacked: isPacked ?? this.isPacked,
      availableStock: availableStock,
    );
  }
}

class SellerHubAuditLog {
  const SellerHubAuditLog({
    required this.id,
    required this.action,
    this.fromStatus,
    this.toStatus,
    this.actorName,
    this.notes,
    this.createdAt,
  });

  factory SellerHubAuditLog.fromJson(Map<String, dynamic> json) {
    return SellerHubAuditLog(
      id: _int(json['id']),
      action: _str(json['action']),
      fromStatus: _strOrNull(json['from_status']),
      toStatus: _strOrNull(json['to_status']),
      actorName: _strOrNull(json['actor_name']),
      notes: _strOrNull(json['notes']),
      createdAt: _date(json['created_at']),
    );
  }

  final int id;
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? actorName;
  final String? notes;
  final DateTime? createdAt;
}

class SellerHubOrder {
  const SellerHubOrder({
    required this.id,
    required this.orderNumber,
    this.sourceOrderId,
    required this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    required this.fulfillmentType,
    this.deliverySlot,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalAmount,
    required this.status,
    this.dispatchJobId,
    this.handlingTechnicianName,
    this.handlingTechnicianPhone,
    required this.itemsCount,
    required this.itemsSummary,
    this.createdAt,
    this.items = const [],
    this.auditLogs = const [],
    this.pickupOtp,
  });

  factory SellerHubOrder.fromJson(Map<String, dynamic> json) {
    return SellerHubOrder(
      id: _int(json['id']),
      orderNumber: _str(json['order_number'], '#${json['id']}'),
      sourceOrderId: _strOrNull(json['source_order_id']),
      customerName: _str(json['customer_name'], 'Customer'),
      customerPhone: _strOrNull(json['customer_phone']),
      deliveryAddress: _strOrNull(json['delivery_address']),
      fulfillmentType: _str(json['fulfillment_type'], 'DELIVERY'),
      deliverySlot: _strOrNull(json['delivery_slot']),
      paymentMethod: _str(json['payment_method']),
      paymentStatus: _str(json['payment_status']),
      totalAmount: _double(json['total_amount']),
      status: _str(json['status']).toUpperCase(),
      dispatchJobId: _intOrNull(json['dispatch_job_id']),
      handlingTechnicianName: _strOrNull(json['handling_technician_name']),
      handlingTechnicianPhone: _strOrNull(json['handling_technician_phone']),
      itemsCount: _int(json['items_count']),
      itemsSummary: _str(json['items_summary']),
      createdAt: _date(json['created_at']),
      items: _maps(json['items']).map(SellerHubOrderItem.fromJson).toList(),
      auditLogs: _maps(json['audit_logs'])
          .map(SellerHubAuditLog.fromJson)
          .toList(),
      pickupOtp: _strOrNull(json['pickup_otp']),
    );
  }

  final int id;
  final String orderNumber;
  final String? sourceOrderId;
  final String customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final String fulfillmentType;
  final String? deliverySlot;
  final String paymentMethod;
  final String paymentStatus;
  final double totalAmount;
  final String status;
  final int? dispatchJobId;
  final String? handlingTechnicianName;
  final String? handlingTechnicianPhone;
  final int itemsCount;
  final String itemsSummary;
  final DateTime? createdAt;

  /// Only populated by the detail endpoint.
  final List<SellerHubOrderItem> items;
  final List<SellerHubAuditLog> auditLogs;
  final String? pickupOtp;

  bool get isStorePickup => fulfillmentType == 'STORE_PICKUP';
  String get fulfillmentLabel => isStorePickup ? 'Store Pickup' : 'Delivery';
  bool get isTerminal => status == 'DELIVERED' || status == 'CANCELLED';
  bool get awaitingRider =>
      status == 'READY_FOR_PICKUP' || status == 'ASSIGNED';
  bool get inRiderPhase => awaitingRider || status == 'HANDED_OVER';

  SellerHubOrder copyWithItems(List<SellerHubOrderItem> newItems) {
    return SellerHubOrder(
      id: id,
      orderNumber: orderNumber,
      sourceOrderId: sourceOrderId,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
      fulfillmentType: fulfillmentType,
      deliverySlot: deliverySlot,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      totalAmount: totalAmount,
      status: status,
      dispatchJobId: dispatchJobId,
      handlingTechnicianName: handlingTechnicianName,
      handlingTechnicianPhone: handlingTechnicianPhone,
      itemsCount: itemsCount,
      itemsSummary: itemsSummary,
      createdAt: createdAt,
      items: newItems,
      auditLogs: auditLogs,
      pickupOtp: pickupOtp,
    );
  }
}

class SellerHubOrderPage {
  const SellerHubOrderPage({required this.results, required this.count});

  factory SellerHubOrderPage.fromJson(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final results = _maps(map['results'])
          .map(SellerHubOrder.fromJson)
          .toList();
      return SellerHubOrderPage(results: results, count: _int(map['count']));
    }
    if (data is List) {
      final results = _maps(data).map(SellerHubOrder.fromJson).toList();
      return SellerHubOrderPage(results: results, count: results.length);
    }
    return const SellerHubOrderPage(results: [], count: 0);
  }

  final List<SellerHubOrder> results;
  final int count;
}

class SellerPackingSlipItem {
  const SellerPackingSlipItem({
    required this.title,
    required this.sku,
    this.unitOrPack,
    required this.orderedQty,
    required this.lineTotal,
  });

  factory SellerPackingSlipItem.fromJson(Map<String, dynamic> json) {
    return SellerPackingSlipItem(
      title: _str(json['title'], 'Item'),
      sku: _str(json['sku']),
      unitOrPack: _strOrNull(json['pack_size']) ?? _strOrNull(json['unit']),
      orderedQty: _double(json['ordered_qty']),
      lineTotal: _double(json['line_total']),
    );
  }

  final String title;
  final String sku;
  final String? unitOrPack;
  final double orderedQty;
  final double lineTotal;
}

class SellerPackingSlip {
  const SellerPackingSlip({
    required this.orderNumber,
    this.sellerName,
    this.sellerAddress,
    this.sellerPhone,
    this.customerName,
    this.customerAddress,
    this.customerPhone,
    required this.items,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalAmount,
  });

  factory SellerPackingSlip.fromJson(Map<String, dynamic> json) {
    final seller = json['seller'] is Map
        ? Map<String, dynamic>.from(json['seller'])
        : const {};
    final customer = json['customer'] is Map
        ? Map<String, dynamic>.from(json['customer'])
        : const {};
    return SellerPackingSlip(
      orderNumber: _str(json['order_number']),
      sellerName: _strOrNull(seller['name']),
      sellerAddress: _strOrNull(seller['address']),
      sellerPhone: _strOrNull(seller['phone']),
      customerName: _strOrNull(customer['name']),
      customerAddress: _strOrNull(customer['delivery_address']),
      customerPhone: _strOrNull(customer['phone']),
      items: _maps(json['items']).map(SellerPackingSlipItem.fromJson).toList(),
      paymentMethod: _str(json['payment_method']),
      paymentStatus: _str(json['payment_status']),
      totalAmount: _double(json['total_amount']),
    );
  }

  final String orderNumber;
  final String? sellerName;
  final String? sellerAddress;
  final String? sellerPhone;
  final String? customerName;
  final String? customerAddress;
  final String? customerPhone;
  final List<SellerPackingSlipItem> items;
  final String paymentMethod;
  final String paymentStatus;
  final double totalAmount;
}

class SellerEligibleRider {
  const SellerEligibleRider({
    required this.name,
    this.distanceKm,
    this.score,
    this.gpsAgeSeconds,
  });

  factory SellerEligibleRider.fromJson(Map<String, dynamic> json) {
    return SellerEligibleRider(
      name: _str(json['name'], 'Rider'),
      distanceKm: json['distance_km'] == null
          ? null
          : _double(json['distance_km']),
      score: json['score'] == null ? null : _double(json['score']),
      gpsAgeSeconds: json['gps_age_seconds'] == null
          ? null
          : _double(json['gps_age_seconds']),
    );
  }

  final String name;
  final double? distanceKm;
  final double? score;
  final double? gpsAgeSeconds;
}

class SellerIneligibleRider {
  const SellerIneligibleRider({required this.name, this.reason, this.gate});

  factory SellerIneligibleRider.fromJson(Map<String, dynamic> json) {
    return SellerIneligibleRider(
      name: _str(json['name'], 'Rider'),
      reason: _strOrNull(json['reason']),
      gate: _strOrNull(json['gate']),
    );
  }

  final String name;
  final String? reason;
  final String? gate;
}

/// A rider from the warehouse-radius summary shape (`riders: [...]`).
class SellerNearbyRider {
  const SellerNearbyRider({
    required this.name,
    this.distanceKm,
    required this.isOnline,
  });

  factory SellerNearbyRider.fromJson(Map<String, dynamic> json) {
    return SellerNearbyRider(
      name: _str(json['name'], 'Rider'),
      distanceKm: json['distance_km'] == null
          ? null
          : _double(json['distance_km']),
      isOnline: _bool(json['is_online']),
    );
  }

  final String name;
  final double? distanceKm;
  final bool isOnline;
}

/// Response of `GET .../available-riders/`.
///
/// Two payload shapes exist: the dispatch-gate shape the Web modal reads
/// (`eligible_riders`, `ineligible_riders`, `store_location_missing`, ...)
/// and the warehouse-radius shape returned by
/// `automatic_dispatch.get_available_riders_summary` (`riders`,
/// `warehouse_missing`, `online_riders_count`, ...). Both are parsed; the UI
/// renders only what the server actually sent.
class SellerRiderAvailability {
  const SellerRiderAvailability({
    required this.storeLocationMissing,
    required this.warehouseMissing,
    this.error,
    this.eligibleCount,
    this.diagnosticSummary,
    this.activeOfferEmployeeName,
    this.eligibleRiders = const [],
    this.ineligibleRiders = const [],
    this.pickupLocationName,
    this.totalActiveRiders,
    this.onlineRidersCount,
    this.ridersInRadius,
    this.nearbyRiders = const [],
  });

  factory SellerRiderAvailability.fromJson(Map<String, dynamic> json) {
    final offer = json['active_offer'];
    final pickup = json['pickup_location'];
    return SellerRiderAvailability(
      storeLocationMissing: _bool(json['store_location_missing']),
      warehouseMissing: _bool(json['warehouse_missing']),
      error: _strOrNull(json['error']),
      eligibleCount: _intOrNull(json['eligible_count']),
      diagnosticSummary: _strOrNull(json['diagnostic_summary']),
      activeOfferEmployeeName: offer is Map
          ? _strOrNull(offer['employee_name'])
          : null,
      eligibleRiders: _maps(json['eligible_riders'])
          .map(SellerEligibleRider.fromJson)
          .toList(),
      ineligibleRiders: _maps(json['ineligible_riders'])
          .map(SellerIneligibleRider.fromJson)
          .toList(),
      pickupLocationName: pickup is Map ? _strOrNull(pickup['name']) : null,
      totalActiveRiders: _intOrNull(json['total_active_riders']),
      onlineRidersCount: _intOrNull(json['online_riders_count']),
      ridersInRadius: _intOrNull(json['riders_in_radius']),
      nearbyRiders: _maps(json['riders'])
          .map(SellerNearbyRider.fromJson)
          .toList(),
    );
  }

  final bool storeLocationMissing;
  final bool warehouseMissing;
  final String? error;

  // Dispatch-gate shape.
  final int? eligibleCount;
  final String? diagnosticSummary;
  final String? activeOfferEmployeeName;
  final List<SellerEligibleRider> eligibleRiders;
  final List<SellerIneligibleRider> ineligibleRiders;

  // Warehouse-radius shape.
  final String? pickupLocationName;
  final int? totalActiveRiders;
  final int? onlineRidersCount;
  final int? ridersInRadius;
  final List<SellerNearbyRider> nearbyRiders;
}

/// Result of `POST .../retry-dispatch/`.
class SellerRetryDispatchResult {
  const SellerRetryDispatchResult({this.order, this.availableRiders});

  final SellerHubOrder? order;
  final SellerRiderAvailability? availableRiders;
}

// ─────────────────────────────────────────────────────────────────────────────
// Returns — /workforce/seller-hub/returns/
// ─────────────────────────────────────────────────────────────────────────────

class SellerHubReturnItem {
  const SellerHubReturnItem({
    required this.id,
    required this.productTitle,
    required this.sku,
    required this.returnedQuantity,
    required this.restockedQuantity,
    required this.scrappedQuantity,
    this.itemCondition,
    this.qcResult,
  });

  factory SellerHubReturnItem.fromJson(Map<String, dynamic> json) {
    return SellerHubReturnItem(
      id: _int(json['id']),
      productTitle: _str(json['product_title'], 'Item'),
      sku: _str(json['sku']),
      returnedQuantity: _double(json['returned_quantity']),
      restockedQuantity: _double(json['restocked_quantity']),
      scrappedQuantity: _double(json['scrapped_quantity']),
      itemCondition: _strOrNull(json['item_condition']),
      qcResult: _strOrNull(json['qc_result']),
    );
  }

  final int id;
  final String productTitle;
  final String sku;
  final double returnedQuantity;
  final double restockedQuantity;
  final double scrappedQuantity;
  final String? itemCondition;
  final String? qcResult;
}

class SellerHubReturn {
  const SellerHubReturn({
    required this.id,
    required this.returnNumber,
    this.sourceReturnId,
    this.orderNumber,
    this.customerName,
    this.customerPhone,
    required this.reason,
    required this.status,
    this.qualityCheckStatus,
    this.restockDecision,
    required this.itemsCount,
    this.itemsSummary,
    this.createdAt,
    this.customerNotes,
    this.evidenceUrls = const [],
    this.qualityCheckNotes,
    this.restockNotes,
    this.items = const [],
    this.auditLogs = const [],
  });

  factory SellerHubReturn.fromJson(Map<String, dynamic> json) {
    final evidence = json['evidence_urls'];
    return SellerHubReturn(
      id: _int(json['id']),
      returnNumber: _str(json['return_number'], 'Return #${json['id']}'),
      sourceReturnId: _strOrNull(json['source_return_id']),
      orderNumber: _strOrNull(json['order_number']),
      customerName: _strOrNull(json['customer_name']),
      customerPhone: _strOrNull(json['customer_phone']),
      reason: _str(json['reason']),
      status: _str(json['status']).toUpperCase(),
      qualityCheckStatus: _strOrNull(json['quality_check_status']),
      restockDecision: _strOrNull(json['restock_decision']),
      itemsCount: _int(json['items_count']),
      itemsSummary: _strOrNull(json['items_summary']),
      createdAt: _date(json['created_at']),
      customerNotes: _strOrNull(json['customer_notes']),
      evidenceUrls: evidence is List
          ? evidence
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      qualityCheckNotes: _strOrNull(json['quality_check_notes']),
      restockNotes: _strOrNull(json['restock_notes']),
      items: _maps(json['items']).map(SellerHubReturnItem.fromJson).toList(),
      auditLogs: _maps(json['audit_logs'])
          .map(SellerHubAuditLog.fromJson)
          .toList(),
    );
  }

  final int id;
  final String returnNumber;
  final String? sourceReturnId;
  final String? orderNumber;
  final String? customerName;
  final String? customerPhone;
  final String reason;
  final String status;
  final String? qualityCheckStatus;
  final String? restockDecision;
  final int itemsCount;
  final String? itemsSummary;
  final DateTime? createdAt;

  /// Only populated by the detail endpoint.
  final String? customerNotes;
  final List<String> evidenceUrls;
  final String? qualityCheckNotes;
  final String? restockNotes;
  final List<SellerHubReturnItem> items;
  final List<SellerHubAuditLog> auditLogs;

  bool get needsReview =>
      status == 'REQUESTED' || status == 'UNDER_SELLER_REVIEW';
  bool get canSchedulePickup => status == 'APPROVED';
  bool get awaitingReceipt => status == 'PICKUP_SCHEDULED';
  bool get canInspectOrRestock =>
      status == 'RECEIVED' || status == 'QUALITY_CHECK';
  bool get canClose =>
      status == 'RESTOCKED' || status == 'DISCARDED' || status == 'REJECTED';
}

// ─────────────────────────────────────────────────────────────────────────────
// Claims — /workforce/seller-hub/claims/
// ─────────────────────────────────────────────────────────────────────────────

/// Claim types in the order the Web filter / create form lists them.
const sellerClaimTypes = <(String, String)>[
  ('DAMAGED_ITEM', 'Damaged Item'),
  ('MISSING_ITEM', 'Missing / Undelivered Item'),
  ('WRONG_ITEM', 'Wrong Item Delivered'),
  ('QUALITY_ISSUE', 'Quality / Freshness Issue'),
  ('DELIVERY_DAMAGE', 'Damage During Delivery / In-Transit'),
  ('SELLER_DISPUTE', 'Seller Operational Dispute'),
  ('SETTLEMENT_DISPUTE', 'Settlement / Fee Dispute'),
  ('OTHER', 'Other Claim / Dispute'),
];

class SellerHubClaim {
  const SellerHubClaim({
    required this.id,
    required this.claimNumber,
    required this.description,
    this.orderNumber,
    this.returnNumber,
    required this.claimType,
    this.claimTypeDisplay,
    required this.claimedAmount,
    required this.status,
    this.createdAt,
    this.companyName,
    this.customerName,
    this.customerPhone,
    this.evidenceUrls = const [],
    this.sellerResponse,
    this.sellerRespondedByName,
    this.sellerRespondedAt,
    this.adminDecision,
    this.adminDecisionReason,
    this.adminDecidedByName,
    this.adminDecidedAt,
    this.auditLogs = const [],
  });

  factory SellerHubClaim.fromJson(Map<String, dynamic> json) {
    final evidence = json['evidence_urls'];
    return SellerHubClaim(
      id: _int(json['id']),
      claimNumber: _str(json['claim_number'], '${json['id']}'),
      description: _str(json['description']),
      orderNumber: _strOrNull(json['order_number']),
      returnNumber: _strOrNull(json['return_number']),
      claimType: _str(json['claim_type'], 'OTHER'),
      claimTypeDisplay: _strOrNull(json['claim_type_display']),
      claimedAmount: _double(json['claimed_amount']),
      status: _str(json['status']).toUpperCase(),
      createdAt: _date(json['created_at']),
      companyName: _strOrNull(json['company_name']),
      customerName: _strOrNull(json['customer_name']),
      customerPhone: _strOrNull(json['customer_phone']),
      evidenceUrls: evidence is List
          ? evidence
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      sellerResponse: _strOrNull(json['seller_response']),
      sellerRespondedByName: _strOrNull(json['seller_responded_by_name']),
      sellerRespondedAt: _date(json['seller_responded_at']),
      adminDecision: _strOrNull(json['admin_decision']),
      adminDecisionReason: _strOrNull(json['admin_decision_reason']),
      adminDecidedByName: _strOrNull(json['admin_decided_by_name']),
      adminDecidedAt: _date(json['admin_decided_at']),
      auditLogs: _maps(json['audit_logs'])
          .map(SellerHubAuditLog.fromJson)
          .toList(),
    );
  }

  final int id;
  final String claimNumber;
  final String description;
  final String? orderNumber;
  final String? returnNumber;
  final String claimType;
  final String? claimTypeDisplay;
  final double claimedAmount;
  final String status;
  final DateTime? createdAt;

  /// Detail-only fields.
  final String? companyName;
  final String? customerName;
  final String? customerPhone;
  final List<String> evidenceUrls;
  final String? sellerResponse;
  final String? sellerRespondedByName;
  final DateTime? sellerRespondedAt;
  final String? adminDecision;
  final String? adminDecisionReason;
  final String? adminDecidedByName;
  final DateTime? adminDecidedAt;
  final List<SellerHubAuditLog> auditLogs;

  String get typeLabel {
    if (claimTypeDisplay != null) return claimTypeDisplay!;
    for (final (v, l) in sellerClaimTypes) {
      if (v == claimType) return l;
    }
    return claimType;
  }

  bool get canRespond =>
      sellerResponse == null &&
      (status == 'SELLER_RESPONSE_REQUIRED' ||
          status == 'OPEN' ||
          status == 'UNDER_REVIEW');
  bool get hasAdminDecision =>
      adminDecision != null && adminDecision != 'PENDING';
  bool get isFinal => status == 'CLOSED' || status == 'SETTLED';
  bool get canEscalate => status != 'ESCALATED' && !isFinal;
  bool get canClose => status != 'CLOSED';
}

// ─────────────────────────────────────────────────────────────────────────────
// Inventory — /workforce/seller-hub/inventory/
// ─────────────────────────────────────────────────────────────────────────────

class SellerHubInventoryItem {
  const SellerHubInventoryItem({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.productSku,
    this.productBrand,
    this.productBarcode,
    required this.productUnit,
    this.productPackSize,
    required this.productSellingPrice,
    this.productCategoryName,
    this.productCategoryPath,
    this.productImage,
    required this.onHandQty,
    required this.reservedQty,
    required this.availableQty,
    required this.lowStockThreshold,
    required this.reorderLevel,
    required this.batchesCount,
    required this.hasExpiringBatches,
  });

  factory SellerHubInventoryItem.fromJson(Map<String, dynamic> json) {
    final threshold = _double(json['low_stock_threshold']);
    return SellerHubInventoryItem(
      id: _int(json['id']),
      productId: _int(json['product']),
      productTitle: _str(json['product_title'], 'Product'),
      productSku: _str(json['product_sku']),
      productBrand: _strOrNull(json['product_brand']),
      productBarcode: _strOrNull(json['product_barcode']),
      productUnit: _str(json['product_unit']),
      productPackSize: _strOrNull(json['product_pack_size']),
      productSellingPrice: _double(json['product_selling_price']),
      productCategoryName: _strOrNull(json['product_category_name']),
      productCategoryPath: _strOrNull(json['product_category_path']),
      productImage: _strOrNull(json['product_image']),
      onHandQty: _double(json['on_hand_qty']),
      reservedQty: _double(json['reserved_qty']),
      availableQty: _double(json['available_qty']),
      // The Web treats a zero / missing threshold as 10.
      lowStockThreshold: threshold == 0 ? 10 : threshold,
      reorderLevel: _double(json['reorder_level']),
      batchesCount: _int(json['batches_count']),
      hasExpiringBatches: _bool(json['has_expiring_batches']),
    );
  }

  final int id;
  final int productId;
  final String productTitle;
  final String productSku;
  final String? productBrand;
  final String? productBarcode;
  final String productUnit;
  final String? productPackSize;
  final double productSellingPrice;
  final String? productCategoryName;
  final String? productCategoryPath;
  final String? productImage;
  final double onHandQty;
  final double reservedQty;
  final double availableQty;
  final double lowStockThreshold;
  final double reorderLevel;
  final int batchesCount;
  final bool hasExpiringBatches;

  /// Row badge, same rule as the Web table.
  String get stockStatus {
    if (onHandQty <= 0) return 'OUT_OF_STOCK';
    if (availableQty <= lowStockThreshold) return 'LOW_STOCK';
    return 'IN_STOCK';
  }
}

/// Summary cards / tab counts, computed from the loaded rows exactly like the
/// Web `metrics` memo (on-hand vs threshold; value at selling price).
class SellerInventorySummary {
  const SellerInventorySummary({
    required this.total,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
    required this.expiring,
    required this.totalValue,
  });

  factory SellerInventorySummary.of(List<SellerHubInventoryItem> items) {
    var inStock = 0, low = 0, out = 0, expiring = 0;
    var value = 0.0;
    for (final i in items) {
      if (i.onHandQty <= 0) {
        out++;
      } else if (i.onHandQty <= i.lowStockThreshold) {
        low++;
      } else {
        inStock++;
      }
      if (i.hasExpiringBatches) expiring++;
      value += i.onHandQty * i.productSellingPrice;
    }
    return SellerInventorySummary(
      total: items.length,
      inStock: inStock,
      lowStock: low,
      outOfStock: out,
      expiring: expiring,
      totalValue: value,
    );
  }

  final int total;
  final int inStock;
  final int lowStock;
  final int outOfStock;
  final int expiring;
  final double totalValue;
}

class SellerInventoryMovement {
  const SellerInventoryMovement({
    required this.id,
    required this.movementType,
    this.movementTypeDisplay,
    required this.quantityChange,
    required this.balanceBefore,
    required this.balanceAfter,
    this.reason,
    this.referenceId,
    this.actorName,
    this.createdAt,
  });

  factory SellerInventoryMovement.fromJson(Map<String, dynamic> json) {
    return SellerInventoryMovement(
      id: _int(json['id']),
      movementType: _str(json['movement_type']),
      movementTypeDisplay: _strOrNull(json['movement_type_display']),
      quantityChange: _double(json['quantity_change']),
      balanceBefore: _double(json['balance_before']),
      balanceAfter: _double(json['balance_after']),
      reason: _strOrNull(json['reason']),
      referenceId: _strOrNull(json['reference_id']),
      actorName: _strOrNull(json['actor_name']) ?? _strOrNull(json['username']),
      createdAt: _date(json['created_at']),
    );
  }

  final int id;
  final String movementType;
  final String? movementTypeDisplay;
  final double quantityChange;
  final double balanceBefore;
  final double balanceAfter;
  final String? reason;
  final String? referenceId;
  final String? actorName;
  final DateTime? createdAt;
}

class SellerInventoryBatch {
  const SellerInventoryBatch({
    required this.id,
    required this.batchNumber,
    this.receivedDate,
    this.expiryDate,
    required this.initialQuantity,
    required this.currentQuantity,
    required this.status,
    this.daysUntilExpiry,
  });

  factory SellerInventoryBatch.fromJson(Map<String, dynamic> json) {
    return SellerInventoryBatch(
      id: _int(json['id']),
      batchNumber: _str(json['batch_number']),
      receivedDate: _strOrNull(json['received_date']),
      expiryDate: _strOrNull(json['expiry_date']),
      initialQuantity: _double(json['initial_quantity']),
      currentQuantity: _double(json['current_quantity']),
      status: _str(json['status']),
      daysUntilExpiry: _intOrNull(json['days_until_expiry']),
    );
  }

  final int id;
  final String batchNumber;
  final String? receivedDate;
  final String? expiryDate;
  final double initialQuantity;
  final double currentQuantity;
  final String status;
  final int? daysUntilExpiry;
}

/// `GET /seller-hub/categories/active/` row (`path` like `Groceries > Oil`).
class SellerActiveCategory {
  const SellerActiveCategory({
    required this.id,
    required this.name,
    required this.path,
    required this.isLeaf,
  });

  factory SellerActiveCategory.fromJson(Map<String, dynamic> json) {
    return SellerActiveCategory(
      id: _int(json['id']),
      name: _str(json['name']),
      path: _str(json['path'], _str(json['name'])),
      isLeaf: _bool(json['is_leaf']),
    );
  }

  final int id;
  final String name;
  final String path;
  final bool isLeaf;
}

// ─────────────────────────────────────────────────────────────────────────────
// Catalog products — /workforce/seller-hub/products/
// ─────────────────────────────────────────────────────────────────────────────

class SellerHubProduct {
  const SellerHubProduct({
    required this.id,
    required this.title,
    this.description,
    this.brand,
    required this.sku,
    this.barcode,
    this.categoryId,
    this.categoryName,
    this.categoryPath,
    this.unit,
    this.packSize,
    required this.mrp,
    required this.sellingPrice,
    this.procurementPrice,
    required this.taxRate,
    this.hsnCode,
    this.storageInfo,
    this.expiryInfo,
    required this.status,
    this.adminReviewNote,
    this.rejectionReason,
    this.primaryImage,
    required this.imagesCount,
    this.companyName,
    this.updatedAt,
    this.submittedAt,
  });

  factory SellerHubProduct.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    return SellerHubProduct(
      id: _int(json['id']),
      title: _str(json['title'], 'Product'),
      description: _strOrNull(json['description']),
      brand: _strOrNull(json['brand']),
      sku: _str(json['sku']),
      barcode: _strOrNull(json['barcode']),
      categoryId: category is Map
          ? _intOrNull(category['id'])
          : _intOrNull(category),
      categoryName: _strOrNull(json['category_name']),
      categoryPath:
          _strOrNull(json['category_path']) ?? _strOrNull(json['path_string']),
      unit: _strOrNull(json['unit']),
      packSize: _strOrNull(json['pack_size']),
      mrp: _double(json['mrp']),
      sellingPrice: _double(json['selling_price']),
      procurementPrice: json['procurement_price'] == null
          ? null
          : _double(json['procurement_price']),
      taxRate: _double(json['tax_rate']),
      hsnCode: _strOrNull(json['hsn_code']),
      storageInfo: _strOrNull(json['storage_info']),
      expiryInfo: _strOrNull(json['expiry_info']),
      status: _str(json['status'], 'DRAFT').toUpperCase(),
      adminReviewNote: _strOrNull(json['admin_review_note']),
      rejectionReason: _strOrNull(json['rejection_reason']),
      primaryImage: _strOrNull(json['primary_image']),
      imagesCount: _int(json['images_count']),
      companyName: _strOrNull(json['company_name']),
      updatedAt: _date(json['updated_at']),
      submittedAt: _date(json['submitted_at']),
    );
  }

  final int id;
  final String title;
  final String? description;
  final String? brand;
  final String sku;
  final String? barcode;
  final int? categoryId;
  final String? categoryName;
  final String? categoryPath;
  final String? unit;
  final String? packSize;
  final double mrp;
  final double sellingPrice;
  final double? procurementPrice;
  final double taxRate;
  final String? hsnCode;
  final String? storageInfo;
  final String? expiryInfo;
  final String status;
  final String? adminReviewNote;
  final String? rejectionReason;
  final String? primaryImage;
  final int imagesCount;
  final String? companyName;
  final DateTime? updatedAt;
  final DateTime? submittedAt;

  /// `13% OFF` style discount, rounded like the Web.
  int? get discountPercent {
    if (mrp <= 0 || sellingPrice >= mrp) return null;
    return (((mrp - sellingPrice) / mrp) * 100).round();
  }

  /// `1 piece`, `500 ml` — pack size and unit as the Web prints them.
  String get packLabel =>
      [packSize, unit].whereType<String>().where((s) => s.isNotEmpty).join(' ');
}

/// Node in the seller category picker
/// (`GET /seller-hub/catalog/categories/?parent_id=…|q=…`).
class SellerCatalogPickerCategory {
  const SellerCatalogPickerCategory({
    required this.id,
    required this.name,
    required this.hasChildren,
    required this.isLeaf,
    this.pathString,
  });

  factory SellerCatalogPickerCategory.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    String? pathString = _strOrNull(json['path_string']);
    if (pathString == null && path is List) {
      pathString = path
          .map((p) => p is Map ? _str(p['name']) : p.toString())
          .where((s) => s.isNotEmpty)
          .join(' > ');
    } else if (pathString == null && path is String) {
      pathString = _strOrNull(path);
    }
    final hasChildren = _bool(json['has_children']);
    return SellerCatalogPickerCategory(
      id: _int(json['id']),
      name: _str(json['name']),
      hasChildren: hasChildren,
      isLeaf: json.containsKey('is_leaf')
          ? _bool(json['is_leaf'])
          : !hasChildren,
      pathString: pathString,
    );
  }

  final int id;
  final String name;
  final bool hasChildren;
  final bool isLeaf;
  final String? pathString;
}

/// Row of `GET /seller-hub/products/batches/` (bulk feed history).
class SellerCatalogUploadBatch {
  const SellerCatalogUploadBatch({
    required this.id,
    required this.fileName,
    this.uploadedByName,
    required this.totalRows,
    required this.importedRows,
    required this.status,
    this.createdAt,
  });

  factory SellerCatalogUploadBatch.fromJson(Map<String, dynamic> json) {
    return SellerCatalogUploadBatch(
      id: _int(json['id']),
      fileName: _str(json['file_name'], 'upload'),
      uploadedByName: _strOrNull(json['uploaded_by_name']),
      totalRows: _int(json['total_rows']),
      importedRows: _int(json['imported_rows']),
      status: _str(json['status']).toUpperCase(),
      createdAt: _date(json['created_at']),
    );
  }

  final int id;
  final String fileName;
  final String? uploadedByName;
  final int totalRows;
  final int importedRows;
  final String status;
  final DateTime? createdAt;
}

class SellerBulkPreviewItem {
  const SellerBulkPreviewItem({
    required this.rowNumber,
    required this.title,
    required this.sku,
    this.categoryName,
    required this.sellingPrice,
    required this.mrp,
    required this.hasErrors,
  });

  factory SellerBulkPreviewItem.fromJson(Map<String, dynamic> json) {
    return SellerBulkPreviewItem(
      rowNumber: _int(json['row_number']),
      title: _str(json['title']),
      sku: _str(json['sku']),
      categoryName: _strOrNull(json['category_name']),
      sellingPrice: _str(json['selling_price']),
      mrp: _str(json['mrp']),
      hasErrors: _bool(json['has_errors']),
    );
  }

  final int rowNumber;
  final String title;
  final String sku;
  final String? categoryName;
  final String sellingPrice;
  final String mrp;
  final bool hasErrors;
}

/// Response of `POST /seller-hub/products/bulk-upload/?preview=true`.
class SellerBulkPreview {
  const SellerBulkPreview({
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.canImport,
    required this.errors,
    required this.items,
  });

  factory SellerBulkPreview.fromJson(Map<String, dynamic> json) {
    return SellerBulkPreview(
      totalRows: _int(json['total_rows']),
      validRows: _int(json['valid_rows_count']),
      invalidRows: _int(json['invalid_rows_count']),
      canImport: _bool(json['can_import']),
      errors: [
        for (final e in _maps(json['errors']))
          (
            row: _int(e['row']),
            sku: _str(e['sku']),
            errors: e['errors'] is List
                ? (e['errors'] as List).map((x) => x.toString()).toList()
                : <String>[],
          ),
      ],
      items: _maps(json['items']).map(SellerBulkPreviewItem.fromJson).toList(),
    );
  }

  final int totalRows;
  final int validRows;
  final int invalidRows;
  final bool canImport;
  final List<({int row, String sku, List<String> errors})> errors;
  final List<SellerBulkPreviewItem> items;
}

/// `GET /seller-hub/products/<id>/` — product plus images and audit trail.
class SellerProductDetail {
  const SellerProductDetail({
    required this.product,
    required this.imageUrls,
    required this.auditLogs,
  });

  factory SellerProductDetail.fromJson(Map<String, dynamic> json) {
    return SellerProductDetail(
      product: SellerHubProduct.fromJson(json),
      imageUrls: [
        for (final img in _maps(json['images']))
          if (_strOrNull(img['image_url']) != null) _str(img['image_url']),
      ],
      auditLogs: _maps(json['audit_logs'])
          .map(SellerHubAuditLog.fromJson)
          .toList(),
    );
  }

  final SellerHubProduct product;
  final List<String> imageUrls;
  final List<SellerHubAuditLog> auditLogs;
}

/// Row of `GET /seller-hub/categories/` (Categories admin tree).
class SellerHubCategory {
  const SellerHubCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.parentId,
    required this.sortOrder,
    required this.isActive,
    required this.productsCount,
    this.childrenCount,
  });

  factory SellerHubCategory.fromJson(Map<String, dynamic> json) {
    final parent = json['parent_id'] ?? json['parent'];
    return SellerHubCategory(
      id: _int(json['id']),
      name: _str(json['name']),
      slug: _str(json['slug']),
      description: _strOrNull(json['description']),
      icon: _strOrNull(json['icon']),
      parentId: parent is Map ? _intOrNull(parent['id']) : _intOrNull(parent),
      sortOrder: _int(json['sort_order']),
      isActive: _bool(json['is_active']),
      productsCount: _int(json['products_count']),
      childrenCount:
          _intOrNull(json['children_count']) ??
          _intOrNull(json['subcategories_count']),
    );
  }

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final int? parentId;
  final int sortOrder;
  final bool isActive;
  final int productsCount;
  final int? childrenCount;

  SellerHubCategory copyWith({bool? isActive}) => SellerHubCategory(
    id: id,
    name: name,
    slug: slug,
    description: description,
    icon: icon,
    parentId: parentId,
    sortOrder: sortOrder,
    isActive: isActive ?? this.isActive,
    productsCount: productsCount,
    childrenCount: childrenCount,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Warehouses — /workforce/admin/warehouses/
// ─────────────────────────────────────────────────────────────────────────────

class SellerWarehouseMerchant {
  const SellerWarehouseMerchant({
    required this.id,
    required this.name,
    this.slug,
    this.address,
    this.assignedAt,
  });

  factory SellerWarehouseMerchant.fromJson(Map<String, dynamic> json) {
    return SellerWarehouseMerchant(
      id: _int(json['id']),
      name: _str(json['name'], _str(json['company_name'], 'Merchant')),
      slug: _strOrNull(json['slug']),
      address: _strOrNull(json['address']),
      assignedAt: _date(json['assigned_at']),
    );
  }

  final int id;
  final String name;
  final String? slug;
  final String? address;
  final DateTime? assignedAt;
}

class SellerWarehouse {
  const SellerWarehouse({
    required this.id,
    required this.name,
    this.code,
    this.address,
    this.city,
    this.region,
    this.contactPhone,
    this.latitude,
    this.longitude,
    required this.isActive,
    required this.assignedSellersCount,
    this.sellers = const [],
  });

  factory SellerWarehouse.fromJson(Map<String, dynamic> json) {
    return SellerWarehouse(
      id: _int(json['id']),
      name: _str(json['name'], 'Warehouse'),
      code: _strOrNull(json['code']),
      address: _strOrNull(json['address']),
      city: _strOrNull(json['city']),
      region: _strOrNull(json['region']),
      contactPhone: _strOrNull(json['contact_phone']),
      latitude: json['latitude'] == null ? null : _double(json['latitude']),
      longitude: json['longitude'] == null ? null : _double(json['longitude']),
      isActive: _bool(json['is_active']),
      assignedSellersCount: _int(json['assigned_sellers_count']),
      sellers: _maps(json['sellers'])
          .map(SellerWarehouseMerchant.fromJson)
          .toList(),
    );
  }

  final int id;
  final String name;
  final String? code;
  final String? address;
  final String? city;
  final String? region;
  final String? contactPhone;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final int assignedSellersCount;

  /// Detail endpoint only.
  final List<SellerWarehouseMerchant> sellers;

  bool get hasGps => latitude != null && longitude != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Categories Approval — /workforce/admin/seller-hub/approval/
// ─────────────────────────────────────────────────────────────────────────────

class SellerApprovalStore {
  const SellerApprovalStore({
    required this.id,
    required this.name,
    this.slug,
    this.warehouseId,
    this.warehouseName,
    required this.pendingCount,
    required this.approvedCount,
    required this.rejectedCount,
    required this.totalCount,
    this.latestSubmittedAt,
  });

  factory SellerApprovalStore.fromJson(Map<String, dynamic> json) {
    return SellerApprovalStore(
      id: _int(json['id']),
      name: _str(json['name'], _str(json['company_name'], 'Store')),
      slug: _strOrNull(json['slug']),
      warehouseId: _intOrNull(json['warehouse_id']),
      warehouseName: _strOrNull(json['warehouse_name']),
      pendingCount: _int(json['pending_count']),
      approvedCount: _int(json['approved_count']),
      rejectedCount: _int(json['rejected_count']),
      totalCount: _int(json['total_count']),
      latestSubmittedAt: _date(json['latest_submitted_at']),
    );
  }

  final int id;
  final String name;
  final String? slug;
  final int? warehouseId;
  final String? warehouseName;
  final int pendingCount;
  final int approvedCount;
  final int rejectedCount;
  final int totalCount;
  final DateTime? latestSubmittedAt;
}

/// A paginated `{results, count, total_pages}` page.
class SellerPage<T> {
  const SellerPage({
    required this.results,
    required this.count,
    required this.totalPages,
  });

  final List<T> results;
  final int count;
  final int totalPages;
}

/// Products page for one seller, with the seller header counts.
class SellerApprovalProductsPage {
  const SellerApprovalProductsPage({required this.seller, required this.page});

  final SellerApprovalStore? seller;
  final SellerPage<SellerHubProduct> page;
}

/// Node of `GET /seller-hub/categories/tree/`, flattened to `A > B > C`.
List<({int id, String path})> flattenSellerCategoryTree(dynamic data) {
  final out = <({int id, String path})>[];
  void walk(dynamic nodes, String prefix) {
    for (final n in _maps(nodes)) {
      final name = _str(n['name']);
      final path = prefix.isEmpty ? name : '$prefix > $name';
      out.add((id: _int(n['id']), path: path));
      walk(n['children'], path);
    }
  }

  walk(data, '');
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Coupons — /workforce/seller-hub/coupons/
// ─────────────────────────────────────────────────────────────────────────────

class SellerHubCoupon {
  const SellerHubCoupon({
    required this.id,
    required this.code,
    this.description,
    this.companyName,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    this.maxDiscountAmount,
    this.usageLimitTotal,
    required this.usageLimitPerUser,
    required this.timesUsed,
    this.validFrom,
    this.validUntil,
    required this.isActive,
  });

  factory SellerHubCoupon.fromJson(Map<String, dynamic> json) {
    return SellerHubCoupon(
      id: _int(json['id']),
      code: _str(json['code']),
      description: _strOrNull(json['description']),
      companyName: _strOrNull(json['company_name']),
      discountType: _str(json['discount_type'], 'percent'),
      discountValue: _double(json['discount_value']),
      minOrderAmount: _double(json['min_order_amount']),
      maxDiscountAmount: json['max_discount_amount'] == null
          ? null
          : _double(json['max_discount_amount']),
      usageLimitTotal: _intOrNull(json['usage_limit_total']),
      usageLimitPerUser: _intOrNull(json['usage_limit_per_user']) ?? 1,
      timesUsed: _int(json['times_used']),
      validFrom: _date(json['valid_from']),
      validUntil: _date(json['valid_until']),
      isActive: _bool(json['is_active']),
    );
  }

  final int id;
  final String code;
  final String? description;
  final String? companyName;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final double? maxDiscountAmount;
  final int? usageLimitTotal;
  final int usageLimitPerUser;
  final int timesUsed;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool isActive;

  bool get isPercent => discountType == 'percent';

  /// `Inactive` / `Expired` / `Active`, same precedence as the Web badge.
  String statusAt(DateTime now) {
    if (!isActive) return 'Inactive';
    if (validUntil != null && validUntil!.isBefore(now)) return 'Expired';
    return 'Active';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reports & Quality — /workforce/seller-hub/reports/*
// ─────────────────────────────────────────────────────────────────────────────

/// `GET /seller-hub/reports/summary/?days=…`
class SellerReportsSummary {
  const SellerReportsSummary(this._j);

  factory SellerReportsSummary.fromJson(Map<String, dynamic> json) =>
      SellerReportsSummary(json);

  final Map<String, dynamic> _j;

  double get catalogQualityScore => _double(_j['catalog_quality_score']);
  int get approvedProducts => _int(_j['approved_products_count']);
  int get pendingProducts => _int(_j['pending_products_count']);
  int get rejectedProducts => _int(_j['rejected_products_count']);
  int get totalProducts => _int(_j['total_products_count']);
  int get missingImages => _int(_j['missing_images_count']);
  int get missingDescriptions => _int(_j['missing_descriptions_count']);
  double get fulfilledGrossValue => _double(_j['fulfilled_order_gross_value']);
  int get deliveredOrders => _int(_j['delivered_orders_count']);
  int get totalOrders => _int(_j['total_orders_count']);
  int get pendingOrders => _int(_j['pending_orders_count']);
  int get inPrepOrders => _int(_j['in_prep_orders_count']);
  double get fulfilmentSuccessRate => _double(_j['fulfilment_success_rate']);
  double get inventoryHealthIndex => _double(_j['inventory_health_index']);
  int get totalInventoryItems => _int(_j['total_inventory_items_count']);
  int get lowStock => _int(_j['low_stock_count']);
  int get outOfStock => _int(_j['out_of_stock_count']);
  int get expiringBatches => _int(_j['expiring_batches_count']);
  double get totalOnHandQuantity => _double(_j['total_on_hand_quantity']);
  double get inventoryValuation => _double(_j['inventory_valuation']);
  double get returnRate => _double(_j['return_rate']);
  int get totalReturns => _int(_j['total_returns_count']);
  int get pendingReturns => _int(_j['pending_returns_count']);
  int get totalClaims => _int(_j['total_claims_count']);
  int get claimsRequiringResponse =>
      _int(_j['claims_requiring_response_count']);

  /// Web band: ≥80 Optimal, ≥50 Fair, otherwise Needs Review.
  String get catalogQualityBand => catalogQualityScore >= 80
      ? 'Optimal'
      : (catalogQualityScore >= 50 ? 'Fair' : 'Needs Review');
}

/// `GET /seller-hub/reports/performance/?days=…`
class SellerReportsPerformance {
  const SellerReportsPerformance({
    required this.dailyTrends,
    required this.movementBreakdown,
    required this.returnReasons,
    required this.claimTypes,
  });

  factory SellerReportsPerformance.fromJson(Map<String, dynamic> json) {
    return SellerReportsPerformance(
      dailyTrends: [
        for (final d in _maps(json['daily_trends']))
          (
            date: _str(d['date']),
            orders: _int(d['orders_count']),
            delivered: _int(d['delivered_count']),
            cancelled: _int(d['cancelled_count']),
            value: _double(d['fulfilled_gross_value']),
          ),
      ],
      movementBreakdown: [
        for (final m in _maps(json['movement_breakdown']))
          (
            type: _str(m['movement_type']),
            quantity: _double(m['total_quantity']),
            events: _int(m['events_count']),
          ),
      ],
      returnReasons: [
        for (final r in _maps(json['return_reasons']))
          (label: _str(r['reason']), count: _int(r['count'])),
      ],
      claimTypes: [
        for (final c in _maps(json['claim_types']))
          (label: _str(c['claim_type']), count: _int(c['count'])),
      ],
    );
  }

  final List<
    ({String date, int orders, int delivered, int cancelled, double value})
  >
  dailyTrends;
  final List<({String type, double quantity, int events})> movementBreakdown;
  final List<({String label, int count})> returnReasons;
  final List<({String label, int count})> claimTypes;
}

/// `GET /seller-hub/reports/quality-audit/`
class SellerQualityAudit {
  const SellerQualityAudit({
    required this.totalIssues,
    required this.outOfStockApproved,
    required this.expiringBatches,
    required this.missingImages,
    required this.claimsRequiringResponse,
    required this.returnsPendingQc,
  });

  factory SellerQualityAudit.fromJson(Map<String, dynamic> json) {
    return SellerQualityAudit(
      totalIssues: _int(json['total_issues_count']),
      outOfStockApproved: _int(json['out_of_stock_approved_count']),
      expiringBatches: _int(json['expiring_batches_count']),
      missingImages: _int(json['missing_images_count']),
      claimsRequiringResponse: _int(json['claims_requiring_response_count']),
      returnsPendingQc: _int(json['returns_pending_qc_count']),
    );
  }

  final int totalIssues;
  final int outOfStockApproved;
  final int expiringBatches;
  final int missingImages;
  final int claimsRequiringResponse;
  final int returnsPendingQc;
}
