import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seller_hub_repository.dart';
import '../domain/seller_hub_models.dart';

/// Seller Home data: `GET /workforce/seller-hub/metrics/` (one request; the
/// category / coupon lists are only fetched if the counts are missing).
final sellerHomeSummaryProvider = FutureProvider.autoDispose<SellerHomeSummary>(
  (ref) {
    return ref.watch(sellerHubRepositoryProvider).getHomeSummary();
  },
);

/// Metrics header cards on the Orders and Returns screens.
final sellerHubMetricsProvider = FutureProvider.autoDispose<SellerHubMetrics>((
  ref,
) {
  return ref.watch(sellerHubRepositoryProvider).getMetrics();
});
