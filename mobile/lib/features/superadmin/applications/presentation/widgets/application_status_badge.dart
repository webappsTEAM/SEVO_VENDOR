import 'package:flutter/material.dart';

import '../../../../../shared/widgets/sevo/sevo_controls.dart';

/// Semantic status badge for platform application statuses.
class ApplicationStatusBadge extends StatelessWidget {
  const ApplicationStatusBadge({
    super.key,
    required this.status,
    this.dense = false,
  });

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase().trim();
    final (String label, SevoTone tone, IconData icon) = switch (normalized) {
      'submitted' ||
      'pending' => ('Pending Review', SevoTone.warning, Icons.schedule_rounded),
      'under_review' => ('Under Review', SevoTone.info, Icons.search_rounded),
      'approved' ||
      'active' => ('Approved', SevoTone.success, Icons.check_circle_rounded),
      'correction_required' => (
        'Corrections Required',
        SevoTone.warning,
        Icons.edit_note_rounded,
      ),
      'rejected' => ('Rejected', SevoTone.error, Icons.cancel_rounded),
      _ => (_humanize(status), SevoTone.neutral, Icons.help_outline_rounded),
    };
    return SevoBadge(label: label, tone: tone, icon: icon);
  }

  static String _humanize(String raw) {
    final s = raw.replaceAll('_', ' ').trim();
    if (s.isEmpty) return 'Unknown';
    return s[0].toUpperCase() + s.substring(1);
  }
}
