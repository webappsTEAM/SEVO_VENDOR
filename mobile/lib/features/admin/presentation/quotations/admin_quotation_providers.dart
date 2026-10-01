import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_quotation.dart';

/// Active tab on the Quotation Approvals screen (Web order and default):
/// - 'presend': Held before sending (awaiting CRM clearance)
/// - 'acceptance': Awaiting SEVO approval (after customer accepts)
/// - 'all': All Quotations & History
final adminQuotationTabProvider = StateProvider<String>((ref) => 'presend');

List<AdminQuotation> _parse(List<dynamic> raw) => raw
    .whereType<Map>()
    .map((e) => AdminQuotation.fromJson(Map<String, dynamic>.from(e)))
    .toList();

/// Quotations awaiting SEVO authorization after customer acceptance.
final adminQuotesPendingApprovalProvider =
    FutureProvider.autoDispose<List<AdminQuotation>>((ref) async {
      return _parse(
        await ref.watch(adminDashboardApiProvider).fetchQuotesPendingApproval(),
      );
    });

/// Quotations held before sending to customer (pre-send review queue).
final adminQuotesPendingReviewProvider =
    FutureProvider.autoDispose<List<AdminQuotation>>((ref) async {
      return _parse(
        await ref.watch(adminDashboardApiProvider).fetchQuotesPendingReview(),
      );
    });

/// Full quotation history.
final adminQuotesAllProvider = FutureProvider.autoDispose<List<AdminQuotation>>(
  (ref) async {
    return _parse(await ref.watch(adminDashboardApiProvider).fetchAllQuotes());
  },
);
