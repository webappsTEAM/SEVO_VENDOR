import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/seller_hub_models.dart';

final sellerHubRepositoryProvider = Provider<SellerHubRepository>((ref) {
  return SellerHubRepository(ref.watch(apiClientProvider));
});

/// A failed Seller Hub call, carrying the backend's `error` text and `code`
/// (e.g. `WAREHOUSE_ASSIGNMENT_REQUIRED`) so screens can react like the Web.
class SellerHubException implements Exception {
  const SellerHubException(this.message, {this.code, this.statusCode});

  factory SellerHubException.fromDio(DioException e, String fallback) {
    final data = e.response?.data;
    String? code;
    if (data is Map && data['code'] is String) code = data['code'] as String;
    var message = describeDioError(e, fallback: fallback);
    // Never surface raw HTML error pages from a proxy / 5xx.
    if (message.trimLeft().startsWith('<')) message = fallback;
    return SellerHubException(
      message,
      code: code,
      statusCode: e.response?.statusCode,
    );
  }

  final String message;
  final String? code;
  final int? statusCode;

  bool get needsWarehouseOrLocation =>
      code == 'WAREHOUSE_ASSIGNMENT_REQUIRED' ||
      code == 'STORE_LOCATION_REQUIRED';

  @override
  String toString() => message;
}

/// Seller Hub fulfilment API (`/workforce/seller-hub/*`) — the same endpoints
/// and payloads used by the Web Seller Home, Orders and Returns pages.
class SellerHubRepository {
  SellerHubRepository(this._dio);

  final Dio _dio;

  static const ordersPageSize = 20;

