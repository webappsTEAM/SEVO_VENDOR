import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/jobs/presentation/jobs_providers.dart';
import '../../features/notifications/presentation/notifications_providers.dart';
import '../../features/profile/presentation/profile_providers.dart';
import '../../routing/app_routes.dart';
import 'sevo_brand_mark.dart';
import 'theme_toggle_button.dart';
import 'workforce_avatar.dart';

/// The official Workforce Mobile Header / AppBar.
/// Features:
/// - Left: Calservices brand icon badge + Company Name + "WORKFORCE" tag
/// - Right: Search icon + Notification bell with unread badge + Circular profile avatar
/// - Optional Sub-header: Live workforce status (AVAILABLE / ON JOB / OFFLINE)
class WorkforceAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const WorkforceAppBar({
    super.key,
    this.titleText,
    this.showBrand = true,
    this.showSearch = true,
    this.showNotifications = true,
    this.showAvatar = true,
    this.showStatusSubBar = false,
    this.showDrawerMenu = false,
    this.onSearchPressed,
  });

  final String? titleText;
  final bool showBrand;
  final bool showSearch;
  final bool showNotifications;
  final bool showAvatar;
  final bool showStatusSubBar;
  final bool showDrawerMenu;
  final VoidCallback? onSearchPressed;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (showStatusSubBar ? 36.0 : 0.0),
      );

  void _defaultSearchAction(BuildContext context) {
    showSearchDialog(context);
  }

  static void showSearchDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => const _QuickSearchSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final profileAsync = ref.watch(employeeProfileProvider);
    // Only subscribe to the technician workload when the status sub-bar is
    // actually rendered. hasActiveJobProvider resolves through
    // activeJobsProvider, which hits GET /workforce/jobs/?status=active —
    // watching it unconditionally fired that request on every screen using
    // this AppBar (including all admin screens, where the value is unused
    // and the same endpoint is already the slow one being loaded).
    final hasActiveJob = showStatusSubBar ? ref.watch(hasActiveJobProvider) : false;
    final isOnline = profileAsync.valueOrNull?.isOnline ?? false;

    final displayName = user?.displayName ?? 'Tech';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'T';
    final photoUrl = profileAsync.valueOrNull?.avatar;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF003B46), // Deep rich teal
              Color(0xFF005965), // Teal
              Color(0xFF028090), // Cyan/Teal accent
            ],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        ),
      ),
      titleSpacing: showDrawerMenu ? 0 : AppSpacing.md,
      leading: showDrawerMenu
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                tooltip: 'Navigation Menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      title: (titleText != null && !showBrand) || (titleText != null && titleText!.isNotEmpty)
          ? Text(
              titleText!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            )
          : const SevoHeaderTitle(fontSize: 22),
      actions: [
        const ThemeToggleButton(),
        if (showSearch)
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22, color: Colors.white),
            tooltip: 'Search Jobs',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: onSearchPressed ?? () => _defaultSearchAction(context),
          ),
        if (showNotifications)
          IconButton(
            icon: unreadCount > 0
                ? Badge(
                    label: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: const Color(0xFFEF4444),
                    child: const Icon(Icons.notifications_outlined, size: 22, color: Colors.white),
                  )
                : const Icon(Icons.notifications_outlined, size: 22, color: Colors.white),
            tooltip: 'Notifications',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => context.push(AppRoutes.notifications),
          ),
        if (showAvatar)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: AppSpacing.md),
            child: PopupMenuButton<String>(
              tooltip: 'Profile & Account',
              offset: const Offset(0, 48),
              elevation: 8,
              shadowColor: const Color(0x28000000),
              color: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: AppColors.border,
                  width: 1.0,
                ),
              ),
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
              onSelected: (value) async {
                if (value == 'profile') {
                  context.push(AppRoutes.moreProfile);
                } else if (value == 'settings') {
                  context.push(AppRoutes.moreSettings);
                } else if (value == 'logout') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.border, width: 1.0),
                      ),
                      title: Text(
                        'Sign Out',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      content: Text(
                        'Are you sure you want to sign out of Workforce?',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dCtx).pop(false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(dCtx).pop(true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(authControllerProvider.notifier).logout();
                  }
                }
              },
              itemBuilder: (context) {
                final isAdmin = user?.isAdmin == true;
                final roleLabel = isAdmin ? 'ADMIN' : 'TECHNICIAN';

                return [
                  PopupMenuItem<String>(
                    enabled: false,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? (AppColors.isDark ? const Color(0xFF78350F).withValues(alpha: 0.4) : const Color(0xFFFEF3C7))
                                : (AppColors.isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.4) : const Color(0xFFEFF6FF)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isAdmin
                                  ? (AppColors.isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A))
                                  : (AppColors.isDark ? const Color(0xFF3B82F6) : const Color(0xFFBFDBFE)),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            roleLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: isAdmin
                                  ? (AppColors.isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E))
                                  : (AppColors.isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E40AF)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem<String>(
                    value: 'profile',
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'My Profile',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: Color(0xFFEF4444),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Sign out',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ];
              },
              child: WorkforceAvatar(
                imageUrl: photoUrl,
                name: displayName,
                initial: initial,
                radius: 16,
                borderColor: Colors.white.withValues(alpha: 0.8),
                borderWidth: 1.5,
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
      ],
      bottom: showStatusSubBar
          ? PreferredSize(
              preferredSize: const Size.fromHeight(36),
              child: _StatusSubBar(
                hasActiveJob: hasActiveJob,
                isOnline: isOnline,
              ),
            )
          : null,
    );
  }
}

class _StatusSubBar extends StatelessWidget {
  const _StatusSubBar({
    required this.hasActiveJob,
    required this.isOnline,
  });

  final bool hasActiveJob;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final statusText = hasActiveJob
        ? 'ON JOB (BUSY)'
        : (isOnline ? 'AVAILABLE FOR DISPATCH' : 'OFFLINE');

    final statusColor = hasActiveJob
        ? const Color(0xFFF59E0B)
        : (isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF002830).withValues(alpha: 0.75),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          bottom: BorderSide(color: const Color(0xFF005965).withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7.5,
            height: 7.5,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.7),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'WORKFORCE STATUS:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFFBAE6FD), // Sky-200 for maximum readability on Peacock
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: statusColor,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickSearchSheet extends ConsumerStatefulWidget {
  const _QuickSearchSheet();

  @override
  ConsumerState<_QuickSearchSheet> createState() => _QuickSearchSheetState();
}

class _QuickSearchSheetState extends ConsumerState<_QuickSearchSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeJobs = ref.watch(activeJobsProvider).valueOrNull ?? [];
    final filtered = _query.isEmpty
        ? activeJobs
        : activeJobs.where((j) {
            final q = _query.toLowerCase();
            return j.requestId.toLowerCase().contains(q) ||
                j.displayTitle.toLowerCase().contains(q) ||
                (j.customerName?.toLowerCase().contains(q) ?? false) ||
                (j.address?.toLowerCase().contains(q) ?? false);
          }).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Search Jobs & Requests',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search by ID (e.g. SR-), customer, or title...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              isDense: true,
            ),
            onChanged: (val) => setState(() => _query = val.trim()),
          ),
          const SizedBox(height: AppSpacing.md),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _query.isEmpty ? 'No active jobs found.' : 'No results matching "$_query"',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (ctx, idx) {
                  final job = filtered[idx];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${job.requestId} — ${job.displayTitle}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    subtitle: job.address != null
                        ? Text(job.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push('/jobs/${job.id}');
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
