import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Return status badge (labels match the Web `getStatusBadge`).
class SellerReturnStatusBadge extends StatelessWidget {
  const SellerReturnStatusBadge(this.status, {super.key});

  final String status;

  static const _styles = <String, (String, Color)>{
    'REQUESTED': ('Requested', Color(0xFFD97706)),
    'UNDER_SELLER_REVIEW': ('Under Review', Color(0xFF2563EB)),
    'APPROVED': ('Approved', Color(0xFF4F46E5)),
    'PICKUP_SCHEDULED': ('Pickup Scheduled', Color(0xFF7C3AED)),
    'RECEIVED': ('Received at Store', Color(0xFF0891B2)),
    'QUALITY_CHECK': ('Quality Check', Color(0xFFCA8A04)),
    'RESTOCKED': ('Restocked', Color(0xFF059669)),
    'CLOSED': ('Closed', Color(0xFF475569)),
    'REJECTED': ('Rejected', Color(0xFFDC2626)),
    'DISCARDED': ('Scrapped', Color(0xFFEA580C)),
    'ESCALATED_TO_ADMIN': ('Escalated', Color(0xFFE11D48)),
  };

  static String labelFor(String status) => _styles[status]?.$1 ?? status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _styles[status] ?? (status, const Color(0xFF64748B));
    return SellerPill(label: label, color: color);
  }
}

/// Return case management sheet (Web: the Returns page drawer), driving the
/// backend state machine: review → pickup → receive → QC → restock → close.
class SellerReturnDetailSheet extends ConsumerStatefulWidget {
  const SellerReturnDetailSheet({
    super.key,
    required this.returnId,
    required this.onChanged,
  });

  final int returnId;
  final VoidCallback onChanged;

  static Future<void> show(
    BuildContext context, {
    required int returnId,
    required VoidCallback onChanged,
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
      builder: (_) =>
          SellerReturnDetailSheet(returnId: returnId, onChanged: onChanged),
    );
  }

  @override
  ConsumerState<SellerReturnDetailSheet> createState() =>
      _SellerReturnDetailSheetState();
}

