import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Status badge for a Seller Hub order (labels match the Web
/// `renderStatusBadge`).
class SellerOrderStatusBadge extends StatelessWidget {
  const SellerOrderStatusBadge(this.status, {super.key});

  final String status;

  static (String, Color, IconData) styleFor(String status) {
    switch (status) {
      case 'NEW':
        return ('New Order', const Color(0xFFD97706), Icons.schedule_rounded);
      case 'ACCEPTED':
        return ('Accepted', const Color(0xFF2563EB), Icons.check_rounded);
      case 'PICKING':
        return ('Picking', const Color(0xFF4F46E5), Icons.inventory_2_outlined);
      case 'PACKED':
        return ('Packed', const Color(0xFF7C3AED), Icons.check_box_outlined);
      case 'READY_FOR_PICKUP':
        return (
          'Ready for Pickup',
          const Color(0xFF0891B2),
          Icons.local_shipping_outlined,
        );
      case 'ASSIGNED':
        return (
          'Rider Assigned',
          const Color(0xFF0D9488),
          Icons.local_shipping_outlined,
        );
      case 'HANDED_OVER':
        return (
          'Out for Delivery',
          const Color(0xFF0284C7),
          Icons.local_shipping_rounded,
        );
      case 'DELIVERED':
        return (
          'Delivered',
          const Color(0xFF059669),
          Icons.check_circle_rounded,
        );
      case 'CANCELLED':
        return ('Cancelled', const Color(0xFFDC2626), Icons.block_rounded);
      default:
        return (status, const Color(0xFF64748B), Icons.circle_outlined);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = styleFor(status);
    return SellerPill(label: label, color: color, icon: icon);
  }
}

/// The per-status primary quick action shown on order cards and in the
/// detail sheet: (transition action, card label, sheet label).
(String, String, String)? primaryOrderAction(String status) {
  switch (status) {
    case 'NEW':
      return ('accept', 'Accept', 'Accept Order & Reserve Stock');
    case 'ACCEPTED':
      return ('start_picking', 'Start Picking', 'Start Picking Items');
    case 'PICKING':
      return ('mark_packed', 'Mark Packed', 'Mark Items Packed');
    case 'PACKED':
      return ('mark_ready', 'Dispatch Rider', 'Dispatch 2-Wheeler Rider');
    default:
      return null;
  }
}

/// Order workflow actions shared by the list and the detail sheet. Every
/// call goes to the same endpoint the Web uses; [onChanged] receives the
/// updated order (when the server returns one) so callers can refresh.
class SellerOrderActions {
  SellerOrderActions({
    required this.context,
    required this.ref,
    required this.onChanged,
  });

  final BuildContext context;
  final WidgetRef ref;
  final void Function(SellerHubOrder? updated) onChanged;

  SellerHubRepository get _repo => ref.read(sellerHubRepositoryProvider);

  void _snack(String message, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
      ),
    );
  }

  Future<void> _handleError(Object e) async {
    if (e is SellerHubException && e.needsWarehouseOrLocation) {
      await showWarehouseRequiredDialog(context, e);
      return;
    }
    _snack(
      e is SellerHubException ? e.message : 'Network error. Please try again.',
      error: true,
    );
  }

  Future<bool> transition(
    SellerHubOrder order,
    String action, {
    String cancellationReason = '',
  }) async {
    try {
      final updated = await _repo.transitionOrder(
        order.id,
        action,
        cancellationReason: cancellationReason,
      );
      onChanged(updated);
      return true;
    } catch (e) {
      await _handleError(e);
      return false;
    }
  }

  Future<bool> cancel(SellerHubOrder order) async {
    final reason = await _promptReason(
      title: 'Cancel Fulfilment Order',
      message: 'Reserved stock will be automatically released back to available balance.',
      label: 'Cancellation Reason (Mandatory)',
      hint: 'E.g. Item damaged in warehouse / Out of stock / Customer requested cancellation...',
      confirmLabel: 'Confirm Cancellation',
      backLabel: 'Back',
    );
    if (reason == null) return false;
    return transition(order, 'cancel', cancellationReason: reason);
  }

  Future<bool> adminOverride(SellerHubOrder order, String action) async {
    final isHandover = action == 'admin_override_handover';
    final reason = await _promptReason(
      title: isHandover ? 'Admin Override Handover' : 'Admin Override Delivery',
      message:
          'Bypass OTP verification for order #${order.orderNumber}.\n\n'
          'This action forcefully advances the order status without requiring rider OTP entry. Your username, '
          'timestamp, and mandatory justification reason will be recorded in the immutable audit trail.',
      label: 'Justification Reason *',
      hint: 'e.g. Rider device battery failed at store; physical package handover confirmed by store manager via phone.',
      confirmLabel: 'Confirm Override',
      backLabel: 'Cancel',
    );
    if (reason == null) return false;
    try {
      final updated = await _repo.adminOverride(order.id, action, reason);
      onChanged(updated);
      return true;
    } catch (e) {
      await _handleError(e);
      return false;
    }
  }

  Future<void> retryDispatch(SellerHubOrder order) async {
    try {
      final result = await _repo.retryDispatch(order.id);
      onChanged(result.order);
      _snack('Dispatch retried for #${order.orderNumber}.');
    } catch (e) {
      await _handleError(e);
    }
  }

  Future<void> showRiders(SellerHubOrder order) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => _RiderAvailabilitySheet(
        order: order,
        repo: _repo,
        onRetry: () => retryDispatch(order),
      ),
    );
  }

  Future<void> previewPackingSlip(SellerHubOrder order) async {
    try {
      final slip = await _repo.getPackingSlip(order.id);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        builder: (_) => _PackingSlipSheet(
          slip: slip,
          onDownloadLabel: () => downloadShippingLabel(order),
        ),
      );
    } catch (e) {
      await _handleError(e);
    }
  }

  /// Downloads the printable 4x6 shipping label and hands it to the OS
  /// share sheet (print / save / open in a PDF viewer).
  Future<void> downloadShippingLabel(SellerHubOrder order) async {
    try {
      final bytes = await _repo.downloadShippingLabelPdf(order.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/shipping_label_${order.orderNumber}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Shipping Label ${order.orderNumber}',
        ),
      );
    } catch (e) {
      await _handleError(e);
    }
  }

  /// Opens the Web public live-tracking page for the dispatch job.
  Future<void> trackRider(SellerHubOrder order) async {
    final jobId = order.dispatchJobId;
    if (jobId == null) return;
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/track/$jobId');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _snack('Unable to open live tracking.', error: true);
  }

  Future<String?> _promptReason({
    required String title,
    required String message,
    required String label,
    required String hint,
    required String confirmLabel,
    required String backLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(
        title: title,
        message: message,
        label: label,
        hint: hint,
        confirmLabel: confirmLabel,
        backLabel: backLabel,
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.backLabel,
  });

  final String title;
  final String message;
  final String label;
  final String hint;
  final String confirmLabel;
  final String backLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                hintMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.backLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Web `storeLocationModal`: warehouse assignment / store GPS pin required.
Future<void> showWarehouseRequiredDialog(
  BuildContext context,
  SellerHubException e,
) {
  final isWarehouse = e.code == 'WAREHOUSE_ASSIGNMENT_REQUIRED';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warehouse_rounded, color: Color(0xFFD97706)),
      title: Text(
        isWarehouse
            ? 'Warehouse Assignment Required'
            : 'Store Location Required',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: Text(
        e.message,
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
        if (!isWarehouse)
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go(AppRoutes.sellerStoreProfile);
            },
            child: const Text('Configure Store Location'),
          ),
      ],
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    this.subtitle,
    required this.children,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            title: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            subtitle: subtitle == null
                ? null
                : Text(subtitle!, style: const TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(AppSpacing.md),
              children: children,
            ),
          ),
          if (footer != null) SafeArea(top: false, child: footer!),
        ],
      ),
    );
  }
}

