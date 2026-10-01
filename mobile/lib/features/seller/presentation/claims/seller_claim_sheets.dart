import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/seller_hub_repository.dart';
import '../../domain/seller_hub_models.dart';
import '../widgets/seller_hub_widgets.dart';

/// Claim status badge (labels match the Web `renderStatusBadge`).
class SellerClaimStatusBadge extends StatelessWidget {
  const SellerClaimStatusBadge(this.status, {super.key});

  final String status;

  static const _styles = <String, (String, Color)>{
    'OPEN': ('Open', Color(0xFF2563EB)),
    'SELLER_RESPONSE_REQUIRED': ('Response Required', Color(0xFFD97706)),
    'UNDER_REVIEW': ('Under Review', Color(0xFF4F46E5)),
    'ESCALATED': ('Escalated to Admin', Color(0xFFE11D48)),
    'APPROVED': ('Approved', Color(0xFF059669)),
    'REJECTED': ('Rejected', Color(0xFFDC2626)),
    'SETTLED': ('Settled', Color(0xFF0D9488)),
    'CLOSED': ('Closed', Color(0xFF475569)),
  };

  static Color typeColor(String type) => switch (type) {
    'DAMAGED_ITEM' => const Color(0xFFEA580C),
    'MISSING_ITEM' => const Color(0xFFE11D48),
    'WRONG_ITEM' => const Color(0xFF7C3AED),
    'QUALITY_ISSUE' => const Color(0xFFD97706),
    'DELIVERY_DAMAGE' => const Color(0xFFDC2626),
    'SELLER_DISPUTE' => const Color(0xFF2563EB),
    'SETTLEMENT_DISPUTE' => const Color(0xFF0D9488),
    _ => const Color(0xFF475569),
  };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _styles[status] ?? (status, const Color(0xFF64748B));
    return SellerPill(label: label, color: color);
  }
}

List<String> _splitUrls(String raw) => raw
    .split(RegExp(r'[\n,]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
    ),
  );
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
                Expanded(child: header),
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
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Claim detail & action drawer (Web: Claims page drawer).
class SellerClaimDetailSheet extends ConsumerStatefulWidget {
  const SellerClaimDetailSheet({
    super.key,
    required this.claimId,
    required this.onChanged,
  });

  final int claimId;
  final VoidCallback onChanged;

  static Future<void> show(
    BuildContext context, {
    required int claimId,
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
          SellerClaimDetailSheet(claimId: claimId, onChanged: onChanged),
    );
  }

  @override
  ConsumerState<SellerClaimDetailSheet> createState() =>
      _SellerClaimDetailSheetState();
}

