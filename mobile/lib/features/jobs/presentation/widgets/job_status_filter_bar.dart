import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

enum JobStatusFilter {
  all,
  newOffers,
  inProgress,
  completed,
  cancelled,
}

/// Single dropdown control for Job Status filter matching SEVO design.
/// Shows EXACTLY ONE visible control: [ 💼 All Jobs (14) ▼ ]
/// Tapping it opens a dropdown menu with all status options.
class JobStatusFilterBar extends StatelessWidget {
  const JobStatusFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterSelected,
    required this.allCount,
    required this.newOffersCount,
    required this.inProgressCount,
    required this.completedCount,
    this.cancelledCount = 0,
  });

  final JobStatusFilter selectedFilter;
  final ValueChanged<JobStatusFilter> onFilterSelected;
  final int allCount;
  final int newOffersCount;
  final int inProgressCount;
  final int completedCount;
  final int cancelledCount;

  @override
  Widget build(BuildContext context) {
    final filters = <_StatusFilterItem>[
      _StatusFilterItem(
        filter: JobStatusFilter.all,
        label: 'All Jobs ($allCount)',
        icon: Icons.business_center_rounded,
      ),
      _StatusFilterItem(
        filter: JobStatusFilter.newOffers,
        label: 'New Offers ($newOffersCount)',
        icon: Icons.bolt_rounded,
        isAlert: newOffersCount > 0,
      ),
      _StatusFilterItem(
        filter: JobStatusFilter.inProgress,
        label: 'In Progress ($inProgressCount)',
        icon: Icons.play_arrow_rounded,
      ),
      _StatusFilterItem(
        filter: JobStatusFilter.completed,
        label: 'Completed ($completedCount)',
        icon: Icons.check_circle_outline_rounded,
      ),
      if (cancelledCount > 0 || selectedFilter == JobStatusFilter.cancelled)
        _StatusFilterItem(
          filter: JobStatusFilter.cancelled,
          label: 'Cancelled ($cancelledCount)',
          icon: Icons.cancel_outlined,
        ),
    ];

    final currentItem = filters.firstWhere(
      (f) => f.filter == selectedFilter,
      orElse: () => filters.first,
    );

    final isFiltered = selectedFilter != JobStatusFilter.all;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFiltered ? const Color(0xFF005965) : AppColors.border,
          width: isFiltered ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060A2540),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<JobStatusFilter>(
        tooltip: 'Select Job Status',
        onSelected: onFilterSelected,
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: AppColors.surface,
        elevation: 6,
        constraints: const BoxConstraints(minWidth: 280),
        itemBuilder: (context) => filters.map((f) {
          final isSelected = f.filter == selectedFilter;
          return PopupMenuItem<JobStatusFilter>(
            value: f.filter,
            child: Row(
              children: [
                Icon(
                  f.icon,
                  size: 19,
                  color: isSelected ? const Color(0xFF005965) : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF005965) : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Color(0xFF005965),
                  ),
              ],
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                currentItem.icon,
                size: 20,
                color: const Color(0xFF005965),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentItem.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusFilterItem {
  const _StatusFilterItem({
    required this.filter,
    required this.label,
    required this.icon,
    this.isAlert = false,
  });

  final JobStatusFilter filter;
  final String label;
  final IconData icon;
  final bool isAlert;
}
