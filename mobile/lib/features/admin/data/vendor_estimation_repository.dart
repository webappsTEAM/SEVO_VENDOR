import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/vendor_estimation.dart';

final vendorEstimationRepositoryProvider = Provider<VendorEstimationRepository>(
  (ref) {
    return VendorEstimationRepository(ref.watch(apiClientProvider));
  },
);

class VendorEstimationException implements Exception {
  const VendorEstimationException(this.message);

  factory VendorEstimationException.fromDio(DioException e, String fallback) {
    var message = describeDioError(e, fallback: fallback);
    if (message.trimLeft().startsWith('<')) message = fallback;
    return VendorEstimationException(message);
  }

  final String message;

  @override
  String toString() => message;
}

/// AC Inspection & Estimation workflow (`/vendor/estimations/*`, Web
/// `vendorEstimationService.js`). The Web client double-prefixes `/api` on these
/// calls, so the live page shows "Request failed"; the mobile client's base URL
/// already ends in `/api`, so the real route is used here.
class VendorEstimationRepository {
  VendorEstimationRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call, String fallback) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw VendorEstimationException.fromDio(e, fallback);
    }
  }

  /// Web actions return `res.data ?? res`.
  VendorEstimation _lead(Response<dynamic> res) {
    final body = res.data;
    final inner = body is Map && body['data'] is Map ? body['data'] : body;
    if (inner is! Map)
      throw const VendorEstimationException(
        'Unexpected response from the server.',
      );
    return VendorEstimation.fromJson(Map<String, dynamic>.from(inner));
  }

  Future<VendorEstimationList> list({
    String status = 'all',
    String? date,
    String? search,
    int? page,
  }) => _guard(() async {
    final res = await _dio.get(
      '/vendor/estimations/',
      queryParameters: {
        if (status != 'all') 'status': status,
        if (date != null && date.isNotEmpty) 'date': date,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': ?page,
      },
    );
    return VendorEstimationList.fromJson(res.data);
  }, 'Failed to load estimation leads.');

  Future<VendorEstimation> detail(int id) => _guard(
    () async => _lead(await _dio.get('/vendor/estimations/$id/')),
    'Could not fetch full lead details.',
  );

  Future<VendorEstimation> confirm(int id) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/confirm/',
        data: <String, dynamic>{},
      ),
    ),
    'Failed to confirm lead.',
  );

  Future<VendorEstimation> startJourney(int id) => _guard(
    () async =>
        _lead(await _dio.post('/vendor/estimations/$id/start-journey/')),
    'Failed to start trip.',
  );

  Future<VendorEstimation> markArrived(int id) => _guard(
    () async => _lead(await _dio.post('/vendor/estimations/$id/arrived/')),
    'Failed to mark arrival.',
  );

  Future<VendorEstimation> verifyOtp(int id, String otp) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/verify-otp/',
        data: {'otp': otp.trim()},
      ),
    ),
    'Invalid OTP. Please verify with the customer.',
  );

  Future<VendorEstimation> assignTechnician(
    int id, {
    String? technicianId,
    required String name,
    required String phone,
  }) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/assign-technician/',
        data: {
          'technician_id': (technicianId ?? '').isEmpty ? null : technicianId,
          'technician_name': name,
          'technician_phone': phone,
        },
      ),
    ),
    'Failed to assign technician.',
  );

  Future<List<VendorTechnician>> technicians() => _guard(() async {
    final res = await _dio.get('/vendor/technicians/');
    final body = res.data;
    final rows = body is Map && body['technicians'] is List
        ? body['technicians'] as List
        : const [];
    return [
      for (final r in rows)
        if (r is Map) VendorTechnician.fromJson(Map<String, dynamic>.from(r)),
    ];
  }, 'Could not fetch technicians list.');

  /// `paymentMethod` is `CASH` or `UPI`.
  Future<void> collectFee(
    int id, {
    required String paymentMethod,
    String reference = '',
  }) => _guard(() async {
    await _dio.post(
      '/vendor/estimations/$id/fee/collect/',
      data: {
        'payment_method': paymentMethod,
        'payment_reference': reference.trim(),
      },
    );
  }, 'Failed to update fee record.');

  Future<void> waiveFee(int id, {required String reason}) => _guard(() async {
    await _dio.post(
      '/vendor/estimations/$id/fee/waive/',
      data: {'reason': reason.trim()},
    );
  }, 'Failed to update fee record.');

  /// Inspection sheet step 1: `{ac_details, diagnosis, notes, findings}`.
  Future<void> saveInspectionDetails(int id, Map<String, dynamic> payload) =>
      _guard(() async {
        await _dio.post(
          '/vendor/estimations/$id/inspection/save/',
          data: payload,
        );
      }, 'Failed to save inspection details.');

  /// Inspection sheet step 2: mark the inspection complete.
  Future<VendorEstimation> completeInspection(
    int id, {
    required String diagnosis,
    String notes = '',
  }) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/inspection/complete/',
        data: {'diagnosis_summary': diagnosis, 'notes': notes},
      ),
    ),
    'Failed to complete inspection.',
  );

  /// Uploads one defect photo; returns the created photo object when present.
  Future<Map<String, dynamic>?> uploadInspectionPhoto(
    int id,
    String filePath, {
    String caption = '',
  }) => _guard(() async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath),
      'caption': caption,
    });
    final res = await _dio.post(
      '/vendor/estimations/$id/inspection/photos/',
      data: form,
    );
    final body = res.data;
    return body is Map && body['photo'] is Map
        ? Map<String, dynamic>.from(body['photo'] as Map)
        : null;
  }, 'Failed to upload photo.');

  /// Saves the draft quotation; returns the refreshed lead (with `latest_quotation`).
  Future<VendorEstimation> saveQuotation(
    int id,
    Map<String, dynamic> payload,
  ) => _guard(
    () async => _lead(
      await _dio.post('/vendor/estimations/$id/quotation/', data: payload),
    ),
    'Failed to save quotation draft.',
  );

  Future<VendorEstimation> submitQuotationForReview(int id, int quoteId) =>
      _guard(
        () async => _lead(
          await _dio.post('/vendor/estimations/$id/quotation/$quoteId/submit/'),
        ),
        'Failed to submit quotation for admin review.',
      );

  Future<VendorEstimation> reviseQuotation(int id, int quoteId) => _guard(
    () async => _lead(
      await _dio.post('/vendor/estimations/$id/quotation/$quoteId/revise/'),
    ),
    'Failed to revise quotation.',
  );

  /// `action` is `APPROVE` or `SEND_BACK`.
  Future<VendorEstimation> adminReviewQuotation(
    int id,
    int quoteId, {
    required String action,
    required String notes,
    bool autoConvert = false,
  }) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/quotation/$quoteId/admin-review/',
        data: {
          'action': action,
          'admin_notes': notes,
          'auto_convert': action == 'APPROVE' && autoConvert,
        },
      ),
    ),
    'Failed to submit admin review decision.',
  );

  Future<VendorEstimation> approveQuotationForCustomer(
    int id, {
    required String date,
    required String time,
  }) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/customer-decide/',
        data: {
          'decision': 'APPROVE',
          'scheduled_date': date,
          'scheduled_time': time,
        },
      ),
    ),
    'Failed to approve quotation and book job.',
  );

  Future<VendorEstimation> rejectQuotationForCustomer(
    int id, {
    required String reason,
    String note = '',
    required String paymentMethod,
  }) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/customer-decide/',
        data: {
          'decision': 'REJECT',
          'rejection_reason': reason,
          'rejection_note': note,
          'payment_method': paymentMethod,
        },
      ),
    ),
    'Failed to reject estimation.',
  );

  /// `stage`: START_REPAIR, COMPLETE_REPAIR, TEST_AC or CUSTOMER_CONFIRM.
  Future<VendorEstimation> progressRepair(int id, String stage) => _guard(
    () async => _lead(
      await _dio.post(
        '/vendor/estimations/$id/repair/progress/',
        data: {'stage': stage},
      ),
    ),
    'Failed to advance repair stage to $stage.',
  );
}
