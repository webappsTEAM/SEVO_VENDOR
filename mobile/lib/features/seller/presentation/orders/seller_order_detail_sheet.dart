import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';
import 'seller_order_actions.dart';

/// Order detail & fulfilment checklist (Web: the Orders page detail drawer).
class SellerOrderDetailSheet extends ConsumerStatefulWidget {
  const SellerOrderDetailSheet({
    super.key,
    required this.orderId,
    required this.onOrderChanged,
  });

  final int orderId;

  /// Notifies the list screen so it refreshes the list and metrics.
  final VoidCallback onOrderChanged;

  static Future<void> show(
    BuildContext context, {
    required int orderId,
    required VoidCallback onOrderChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => SellerOrderDetailSheet(
        orderId: orderId,
        onOrderChanged: onOrderChanged,
      ),
    );
  }

  @override
  ConsumerState<SellerOrderDetailSheet> createState() =>
      _SellerOrderDetailSheetState();
}

class _SellerOrderDetailSheetState
    extends ConsumerState<SellerOrderDetailSheet> {
  SellerHubOrder? _order;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  final Set<int> _pickingItemIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(sellerHubRepositoryProvider)
          .getOrderDetail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SellerHubException
            ? e.message
            : 'Failed to load order details.';
        _loading = false;
      });
    }
  }

  SellerOrderActions get _actions => SellerOrderActions(
    context: context,
    ref: ref,
    onChanged: (updated) {
      widget.onOrderChanged();
      if (!mounted) return;
      if (updated != null && updated.items.isNotEmpty) {
        setState(() => _order = updated);
      } else {
        _load();
      }
    },
  );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePicked(
    SellerHubOrder order,
    SellerHubOrderItem item,
  ) async {
    if (_pickingItemIds.contains(item.id)) return;
    setState(() => _pickingItemIds.add(item.id));
    try {
      final server = await ref
          .read(sellerHubRepositoryProvider)
          .setItemPicked(
            order.id,
            item.id,
            isPicked: !item.isPicked,
            fulfilledQuantity: item.orderedQuantity,
          );
      if (!mounted) return;
      final isPicked = server.containsKey('is_picked')
          ? server['is_picked'] == true
          : !item.isPicked;
      final isPacked = server.containsKey('is_packed')
          ? server['is_packed'] == true
          : item.isPacked;
      setState(() {
        _order = order.copyWithItems([
          for (final it in order.items)
            it.id == item.id
                ? it.copyWithPick(isPicked: isPicked, isPacked: isPacked)
                : it,
        ]);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SellerHubException
                  ? e.message
                  : 'Failed to update picking status.',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingItemIds.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final isSuperAdmin =
        ref.watch(authControllerProvider).user?.isSuperAdmin == true;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Column(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order?.orderNumber ?? 'Loading Order...',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (order?.sourceOrderId != null)
                        Text(
                          'Marketplace Reference: ${order!.sourceOrderId}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (order != null) SellerOrderStatusBadge(order.status),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (_loading && order == null)
                  const SellerLoading(
                    message: 'Fetching order details & item checklist...',
                  )
                else if (_error != null && order == null)
                  SellerStateMessage(
                    icon: Icons.error_outline_rounded,
                    color: const Color(0xFFDC2626),
                    title: 'Unable to load order',
                    message: _error!,
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                else if (order != null)
                  ..._buildBody(order, isSuperAdmin),
              ],
            ),
          ),
          if (order != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => _actions.downloadShippingLabel(order),
                              ),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                        label: const Text('Shipping Label (PDF)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () =>
                                _run(() => _actions.previewPackingSlip(order)),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text('Preview'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(SellerHubOrder order, bool isSuperAdmin) {
    final primary = primaryOrderAction(order.status);
    return [
      SellerPanel(
        title: 'Customer & Delivery',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.customerName,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (order.customerPhone != null)
              Text(order.customerPhone!, style: const TextStyle(fontSize: 12)),
            if (order.deliveryAddress != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  order.deliveryAddress!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Fulfilment Info',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SellerKeyValue('Type', order.fulfillmentLabel),
            if (order.deliverySlot != null)
              SellerKeyValue('Slot', order.deliverySlot!),
            SellerKeyValue(
              'Total',
              '${formatRupees(order.totalAmount)} (${order.paymentStatus})',
            ),
          ],
        ),
      ),
      SellerSectionLabel('Item Picking Checklist (${order.items.length})'),
      Text(
        'Tap the checkbox to update picking status',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      const SizedBox(height: 8),
      for (final item in order.items) _itemRow(order, item),
      if (order.inRiderPhase) ...[
        const SizedBox(height: 6),
        _riderPanel(order),
      ],
      const SellerSectionLabel('Advance Fulfilment State'),
      if (primary != null)
        _WideButton(
          label: primary.$3,
          color: AppColors.primary,
          icon: primary.$1 == 'mark_ready'
              ? Icons.local_shipping_rounded
              : Icons.arrow_forward_rounded,
          onPressed: _busy
              ? null
              : () => _run(() => _actions.transition(order, primary.$1)),
        ),
      if (order.inRiderPhase && order.dispatchJobId != null)
        _WideButton(
          label: 'Live Track Rider',
          color: const Color(0xFF0284C7),
          icon: Icons.navigation_rounded,
          onPressed: () => _actions.trackRider(order),
        ),
      if (!order.isTerminal)
        _WideButton(
          label: 'Cancel Order',
          color: const Color(0xFFDC2626),
          outlined: true,
          icon: Icons.block_rounded,
          onPressed: _busy ? null : () => _run(() => _actions.cancel(order)),
        ),
      if (primary == null && order.isTerminal)
        Text(
          'No further fulfilment actions for this order.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      if (isSuperAdmin && !order.isTerminal && order.inRiderPhase) ...[
        const SizedBox(height: 10),
        SellerPanel(
          tint: const Color(0xFFDC2626),
          title: 'Platform Admin Manual Override',
          subtitle:
              'Emergency bypass for stuck orders (rider device died, OTP delivery failure, unreachable '
              'customer). Reason is required and logged in immutable audit history.',
          child: Column(
            children: [
              if (order.awaitingRider)
                _WideButton(
                  label: 'Override: Force Handover',
                  color: const Color(0xFFDC2626),
                  outlined: true,
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _actions.adminOverride(
                            order,
                            'admin_override_handover',
                          ),
                        ),
                ),
              _WideButton(
                label: 'Override: Force Deliver',
                color: const Color(0xFFDC2626),
                outlined: true,
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _actions.adminOverride(
                          order,
                          'admin_override_deliver',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
      const SellerSectionLabel('Fulfilment Audit History'),
      if (order.auditLogs.isEmpty)
        Text(
          'No history logs recorded yet.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        )
      else
        for (final log in order.auditLogs)
          SellerAuditRow(
            title: log.action,
            subtitle:
                'Actor: ${log.actorName ?? 'System'} | From: ${log.fromStatus ?? 'NEW'} → To: ${log.toStatus ?? '-'}',
            note: log.notes == null ? null : 'Note: "${log.notes}"',
            timestamp: formatSellerTimestamp(log.createdAt),
          ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  Widget _itemRow(SellerHubOrder order, SellerHubOrderItem item) {
    final busy = _pickingItemIds.contains(item.id);
    final meta = [
      if (item.sku.isNotEmpty) item.sku,
      if (item.packSize != null || item.unit != null)
        item.packSize ?? item.unit!,
      if (item.availableStock != null)
        'Avail: ${formatQuantity(item.availableStock!)} in stock',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: item.isPicked ? AppColors.successBg : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isPicked ? AppColors.successBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Mark as Picked',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      item.isPicked
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: item.isPicked
                          ? AppColors.emerald
                          : AppColors.textMuted,
                    ),
                    onPressed: () => _togglePicked(order, item),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productTitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'x ${formatQuantity(item.orderedQuantity)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                formatRupees(item.lineTotal),
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _riderPanel(SellerHubOrder order) {
    final assigned = order.handlingTechnicianName != null;
    return SellerPanel(
      tint: const Color(0xFF0891B2),
      title: assigned
          ? 'Assigned Rider: ${order.handlingTechnicianName}'
          : '2-Wheeler Rider Dispatch',
      subtitle: order.handlingTechnicianPhone != null
          ? 'Contact: ${order.handlingTechnicianPhone}'
          : 'Dispatching to nearest available 2-wheeler rider',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!assigned) ...[
                OutlinedButton.icon(
                  onPressed: () => _actions.showRiders(order),
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  label: const Text('Riders Status'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _actions.retryDispatch(order)),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry Dispatch'),
                ),
              ],
              if (order.dispatchJobId != null)
                OutlinedButton.icon(
                  onPressed: () => _actions.trackRider(order),
                  icon: const Icon(Icons.navigation_rounded, size: 16),
                  label: const Text('Track'),
                ),
            ],
          ),
          if (order.pickupOtp != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Pickup Verification OTP: ',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                  order.pickupOtp!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            Text(
              'Share with Rider at Handover',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: outlined
            ? OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                ),
                child: child,
              )
            : FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(backgroundColor: color),
                child: child,
              ),
      ),
    );
  }
}