class _SellerClaimDetailSheetState
    extends ConsumerState<SellerClaimDetailSheet> {
  SellerHubClaim? _claim;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  final _response = TextEditingController();
  final _responseEvidence = TextEditingController();
  final _adminReason = TextEditingController();
  String _adminDecision = 'APPROVE';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _response.dispose();
    _responseEvidence.dispose();
    _adminReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final claim = await ref
          .read(sellerHubRepositoryProvider)
          .getClaimDetail(widget.claimId);
      if (!mounted) return;
      setState(() {
        _claim = claim;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SellerHubException
            ? e.message
            : 'Error loading claim details';
      });
    }
  }

  Future<void> _act(
    Future<SellerHubClaim?> Function(SellerHubRepository repo) action,
    String success,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await action(ref.read(sellerHubRepositoryProvider));
      widget.onChanged();
      if (!mounted) return;
      _snack(context, success);
      if (updated != null) {
        setState(() => _claim = updated);
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted)
        _snack(
          context,
          e is SellerHubException ? e.message : 'Action failed.',
          error: true,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final claim = _claim;
    final isSuperAdmin =
        ref.watch(authControllerProvider).user?.isSuperAdmin == true;
    return _SheetScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${claim?.claimNumber ?? 'Loading...'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (claim != null) SellerClaimStatusBadge(claim.status),
            ],
          ),
          if (claim != null)
            Text(
              'Filed on ${formatSellerTimestamp(claim.createdAt)}',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
        ],
      ),
      children: [
        if (_loading && claim == null)
          const SellerLoading(message: 'Loading claim details...')
        else if (_error != null && claim == null)
          SellerStateMessage(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFDC2626),
            title: 'Unable to load claim',
            message: _error!,
            actionLabel: 'Retry',
            onAction: _load,
          )
        else if (claim != null)
          ..._body(claim, isSuperAdmin),
      ],
    );
  }

  List<Widget> _body(SellerHubClaim claim, bool isSuperAdmin) {
    return [
      SellerPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Claim Type  ',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                Flexible(
                  child: SellerPill(
                    label: claim.typeLabel,
                    color: SellerClaimStatusBadge.typeColor(claim.claimType),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SellerKeyValue(
              'Claimed',
              claim.claimedAmount > 0
                  ? '₹${claim.claimedAmount.toStringAsFixed(2)}'
                  : 'Not Specified',
            ),
            SellerKeyValue('Company', claim.companyName ?? 'Own Store'),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Linked Operational Records',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SellerKeyValue(
              'Order',
              claim.orderNumber == null ? 'None' : '#${claim.orderNumber}',
            ),
            SellerKeyValue(
              'Return',
              claim.returnNumber == null ? 'None' : '#${claim.returnNumber}',
            ),
            if (claim.customerName != null)
              SellerKeyValue(
                'Customer',
                '${claim.customerName}${claim.customerPhone != null ? ' (${claim.customerPhone})' : ''}',
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Claim Description',
        child: Text(
          claim.description,
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
      ),
      const SizedBox(height: 10),
      SellerPanel(
        title: 'Evidence & Attachments',
        child: claim.evidenceUrls.isEmpty
            ? Text(
                'No file attachments or photos submitted.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < claim.evidenceUrls.length; i++)
                    OutlinedButton.icon(
                      onPressed: () {
                        final url =
                            AppConfig.resolveMediaUrl(claim.evidenceUrls[i]) ??
                            claim.evidenceUrls[i];
                        launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.attach_file_rounded, size: 15),
                      label: Text('Evidence #${i + 1}'),
                    ),
                ],
              ),
      ),
      const SizedBox(height: 10),
      if (claim.sellerResponse != null)
        SellerPanel(
          tint: const Color(0xFF2563EB),
          title: 'Seller Statement / Response',
          subtitle:
              'Responded by ${claim.sellerRespondedByName ?? 'Seller'} on '
              '${claim.sellerRespondedAt == null ? '—' : formatSellerTimestamp(claim.sellerRespondedAt)}',
          child: Text(
            claim.sellerResponse!,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        )
      else if (claim.canRespond)
        SellerPanel(
          tint: const Color(0xFFD97706),
          title: claim.status == 'SELLER_RESPONSE_REQUIRED'
              ? 'Submit Seller Response · Action Required'
              : 'Submit Seller Response',
          subtitle: 'Provide your operational explanation, warehouse packing proof, or courier handover confirmation.',
          child: Column(
            children: [
              TextField(
                controller: _response,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Type your response narrative here...',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _responseEvidence,
                decoration: const InputDecoration(
                  hintText: 'Optional new evidence URLs (separated by comma or newline)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || _response.text.trim().isEmpty
                      ? null
                      : () => _act(
                          (repo) => repo.respondToClaim(
                            claim.id,
                            _response.text,
                            evidenceUrls: _splitUrls(_responseEvidence.text),
                          ),
                          'Response submitted successfully.',
                        ),
                  child: Text(_busy ? 'Submitting...' : 'Submit Statement'),
                ),
              ),
            ],
          ),
        ),
      if (claim.hasAdminDecision) ...[
        const SizedBox(height: 10),
        SellerPanel(
          tint: const Color(0xFF4F46E5),
          title: 'Platform Admin Decision (${claim.adminDecision})',
          subtitle:
              'Arbitrated by ${claim.adminDecidedByName ?? 'Admin'} on '
              '${claim.adminDecidedAt == null ? '—' : formatSellerTimestamp(claim.adminDecidedAt)}',
          child: Text(
            claim.adminDecisionReason ??
                'Decision applied without extra notes.',
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ],
      if (isSuperAdmin && !claim.isFinal) ...[
        const SizedBox(height: 10),
        SellerPanel(
          tint: const Color(0xFF0F172A),
          title: 'Platform Admin Arbitration Decision',
          subtitle: 'Select decision outcome. A mandatory documented rationale is required.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (id, label) in const [
                    ('APPROVE', 'Approve Claim'),
                    ('REJECT', 'Reject Claim'),
                    ('REQUEST_SELLER_RESPONSE', 'Req. Response'),
                    ('SETTLE', 'Mark Settled'),
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _adminDecision == id,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _adminDecision = id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adminReason,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Enter mandatory arbitration decision rationale...',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || _adminReason.text.trim().isEmpty
                      ? null
                      : () => _act(
                          (repo) => repo.decideClaim(
                            claim.id,
                            _adminDecision,
                            _adminReason.text,
                          ),
                          "Admin decision '$_adminDecision' recorded successfully.",
                        ),
                  child: Text(
                    _busy ? 'Recording Decision...' : 'Apply Admin Decision',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 10),
      Row(
        children: [
          if (claim.canEscalate)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!await _confirm(
                          'Are you sure you want to escalate this claim to the Platform Admin for arbitration?',
                        )) {
                          return;
                        }
                        await _act(
                          (repo) => repo.escalateClaim(claim.id),
                          'Claim successfully escalated to Platform Admin.',
                        );
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE11D48),
                ),
                icon: const Icon(Icons.gavel_rounded, size: 16),
                label: const Text('Escalate to Admin'),
              ),
            ),
          if (claim.canEscalate && claim.canClose) const SizedBox(width: 8),
          if (claim.canClose)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!await _confirm(
                          'Are you sure you want to close and archive this claim?',
                        ))
                          return;
                        await _act(
                          (repo) => repo.closeClaim(claim.id),
                          'Claim marked as closed.',
                        );
                      },
                icon: const Icon(Icons.archive_outlined, size: 16),
                label: const Text('Close Claim'),
              ),
            ),
        ],
      ),
      const SellerSectionLabel('Immutable Audit History'),
      if (claim.auditLogs.isEmpty)
        Text(
          'No prior audit records.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        )
      else
        for (final log in claim.auditLogs)
          SellerAuditRow(
            title: log.action,
            subtitle: [
              if (log.fromStatus != null || log.toStatus != null)
                'Status: ${log.fromStatus ?? 'INITIAL'} ➔ ${log.toStatus ?? '-'}',
              'Actor: ${log.actorName ?? 'System'}',
            ].join(' · '),
            note: log.notes == null ? null : '"${log.notes}"',
            timestamp: formatSellerTimestamp(log.createdAt),
          ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }
}

