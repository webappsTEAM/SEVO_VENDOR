import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/shared/widgets/sevo/sevo_controls.dart';
import 'package:mobile/shared/widgets/sevo/sevo_module_art.dart';
import 'package:mobile/shared/widgets/sevo/sevo_module_scaffold.dart';
import 'package:mobile/shared/widgets/sevo/sevo_search_field.dart';
import 'package:mobile/shared/widgets/sevo/sevo_skeleton.dart';
import 'package:mobile/shared/widgets/sevo/sevo_state_views.dart';

import '../data/superadmin_applications_repository.dart';
import '../domain/platform_application.dart';
import 'superadmin_applications_providers.dart';
import 'widgets/application_action_dialog.dart';
import 'widgets/application_card.dart';
import 'widgets/application_detail_sheet.dart';
import 'widgets/application_metrics.dart';
import 'widgets/profile_change_request_card.dart';

/// Super Admin: Applications Approval Module Screen.
/// Platform-level review center featuring:
/// 1. Onboarding Applications (Dossier audit, document verification, platform decisions)
/// 2. Profile Change Requests (Employee controlled field modifications queue)
class SuperAdminApplicationsScreen extends ConsumerStatefulWidget {
  const SuperAdminApplicationsScreen({
    super.key,
    this.initialStatusFilter,
    this.openChangeRequests = false,
  });

  final String? initialStatusFilter;

  /// Opens on the Profile Change Requests section (`?tab=change_requests`).
  final bool openChangeRequests;

  @override
  ConsumerState<SuperAdminApplicationsScreen> createState() =>
      _SuperAdminApplicationsScreenState();
}