  Future<T> _guard<T>(Future<T> Function() call, String fallback) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw SellerHubException.fromDio(e, fallback);
    }
  }

  Map<String, dynamic> _map(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  // ── Metrics / Home ─────────────────────────────────────────────────────────

  Future<SellerHubMetrics> getMetrics() => _guard(() async {
    final res = await _dio.get('/workforce/seller-hub/metrics/');
    return SellerHubMetrics.fromJson(_map(res.data));
  }, 'Failed to load Seller Hub metrics.');

  /// Seller Home data. The metrics payload already carries `active_categories`
  /// and `active_coupons`; the category / coupon lists are only fetched (in
  /// parallel) when an older backend omits those counts.
  Future<SellerHomeSummary> getHomeSummary() async {
    final metrics = await getMetrics();
    final needCategories = metrics.activeCategories == null;
    final needCoupons = metrics.activeCoupons == null;
    final counts = await Future.wait([
      needCategories
          ? _countList('/workforce/seller-hub/categories/')
          : Future.value(metrics.activeCategories!),
      needCoupons
          ? _countList('/workforce/seller-hub/coupons/')
          : Future.value(metrics.activeCoupons!),
    ]);
    return SellerHomeSummary(
      metrics: metrics,
      categoriesCount: counts[0],
      couponsCount: counts[1],
    );
  }

  Future<int> _countList(String path) async {
    try {
      final res = await _dio.get(path);
      final data = res.data;
      if (data is List) return data.length;
      if (data is Map && data['results'] is List)
        return (data['results'] as List).length;
    } on DioException {
      // Mirrors the Web fallback (`.catch(() => [])`).
    }
    return 0;
  }

  // ── Orders ─────────────────────────────────────────────────────────────────

  Future<SellerHubOrderPage> getOrders({
    int page = 1,
    String status = 'ALL',
    String fulfillmentType = 'ALL',
    String search = '',
  }) => _guard(() async {
    final params = <String, dynamic>{'page': page, 'page_size': ordersPageSize};
    if (status != 'ALL') params['status'] = status;
    if (fulfillmentType != 'ALL') params['fulfillment_type'] = fulfillmentType;
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    final res = await _dio.get(
      '/workforce/seller-hub/orders/',
      queryParameters: params,
    );
    return SellerHubOrderPage.fromJson(res.data);
  }, 'Failed to fetch orders from server.');

  Future<SellerHubOrder> getOrderDetail(int orderId) => _guard(() async {
    final res = await _dio.get('/workforce/seller-hub/orders/$orderId/');
    return SellerHubOrder.fromJson(_map(res.data));
  }, 'Failed to load order details.');

  /// `action` is one of `accept`, `start_picking`, `mark_packed`,
  /// `mark_ready`, `cancel`. Returns the updated order.
  Future<SellerHubOrder?> transitionOrder(
    int orderId,
    String action, {
    String notes = '',
    String cancellationReason = '',
  }) => _guard(() async {
    final res = await _dio.post(
      '/workforce/seller-hub/orders/$orderId/transition/',
      data: {
        'action': action,
        'notes': notes,
        'cancellation_reason': cancellationReason,
      },
    );
    final order = _map(res.data)['order'];
    return order is Map
        ? SellerHubOrder.fromJson(Map<String, dynamic>.from(order))
        : null;
  }, 'Failed to update order state.');

  /// Platform admin emergency bypass: `admin_override_handover` or
  /// `admin_override_deliver`, with a mandatory reason.
  Future<SellerHubOrder?> adminOverride(
    int orderId,
    String action,
    String reason,
  ) => _guard(() async {
    final res = await _dio.post(
      '/workforce/seller-hub/orders/$orderId/admin-override/',
      data: {'action': action, 'reason': reason.trim()},
    );
    final order = _map(res.data)['order'];
    return order is Map
        ? SellerHubOrder.fromJson(Map<String, dynamic>.from(order))
        : null;
  }, 'Failed to execute admin override.');

  Future<SellerRiderAvailability> getAvailableRiders(int orderId) =>
      _guard(() async {
        final res = await _dio.get(
          '/workforce/seller-hub/orders/$orderId/available-riders/',
        );
        return SellerRiderAvailability.fromJson(_map(res.data));
      }, 'Failed to load rider availability.');

  Future<SellerRetryDispatchResult> retryDispatch(int orderId) =>
      _guard(() async {
        final res = await _dio.post(
          '/workforce/seller-hub/orders/$orderId/retry-dispatch/',
          data: const {},
        );
        final data = _map(res.data);
        final order = data['order'];
        final riders = data['available_riders'];
        return SellerRetryDispatchResult(
          order: order is Map
              ? SellerHubOrder.fromJson(Map<String, dynamic>.from(order))
              : null,
          availableRiders: riders is Map
              ? SellerRiderAvailability.fromJson(
                  Map<String, dynamic>.from(riders),
                )
              : null,
        );
      }, 'Failed to retry dispatch.');

  /// Toggles picking for one line item; returns the server's item fields.
  Future<Map<String, dynamic>> setItemPicked(
    int orderId,
    int itemId, {
    required bool isPicked,
    double? fulfilledQuantity,
  }) => _guard(() async {
    final payload = <String, dynamic>{'item_id': itemId, 'is_picked': isPicked};
    if (fulfilledQuantity != null)
      payload['fulfilled_quantity'] = fulfilledQuantity;
    final res = await _dio.post(
      '/workforce/seller-hub/orders/$orderId/item-pick/',
      data: payload,
    );
    return _map(_map(res.data)['item']);
  }, 'Failed to update picking status.');

  Future<SellerPackingSlip> getPackingSlip(int orderId) => _guard(() async {
    final res = await _dio.get(
      '/workforce/seller-hub/orders/$orderId/packing-slip/',
    );
    return SellerPackingSlip.fromJson(_map(res.data));
  }, 'Failed to load packing slip.');

  /// The printable 4x6 shipping label with scannable barcode.
  Future<Uint8List> downloadShippingLabelPdf(int orderId) => _guard(() async {
    final res = await _dio.get<List<int>>(
      '/workforce/seller-hub/orders/$orderId/packing-slip/pdf/',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }, 'Failed to generate shipping label PDF.');

  // ── Returns ────────────────────────────────────────────────────────────────

  Future<List<SellerHubReturn>> getReturns({
    String status = 'ALL',
    String search = '',
  }) => _guard(() async {
    final params = <String, dynamic>{};
    if (status != 'ALL') params['status'] = status;
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    final res = await _dio.get(
      '/workforce/seller-hub/returns/',
      queryParameters: params,
    );
    final data = res.data;
    final list = data is List
        ? data
        : (data is Map && data['results'] is List
              ? data['results'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => SellerHubReturn.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }, 'Failed to fetch returns from server.');

  Future<SellerHubReturn> getReturnDetail(int returnId) => _guard(() async {
    final res = await _dio.get('/workforce/seller-hub/returns/$returnId/');
    return SellerHubReturn.fromJson(_map(res.data));
  }, 'Failed to load return case.');

  /// `decision` is `approve`, `reject` or `escalate`.
  Future<void> reviewReturn(
    int returnId, {
    required String decision,
    String sellerNotes = '',
    String rejectionReason = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/seller-hub/returns/$returnId/review/',
      data: {
        'decision': decision,
        'seller_notes': sellerNotes,
        'rejection_reason': rejectionReason,
      },
    );
  }, 'Review action failed.');

  Future<void> scheduleReturnPickup(
    int returnId, {
    String pickupRef = '',
    String notes = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/seller-hub/returns/$returnId/schedule-pickup/',
      data: {'pickup_ref': pickupRef, 'notes': notes},
    );
  }, 'Failed to schedule pickup.');

  Future<void> receiveReturn(int returnId, {String notes = ''}) =>
      _guard(() async {
        await _dio.post(
          '/workforce/seller-hub/returns/$returnId/receive/',
          data: {'notes': notes},
        );
      }, 'Failed to acknowledge receipt.');

  /// `status` is `PASSED`, `FAILED` or `PARTIAL_PASS`. Per-item QC rows are
  /// pre-filled from the case, exactly as the Web form does.
  Future<void> submitReturnQualityCheck(
    SellerHubReturn ret, {
    required String status,
    String notes = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/seller-hub/returns/${ret.id}/quality-check/',
      data: {
        'quality_check_status': status,
        'quality_check_notes': notes,
        'items_qc': [
          for (final it in ret.items)
            {
              'item_id': it.id,
              'item_condition': it.itemCondition ?? 'SEALED_INTACT',
              'qc_result': it.qcResult ?? 'PASSED',
              'qc_notes': '',
            },
        ],
      },
    );
  }, 'Failed to submit quality check.');

  /// `decision` is `FULL_RESTOCK`, `PARTIAL_RESTOCK` or `SCRAP_DISPOSE`.
  Future<void> restockReturn(
    SellerHubReturn ret, {
    required String decision,
    String notes = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/seller-hub/returns/${ret.id}/restock/',
      data: {
        'restock_decision': decision,
        'restock_notes': notes,
        'items_breakdown': [
          for (final it in ret.items)
            {
              'item_id': it.id,
              'restocked_quantity': it.restockedQuantity > 0
                  ? it.restockedQuantity
                  : it.returnedQuantity,
              'scrapped_quantity': it.scrappedQuantity,
            },
        ],
      },
    );
  }, 'Failed to complete restocking.');

  Future<void> closeReturn(int returnId, {String notes = ''}) =>
      _guard(() async {
        await _dio.post(
          '/workforce/seller-hub/returns/$returnId/close/',
          data: {'notes': notes},
        );
      }, 'Failed to close return case.');

  // ── Inventory ──────────────────────────────────────────────────────────────

  /// `status` is a Web tab key (`ALL`, `IN_STOCK`, `LOW_STOCK`, ...).
  Future<List<SellerHubInventoryItem>> getInventory({
    String status = 'ALL',
    String search = '',
    int? categoryId,
  }) => _guard(() async {
    final params = <String, dynamic>{'status': status};
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    if (categoryId != null) params['category_id'] = categoryId;
    final res = await _dio.get(
      '/workforce/seller-hub/inventory/',
      queryParameters: params,
    );
    return _list(res.data, SellerHubInventoryItem.fromJson);
  }, 'Error fetching store inventory.');

  Future<List<SellerActiveCategory>> getActiveCategories({
    bool leafOnly = false,
  }) => _guard(() async {
    final res = await _dio.get(
      '/workforce/seller-hub/categories/active/',
      queryParameters: leafOnly ? {'leaf_only': 'true'} : null,
    );
    return _list(res.data, SellerActiveCategory.fromJson);
  }, 'Failed to load categories.');

  Future<List<SellerInventoryMovement>> getInventoryMovements(
    int inventoryId, {
    String movementType = '',
  }) => _guard(() async {
    final res = await _dio.get(
      '/workforce/seller-hub/inventory/$inventoryId/movements/',
      queryParameters: movementType.isEmpty
          ? null
          : {'movement_type': movementType},
    );
    return _list(res.data, SellerInventoryMovement.fromJson);
  }, 'Failed to load movement ledger.');

  Future<List<SellerInventoryBatch>> getInventoryBatches(int inventoryId) =>
      _guard(() async {
        final res = await _dio.get(
          '/workforce/seller-hub/inventory/$inventoryId/batches/',
        );
        return _list(res.data, SellerInventoryBatch.fromJson);
      }, 'Failed to load batches.');

  /// Records a stock movement: `STOCK_IN`, `ADJUSTMENT_INCREASE`,
  /// `ADJUSTMENT_DECREASE` or `DAMAGE` (payloads as sent by the Web modals).
  Future<void> adjustInventory(
    int inventoryId, {
    required String movementType,
    required String quantity,
    String reason = '',
    String referenceId = '',
    String? batchNumber,
    String? expiryDate,
    String? costPrice,
  }) => _guard(() async {
    final data = <String, dynamic>{
      'movement_type': movementType,
      'quantity': quantity,
      'reason': reason,
      'reference_id': referenceId,
    };
    if (movementType == 'STOCK_IN') {
      data['batch_number'] = batchNumber ?? '';
      data['expiry_date'] = (expiryDate ?? '').isEmpty ? null : expiryDate;
      data['cost_price'] = (costPrice ?? '').isEmpty ? null : costPrice;
    }
    await _dio.post(
      '/workforce/seller-hub/inventory/$inventoryId/adjust/',
      data: data,
    );
  }, 'Failed to record stock movement.');

  Future<void> updateInventoryThresholds(
    int inventoryId, {
    required String lowStockThreshold,
    required String reorderLevel,
  }) => _guard(() async {
    await _dio.patch(
      '/workforce/seller-hub/inventory/$inventoryId/',
      data: {
        'low_stock_threshold': lowStockThreshold,
        'reorder_level': reorderLevel,
      },
    );
  }, 'Failed to update thresholds.');

  Future<void> initializeInventory({
    required int productId,
    required String onHandQty,
    required String lowStockThreshold,
    required String reorderLevel,
    String batchNumber = '',
    String? expiryDate,
    String? costPrice,
    String reason = 'Initial opening stock setup.',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/seller-hub/inventory/initialize/',
      data: {
        'product_id': productId,
        'on_hand_qty': onHandQty,
        'low_stock_threshold': lowStockThreshold,
        'reorder_level': reorderLevel,
        'batch_number': batchNumber,
        'expiry_date': (expiryDate ?? '').isEmpty ? null : expiryDate,
        'cost_price': (costPrice ?? '').isEmpty ? null : costPrice,
        'reason': reason,
      },
    );
  }, 'Failed to initialize inventory.');

  // ── Catalog products ───────────────────────────────────────────────────────

  Future<List<SellerHubProduct>> getProducts({
    String status = '',
    int? categoryId,
    String search = '',
  }) => _guard(() async {
    final params = <String, dynamic>{};
    if (status.isNotEmpty) params['status'] = status;
    if (categoryId != null) params['category_id'] = categoryId;
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    final res = await _dio.get(
      '/workforce/seller-hub/products/',
      queryParameters: params,
    );
    return _list(res.data, SellerHubProduct.fromJson);
  }, 'Failed to load products.');

  String? _message(dynamic data) {
    final m = _map(data)['message'];
    return m is String && m.isNotEmpty ? m : null;
  }

  /// Category picker column (`parentId` null = root) or search (`query`).
  Future<List<SellerCatalogPickerCategory>> getCatalogPickerCategories({
    int? parentId,
    String? query,
  }) => _guard(() async {
    final params = <String, dynamic>{};
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    } else {
      params['parent_id'] = parentId?.toString() ?? 'null';
    }
    final res = await _dio.get(
      '/workforce/seller-hub/catalog/categories/',
      queryParameters: params,
    );
    return _list(res.data, SellerCatalogPickerCategory.fromJson);
  }, 'Failed to load categories');

  Future<List<SellerCatalogUploadBatch>> getProductBatches() =>
      _guard(() async {
        final res = await _dio.get('/workforce/seller-hub/products/batches/');
        return _list(res.data, SellerCatalogUploadBatch.fromJson);
      }, 'Failed to load upload batches.');

  Future<SellerProductDetail> getProductDetail(int productId) => _guard(
    () async {
      final res = await _dio.get('/workforce/seller-hub/products/$productId/');
      return SellerProductDetail.fromJson(_map(res.data));
    },
    'Failed to load product details.',
  );

  /// Creates (`productId` null) or updates a product with the Web form
  /// payload. Returns the server message.
  Future<String?> saveProduct(Map<String, dynamic> payload, {int? productId}) =>
      _guard(() async {
        final res = productId == null
            ? await _dio.post('/workforce/seller-hub/products/', data: payload)
            : await _dio.patch(
                '/workforce/seller-hub/products/$productId/',
                data: payload,
              );
        return _message(res.data);
      }, 'Failed to save product');

  Future<String?> submitProduct(int productId) => _guard(() async {
    final res = await _dio.post(
      '/workforce/seller-hub/products/$productId/submit/',
    );
    return _message(res.data);
  }, 'Failed to submit product');

  Future<String?> deleteProduct(int productId) => _guard(() async {
    final res = await _dio.delete('/workforce/seller-hub/products/$productId/');
    return _message(res.data);
  }, 'Failed to delete product');

  /// Admin decision: `approve`, `reject`, `request_changes` or `pause`.
  Future<String?> reviewProduct(int productId, String action, String note) =>
      _guard(() async {
        final res = await _dio.post(
          '/workforce/seller-hub/products/$productId/review/',
          data: {'action': action, 'note': note.trim()},
        );
        return _message(res.data);
      }, 'Failed to execute review decision');

  /// Uploads a product photo; returns its public URL.
  Future<String> uploadProductImage(String filePath) => _guard(() async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post(
      '/workforce/seller-hub/products/upload-image/',
      data: form,
    );
    final url = _map(res.data)['image_url'];
    if (url is! String || url.isEmpty)
      throw const SellerHubException('Failed to upload image');
    return url;
  }, 'Failed to upload image');

  Future<SellerBulkPreview> previewBulkUpload(
    Uint8List bytes,
    String fileName,
  ) => _guard(() async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final res = await _dio.post(
      '/workforce/seller-hub/products/bulk-upload/',
      queryParameters: {'preview': 'true'},
      data: form,
    );
    return SellerBulkPreview.fromJson(_map(res.data));
  }, 'Failed to parse file');

  Future<String?> importBulkUpload(Uint8List bytes, String fileName) =>
      _guard(() async {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        });
        final res = await _dio.post(
          '/workforce/seller-hub/products/bulk-upload/',
          data: form,
        );
        return _message(res.data);
      }, 'Bulk import failed');

  Future<Uint8List> downloadProductTemplate() => _guard(() async {
    final res = await _dio.get<List<int>>(
      '/workforce/seller-hub/products/template/',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }, 'Failed to download template.');

  // ── Categories (admin tree) ────────────────────────────────────────────────

  Future<List<SellerHubCategory>> getCategories() => _guard(() async {
    final res = await _dio.get('/workforce/seller-hub/categories/');
    return _list(res.data, SellerHubCategory.fromJson);
  }, 'Failed to load catalog categories');

  Future<void> createCategory(Map<String, dynamic> payload) => _guard(() async {
    await _dio.post('/workforce/seller-hub/categories/', data: payload);
  }, 'Failed to save category.');

  Future<void> updateCategory(int id, Map<String, dynamic> patch) =>
      _guard(() async {
        await _dio.patch('/workforce/seller-hub/categories/$id/', data: patch);
      }, 'Failed to save category.');

  Future<void> deleteCategory(int id) => _guard(() async {
    await _dio.delete('/workforce/seller-hub/categories/$id/');
  }, 'Failed to delete category.');

  // ── Warehouses (platform admin) ────────────────────────────────────────────

  Future<List<SellerWarehouse>> getWarehouses({
    String search = '',
    String? city,
    bool? isActive,
  }) => _guard(() async {
    final params = <String, dynamic>{};
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    if (city != null && city.isNotEmpty) params['city'] = city;
    if (isActive != null) params['is_active'] = '$isActive';
    final res = await _dio.get(
      '/workforce/admin/warehouses/',
      queryParameters: params,
    );
    return _list(res.data, SellerWarehouse.fromJson);
  }, 'Failed to fetch warehouse facilities.');

  Future<SellerWarehouse> getWarehouseDetail(int id) => _guard(() async {
    final res = await _dio.get('/workforce/admin/warehouses/$id/');
    return SellerWarehouse.fromJson(_map(res.data));
  }, 'Failed to load warehouse details.');

  Future<void> saveWarehouse(Map<String, dynamic> payload, {int? id}) =>
      _guard(() async {
        if (id == null) {
          await _dio.post('/workforce/admin/warehouses/', data: payload);
        } else {
          await _dio.patch('/workforce/admin/warehouses/$id/', data: payload);
        }
      }, 'Failed to save warehouse facility.');

  /// The Web "deactivate" action is a DELETE on the warehouse.
  Future<void> deactivateWarehouse(int id) => _guard(() async {
    await _dio.delete('/workforce/admin/warehouses/$id/');
  }, 'Failed to toggle warehouse active state.');

  // ── Categories Approval (platform admin) ───────────────────────────────────

  SellerPage<T> _page<T>(dynamic data, T Function(Map<String, dynamic>) parse) {
    final map = _map(data);
    final results = _list(map['results'] ?? data, parse);
    return SellerPage(
      results: results,
      count: map['count'] is num
          ? (map['count'] as num).toInt()
          : results.length,
      totalPages: map['total_pages'] is num
          ? (map['total_pages'] as num).toInt()
          : 1,
    );
  }

  Future<SellerPage<SellerApprovalStore>> getApprovalSellers({
    String search = '',
    bool hasPending = false,
    int page = 1,
  }) => _guard(() async {
    final params = <String, dynamic>{'page': page, 'page_size': 20};
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    if (hasPending) params['has_pending'] = 'true';
    final res = await _dio.get(
      '/workforce/admin/seller-hub/approval/sellers/',
      queryParameters: params,
    );
    return _page(res.data, SellerApprovalStore.fromJson);
  }, 'Failed to fetch sellers list.');

  /// `status` is `PENDING`, `APPROVED`, `REJECTED` or `ALL`.
  Future<SellerApprovalProductsPage> getApprovalProducts(
    int sellerId, {
    String status = 'PENDING',
    String search = '',
    int? categoryId,
    int page = 1,
  }) => _guard(() async {
    final params = <String, dynamic>{
      'status': status,
      'page': page,
      'page_size': 20,
    };
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    if (categoryId != null) params['category_id'] = categoryId;
    final res = await _dio.get(
      '/workforce/admin/seller-hub/approval/sellers/$sellerId/products/',
      queryParameters: params,
    );
    final seller = _map(res.data)['seller'];
    return SellerApprovalProductsPage(
      seller: seller is Map
          ? SellerApprovalStore.fromJson(Map<String, dynamic>.from(seller))
          : null,
      page: _page(res.data, SellerHubProduct.fromJson),
    );
  }, 'Failed to fetch seller products.');

  Future<SellerProductDetail> getApprovalProductDetail(int productId) =>
      _guard(() async {
        final res = await _dio.get(
          '/workforce/admin/seller-hub/approval/products/$productId/',
        );
        return SellerProductDetail.fromJson(_map(res.data));
      }, 'Failed to load product full details.');

  Future<String?> approveProduct(int productId) => _guard(() async {
    final res = await _dio.post(
      '/workforce/admin/seller-hub/approval/products/$productId/approve/',
      data: {},
    );
    return _message(res.data);
  }, 'Failed to approve product.');

  Future<String?> rejectProduct(int productId, String reason) =>
      _guard(() async {
        final res = await _dio.post(
          '/workforce/admin/seller-hub/approval/products/$productId/reject/',
          data: {'reason': reason.trim()},
        );
        return _message(res.data);
      }, 'Failed to reject product.');

  /// Returns how many of [productIds] were approved.
  Future<int> bulkApproveProducts(List<int> productIds) => _guard(() async {
    final res = await _dio.post(
      '/workforce/admin/seller-hub/approval/products/bulk-approve/',
      data: {'product_ids': productIds},
    );
    final results = _map(res.data)['results'];
    return results is List
        ? results.whereType<Map>().where((r) => r['success'] == true).length
        : 0;
  }, 'Bulk approval failed.');

  Future<List<({int id, String path})>> getCategoryTreePaths() =>
      _guard(() async {
        final res = await _dio.get('/workforce/seller-hub/categories/tree/');
        return flattenSellerCategoryTree(res.data);
      }, 'Failed to load category tree.');

  Future<void> assignSellerWarehouse(
    int sellerId,
    int warehouseId, {
    String notes = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/admin/sellers/$sellerId/warehouse/',
      data: {'warehouse_id': warehouseId, 'notes': notes},
    );
  }, 'Failed to assign warehouse.');

  // ── Coupons ────────────────────────────────────────────────────────────────

  /// `status` is `all`, `active`, `expired` or `inactive`; `discountType`
  /// is `all`, `percent` or `flat`.
  Future<List<SellerHubCoupon>> getCoupons({
    String search = '',
    String status = 'all',
    String discountType = 'all',
  }) => _guard(() async {
    final params = <String, dynamic>{};
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    if (status != 'all') params['status'] = status;
    if (discountType != 'all') params['discount_type'] = discountType;
    final res = await _dio.get(
      '/workforce/seller-hub/coupons/',
      queryParameters: params,
    );
    return _list(res.data, SellerHubCoupon.fromJson);
  }, 'Failed to load coupons');

  Future<void> saveCoupon(Map<String, dynamic> payload, {int? id}) =>
      _guard(() async {
        if (id == null) {
          await _dio.post('/workforce/seller-hub/coupons/', data: payload);
        } else {
          await _dio.patch('/workforce/seller-hub/coupons/$id/', data: payload);
        }
      }, 'Failed to save coupon');

  Future<void> deleteCoupon(int id) => _guard(() async {
    await _dio.delete('/workforce/seller-hub/coupons/$id/');
  }, 'Failed to delete coupon');

  // ── Reports & Quality ──────────────────────────────────────────────────────

  /// `days` is `7`, `30`, `90` or `all`.
  Future<SellerReportsSummary> getReportsSummary(String days) =>
      _guard(() async {
        final res = await _dio.get(
          '/workforce/seller-hub/reports/summary/',
          queryParameters: {'days': days},
        );
        return SellerReportsSummary.fromJson(_map(res.data));
      }, 'Failed to load seller reports summary');

  Future<SellerReportsPerformance> getReportsPerformance(String days) =>
      _guard(() async {
        final res = await _dio.get(
          '/workforce/seller-hub/reports/performance/',
          queryParameters: {'days': days},
        );
        return SellerReportsPerformance.fromJson(_map(res.data));
      }, 'Failed to load performance breakdown');

  Future<SellerQualityAudit> getQualityAudit() => _guard(() async {
    final res = await _dio.get('/workforce/seller-hub/reports/quality-audit/');
    return SellerQualityAudit.fromJson(_map(res.data));
  }, 'Failed to load quality audit');

  /// CSV export: `type` is `orders`, `inventory`, `returns`, `claims` or `quality`.
  Future<Uint8List> exportReportCsv(String type, String days) =>
      _guard(() async {
        final res = await _dio.get<List<int>>(
          '/workforce/seller-hub/reports/export-csv/',
          queryParameters: {'type': type, 'days': days},
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      }, 'Failed to export report');

  // ── Claims ─────────────────────────────────────────────────────────────────

  List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) parse) {
    final list = data is List
        ? data
        : (data is Map && data['results'] is List
              ? data['results'] as List
              : const []);
    return list
        .whereType<Map>()
        .map((e) => parse(Map<String, dynamic>.from(e)))
        .toList();
  }

  SellerHubClaim? _claimFrom(dynamic data) {
    final claim = _map(data)['claim'];
    return claim is Map
        ? SellerHubClaim.fromJson(Map<String, dynamic>.from(claim))
        : null;
  }

  /// `status` is a Web tab id (`OPEN`, `NEEDS_RESPONSE`, ...); `claimType`
  /// empty means all types.
  Future<List<SellerHubClaim>> getClaims({
    String status = 'ALL',
    String claimType = '',
    String search = '',
  }) => _guard(() async {
    final params = <String, dynamic>{};
    if (status != 'ALL') params['status'] = status;
    if (claimType.isNotEmpty) params['claim_type'] = claimType;
    if (search.trim().isNotEmpty) params['search'] = search.trim();
    final res = await _dio.get(
      '/workforce/seller-hub/claims/',
      queryParameters: params,
    );
    return _list(res.data, SellerHubClaim.fromJson);
  }, 'Failed to load claims list');

  Future<SellerHubClaim> getClaimDetail(int claimId) => _guard(() async {
    final res = await _dio.get('/workforce/seller-hub/claims/$claimId/');
    return SellerHubClaim.fromJson(_map(res.data));
  }, 'Error loading claim details');

  /// Files a new claim; returns the created claim number when present.
  Future<String?> createClaim({
    required String claimType,
    required String description,
    int? orderId,
    int? returnId,
    double claimedAmount = 0,
    List<String> evidenceUrls = const [],
    String customerName = '',
    String customerPhone = '',
  }) => _guard(() async {
    final res = await _dio.post(
      '/workforce/seller-hub/claims/',
      data: {
        'claim_type': claimType,
        'description': description.trim(),
        'order_id': orderId,
        'return_id': returnId,
        'claimed_amount': claimedAmount,
        'evidence_urls': evidenceUrls,
        'customer_name': customerName.trim(),
        'customer_phone': customerPhone.trim(),
      },
    );
    return _claimFrom(res.data)?.claimNumber;
  }, 'Failed to create claim');

  Future<SellerHubClaim?> respondToClaim(
    int claimId,
    String response, {
    List<String> evidenceUrls = const [],
  }) => _guard(() async {
    final res = await _dio.post(
      '/workforce/seller-hub/claims/$claimId/respond/',
      data: {'seller_response': response.trim(), 'evidence_urls': evidenceUrls},
    );
    return _claimFrom(res.data);
  }, 'Failed to submit response');

  Future<SellerHubClaim?> escalateClaim(int claimId, {String notes = ''}) =>
      _guard(() async {
        final res = await _dio.post(
          '/workforce/seller-hub/claims/$claimId/escalate/',
          data: {
            'notes': notes.trim().isEmpty
                ? 'Escalated to Platform Admin for dispute review.'
                : notes.trim(),
          },
        );
        return _claimFrom(res.data);
      }, 'Failed to escalate claim');

  /// Platform admin arbitration: `APPROVE`, `REJECT`,
  /// `REQUEST_SELLER_RESPONSE` or `SETTLE`, with a mandatory reason.
  Future<SellerHubClaim?> decideClaim(
    int claimId,
    String decision,
    String reason,
  ) => _guard(() async {
    final res = await _dio.post(
      '/workforce/seller-hub/claims/$claimId/admin-decision/',
      data: {'decision': decision, 'reason': reason.trim()},
    );
    return _claimFrom(res.data);
  }, 'Failed to submit admin decision');

  Future<SellerHubClaim?> closeClaim(int claimId, {String notes = ''}) =>
      _guard(() async {
        final res = await _dio.post(
          '/workforce/seller-hub/claims/$claimId/close/',
          data: {
            'notes': notes.trim().isEmpty
                ? 'Claim resolved and archived.'
                : notes.trim(),
          },
        );
        return _claimFrom(res.data);
      }, 'Failed to close claim');
}
