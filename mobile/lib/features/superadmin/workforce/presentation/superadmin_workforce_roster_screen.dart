import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';
import '../../../../shared/widgets/sevo/sevo_module_scaffold.dart';
import '../../../../shared/widgets/sevo/sevo_search_field.dart';
import '../../../../shared/widgets/sevo/sevo_skeleton.dart';
import '../../../../shared/widgets/sevo/sevo_state_views.dart';
import '../data/superadmin_workforce_repository.dart';
import '../domain/platform_relieving_request.dart';
import '../domain/platform_worker.dart';
import 'superadmin_workforce_providers.dart';
import 'widgets/approve_relieving_bottom_sheet.dart';
import 'widgets/relieving_audit_card.dart';
import 'widgets/tie_vendor_bottom_sheet.dart';
import 'widgets/worker_card.dart';
import 'widgets/workforce_summary_metrics.dart';

/// Super Admin Platform Governance: Workforce Roster (Manage All Workforce - Solo & Tied).
class SuperAdminWorkforceRosterScreen extends ConsumerStatefulWidget {
  const SuperAdminWorkforceRosterScreen({super.key, this.initialVendorId});

  final int? initialVendorId;

  @override
  ConsumerState<SuperAdminWorkforceRosterScreen> createState() =>
      _SuperAdminWorkforceRosterScreenState();
}

class _SuperAdminWorkforceRosterScreenState
    extends ConsumerState<SuperAdminWorkforceRosterScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyInitialFilters();
    });
  }

  @override
  void didUpdateWidget(covariant SuperAdminWorkforceRosterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialVendorId != widget.initialVendorId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialFilters();
      });
    }
  }

  void _applyInitialFilters() {
    if (widget.initialVendorId != null && widget.initialVendorId! > 0) {
      ref.read(workforceSelectedVendorIdProvider.notifier).state =
          widget.initialVendorId;
      ref.read(workforceFilterTypeProvider.notifier).state =
          WorkforceFilterType.all;
    } else {
      // General workforce entry: ensure no vendor filter is applied and All Workforce is selected
      ref.read(workforceSelectedVendorIdProvider.notifier).state = null;
      ref.read(workforceFilterTypeProvider.notifier).state =
          WorkforceFilterType.all;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {});
    ref.read(workforceSearchQueryProvider.notifier).state = query.trim();
  }

  void _openTieModal(
    PlatformWorker worker,
    List<PlatformVendorSummary> vendors,
  ) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TieVendorBottomSheet(worker: worker, vendors: vendors),
    );
  }

  void _openAuditModal(PlatformRelievingRequest request) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ApproveRelievingBottomSheet(request: request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedFilter = ref.watch(workforceFilterTypeProvider);
    final selectedVendorId = ref.watch(workforceSelectedVendorIdProvider);
    final workforceAsync = ref.watch(platformWorkforceDataProvider);

    return SevoModuleScaffold(
      module: SevoModule.workforceRoster,
      title: 'Workforce Roster',
      subtitle: 'Manage solo & tied technicians',
      ready: !workforceAsync.isLoading,
      onRefresh: () async {
        ref.invalidate(platformWorkforceDataProvider);
        await ref.read(platformWorkforceDataProvider.future);
      },
      heroTrailing: IconButton.filled(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
        tooltip: 'Refresh Roster',
        onPressed: () => ref.invalidate(platformWorkforceDataProvider),
      ),
      heroBottom: selectedFilter == WorkforceFilterType.relievingAudits
          ? null
          : SevoSearchField(
              controller: _searchController,
              hint: 'Search name, ID, email or phone',
              onChanged: _onSearchChanged,
            ),
      children: _body(workforceAsync, selectedFilter, selectedVendorId),
    );
  }

  List<Widget> _body(
    AsyncValue<PlatformWorkforceOverviewData> async,
    WorkforceFilterType selectedFilter,
    int? selectedVendorId,
  ) {
    if (async.hasError && !async.hasValue) {
      return [
        SevoErrorState(
          message: 'Unable to load platform workforce roster',
          onRetry: () => ref.invalidate(platformWorkforceDataProvider),
        ),
      ];
    }
    if (!async.hasValue) return const [SevoListSkeleton(count: 3)];

    final data = async.requireValue;
    final isAuditsTab = selectedFilter == WorkforceFilterType.relievingAudits;
    void select(WorkforceFilterType f) =>
        ref.read(workforceFilterTypeProvider.notifier).state = f;

    return [
      SevoLinkCard(
        title: 'Manage Vendor Companies',
        subtitle: 'View registered vendor directory and provider fleet sizes',
        icon: Icons.business_rounded,
        tone: SevoTone.info,
        onTap: () => context.go(AppRoutes.superAdminVendors),
      ),
      const SizedBox(height: 12),
      WorkforceSummaryMetrics(
        data: data,
        selectedFilter: selectedFilter,
        onSelectFilter: select,
      ),
      const SizedBox(height: 14),
      SevoFilterRow(
        chips: [
          SevoFilterChip(
            label: 'All Workforce',
            count: data.totalTechnicians,
            selected: selectedFilter == WorkforceFilterType.all,
            color: const Color(0xFF0D9488),
            onTap: () => select(WorkforceFilterType.all),
          ),
          SevoFilterChip(
            label: 'Solo Workers',
            count: data.soloWorkersCount,
            selected: selectedFilter == WorkforceFilterType.solo,
            color: const Color(0xFF2563EB),
            onTap: () => select(WorkforceFilterType.solo),
          ),
          SevoFilterChip(
            label: 'Tied Workers',
            count: data.tiedWorkersCount,
            selected: selectedFilter == WorkforceFilterType.tied,
            color: const Color(0xFF059669),
            onTap: () => select(WorkforceFilterType.tied),
          ),
          SevoFilterChip(
            label: 'Resignation Audits',
            count: data.pendingSevoAuditCount,
            selected: isAuditsTab,
            color: const Color(0xFF7C3AED),
            alert: data.pendingSevoAuditCount > 0,
            onTap: () => select(WorkforceFilterType.relievingAudits),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (!isAuditsTab && data.vendors.isNotEmpty) ...[
        SevoDropdownField<int?>(
          value: selectedVendorId,
          icon: Icons.business_outlined,
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All Vendors'),
            ),
            for (final v in data.vendors)
              DropdownMenuItem<int?>(
                value: v.id,
                child: Text(
                  '${v.companyName} (${v.tiedWorkersCount} tied)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (val) =>
              ref.read(workforceSelectedVendorIdProvider.notifier).state = val,
        ),
        const SizedBox(height: 14),
      ],
      if (isAuditsTab) ...[
        if (data.relievingRequests.isEmpty)
          const SevoEmptyState(
            module: SevoModule.workforceRoster,
            title: 'No Pending Relieving Audits',
            message: 'All technician resignations and vendor clearances have been audited and resolved.',
          )
        else
          for (var i = 0; i < data.relievingRequests.length; i++)
            RelievingAuditCard(
              index: i,
              request: data.relievingRequests[i],
              onAudit: () => _openAuditModal(data.relievingRequests[i]),
            ),
      ] else ...[
        if (data.workers.isEmpty)
          const SevoEmptyState(
            module: SevoModule.workforceRoster,
            title: 'No technicians found',
            message:
                'No workers match your selected filter or search criteria.',
          )
        else
          for (var i = 0; i < data.workers.length; i++)
            WorkerCard(
              index: i,
              worker: data.workers[i],
              onManageTie: () => _openTieModal(data.workers[i], data.vendors),
            ),
      ],
    ];
  }
}