class _RiderAvailabilitySheet extends StatefulWidget {
  const _RiderAvailabilitySheet({
    required this.order,
    required this.repo,
    required this.onRetry,
  });

  final SellerHubOrder order;
  final SellerHubRepository repo;
  final Future<void> Function() onRetry;

  @override
  State<_RiderAvailabilitySheet> createState() =>
      _RiderAvailabilitySheetState();
}

class _RiderAvailabilitySheetState extends State<_RiderAvailabilitySheet> {
  late Future<SellerRiderAvailability> _future = widget.repo.getAvailableRiders(
    widget.order.id,
  );
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _future = widget.repo.getAvailableRiders(widget.order.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: '2-Wheeler Rider Availability',
      subtitle: 'Order #${widget.order.orderNumber}',
      footer: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _retrying ? null : _retry,
            icon: _retrying
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry Dispatch'),
          ),
        ),
      ),
      children: [
        FutureBuilder<SellerRiderAvailability>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SellerLoading(
                message: 'Evaluating dispatch criteria & live GPS...',
              );
            }
            if (snap.hasError) {
              final err = snap.error;
              return SellerStateMessage(
                icon: Icons.error_outline_rounded,
                color: const Color(0xFFDC2626),
                title: 'Failed to load rider availability',
                message: err is SellerHubException
                    ? err.message
                    : 'Please try again.',
              );
            }
            return _RiderAvailabilityBody(data: snap.data!);
          },
        ),
      ],
    );
  }
}

