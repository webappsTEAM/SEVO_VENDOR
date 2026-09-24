import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_theme.dart';

/// Helper dialogs for Super Admin application approval decisions.
class ApplicationActionDialog {
  ApplicationActionDialog._();

  /// Shows confirmation dialog to approve a technician application.
  static Future<bool?> showApproveDialog(
    BuildContext context, {
    required String technicianName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.successText,
              size: 22,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Approve Application?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This technician ($technicianName) will be approved for platform onboarding.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.successBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: AppColors.successText),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The technician will receive operational status and become ready for field dispatch.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.successText),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.successText,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Approve'),
          ),
        ],
      ),
    );
  }

  /// Shows dialog requiring a rejection reason for an application.
  static Future<String?> showRejectDialog(
    BuildContext context, {
    required String technicianName,
  }) {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Row(
          children: [
            Icon(
              Icons.cancel_rounded,
              color: AppColors.errorText,
              size: 22,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reject Application',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reject candidate application for $technicianName:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for rejection *',
                  hintText: 'e.g. Ineligible trade certification or document fraud...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                maxLines: 3,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Reason for rejection is required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorText,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(reasonController.text.trim());
              }
            },
            child: Text('Reject'),
          ),
        ],
      ),
    );
  }

  /// Shows dialog requiring correction instructions for the technician.
  static Future<String?> showRequestCorrectionDialog(
    BuildContext context, {
    required String technicianName,
  }) {
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Row(
          children: [
            Icon(
              Icons.edit_note_rounded,
              color: AppColors.warningText,
              size: 22,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Request Corrections',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request corrections from $technicianName:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Correction Notes *',
                  hintText: 'Please re-upload the required documents...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                maxLines: 3,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Correction notes are required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warningText,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(notesController.text.trim());
              }
            },
            child: Text('Send Request'),
          ),
        ],
      ),
    );
  }
}