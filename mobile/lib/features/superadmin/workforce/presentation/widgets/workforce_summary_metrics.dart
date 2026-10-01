import 'package:flutter/material.dart';

import '../../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../data/superadmin_workforce_repository.dart';
import '../superadmin_workforce_providers.dart';

/// Live summary metrics of the Workforce Roster. Each tile doubles as a filter.
class WorkforceSummaryMetrics extends StatelessWidget {
  const WorkforceSummaryMetrics({
    super.key,
    required this.data,
    required this.selectedFilter,
    required this.onSelectFilter,
  });

  final PlatformWorkforceOverviewData data;
  final WorkforceFilterType selectedFilter;
  final ValueChanged<WorkforceFilterType> onSelectFilter;

  @override
  Widget build(BuildContext context) {
    final audits = data.pendingSevoAuditCount;
    return SevoTileGrid(
      tiles: [
        SevoStatTile(
          index: 0,
          label: 'TOTAL TECHNICIANS',
          value: data.totalTechnicians,
          caption: 'Registered on platform',
          icon: Icons.people_alt_rounded,
          accent: const Color(0xFF0D9488),
          selected: selectedFilter == WorkforceFilterType.all,
          onTap: () => onSelectFilter(WorkforceFilterType.all),
        ),
        SevoStatTile(
          index: 1,
          label: 'SOLO WORKERS',
          value: data.soloWorkersCount,
          caption: 'Independent technicians',
          icon: Icons.person_rounded,
          accent: const Color(0xFF2563EB),
          selected: selectedFilter == WorkforceFilterType.solo,
          onTap: () => onSelectFilter(WorkforceFilterType.solo),
        ),
        SevoStatTile(
          index: 2,
          label: 'TIED WORKERS',
          value: data.tiedWorkersCount,
          caption: 'Vendor-linked personnel',
          icon: Icons.business_rounded,
          accent: const Color(0xFF059669),
          selected: selectedFilter == WorkforceFilterType.tied,
          onTap: () => onSelectFilter(WorkforceFilterType.tied),
        ),
        SevoStatTile(
          index: 3,
          label: 'RELIEVING AUDITS',
          value: audits,
          caption: audits > 0 ? 'Action required' : 'All audits cleared',
          icon: Icons.gavel_rounded,
          accent: const Color(0xFF7C3AED),
          alert: audits > 0,
          alertLabel: 'AUDIT',
          selected: selectedFilter == WorkforceFilterType.relievingAudits,
          onTap: () => onSelectFilter(WorkforceFilterType.relievingAudits),
        ),
      ],
    );
  }
}