class _RiderAvailabilityBody extends StatelessWidget {
  const _RiderAvailabilityBody({required this.data});

  final SellerRiderAvailability data;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFD97706);
    final locationMissing = data.storeLocationMissing || data.warehouseMissing;
    final String statusLabel;
    if (locationMissing) {
      statusLabel = data.warehouseMissing
          ? 'Warehouse Not Assigned'
          : 'Location Not Set';
    } else if (data.eligibleCount != null) {
      statusLabel = '${data.eligibleCount} Eligible Rider(s)';
    } else {
      statusLabel = '${data.onlineRidersCount ?? 0} Online Rider(s)';
    }
    final positive =
        !locationMissing &&
        ((data.eligibleCount ?? data.onlineRidersCount ?? 0) > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SellerPanel(
          tint: positive ? AppColors.emerald : amber,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Dispatch Evaluation Status',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  SellerPill(
                    label: statusLabel,
                    color: positive ? AppColors.emerald : amber,
                  ),
                ],
              ),
              if (data.diagnosticSummary != null || data.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  data.diagnosticSummary ?? data.error!,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
              if (data.pickupLocationName != null)
                SellerKeyValue('Pickup from', data.pickupLocationName!),
              if (data.totalActiveRiders != null)
                SellerKeyValue('Active riders', '${data.totalActiveRiders}'),
              if (data.ridersInRadius != null)
                SellerKeyValue('In radius', '${data.ridersInRadius}'),
            ],
          ),
        ),
        if (data.storeLocationMissing) ...[
          const SizedBox(height: 10),
          SellerPanel(
            tint: amber,
            title: 'Store Location Pin Missing',
            subtitle:
                'Your store or warehouse GPS coordinates have not been configured. Rider matching and dispatch '
                'require exact store coordinates to calculate distances and route nearby riders.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go(AppRoutes.sellerStoreProfile);
                },
                child: const Text('Configure Store Location'),
              ),
            ),
          ),
        ],
        if (data.activeOfferEmployeeName != null) ...[
          const SizedBox(height: 10),
          SellerPanel(
            tint: const Color(0xFF2563EB),
            title: 'Live Exclusive Offer Active',
            subtitle:
                'Offered to ${data.activeOfferEmployeeName}. Auto-expires if not accepted within the dispatch window.',
            child: const SizedBox.shrink(),
          ),
        ],
        if (data.eligibleRiders.isNotEmpty) ...[
          const SellerSectionLabel('Eligible Technicians Ready For Offer'),
          for (final r in data.eligibleRiders)
            _RiderRow(
              name: r.name,
              detail: [
                if (r.distanceKm != null) '${r.distanceKm} km away',
                if (r.score != null) 'Proximity score: ${r.score}',
                if (r.gpsAgeSeconds != null)
                  'GPS ping ${r.gpsAgeSeconds!.round()}s ago',
              ].join(' • '),
              tag: 'Ready',
              tagColor: AppColors.emerald,
            ),
        ],
        if (data.ineligibleRiders.isNotEmpty) ...[
          const SellerSectionLabel(
            'Other Registered Technicians (Rejection Reason)',
          ),
          for (final r in data.ineligibleRiders)
            _RiderRow(
              name: r.name,
              detail: r.reason ?? '',
              tag: r.gate,
              tagColor: const Color(0xFF64748B),
            ),
        ],
        if (data.nearbyRiders.isNotEmpty) ...[
          const SellerSectionLabel('Registered Riders'),
          for (final r in data.nearbyRiders)
            _RiderRow(
              name: r.name,
              detail: r.distanceKm == null
                  ? 'No recent GPS location'
                  : '${r.distanceKm} km away',
              tag: r.isOnline ? 'Online' : 'Offline',
              tagColor: r.isOnline
                  ? AppColors.emerald
                  : const Color(0xFF64748B),
            ),
        ],
      ],
    );
  }
}