class _SuperAdminApplicationsScreenState
    extends ConsumerState<SuperAdminApplicationsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.openChangeRequests) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(superAdminSelectedSectionProvider.notifier).state =
            SuperAdminApplicationsSection.profileChangeRequests;
      });
    }
    if (widget.initialStatusFilter != null &&
        widget.initialStatusFilter!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialFilter(widget.initialStatusFilter!);
      });
    }
  }

  void _applyInitialFilter(String status) {
    final normalized = status.toLowerCase().trim();
    PlatformApplicationStatusFilter filter =
        PlatformApplicationStatusFilter.all;

    if (normalized == 'submitted' || normalized == 'pending') {
      filter = PlatformApplicationStatusFilter.pending;
    } else if (normalized == 'under_review') {
      filter = PlatformApplicationStatusFilter.underReview;
    } else if (normalized == 'approved' || normalized == 'active') {
      filter = PlatformApplicationStatusFilter.approved;
    } else if (normalized == 'correction_required') {
      filter = PlatformApplicationStatusFilter.correctionsRequired;
    } else if (normalized == 'rejected') {
      filter = PlatformApplicationStatusFilter.rejected;
    }

    ref.read(applicationStatusFilterProvider.notifier).state = filter;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {});
    ref.read(applicationSearchQueryProvider.notifier).state = query.trim();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _extractErrorMessage(dynamic error, String fallback) {
    if (error is DioException && error.response?.data is Map) {
      final data = error.response!.data as Map;
      if (data['error'] != null) return data['error'].toString();
      if (data['message'] != null) return data['message'].toString();
      if (data['detail'] != null) return data['detail'].toString();
    }
    return error?.toString() ?? fallback;
  }

  bool _isSubmittingAction = false;

  Future<void> _refreshApplications() async {
    ref.invalidate(superAdminApplicationsListProvider);
    ref.invalidate(superAdminChangeRequestsListProvider);
    await Future.wait([
      ref.read(superAdminApplicationsListProvider.future),
      ref.read(superAdminChangeRequestsListProvider.future),
    ]);
  }

  // ── Application Actions ───────────────────────────────────────────────────

  Future<void> _handleApprove(AdminApplication app) async {
    if (_isSubmittingAction) return;
    final confirmed = await ApplicationActionDialog.showApproveDialog(
      context,
      technicianName: app.name ?? 'Technician #${app.id}',
    );

    if (confirmed != true) return;

    setState(() => _isSubmittingAction = true);
    try {
      final res = await ref
          .read(superAdminApplicationsRepositoryProvider)
          .approveApplication(app.id);
      await _refreshApplications();
      final msg =
          res['message'] ??
          '${app.name ?? "Technician"} has been approved for platform onboarding.';
      _showFeedback(msg);
    } catch (e) {
      _showFeedback(
        _extractErrorMessage(
          e,
          'Failed to approve application. Please ensure all documents and at least 1 service are verified.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmittingAction = false);
    }
  }

  Future<void> _handleReject(AdminApplication app) async {
    if (_isSubmittingAction) return;
    final reason = await ApplicationActionDialog.showRejectDialog(
      context,
      technicianName: app.name ?? 'Technician #${app.id}',
    );

    if (reason == null || reason.isEmpty) return;

    setState(() => _isSubmittingAction = true);
    try {
      final res = await ref
          .read(superAdminApplicationsRepositoryProvider)
          .rejectApplication(app.id, reason: reason);
      await _refreshApplications();
      final msg =
          res['message'] ??
          'Application for ${app.name ?? "Technician"} has been rejected.';
      _showFeedback(msg);
    } catch (e) {
      _showFeedback(
        _extractErrorMessage(e, 'Failed to reject application.'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmittingAction = false);
    }
  }

  Future<void> _handleRequestCorrection(AdminApplication app) async {
    if (_isSubmittingAction) return;
    final notes = await ApplicationActionDialog.showRequestCorrectionDialog(
      context,
      technicianName: app.name ?? 'Technician #${app.id}',
    );

    if (notes == null || notes.isEmpty) return;

    setState(() => _isSubmittingAction = true);
    try {
      final res = await ref
          .read(superAdminApplicationsRepositoryProvider)
          .requestCorrection(app.id, notes: notes);
      await _refreshApplications();
      final msg =
          res['message'] ??
          'Correction instructions sent to ${app.name ?? "Technician"}.';
      _showFeedback(msg);
    } catch (e) {
      _showFeedback(
        _extractErrorMessage(e, 'Failed to send correction request.'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmittingAction = false);
    }
  }

  void _openApplicationDetail(AdminApplication app) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ApplicationDetailSheet(
        application: app,
        onApprove: () {
          Navigator.of(ctx).pop();
          _handleApprove(app);
        },
        onReject: () {
          Navigator.of(ctx).pop();
          _handleReject(app);
        },
        onRequestCorrection: () {
          Navigator.of(ctx).pop();
          _handleRequestCorrection(app);
        },
        onOpenFullDossier: () {
          Navigator.of(ctx).pop();
          context
              .push('/admin/applications/${app.id}')
              .then((_) => _refreshApplications());
        },
        onDossierUpdated: () => _refreshApplications(),
      ),
    );
  }

  // ── Change Request Actions ────────────────────────────────────────────────

  Future<void> _handleDecideChangeRequest(
    int crId,
    String action,
    String notes,
  ) async {
    if (_isSubmittingAction) return;
    setState(() => _isSubmittingAction = true);
    try {
      final res = await ref
          .read(superAdminApplicationsRepositoryProvider)
          .decideChangeRequest(crId: crId, action: action, notes: notes);
      ref.invalidate(superAdminChangeRequestsListProvider);
      final isApprove = action.toUpperCase() == 'APPROVE';
      final msg =
          res['message'] ??
          (isApprove
              ? 'Change request approved successfully.'
              : 'Change request rejected.');
      _showFeedback(msg);
    } catch (e) {
      _showFeedback(
        _extractErrorMessage(e, 'Failed to process change request decision.'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmittingAction = false);
    }
  }

  void _openDecideChangeRequestModal(AdminChangeRequest cr) {
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Review: ${cr.displayField}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Technician: ${cr.employeeName ?? "Technician"}${cr.employeeId != null && cr.employeeId!.isNotEmpty ? " (${cr.employeeId})" : ""}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Value: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            cr.oldValue?.isNotEmpty == true
                                ? cr.oldValue!
                                : '—',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Requested Value: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            cr.newValue?.isNotEmpty == true
                                ? cr.newValue!
                                : '—',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (cr.reason != null && cr.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reason: ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          cr.reason!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Admin Notes (Optional)',
                  hintText: 'Add decision rationale...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: BorderSide(color: Color(0xFFDC2626)),
            ),
            onPressed: () async {
              Navigator.of(dlgCtx).pop();
              await _handleDecideChangeRequest(
                cr.id,
                'REJECT',
                notesController.text.trim(),
              );
            },
            child: Text('Reject'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            onPressed: () async {
              Navigator.of(dlgCtx).pop();
              await _handleDecideChangeRequest(
                cr.id,
                'APPROVE',
                notesController.text.trim(),
              );
            },
            child: Text('Approve'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final applicationsAsync = ref.watch(superAdminApplicationsListProvider);
    final selectedSection = ref.watch(superAdminSelectedSectionProvider);
    final isOnboarding =
        selectedSection == SuperAdminApplicationsSection.onboardingApplications;

    return SevoModuleScaffold(
      module: SevoModule.technicianApplications,
      title: 'Technician Applications',
      subtitle: 'Review onboarding & profile changes',
      ready: !applicationsAsync.isLoading,
      onRefresh: _refreshApplications,
      heroTrailing: IconButton.filled(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
        tooltip: 'Refresh Applications',
        onPressed: _refreshApplications,
      ),
      heroBottom: isOnboarding
          ? SevoSearchField(
              controller: _searchController,
              hint: 'Search name, ID, email or mobile',
              onChanged: _onSearchChanged,
            )
          : null,
      children: _body(applicationsAsync, selectedSection),
    );
  }

  List<Widget> _body(
    AsyncValue<List<AdminApplication>> async,
    SuperAdminApplicationsSection selectedSection,
  ) {
    if (async.hasError && !async.hasValue) {
      return [
        SevoErrorState(
          message: 'Unable to load technician applications',
          onRetry: _refreshApplications,
        ),
      ];
    }
    if (!async.hasValue) return const [SevoListSkeleton(count: 3)];

    final allApps = async.requireValue;
    final metrics = ref.watch(superAdminApplicationMetricsProvider);
    final selectedFilter = ref.watch(applicationStatusFilterProvider);
    final filteredApplications = ref.watch(
      filteredSuperAdminApplicationsProvider,
    );
    final pendingCRCount = ref.watch(
      superAdminPendingChangeRequestsCountProvider,
    );
    final isOnboarding =
        selectedSection == SuperAdminApplicationsSection.onboardingApplications;
    void setFilter(PlatformApplicationStatusFilter f) =>
        ref.read(applicationStatusFilterProvider.notifier).state = f;
    void setSection(SuperAdminApplicationsSection v) =>
        ref.read(superAdminSelectedSectionProvider.notifier).state = v;

    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SevoFilterChip(
            label: 'Onboarding Applications (${allApps.length})',
            selected: isOnboarding,
            onTap: () => setSection(
              SuperAdminApplicationsSection.onboardingApplications,
            ),
          ),
          SevoFilterChip(
            label: '🔒 Profile Change Requests ($pendingCRCount Pending)',
            selected: !isOnboarding,
            onTap: () =>
                setSection(SuperAdminApplicationsSection.profileChangeRequests),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (isOnboarding) ...[
        ApplicationMetrics(
          metrics: metrics,
          selectedFilter: selectedFilter,
          onSelectFilter: setFilter,
        ),
        const SizedBox(height: 14),
        SevoFilterRow(
          chips: [
            for (final f in _statusChips(metrics))
              SevoFilterChip(
                label: f.$1,
                count: f.$3,
                selected: selectedFilter == f.$2,
                onTap: () => setFilter(f.$2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SevoDropdownField<String>(
          value: ref.watch(applicationServiceFilterProvider),
          icon: Icons.filter_list_rounded,
          label: 'Service',
          items: [
            const DropdownMenuItem(value: 'ALL', child: Text('All Services')),
            for (final name in ref.watch(superAdminUniqueServicesProvider))
              DropdownMenuItem(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) =>
              ref.read(applicationServiceFilterProvider.notifier).state =
                  v ?? 'ALL',
        ),
        const SizedBox(height: 14),
        if (filteredApplications.isEmpty)
          _emptyApplications(selectedFilter, _searchController.text.isNotEmpty)
        else
          for (var i = 0; i < filteredApplications.length; i++)
            ApplicationCard(
              index: i,
              application: filteredApplications[i],
              onViewDetail: () =>
                  _openApplicationDetail(filteredApplications[i]),
            ),
      ] else
        ..._changeRequestsSection(),
    ];
  }

  List<(String, PlatformApplicationStatusFilter, int)> _statusChips(
    SuperAdminApplicationMetrics m,
  ) => [
    ('All', PlatformApplicationStatusFilter.all, m.totalCount),
    ('Pending', PlatformApplicationStatusFilter.pending, m.pendingCount),
    (
      'Under Review',
      PlatformApplicationStatusFilter.underReview,
      m.underReviewCount,
    ),
    ('Approved', PlatformApplicationStatusFilter.approved, m.approvedCount),
    (
      'Corrections',
      PlatformApplicationStatusFilter.correctionsRequired,
      m.correctionsRequiredCount,
    ),
    ('Rejected', PlatformApplicationStatusFilter.rejected, m.rejectedCount),
  ];

  Widget _emptyApplications(
    PlatformApplicationStatusFilter selectedFilter,
    bool hasSearch,
  ) {
    var title = 'No applications found';
    var message =
        'There are currently no technician applications in this view.';
    if (hasSearch) {
      title = 'No search results';
      message =
          'No applications matched your search term. Try adjusting your query.';
    } else {
      switch (selectedFilter) {
        case PlatformApplicationStatusFilter.pending:
          title = 'No pending applications';
          message = 'All submitted technician applications have been reviewed.';
        case PlatformApplicationStatusFilter.underReview:
          title = 'No applications under review';
          message = 'There are no applications currently undergoing active administrative review.';
        case PlatformApplicationStatusFilter.approved:
          title = 'No approved applications';
          message = 'No technician applications have been approved yet.';
        case PlatformApplicationStatusFilter.correctionsRequired:
          title = 'No corrections pending';
          message =
              'No applications are currently awaiting document resubmission.';
        case PlatformApplicationStatusFilter.rejected:
          title = 'No rejected applications';
          message = 'No technician applications have been rejected.';
        case PlatformApplicationStatusFilter.all:
          title = 'No applications registered';
          message = 'No technician applications have been registered on the platform.';
      }
    }
    return SevoEmptyState(
      module: SevoModule.technicianApplications,
      title: title,
      message: message,
    );
  }

  List<Widget> _changeRequestsSection() {
    final async = ref.watch(superAdminChangeRequestsListProvider);
    if (async.hasError && !async.hasValue) {
      return [
        SevoErrorState(
          message: 'Unable to load profile change requests',
          onRetry: () async {
            ref.invalidate(superAdminChangeRequestsListProvider);
            await ref.read(superAdminChangeRequestsListProvider.future);
          },
        ),
      ];
    }
    if (!async.hasValue) return const [SevoListSkeleton(count: 2)];
    final requests = async.requireValue;
    if (requests.isEmpty) {
      return const [
        SevoEmptyState(
          module: SevoModule.technicianApplications,
          title: 'No employee profile change requests pending review.',
          message: 'All technician profile modification requests across the platform have been processed.',
        ),
      ];
    }
    return [
      for (var i = 0; i < requests.length; i++)
        ProfileChangeRequestCard(
          index: i,
          changeRequest: requests[i],
          onDecide: () => _openDecideChangeRequestModal(requests[i]),
        ),
    ];
  }
}
