import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_invoice.dart';

/// Search query string for commercial invoices.
final adminInvoicesSearchQueryProvider = StateProvider<String>((ref) => '');

/// Selected status filter ('' = all, 'PAID', 'ISSUED', 'PARTIALLY_PAID', 'CANCELLED').
final adminInvoicesStatusFilterProvider = StateProvider<String>((ref) => '');

/// All invoices from `/workforce/invoices/`, loaded once like the Web page;
/// search, status tabs, KPIs and CSV export work on this list locally.
final adminInvoicesListProvider =
    FutureProvider.autoDispose<List<AdminInvoice>>((ref) async {
      final raw = await ref.watch(adminDashboardApiProvider).fetchInvoices();
      return raw
          .whereType<Map<String, dynamic>>()
          .map(AdminInvoice.fromJson)
          .toList();
    });

/// Web filter: invoice number, customer name / phone, service, job id.
List<AdminInvoice> filterInvoices(
  List<AdminInvoice> all, {
  required String search,
  required String status,
}) {
  final term = search.trim().toLowerCase();
  return all.where((inv) {
    final matchesSearch =
        term.isEmpty ||
        inv.invoiceNumber.toLowerCase().contains(term) ||
        inv.billToName.toLowerCase().contains(term) ||
        inv.billToPhone.toLowerCase().contains(term) ||
        inv.serviceName.toLowerCase().contains(term) ||
        inv.serviceCategory.toLowerCase().contains(term) ||
        '${inv.jobId ?? ''}'.contains(term) ||
        (inv.jobRequestId ?? '').toLowerCase().contains(term);
    final matchesStatus = status.isEmpty || inv.status == status.toUpperCase();
    return matchesSearch && matchesStatus;
  }).toList();
}

/// Fetches detailed invoice with line items and payment history by invoice ID.
final adminInvoiceDetailProvider = FutureProvider.autoDispose
    .family<AdminInvoice, int>((ref, id) async {
      final raw = await ref
          .watch(adminDashboardApiProvider)
          .fetchInvoiceDetail(id);
      return AdminInvoice.fromJson(raw);
    });
