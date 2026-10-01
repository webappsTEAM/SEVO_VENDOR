import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';
import '../../../../shared/widgets/sevo/sevo_module_scaffold.dart';
import '../../../../shared/widgets/sevo/sevo_skeleton.dart';
import '../../../../shared/widgets/sevo/sevo_state_views.dart';
import '../../../../shared/widgets/sevo/sevo_typography.dart';
import '../../data/seller_applications_repository.dart';
import '../../domain/seller_application.dart';
import 'seller_applications_screen.dart' show sellerStatusTone;

/// Web `AdminSellerApplicationDetailPage` — one merchant's compliance dossier
/// with Overview / Documents / Categories tabs and the review actions.
class SellerApplicationDetailScreen extends ConsumerStatefulWidget {
  const SellerApplicationDetailScreen({super.key, required this.applicationId});

  final int applicationId;

  @override
  ConsumerState<SellerApplicationDetailScreen> createState() =>
      _SellerApplicationDetailScreenState();
}

class _SellerApplicationDetailScreenState
    extends ConsumerState<SellerApplicationDetailScreen> {
  SellerApplication? _seller;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  int _seq = 0;

  SellerApplicationsRepository get _repo =>
      ref.read(sellerApplicationsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final seq = ++_seq;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final data = await _repo.detail(widget.applicationId);
      if (mounted && seq == _seq) {
        setState(() {
          _seller = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _loadError = e is SellerApplicationsException
              ? e.message
              : 'Failed to load seller application dossier.';
        });
      }
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFDC2626) : AppColors.emerald,
      ),
    );
  }

  /// Runs a review action, then reloads the dossier (Web `loadDetail`).
  Future<bool> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      _toast(success);
      await _load(showSpinner: false);
      return true;
    } catch (e) {
      _toast(
        e is SellerApplicationsException
            ? e.message
            : 'Action failed. Please try again.',
        error: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askText({
    required String title,
    required String intro,
    required String label,
    required String confirm,
    required bool required,
    bool danger = false,
    int lines = 3,
    String? hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(intro, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: lines,
                minLines: lines > 1 ? lines : 1,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  labelText: required ? '$label *' : label,
                  hintText: hint,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: required && controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, controller.text.trim()),
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                    )
                  : null,
              child: Text(confirm),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestCorrection(SellerApplication s) async {
    final notes = await _askText(
      title: 'Request Seller Correction',
      intro: 'Specify the exact compliance or profile discrepancies the merchant needs to correct:',
      label: 'Correction Notes',
      confirm: 'Send Correction Request',
      required: true,
      lines: 4,
      hint: 'e.g. Please re-upload a clear copy of your FSSAI certificate showing the valid registration number.',
    );
    if (notes == null) return;
    await _run(
      () => _repo.requestCorrection(s.id, notes),
      'Correction request lodged with seller.',
    );
  }

  Future<void> _reject(SellerApplication s) async {
    final reason = await _askText(
      title: 'Reject Seller Application',
      intro: 'Are you sure you want to reject this grocery seller application? This action will decline merchant onboarding.',
      label: 'Rejection Reason',
      confirm: 'Confirm Rejection',
      required: true,
      danger: true,
      hint: 'Reason for declining application...',
    );
    if (reason == null) return;
    await _run(
      () => _repo.reject(s.id, reason),
      'Seller application marked as rejected.',
    );
  }

  Future<void> _approve(SellerApplication s) async {
    final allApproved =
        s.documents.isNotEmpty && s.documents.every((d) => d.isApproved);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Approve ${s.storeName}?'),
        content: Text(
          allApproved
              ? 'This will activate the company, merchant user account, and enable order intake for this store on the customer marketplace.'
              : 'Warning: Some uploaded compliance documents are not marked as approved yet. All documents must be verified and approved before final activation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
            child: const Text('Approve & Activate Seller'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _repo.approve(s.id),
      'Seller application approved. Storefront and manager account activated.',
    );
  }

  Future<void> _rejectDocument(
    SellerApplication s,
    SellerApplicationDocument doc,
  ) async {
    final reason = await _askText(
      title: 'Reject Document',
      intro: 'Specify why this document is invalid or rejected:',
      label: 'Reason',
      confirm: 'Confirm Rejection',
      required: false,
      danger: true,
      lines: 1,
      hint: 'e.g. Expired FSSAI certificate, unclear image',
    );
    if (reason == null) return;
    await _run(
      () => _repo.verifyDocument(s.id, doc.key, 'reject', reason: reason),
      'Document marked as rejected.',
    );
  }

  Future<void> _openFile(String url) async {
    final uri = Uri.tryParse(url);
    var launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!launched) _toast('Could not open the document file.', error: true);
  }

  int _tab = 0; // 0 overview · 1 documents · 2 categories

  @override
  Widget build(BuildContext context) {
    final s = _seller;
    return SevoModuleScaffold(
      module: SevoModule.sellerApplications,
      transition: false,
      title: s?.storeName ?? 'Seller Dossier',
      subtitle: s == null
          ? 'Review merchant dossier'
          : '#SEL-${s.id} • ${s.companyName}',
      onRefresh: s == null ? null : () => _load(showSpinner: false),
      children: _body(s),
    );
  }

  List<Widget> _body(SellerApplication? s) {
    if (_loading && s == null) return const [SevoListSkeleton(count: 2)];
    if (s == null) {
      return [
        SevoErrorState(
          message:
              _loadError ??
              'The requested seller application could not be found.',
          onRetry: _load,
        ),
      ];
    }
    return [
      // status + actions
      SevoAnimatedCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.createdAt != null
                        ? 'Lodged: ${_date(s.createdAt!)}'
                        : 'Registration status',
                    style: SevoText.caption,
                  ),
                ),
                SevoBadge(
                  label: sellerStatusLabel(s.registrationStatus),
                  tone: sellerStatusTone(s.registrationStatus),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _requestCorrection(s),
                  icon: const Icon(Icons.warning_amber_rounded, size: 16),
                  label: const Text('Request Correction'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _reject(s),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorText,
                    side: BorderSide(color: AppColors.errorBorder),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy || s.isApproved ? null : () => _approve(s),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(
                    s.isApproved ? 'Store Approved' : 'Approve Application',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.actionColor,
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      SevoFilterRow(
        chips: [
          SevoFilterChip(
            label: 'Overview',
            selected: _tab == 0,
            onTap: () => setState(() => _tab = 0),
          ),
          SevoFilterChip(
            label: 'Documents (${s.documents.length})',
            selected: _tab == 1,
            onTap: () => setState(() => _tab = 1),
          ),
          SevoFilterChip(
            label: 'Categories (${s.categories.length})',
            selected: _tab == 2,
            onTap: () => setState(() => _tab = 2),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...switch (_tab) {
        0 => _overview(s),
        1 => _documents(s),
        _ => _categories(s),
      },
    ];
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _section(String title, List<Widget> rows) => SevoAnimatedCard(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SevoText.section),
        const SizedBox(height: 10),
        ...rows,
      ],
    ),
  );

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SevoText.overline),
        const SizedBox(height: 2),
        Text(
          value,
          style: SevoText.body.copyWith(color: AppColors.headingText),
        ),
      ],
    ),
  );

  List<Widget> _overview(SellerApplication s) {
    final o = s.owner;
    return [
      _section('Storefront & Corporate Entity', [
        _kv('Store Display Name', s.storeName),
        _kv('Legal Entity Name', s.companyName),
        _kv('FSSAI License Number', s.fssaiNumber ?? 'Not provided'),
        _kv('GST Number (GSTIN)', s.gstNumber ?? 'Not registered'),
        _kv(
          'Store Street Address',
          s.storeAddress ?? 'No physical address lodged.',
        ),
      ]),
      _section('Store Owner / Primary Manager', [
        _kv('Contact Person', o.hasName ? o.fullName : 'Not designated'),
        _kv('Mobile Number', o.mobile ?? 'None'),
        _kv('Email Address', o.email ?? 'None'),
      ]),
      _section('Review Audit Status', [
        _kv('Registration State', s.registrationStatus),
        _kv('Company Active', s.isCompanyActive ? 'Yes' : 'Inactive'),
        _kv('Accepting Orders', s.isAcceptingOrders ? 'Yes' : 'Disabled'),
        if (s.approvedAt != null) _kv('Approved At', _date(s.approvedAt!)),
        if ((s.correctionNotes ?? '').isNotEmpty)
          _kv('Active Correction Notes', s.correctionNotes!),
        if ((s.rejectionReason ?? '').isNotEmpty)
          _kv('Rejection Reason', s.rejectionReason!),
      ]),
    ];
  }

  List<Widget> _documents(SellerApplication s) {
    return [
      Text('Lodged Compliance Documents', style: SevoText.section),
      const SizedBox(height: 2),
      Text(
        'Verify FSSAI license certificates, tax registrations, and storefront verification files.',
        style: SevoText.caption,
      ),
      if (s.documents.isNotEmpty) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => _repo.bulkApproveAllPending(s.id),
                    'All pending documents approved.',
                  ),
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text('Bulk Approve All Pending'),
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (s.documents.isEmpty)
        const SevoEmptyState(
          module: SevoModule.sellerApplications,
          title: 'No documents',
          message: 'No documents lodged with this application.',
        )
      else
        for (var i = 0; i < s.documents.length; i++)
          _DocumentCard(
            index: i,
            doc: s.documents[i],
            busy: _busy,
            onOpen: s.documents[i].fileUrl == null
                ? null
                : () => _openFile(s.documents[i].fileUrl!),
            onApprove: () => _run(
              () => _repo.verifyDocument(s.id, s.documents[i].key, 'approve'),
              'Document marked as approved.',
            ),
            onReject: () => _rejectDocument(s, s.documents[i]),
          ),
    ];
  }

  List<Widget> _categories(SellerApplication s) {
    return [
      Text('Requested Product Categories', style: SevoText.section),
      const SizedBox(height: 2),
      Text(
        'Authorize or decline retail product segments for this store catalog.',
        style: SevoText.caption,
      ),
      const SizedBox(height: 12),
      if (s.categories.isEmpty)
        const SevoEmptyState(
          module: SevoModule.sellerApplications,
          title: 'No categories',
          message: 'No product categories requested.',
        )
      else
        for (var i = 0; i < s.categories.length; i++)
          SevoAnimatedCard(
            index: i,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.categories[i].name,
                        style: SevoText.cardTitle,
                      ),
                    ),
                    SevoBadge(
                      label: sellerStatusLabel(s.categories[i].status),
                      tone: sellerStatusTone(s.categories[i].status),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _busy || s.categories[i].status == 'approved'
                          ? null
                          : () => _run(
                              () => _repo.decideCategory(
                                s.id,
                                s.categories[i].id,
                                'approve',
                              ),
                              'Category approved.',
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy || s.categories[i].status == 'rejected'
                          ? null
                          : () => _run(
                              () => _repo.decideCategory(
                                s.id,
                                s.categories[i].id,
                                'reject',
                              ),
                              'Category rejected.',
                            ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.errorText,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Decline'),
                    ),
                  ],
                ),
              ],
            ),
          ),
    ];
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.index,
    required this.doc,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    this.onOpen,
  });

  final int index;
  final SellerApplicationDocument doc;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.selectedTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 19,
                  color: AppColors.selectedOnTint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(doc.title, style: SevoText.cardTitle)),
              const SizedBox(width: 8),
              Flexible(
                child: SevoBadge(
                  label: sellerStatusLabel(doc.status),
                  tone: sellerStatusTone(doc.status),
                ),
              ),
            ],
          ),
          if ((doc.documentNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Doc #: ${doc.documentNumber}', style: SevoText.caption),
          ],
          const SizedBox(height: 6),
          if (onOpen != null)
            InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View / Download File',
                      style: SevoText.button.copyWith(
                        color: AppColors.accentOnSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: AppColors.accentOnSurface,
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              'No file attachment',
              style: SevoText.caption.copyWith(color: AppColors.textMuted),
            ),
          if ((doc.rejectionReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Reason: ${doc.rejectionReason}',
                style: SevoText.caption.copyWith(color: AppColors.errorText),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy || doc.isApproved ? null : onApprove,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Approve'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy || doc.isRejected ? null : onReject,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.errorText,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