/// "File Operational Claim / Dispute" form (Web create modal).
class SellerCreateClaimSheet extends ConsumerStatefulWidget {
  const SellerCreateClaimSheet({super.key});

  /// Returns true when a claim was created.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => const SellerCreateClaimSheet(),
    );
  }

  @override
  ConsumerState<SellerCreateClaimSheet> createState() =>
      _SellerCreateClaimSheetState();
}

class _SellerCreateClaimSheetState
    extends ConsumerState<SellerCreateClaimSheet> {
  String _type = 'DAMAGED_ITEM';
  final _orderId = TextEditingController();
  final _returnId = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _evidence = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_orderId, _returnId, _amount, _description, _evidence]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_description.text.trim().isEmpty) {
      _snack(context, 'Description is required.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final number = await ref
          .read(sellerHubRepositoryProvider)
          .createClaim(
            claimType: _type,
            description: _description.text,
            orderId: int.tryParse(_orderId.text.trim()),
            returnId: int.tryParse(_returnId.text.trim()),
            claimedAmount: double.tryParse(_amount.text.trim()) ?? 0,
            evidenceUrls: _splitUrls(_evidence.text),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Claim #${number ?? ''} created successfully.'),
          backgroundColor: AppColors.emerald,
        ),
      );
    } catch (e) {
      if (mounted)
        _snack(
          context,
          e is SellerHubException ? e.message : 'Failed to create claim',
          error: true,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'File Operational Claim / Dispute',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          Text(
            'Record in-transit damage or order delivery loss',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Claim Type',
            isDense: true,
          ),
          items: [
            for (final (v, l) in sellerClaimTypes)
              DropdownMenuItem(value: v, child: Text(l)),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _orderId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Related Order ID (Optional)',
                  hintText: 'e.g. 101',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _returnId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Related Return ID (Optional)',
                  hintText: 'e.g. 5',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Claim Valuation / Amount (₹)',
            hintText: '0.00',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _description,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Detailed Incident Description *',
            hintText: 'Describe the defect, transit damage, or reason for claim dispute...',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _evidence,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Evidence URLs (Photos/Docs)',
            hintText: 'Paste URL references (one per line)...',
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || _description.text.trim().isEmpty
                ? null
                : _submit,
            child: Text(_busy ? 'Creating Claim...' : 'Submit Claim'),
          ),
        ),
      ],
    );
  }
}