class _RiderRow extends StatelessWidget {
  const _RiderRow({
    required this.name,
    required this.detail,
    this.tag,
    required this.tagColor,
  });

  final String name;
  final String detail;
  final String? tag;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (tag != null) SellerPill(label: tag!, color: tagColor),
        ],
      ),
    );
  }
}

class _PackingSlipSheet extends StatelessWidget {
  const _PackingSlipSheet({required this.slip, required this.onDownloadLabel});

  final SellerPackingSlip slip;
  final VoidCallback onDownloadLabel;

  static const _checkW = 34.0;
  static const _unitW = 60.0;
  static const _qtyW = 38.0;
  static const _totalW = 78.0;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'PACKING SLIP',
      subtitle: 'Order #${slip.orderNumber}',
      children: [
        Text(
          'On-screen preview\nUse "Shipping Label (PDF)" to print the actual barcode label',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onDownloadLabel,
            icon: const Icon(Icons.qr_code_2_rounded, size: 16),
            label: const Text('Shipping Label (PDF)'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, c) {
            final parties = [
              _party(
                'Merchant / Store',
                slip.sellerName,
                slip.sellerAddress ?? 'Verified Merchant Store',
                slip.sellerPhone,
              ),
              _party(
                'Ship / Handover To',
                slip.customerName,
                slip.customerAddress,
                slip.customerPhone,
              ),
            ];
            if (c.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [parties[0], const SizedBox(height: 12), parties[1]],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: parties[0]),
                const SizedBox(width: 14),
                Expanded(child: parties[1]),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _table(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Payment: ${slip.paymentMethod.isEmpty ? '—' : slip.paymentMethod}'
          '${slip.paymentStatus.isEmpty ? '' : ' (${slip.paymentStatus})'}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'GRAND TOTAL',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRupees(slip.totalAmount),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _party(String label, String? name, String? address, String? phone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name ?? '—',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (address != null && address.isNotEmpty)
          Text(
            address,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
        if (phone != null && phone.isNotEmpty)
          Text(
            'Tel: $phone',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
      ],
    );
  }

  /// CHECK | PRODUCT / SKU (flexible) | UNIT / PACK | QUANTITY | TOTAL PRICE.
  /// Only the Product / SKU column flexes; the others have fixed compact widths
  /// so long product names wrap instead of overflowing.
  Widget _table() {
    final head = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      color: AppColors.textSecondary,
    );
    Widget headCell(
      String t, {
      double? width,
      TextAlign align = TextAlign.left,
    }) {
      final w = Text(t, textAlign: align, style: head);
      return width == null
          ? Expanded(child: w)
          : SizedBox(width: width, child: w);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceMuted,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                headCell('CHECK', width: _checkW, align: TextAlign.center),
                headCell('PRODUCT / SKU'),
                headCell('UNIT / PACK', width: _unitW),
                headCell('QTY', width: _qtyW, align: TextAlign.center),
                headCell('TOTAL PRICE', width: _totalW, align: TextAlign.right),
              ],
            ),
          ),
          if (slip.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
              child: Center(
                child: Text(
                  'No items available',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            )
          else
            for (var i = 0; i < slip.items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.border),
              _row(slip.items[i]),
            ],
        ],
      ),
    );
  }

  Widget _row(SellerPackingSlipItem item) {
    final unit = (item.unitOrPack ?? '').isEmpty ? '—' : item.unitOrPack!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _checkW,
            child: Center(
              child: Icon(
                Icons.check_box_outline_blank_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'SKU: ${item.sku.isEmpty ? '—' : item.sku}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _unitW,
            child: Text(
              unit,
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(
            width: _qtyW,
            child: Text(
              formatQuantity(item.orderedQty),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: _totalW,
            child: Text(
              formatRupees(item.lineTotal),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
