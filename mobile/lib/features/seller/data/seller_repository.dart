import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/seller_models.dart';

final sellerRepositoryProvider = Provider<SellerRepository>((ref) {
  final dio = ref.watch(apiClientProvider);
  return SellerRepository(dio);
});

/// Store profile API (`/workforce/store/profile/`), shared with the Web
/// Store Profile page. Other Seller Hub modules use [SellerHubRepository].
class SellerRepository {
  const SellerRepository(this._dio);

  final Dio _dio;

  Future<SellerStoreProfile> getStoreProfile() async {
    final res = await _dio.get('/workforce/store/profile/');
    return SellerStoreProfile.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SellerStoreProfile> updateStoreProfile(
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.patch('/workforce/store/profile/', data: data);
    return SellerStoreProfile.fromJson(res.data as Map<String, dynamic>);
  }
}
