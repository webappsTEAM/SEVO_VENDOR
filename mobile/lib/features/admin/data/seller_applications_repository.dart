import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/seller_application.dart';

final sellerApplicationsRepositoryProvider =
    Provider<SellerApplicationsRepository>((ref) {
      return SellerApplicationsRepository(ref.watch(apiClientProvider));
    });

class SellerApplicationsException implements Exception {
  const SellerApplicationsException(this.message);

  factory SellerApplicationsException.fromDio(DioException e, String fallback) {
    var message = describeDioError(e, fallback: fallback);
    if (message.trimLeft().startsWith('<')) message = fallback;
    return SellerApplicationsException(message);
  }

  final String message;

  @override
  String toString() => message;
}

/// Platform / vendor-admin review queue for Grocery Seller Hub merchants
/// (`/workforce/admin/seller-applications/*`, Web `workforceService.js`).
class SellerApplicationsRepository {
  SellerApplicationsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call, String fallback) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw SellerApplicationsException.fromDio(e, fallback);
    }
  }

  /// `status` is the Web filter value (`pending`, `approved`, `correction_required`,
  /// `rejected`); null / empty loads every application.
  Future<List<SellerApplication>> list({String? status}) => _guard(() async {
    final res = await _dio.get(
      '/workforce/admin/seller-applications/',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final data = res.data;
    final rows = data is List
        ? data
        : (data is Map && data['results'] is List
              ? data['results'] as List
              : const []);
    return [
      for (final r in rows)
        if (r is Map) SellerApplication.fromJson(Map<String, dynamic>.from(r)),
    ];
  }, 'Failed to load seller applications.');

  Future<SellerApplication> detail(int id) => _guard(() async {
    final res = await _dio.get('/workforce/admin/seller-applications/$id/');
    final data = res.data;
    if (data is! Map)
      throw const SellerApplicationsException(
        'The requested seller application could not be found.',
      );
    return SellerApplication.fromJson(Map<String, dynamic>.from(data));
  }, 'Failed to load seller application dossier.');

  Future<void> verifyDocument(
    int id,
    String docKey,
    String action, {
    String reason = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/admin/seller-applications/$id/document/$docKey/verify/',
      data: {'action': action, 'reason': reason},
    );
  }, 'Failed to $action document.');

  Future<void> bulkApproveAllPending(int id) => _guard(() async {
    await _dio.post(
      '/workforce/admin/seller-applications/$id/documents/bulk-verify/',
      data: {
        'categories': null,
        'action': 'approve',
        'reason': '',
        'all_pending': true,
      },
    );
  }, 'Failed to bulk approve documents.');

  Future<void> decideCategory(
    int id,
    String categoryId,
    String action, {
    String reason = '',
  }) => _guard(() async {
    await _dio.post(
      '/workforce/admin/seller-applications/$id/category/$categoryId/decide/',
      data: {'action': action, 'reason': reason},
    );
  }, 'Failed to $action category.');

  Future<void> requestCorrection(int id, String notes) => _guard(() async {
    await _dio.post(
      '/workforce/admin/seller-applications/$id/request-correction/',
      data: {'notes': notes},
    );
  }, 'Failed to request correction.');

  Future<void> approve(int id) => _guard(() async {
    await _dio.post('/workforce/admin/seller-applications/$id/approve/');
  }, 'Failed to approve seller application.');

  Future<void> reject(int id, String reason) => _guard(() async {
    await _dio.post(
      '/workforce/admin/seller-applications/$id/reject/',
      data: {'reason': reason},
    );
  }, 'Failed to reject application.');
}
