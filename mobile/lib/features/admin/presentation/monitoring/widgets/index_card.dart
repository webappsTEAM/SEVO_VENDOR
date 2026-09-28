import 'package:flutter/material.dart';

import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/domain/admin_monitoring.dart';

/// Expandable card representing a PostgreSQL database index shortcut.
class IndexCard extends StatefulWidget {
  const IndexCard({
    super.key,
    required this.index,
  });

  final DatabaseIndex index;

  @override
  State<IndexCard> createState() => _IndexCardState();
}

class _IndexCardState extends State<IndexCard> {
  bool _isExpanded = false;
  bool _showSql = false;

  @override
  Widget build(BuildContext context) {
    final idx = widget.index;
    final isUsed = idx.isUsed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x040A2540),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Collapsed View: Table Name, Index Name, Times Used, Status Badge
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          idx.tableName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      idx.indexSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isUsed
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isUsed
                              ? const Color(0xFFA7F3D0)
                              : AppColors.border,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isUsed ? 'USED' : 'NO SCANS',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isUsed
                              ? const Color(0xFF059669)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        idx.indexName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF003B46),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on_rounded, size: 12, color: Color(0xFFD97706)),
                        const SizedBox(width: 2),
                        Text(
                          '${idx.cumulativeScans} scans',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF003B46),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Expanded Details
                if (_isExpanded) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: AppSpacing.sm),

                  // Metrics Grid
                  Row(
                    children: [
                      _buildMetricCol('Size on Disk', idx.indexSize),
                      _buildMetricCol('Times Used', '${idx.cumulativeScans}'),
                      _buildMetricCol('Examined', '${idx.tuplesRead}'),
                      _buildMetricCol('Delivered', '${idx.tuplesFetched}'),
                    ],
                  ),

                  // Note / Explanation
                  if (idx.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        idx.note,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],

                  // View SQL Definition Button (only when definition is available)
                  if (idx.indexDefinition.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setState(() => _showSql = !_showSql),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showSql ? Icons.expand_less_rounded : Icons.code_rounded,
                              size: 14,
                              color: const Color(0xFF005965),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showSql ? 'Hide SQL Definition' : 'View SQL Definition',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF005965),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showSql) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF003B46),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SelectableText(
                          idx.indexDefinition,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            color: Color(0xFF93C5FD),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCol(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              color: Color(0xFF003B46),
            ),
          ),
        ],
      ),
    );
  }
}