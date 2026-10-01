import 'package:flutter/material.dart';

import 'package:mobile/features/superadmin/applications/domain/platform_application.dart';
import 'package:mobile/shared/widgets/sevo/sevo_controls.dart';

/// Metric tiles of the Technician Applications screen. Each tile is also a
/// status filter.
class ApplicationMetrics extends StatelessWidget {
  const ApplicationMetrics({
    super.key,
    required this.metrics,
    required this.selectedFilter,
    required this.onSelectFilter,
  });

  final SuperAdminApplicationMetrics metrics;
  final PlatformApplicationStatusFilter selectedFilter;
  final ValueChanged<PlatformApplicationStatusFilter> onSelectFilter;

  @override
  Widget build(BuildContext context) {
    SevoStatTile tile(
      int i,
      String title,
      String caption,
      int count,
      IconData icon,
      Color accent,
      PlatformApplicationStatusFilter f,
    ) {
      return SevoStatTile(
        index: i,
        label: title,
        caption: caption,
        value: count,
        icon: icon,
        accent: accent,
        selected: selectedFilter == f,
        onTap: () => onSelectFilter(f),
      );
    }

    return SevoTileGrid(
      tiles: [
        tile(
          0,
          'Pending Applications',
          'Waiting for review',
          metrics.pendingCount,
          Icons.schedule_rounded,
          const Color(0xFFD97706),
          PlatformApplicationStatusFilter.pending,
        ),
        tile(
          1,
          'Under Review',
          'Currently being reviewed',
          metrics.underReviewCount,
          Icons.search_rounded,
          const Color(0xFF2563EB),
          PlatformApplicationStatusFilter.underReview,
        ),
        tile(
          2,
          'Approved',
          'Successfully onboarded',
          metrics.approvedCount,
          Icons.check_circle_outline_rounded,
          const Color(0xFF059669),
          PlatformApplicationStatusFilter.approved,
        ),
        tile(
          3,
          'Corrections Required',
          'Awaiting resubmission',
          metrics.correctionsRequiredCount,
          Icons.edit_note_rounded,
          const Color(0xFFEA580C),
          PlatformApplicationStatusFilter.correctionsRequired,
        ),
        tile(
          4,
          'Rejected',
          'Declined applications',
          metrics.rejectedCount,
          Icons.cancel_outlined,
          const Color(0xFFE11D48),
          PlatformApplicationStatusFilter.rejected,
        ),
      ],
    );
  }
}
