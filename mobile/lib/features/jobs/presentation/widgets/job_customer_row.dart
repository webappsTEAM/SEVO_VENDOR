import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/job.dart';

/// Customer row inside a job card matching the SEVO design:
/// Circular avatar initial, customer name, and quick Call & Chat icon buttons.
class JobCustomerRow extends StatelessWidget {
  const JobCustomerRow({
    super.key,
    required this.job,
  });

  final Job job;

  Future<void> _callCustomer(BuildContext context) async {
    final phone = job.phone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer phone number not available.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not initiate call to $phone')),
      );
    }
  }

  Future<void> _messageCustomer(BuildContext context) async {
    final phone = job.phone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer contact not available for messaging.')),
      );
      return;
    }
    final uri = Uri(scheme: 'sms', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open SMS for $phone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (job.customerName != null && job.customerName!.trim().isNotEmpty)
        ? job.customerName!.trim()
        : 'Customer';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';

    return Row(
      children: [
        // Avatar circle with initial
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.isDark
                ? const Color(0xFF005965).withValues(alpha: 0.3)
                : const Color(0xFFE6F4F1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        // Quick Action Icon Buttons: Call & Chat
        _QuickCircularButton(
          icon: Icons.phone_rounded,
          tooltip: 'Call customer',
          onTap: () => _callCustomer(context),
        ),
        const SizedBox(width: 8),
        _QuickCircularButton(
          icon: Icons.chat_bubble_rounded,
          tooltip: 'Message customer',
          onTap: () => _messageCustomer(context),
        ),
      ],
    );
  }
}

class _QuickCircularButton extends StatelessWidget {
  const _QuickCircularButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.isDark
                ? const Color(0xFF005965).withValues(alpha: 0.3)
                : const Color(0xFFE6F4F1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
            color: AppColors.isDark ? const Color(0xFF38BDF8) : const Color(0xFF005965),
          ),
        ),
      ),
    );
  }
}