class _SellerReturnDetailSheetState
    extends ConsumerState<SellerReturnDetailSheet> {
  SellerHubReturn? _ret;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  // Form state (defaults match the Web forms).
  String _decision = 'approve';
  final _sellerNotes = TextEditingController();
  final _rejectionReason = TextEditingController();
  final _pickupRef = TextEditingController();
  String _qcStatus = 'PASSED';
  final _qcNotes = TextEditingController();
  String _restockDecision = 'FULL_RESTOCK';
  final _restockNotes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _sellerNotes,
      _rejectionReason,
      _pickupRef,
      _qcNotes,
      _restockNotes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ret = await ref
          .read(sellerHubRepositoryProvider)
          .getReturnDetail(widget.returnId);
      if (!mounted) return;
      setState(() {
        _ret = ret;
        _loading = false;
        _qcStatus = ret.qualityCheckStatus ?? 'PASSED';
        if (!const ['PASSED', 'FAILED', 'PARTIAL_PASS'].contains(_qcStatus))
          _qcStatus = 'PASSED';
        _qcNotes.text = ret.qualityCheckNotes ?? '';
        _restockDecision = ret.restockDecision ?? 'FULL_RESTOCK';
        if (!const [
          'FULL_RESTOCK',
          'PARTIAL_RESTOCK',
          'SCRAP_DISPOSE',
        ].contains(_restockDecision)) {
          _restockDecision = 'FULL_RESTOCK';
        }
        _restockNotes.text = ret.restockNotes ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SellerHubException
            ? e.message
            : 'Failed to load return case.';
        _loading = false;
      });
    }
  }

  Future<void> _submit(
    Future<void> Function(SellerHubRepository repo) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(sellerHubRepositoryProvider));
      widget.onChanged();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SellerHubException
                  ? e.message
                  : 'Action failed. Please try again.',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRestock(SellerHubReturn ret) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Confirm Restock',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Are you sure you want to restock these items? Verified quantities will be atomically added back to '
          'your active store inventory ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restock'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _submit(
      (repo) => repo.restockReturn(
        ret,
        decision: _restockDecision,
        notes: _restockNotes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ret = _ret;
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
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            ret?.returnNumber ?? 'Return #${widget.returnId}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (ret != null) SellerReturnStatusBadge(ret.status),
                        ],
                      ),
                      if (ret != null)
                        Text(
                          'Order Ref: #${ret.orderNumber ?? 'N/A'}'
                          '${ret.sourceReturnId != null ? ' · Source Ref: ${ret.sourceReturnId}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
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
                if (_loading && ret == null)
                  const SellerLoading(message: 'Loading return dossier...')
                else if (_error != null && ret == null)
                  SellerStateMessage(
                    icon: Icons.error_outline_rounded,
                    color: const Color(0xFFDC2626),
                    title: 'Unable to load return case',
                    message: _error!,
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                else if (ret != null)
                  ..._buildBody(ret),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(SellerHubReturn ret) {
    return [
      SellerPanel(
        title: 'Customer Information',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SellerKeyValue('Name', ret.customerName ?? 'N/A'),
            SellerKeyValue('Phone', ret.customerPhone ?? 'N/A'),
            if (ret.createdAt != null)
              SellerKeyValue('Opened', formatSellerTimestamp(ret.createdAt)),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Reason for Return',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ret.reason,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (ret.customerNotes != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '"${ret.customerNotes}"',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (ret.evidenceUrls.isNotEmpty) ...[
        const SellerSectionLabel('Submitted Evidence'),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ret.evidenceUrls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final url =
                  AppConfig.resolveMediaUrl(ret.evidenceUrls[i]) ??
                  ret.evidenceUrls[i];
              return InkWell(
                onTap: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 84,
                      height: 84,
                      color: AppColors.surfaceMuted,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
      SellerSectionLabel('Returned Items (${ret.items.length})'),
      if (ret.items.isEmpty)
        Text(
          'No line items recorded for this return.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      for (final it in ret.items)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it.productTitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'SKU: ${it.sku} · Qty Returned: ${formatQuantity(it.returnedQuantity)}',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (it.itemCondition != null)
                    SellerPill(
                      label: 'Condition: ${it.itemCondition}',
                      color: const Color(0xFF64748B),
                    ),
                  if (it.restockedQuantity > 0)
                    SellerPill(
                      label:
                          '+${formatQuantity(it.restockedQuantity)} Restocked',
                      color: AppColors.emerald,
                    ),
                  if (it.scrappedQuantity > 0)
                    SellerPill(
                      label: '${formatQuantity(it.scrappedQuantity)} Scrapped',
                      color: const Color(0xFFEA580C),
                    ),
                ],
              ),
            ],
          ),
        ),
      const SizedBox(height: 6),
      ..._workflowPanels(ret),
      const SellerSectionLabel('Audit Trail & State History'),
      if (ret.auditLogs.isEmpty)
        Text(
          'No history logs recorded yet.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        )
      else
        for (final log in ret.auditLogs)
          SellerAuditRow(
            title: log.action,
            note: log.notes,
            subtitle: 'By ${log.actorName ?? 'System'}',
            timestamp: formatSellerTimestamp(log.createdAt),
          ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  List<Widget> _workflowPanels(SellerHubReturn ret) {
    const blue = Color(0xFF2563EB);
    const purple = Color(0xFF7C3AED);
    const cyan = Color(0xFF0891B2);
    const yellow = Color(0xFFCA8A04);
    const slate = Color(0xFF475569);

    final panels = <Widget>[];

    if (ret.needsReview) {
      panels.add(
        SellerPanel(
          tint: blue,
          title: 'Step 1: Seller Review Decision',
          subtitle: 'Review customer claim. Approve to schedule return pickup, or reject with a documented rationale.',
          child: Column(
            children: [
              _Dropdown(
                label: 'Decision',
                value: _decision,
                options: const [
                  ('approve', 'Approve Return (Accept Item Return)'),
                  ('reject', 'Reject Return'),
                  ('escalate', 'Escalate to Platform Admin'),
                ],
                onChanged: (v) => setState(() => _decision = v),
              ),
              if (_decision == 'reject')
                _Field(
                  controller: _rejectionReason,
                  label: 'Rejection Reason *',
                  hint: 'e.g. Return window expired, non-returnable grocery category',
                  onChanged: (_) => setState(() {}),
                ),
              _Field(
                controller: _sellerNotes,
                label: 'Seller Notes (Optional)',
                hint: 'Internal instructions or notes...',
                maxLines: 2,
              ),
              _SubmitButton(
                label: _busy
                    ? 'Recording Decision...'
                    : 'Confirm Review Decision',
                color: blue,
                onPressed:
                    _busy ||
                        (_decision == 'reject' &&
                            _rejectionReason.text.trim().isEmpty)
                    ? null
                    : () => _submit(
                        (repo) => repo.reviewReturn(
                          ret.id,
                          decision: _decision,
                          sellerNotes: _sellerNotes.text.trim(),
                          rejectionReason: _rejectionReason.text.trim(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    if (ret.canSchedulePickup) {
      panels.add(
        SellerPanel(
          tint: purple,
          title: 'Step 2: Reverse Pickup / Courier Dispatch',
          subtitle: 'Record pickup reference or courier tracking number.',
          child: Column(
            children: [
              _Field(
                controller: _pickupRef,
                label: 'Pickup Tracking / Ref #',
                hint: 'e.g. SEVO-RIDER-PICKUP-8902',
              ),
              _SubmitButton(
                label: _busy ? 'Scheduling...' : 'Mark Pickup Scheduled',
                color: purple,
                onPressed: _busy
                    ? null
                    : () => _submit(
                        (repo) => repo.scheduleReturnPickup(
                          ret.id,
                          pickupRef: _pickupRef.text.trim(),
                        ),
                      ),
              ),
              _SubmitButton(
                label: 'Mark Received Directly',
                color: purple,
                outlined: true,
                onPressed: _busy
                    ? null
                    : () => _submit((repo) => repo.receiveReturn(ret.id)),
              ),
            ],
          ),
        ),
      );
    }

    if (ret.awaitingReceipt) {
      panels.add(
        SellerPanel(
          tint: cyan,
          title: 'Step 3: Parcel Arrival at Store',
          subtitle: 'Acknowledge physical receipt of the returned item package at your store warehouse.',
          child: _SubmitButton(
            label: _busy ? 'Updating...' : 'Acknowledge Package Received',
            color: cyan,
            onPressed: _busy
                ? null
                : () => _submit((repo) => repo.receiveReturn(ret.id)),
          ),
        ),
      );
    }

    if (ret.canInspectOrRestock) {
      panels.add(
        SellerPanel(
          tint: yellow,
          title: 'Step 4: Quality Inspection (QC)',
          subtitle: 'Perform physical check on seal integrity, expiry date, and condition.',
          child: Column(
            children: [
              _Dropdown(
                label: 'Overall QC Result',
                value: _qcStatus,
                options: const [
                  ('PASSED', 'Passed (Fit for Restock)'),
                  ('FAILED', 'Failed (Damaged / Unusable / Expired)'),
                  ('PARTIAL_PASS', 'Partial Pass'),
                ],
                onChanged: (v) => setState(() => _qcStatus = v),
              ),
              _Field(
                controller: _qcNotes,
                label: 'QC Notes',
                hint: 'e.g. Seal intact, expiry in 6 months, original packaging verified',
              ),
              _SubmitButton(
                label: _busy
                    ? 'Saving Inspection...'
                    : 'Save Quality Inspection Result',
                color: yellow,
                onPressed: _busy
                    ? null
                    : () => _submit(
                        (repo) => repo.submitReturnQualityCheck(
                          ret,
                          status: _qcStatus,
                          notes: _qcNotes.text.trim(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
      panels.add(
        SellerPanel(
          tint: AppColors.emerald,
          title: 'Step 5: Restocking & Inventory Ledger Update',
          subtitle: 'Put fit goods back into active stock. Immutable STOCK_IN movements will be recorded.',
          child: Column(
            children: [
              _Dropdown(
                label: 'Restock Mode',
                value: _restockDecision,
                options: const [
                  ('FULL_RESTOCK', 'Full Restock (All Returned Units)'),
                  ('PARTIAL_RESTOCK', 'Partial Restock'),
                  ('SCRAP_DISPOSE', 'Scrap / Dispose All (0 Units Restocked)'),
                ],
                onChanged: (v) => setState(() => _restockDecision = v),
              ),
              _Field(
                controller: _restockNotes,
                label: 'Restock Notes',
                hint: 'e.g. Restocked shelf A-04',
              ),
              _SubmitButton(
                label: _busy
                    ? 'Updating Inventory Ledger...'
                    : 'Execute Restock & Balance Update',
                color: AppColors.emerald,
                onPressed: _busy ? null : () => _confirmRestock(ret),
              ),
            ],
          ),
        ),
      );
    }

    if (ret.canClose) {
      panels.add(
        SellerPanel(
          tint: slate,
          title: 'Final Step: Close Return Case',
          subtitle: 'Mark this return case as fully resolved and closed.',
          child: _SubmitButton(
            label: _busy ? 'Closing...' : 'Close Return Case',
            color: slate,
            onPressed: _busy
                ? null
                : () => _submit((repo) => repo.closeReturn(ret.id)),
          ),
        ),
      );
    }

    return [
      for (final p in panels) ...[p, const SizedBox(height: 10)],
    ];
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        // Keyed on the value so a reloaded case re-seeds the field.
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        items: [
          for (final (v, l) in options)
            DropdownMenuItem(value: v, child: Text(l)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: outlined
            ? OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                ),
                child: text,
              )
            : FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(backgroundColor: color),
                child: text,
              ),
      ),
    );
  }
}
