import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/vendor_stock.dart';

final vendorStockRepositoryProvider = Provider<VendorStockRepository>((ref) {
  return VendorStockRepository(ref.watch(apiClientProvider));
});

class VendorStockException implements Exception {
  const VendorStockException(this.message);

  factory VendorStockException.fromDio(DioException e, String fallback) {
    final data = e.response?.data;
    // Web `extractStockErrorMessage`: `err.data.message` first.
    final fromBody = data is Map && data['message'] is String
        ? data['message'] as String
        : null;
    var message = fromBody ?? describeDioError(e, fallback: fallback);
    if (message.trimLeft().startsWith('<')) message = fallback;
    return VendorStockException(message);
  }

  final String message;

  @override
  String toString() => message;
}

/// Vendor-scoped stock endpoints (`/vendor/stock/*`, Web `stockService.js`).
/// The server scopes every call to the signed-in vendor's own company, so no
/// company id is ever sent.
class VendorStockRepository {
  VendorStockRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call, String fallback) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw VendorStockException.fromDio(e, fallback);
    }
  }

  VendorStockWriteResult _result(Response<dynamic> res) {
    final body = res.data;
    if (body is! Map) return const VendorStockWriteResult();
    return VendorStockWriteResult(
      message: body['message'] is String ? body['message'] as String : null,
      data: body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : null,
    );
  }

  Future<List<VendorStockProduct>> list() => _guard(() async {
    final res = await _dio.get('/vendor/stock/');
    final body = res.data;
    final rows = body is Map && body['data'] is List
        ? body['data'] as List
        : const [];
    return [
      for (final r in rows)
        if (r is Map) VendorStockProduct.fromJson(Map<String, dynamic>.from(r)),
    ];
  }, 'Could not load your stock.');

  Future<VendorStockWriteResult> restock(
    int productId, {
    required double quantity,
    required String unit,
  }) => _guard(() async {
    final res = await _dio.post(
      '/vendor/stock/$productId/restock/',
      data: {'quantity': quantity, 'unit': unit},
    );
    return _result(res);
  }, 'Could not restock this product.');

  Future<VendorStockWriteResult> markOutOfStock(int productId) =>
      _guard(() async {
        final res = await _dio.post(
          '/vendor/stock/$productId/mark-out-of-stock/',
          data: <String, dynamic>{},
        );
        return _result(res);
      }, 'Could not mark this product out of stock.');

  /// `payload` keys (all optional): price, offer_price, reorder_level_quantity,
  /// reorder_level_unit, restock_level_quantity, restock_level_unit.
  Future<VendorStockWriteResult> updateDetails(
    int productId,
    Map<String, dynamic> payload,
  ) => _guard(() async {
    final res = await _dio.patch(
      '/vendor/stock/$productId/update-details/',
      data: payload,
    );
    return _result(res);
  }, 'Could not update this product.');

  Future<List<VendorStockHistoryRow>> history(int productId) =>
      _guard(() async {
        final res = await _dio.get('/vendor/stock/$productId/history/');
        final body = res.data;
        final rows = body is Map && body['data'] is List
            ? body['data'] as List
            : const [];
        return [
          for (final r in rows)
            if (r is Map)
              VendorStockHistoryRow.fromJson(Map<String, dynamic>.from(r)),
        ];
      }, 'Could not load stock history.');
}
