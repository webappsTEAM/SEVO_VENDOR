import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/presentation/widgets/admin_drawer.dart';
import 'package:mobile/shared/widgets/async_value_view.dart';
import 'package:mobile/shared/widgets/workforce_app_bar.dart';

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
  });

  final String? initialStatusFilter;

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
    if (widget.initialStatusFilter != null &&
        widget.initialStatusFilter!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialFilter(widget.initialStatusFilter!);
      });
    }
  }

  void _applyInitialFilter(String status) {
    final normalized = status.toLowerCase().trim();
    PlatformApplicationStatusFilter filter = PlatformApplicationStatusFilter.all;

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
        backgroundColor:
            isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
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
      final msg = res['message'] ??
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
      final msg = res['message'] ??
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
      final msg = res['message'] ??
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
          context.push('/admin/applications/${app.id}').then((_) => _refreshApplications());
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
          .decideChangeRequest(
            crId: crId,
            action: action,
            notes: notes,
          );
      ref.invalidate(superAdminChangeRequestsListProvider);
      final isApprove = action.toUpperCase() == 'APPROVE';
      final msg = res['message'] ??
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    final metrics = ref.watch(superAdminApplicationMetricsProvider);
    final selectedSection = ref.watch(superAdminSelectedSectionProvider);
    final selectedFilter = ref.watch(applicationStatusFilterProvider);
    final filteredApplications =
        ref.watch(filteredSuperAdminApplicationsProvider);
    final pendingCRCount =
        ref.watch(superAdminPendingChangeRequestsCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WorkforceAppBar(
        titleText: 'Partner Applications',
        showStatusSubBar: false,
        showDrawerMenu: true,
      ),
      drawer: const AdminDrawer(),
      body: RefreshIndicator(
        onRefresh: _refreshApplications,
        child: AsyncValueView<List<AdminApplication>>(
          value: applicationsAsync,
          errorMessage: 'Unable to load technician applications',
          onRetry: _refreshApplications,
          builder: (context, allApps) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                // ── 1. Header ───────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  'PLATFORM GOVERNANCE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Applications Approval',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SEVO Platform Admin: Review technician onboarding applications, verify submitted documents, and manage approval decisions across the platform.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppColors.primary,
                      tooltip: 'Refresh Applications',
                      onPressed: _refreshApplications,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── 2. Top-Level Section Tabs ───────────────────────────────
                _buildTopSectionTabs(
                  selectedSection: selectedSection,
                  onboardingCount: allApps.length,
                  pendingCRCount: pendingCRCount,
                ),
                const SizedBox(height: 14),

                // ── 3. Content Sections ─────────────────────────────────────
                if (selectedSection ==
                    SuperAdminApplicationsSection.onboardingApplications) ...[
                  // Summary Metrics
                  ApplicationMetrics(
                    metrics: metrics,
                    selectedFilter: selectedFilter,
                    onSelectFilter: (PlatformApplicationStatusFilter filter) {
                      ref
                          .read(applicationStatusFilterProvider.notifier)
                          .state = filter;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Filter Chips with Badges
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterTab(
                          label: 'All Applications',
                          count: metrics.totalCount,
                          isSelected: selectedFilter ==
                              PlatformApplicationStatusFilter.all,
                          activeColor: AppColors.primary,
                          onTap: () => ref
                              .read(applicationStatusFilterProvider.notifier)
                              .state = PlatformApplicationStatusFilter.all,
                        ),
                        const SizedBox(width: 6),
                        _FilterTab(
                          label: 'Pending',
                          count: metrics.pendingCount,
                          isSelected: selectedFilter ==
                              PlatformApplicationStatusFilter.pending,
                          activeColor: const Color(0xFFD97706),
                          onTap: () => ref
                              .read(applicationStatusFilterProvider.notifier)
                              .state = PlatformApplicationStatusFilter.pending,
                        ),
                        const SizedBox(width: 6),
                        _FilterTab(
                          label: 'Under Review',
                          count: metrics.underReviewCount,
                          isSelected: selectedFilter ==
                              PlatformApplicationStatusFilter.underReview,
                          activeColor: const Color(0xFF2563EB),
                          onTap: () => ref
                              .read(applicationStatusFilterProvider.notifier)
                              .state =
                              PlatformApplicationStatusFilter.underReview,
                        ),
                        const SizedBox(width: 6),
                        _FilterTab(
                          label: 'Approved',
                          count: metrics.approvedCount,
                          isSelected: selectedFilter ==
                              PlatformApplicationStatusFilter.approved,
                          activeColor: const Color(0xFF059669),
                          onTap: () => ref
                              .read(applicationStatusFilterProvider.notifier)
                              .state = PlatformApplicationStatusFilter.approved,
                        ),
                        const SizedBox(width: 6),
                        _FilterTab(
                          label: 'Corrections Required',
                          count: metrics.correctionsRequiredCount,
                          isSelected: selectedFilter ==
                              PlatformApplicationStatusFilter
                                  .correctionsRequired,
                          activeColor: const Color(0xFFEA580C),
                          onTap: () => ref
                              .read(applicationStatusFilterProvider.notifier)
                              .state =
                              PlatformApplicationStatusFilter
                                  .correctionsRequired,
                        ),
                        const SizedBox(width: 6),
                        _FilterTab(
                          label: 'Rejected',
                          count: metrics.rejectedCount,
                          isSelected: selectedFilter ==
                              PlatformApplicationStatusFilter.rejected,
                          activeColor: const Color(0xFFDC2626),
                          onTap: () => ref
                              .read(applicationStatusFilterProvider.notifier)
                              .state = PlatformApplicationStatusFilter.rejected,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search Bar
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 10, right: 6),
                          child: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Search by technician name, ID, email, or mobile number...',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            color: AppColors.textMuted,
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Applications List
                  if (filteredApplications.isEmpty)
                    _EmptyApplicationsView(
                      selectedFilter: selectedFilter,
                      hasSearch: _searchController.text.isNotEmpty,
                    )
                  else
                    ...filteredApplications.map(
                      (app) => ApplicationCard(
                        application: app,
                        onViewDetail: () => _openApplicationDetail(app),
                      ),
                    ),
                ] else ...[
                  // Section 2: Profile Change Requests View
                  _buildProfileChangeRequestsSection(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Top Navigation Tabs Builder ───────────────────────────────────────────

  Widget _buildTopSectionTabs({
    required SuperAdminApplicationsSection selectedSection,
    required int onboardingCount,
    required int pendingCRCount,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SectionTabButton(
          label: 'Onboarding Applications ($onboardingCount)',
          isSelected: selectedSection ==
              SuperAdminApplicationsSection.onboardingApplications,
          onTap: () {
            ref.read(superAdminSelectedSectionProvider.notifier).state =
                SuperAdminApplicationsSection.onboardingApplications;
          },
        ),
        _SectionTabButton(
          label: '🔒 Profile Change Requests ($pendingCRCount Pending)',
          isSelected: selectedSection ==
              SuperAdminApplicationsSection.profileChangeRequests,
          onTap: () {
            ref.read(superAdminSelectedSectionProvider.notifier).state =
                SuperAdminApplicationsSection.profileChangeRequests;
          },
        ),
      ],
    );
  }

  // ── Profile Change Requests Section ───────────────────────────────────────

  Widget _buildProfileChangeRequestsSection() {
    final changeRequestsAsync = ref.watch(superAdminChangeRequestsListProvider);

    return AsyncValueView<List<AdminChangeRequest>>(
      value: changeRequestsAsync,
      errorMessage: 'Unable to load profile change requests',
      onRetry: () async {
        ref.invalidate(superAdminChangeRequestsListProvider);
        await ref.read(superAdminChangeRequestsListProvider.future);
      },
      builder: (context, changeRequests) {
        if (changeRequests.isEmpty) {
          return const _EmptyProfileChangeRequestsView();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...changeRequests.map(
              (cr) => ProfileChangeRequestCard(
                changeRequest: cr,
                onDecide: () => _openDecideChangeRequestModal(cr),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionTabButton extends StatelessWidget {
  const _SectionTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF005965);

    return Material(
      color: isSelected ? activeColor : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      elevation: isSelected ? 1 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor : AppColors.border,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? activeColor : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor : AppColors.border,
              width: isSelected ? 1.2 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.25) : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyApplicationsView extends StatelessWidget {
  const _EmptyApplicationsView({
    required this.selectedFilter,
    required this.hasSearch,
  });

  final PlatformApplicationStatusFilter selectedFilter;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    String title = 'No applications found';
    String message = 'There are currently no technician applications in this view.';

    if (hasSearch) {
      title = 'No search results';
      message = 'No applications matched your search term. Try adjusting your query.';
    } else {
      switch (selectedFilter) {
        case PlatformApplicationStatusFilter.pending:
          title = 'No pending applications';
          message = 'All submitted technician applications have been reviewed.';
          break;
        case PlatformApplicationStatusFilter.underReview:
          title = 'No applications under review';
          message = 'There are no applications currently undergoing active administrative review.';
          break;
        case PlatformApplicationStatusFilter.approved:
          title = 'No approved applications';
          message = 'No technician applications have been approved yet.';
          break;
        case PlatformApplicationStatusFilter.correctionsRequired:
          title = 'No corrections pending';
          message = 'No applications are currently awaiting document resubmission.';
          break;
        case PlatformApplicationStatusFilter.rejected:
          title = 'No rejected applications';
          message = 'No technician applications have been rejected.';
          break;
        case PlatformApplicationStatusFilter.all:
          title = 'No applications registered';
          message = 'No technician applications have been registered on the platform.';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyProfileChangeRequestsView extends StatelessWidget {
  const _EmptyProfileChangeRequestsView();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_reset_rounded,
            size: 40,
            color: AppColors.textMuted,
          ),
          SizedBox(height: 12),
          Text(
            'No employee profile change requests pending review.',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'All technician profile modification requests across the platform have been processed.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}