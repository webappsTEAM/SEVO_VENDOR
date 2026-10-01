import 'package:flutter/material.dart';

import '../../../../shared/widgets/home_dashboard_widgets.dart';

/// "Workforce Operations Center" card at the top of the Super Admin home:
/// title, subtitle, Refresh Data and Open Dispatch Console.
class SuperAdminDashboardHeader extends StatelessWidget {
  const SuperAdminDashboardHeader({
    super.key,
    required this.onRefresh,
    this.isRefreshing = false,
  });

  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return HomeOpsCard(onRefresh: onRefresh, isRefreshing: isRefreshing);
  }
}
