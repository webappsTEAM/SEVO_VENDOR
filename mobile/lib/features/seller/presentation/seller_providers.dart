import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seller_repository.dart';
import '../domain/seller_models.dart';

// ── Store Profile Providers ───────────────────────────────────────────────────
final sellerStoreProfileProvider =
    FutureProvider.autoDispose<SellerStoreProfile>((ref) async {
      final repo = ref.watch(sellerRepositoryProvider);
      return repo.getStoreProfile();
    });
