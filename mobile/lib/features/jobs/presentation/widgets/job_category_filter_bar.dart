import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'category_helper.dart';

/// Single dropdown control for Category filter matching SEVO design.
/// Shows EXACTLY ONE visible control: [ ▦ All Categories ▼ ]
/// Tapping it opens a dropdown menu with all category options.
class JobCategoryFilterBar extends StatelessWidget {
  const JobCategoryFilterBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.availableCategories = const [],
  });

  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;
  final List<String> availableCategories;

  @override
  Widget build(BuildContext context) {
    // Combine standard categories and any extra dynamic categories from jobs
    final allCategoryNames = <String>[];
    for (final standard in kStandardServiceCategories) {
      allCategoryNames.add(standard.name);
    }
    for (final extra in availableCategories) {
      if (extra.trim().isNotEmpty &&
          !allCategoryNames.any((c) => c.toLowerCase() == extra.toLowerCase())) {
        allCategoryNames.add(extra.trim());
      }
    }

    final isAllSelected = selectedCategory == null || selectedCategory!.isEmpty;
    final displayLabel = isAllSelected ? 'All Categories' : selectedCategory!;
    final displayIcon = isAllSelected ? Icons.apps_rounded : iconForCategory(selectedCategory);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: !isAllSelected
              ? const Color(0xFF005965)
              : AppColors.border,
          width: !isAllSelected ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060A2540),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<String?>(
        tooltip: 'Select Category',
        onSelected: onCategorySelected,
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: AppColors.surface,
        elevation: 6,
        constraints: const BoxConstraints(minWidth: 280),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(
                  Icons.apps_rounded,
                  size: 19,
                  color: isAllSelected ? const Color(0xFF005965) : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'All Categories',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isAllSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isAllSelected ? const Color(0xFF005965) : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isAllSelected)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Color(0xFF005965),
                  ),
              ],
            ),
          ),
          ...allCategoryNames.map((cat) {
            final isCatSelected = !isAllSelected && cat.toLowerCase() == selectedCategory!.toLowerCase();
            return PopupMenuItem<String?>(
              value: cat,
              child: Row(
                children: [
                  Icon(
                    iconForCategory(cat),
                    size: 19,
                    color: isCatSelected ? const Color(0xFF005965) : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isCatSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isCatSelected ? const Color(0xFF005965) : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isCatSelected)
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Color(0xFF005965),
                    ),
                ],
              ),
            );
          }),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                displayIcon,
                size: 20,
                color: const Color(0xFF005965),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  displayLabel,
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
