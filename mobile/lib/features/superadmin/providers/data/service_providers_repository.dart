import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_error.dart';
import '../domain/service_provider.dart';

final serviceProvidersRepositoryProvider = Provider<ServiceProvidersRepository>(
  (ref) {
    return ServiceProvidersRepository(ref.watch(apiClientProvider));
  },
);

class ServiceProvidersException implements Exception {
  const ServiceProvidersException(this.message, {this.unavailable = false});

  factory ServiceProvidersException.fromDio(DioException e, String fallback) {
    // The route is part of the Web contract but is not deployed on every
    // backend; say so plainly instead of showing a raw 404.
    if (e.response?.statusCode == 404) {
      return const ServiceProvidersException(
        'Service Providers is not available on this server yet.',
        unavailable: true,
      );
    }
    var message = describeDioError(e, fallback: fallback);
    if (message.trimLeft().startsWith('<')) message = fallback;
    return ServiceProvidersException(message);
  }

  final String message;

  /// True when the server has no such route (HTTP 404).
  final bool unavailable;

  @override
  String toString() => message;
}

/// Platform-wide service provider governance
/// (`/workforce/superadmin/service-providers/`, Web `workforceService.js`).
class ServiceProvidersRepository {
  ServiceProvidersRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call, String fallback) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ServiceProvidersException.fromDio(e, fallback);
    }
  }

  /// `isActive`: null = all, true = active only, false = inactive only.
  Future<List<ServiceProvider>> list({String q = '', bool? isActive}) => _guard(
    () async {
      final res = await _dio.get(
        '/workforce/superadmin/service-providers/',
        queryParameters: {
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'is_active': ?isActive,
        },
      );
      final body = res.data;
      final rows = body is List
          ? body
          : (body is Map && body['results'] is List
                ? body['results'] as List
                : const []);
      return [
        for (final r in rows)
          if (r is Map) ServiceProvider.fromJson(Map<String, dynamic>.from(r)),
      ];
    },
    'Failed to load service providers.',
  );

  /// Returns the server's confirmation message when it sends one.
  Future<String?> create(NewServiceProvider provider) => _guard(() async {
    final res = await _dio.post(
      '/workforce/superadmin/service-providers/',
      data: provider.toJson(),
    );
    final body = res.data;
    return body is Map && body['message'] is String
        ? body['message'] as String
        : null;
  }, 'Failed to create Service Provider.');
}
