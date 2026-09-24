import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_header_card.dart';
import '../../../shared/widgets/sevo_brand_mark.dart';
import '../../../shared/widgets/theme_toggle_button.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../profile/presentation/profile_providers.dart';
import '../domain/job.dart';
import 'jobs_providers.dart';
import 'widgets/job_card.dart';
import 'widgets/job_card_skeleton.dart';
import 'widgets/job_category_filter_bar.dart';
import 'widgets/job_status_filter_bar.dart';
import 'widgets/new_offer_banner.dart';

/// Modern SEVO Jobs & Orders screen for Workforce mobile app.
///
/// Features:
/// 1. SEVO Header: Branded modern teal/blue gradient AppBar + search, notifications & refresh actions
/// 2. Interactive "My Orders & Jobs" heading section with live available & assigned job count
/// 3. Single dropdown Job Status filter: [ All Jobs (X) ▼ ]
/// 4. Single dropdown Job Category filter: [ All Categories ▼ ]
/// 5. Clean search field: [ 🔍 Search jobs, location, or category... ]
/// 6. Modern SEVO Job Cards with complete information, customer actions, and status action bars
/// 7. Pull-to-refresh and professional loading/empty/error states
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  JobStatusFilter _selectedStatus = JobStatusFilter.all;
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    ref.invalidate(activeJobsProvider);
    ref.invalidate(completedJobsProvider);
    ref.invalidate(employeeProfileProvider);
    ref.invalidate(shiftStatusProvider);
    await Future.wait([
      ref.read(activeJobsProvider.future),
      ref.read(completedJobsProvider.future),
    ]);
  }

  bool _isJobOffer(Job job) {
    return (job.isOffer || job.activeOffer?.status == 'OFFERED') &&
        job.activeOffer?.status != 'EXPIRED' &&
        job.activeOffer?.status != 'SUPERSEDED_BY_ACCEPTANCE' &&
        !(job.activeOffer?.isExpired ?? false) &&
        !job.isAssignedToCurrentEmployee;
  }

  bool _isJobCompleted(Job job) {
    return job.status.toLowerCase() == 'completed';
  }

  bool _isJobCancelled(Job job) {
    return ['cancelled', 'rejected', 'declined'].contains(job.status.toLowerCase());
  }

  bool _isJobInProgress(Job job) {
    return !_isJobOffer(job) && !_isJobCompleted(job) && !_isJobCancelled(job);
  }

  @override
  Widget build(BuildContext context) {
    final activeAsync = ref.watch(activeJobsProvider);
    final completedAsync = ref.watch(completedJobsProvider);
    final hasActiveJob = ref.watch(hasActiveJobProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    final activeJobs = activeAsync.valueOrNull ?? const <Job>[];
    final completedJobs = completedAsync.valueOrNull ?? const <Job>[];

    // Combine active & completed with deduplication by ID
    final allJobsMap = <int, Job>{};
    for (final j in activeJobs) {
      allJobsMap[j.id] = j;
    }
    for (final j in completedJobs) {
      allJobsMap[j.id] = j;
    }
    final allJobs = allJobsMap.values.toList();

    // Compute counts across all known jobs
    int newOffersCount = 0;
    int inProgressCount = 0;
    int completedCount = 0;
    int cancelledCount = 0;

    final availableCategories = <String>{};

    for (final j in allJobs) {
      if (j.serviceCategory != null && j.serviceCategory!.trim().isNotEmpty) {
        availableCategories.add(j.serviceCategory!.trim());
      }
      if (_isJobOffer(j)) {
        newOffersCount++;
      } else if (_isJobCompleted(j)) {
        completedCount++;
      } else if (_isJobCancelled(j)) {
        cancelledCount++;
      } else {
        inProgressCount++;
      }
    }

    // Filter by Status
    List<Job> statusFilteredJobs = switch (_selectedStatus) {
      JobStatusFilter.all => allJobs,
      JobStatusFilter.newOffers => allJobs.where(_isJobOffer).toList(),
      JobStatusFilter.inProgress => allJobs.where(_isJobInProgress).toList(),
      JobStatusFilter.completed => allJobs.where(_isJobCompleted).toList(),
      JobStatusFilter.cancelled => allJobs.where(_isJobCancelled).toList(),
    };

    // Filter by Category
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      final catQuery = _selectedCategory!.toLowerCase();
      statusFilteredJobs = statusFilteredJobs.where((j) {
        final cat = (j.serviceCategory ?? '').toLowerCase();
        final title = j.displayTitle.toLowerCase();
        return cat.contains(catQuery) || title.contains(catQuery);
      }).toList();
    }

    // Filter by Search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      statusFilteredJobs = statusFilteredJobs.where((j) {
        return j.requestId.toLowerCase().contains(q) ||
            j.displayTitle.toLowerCase().contains(q) ||
            (j.customerName?.toLowerCase().contains(q) ?? false) ||
            (j.address?.toLowerCase().contains(q) ?? false) ||
            (j.serviceCategory?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    final isLoading = (activeAsync.isLoading || completedAsync.isLoading) && allJobs.isEmpty;
    final hasError = activeAsync.hasError && allJobs.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B46),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
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
        title: const SevoHeaderTitle(
          fontSize: 22,
        ),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 22,
            ),
            tooltip: 'Search Jobs',
            onPressed: () {
              _searchFocusNode.requestFocus();
            },
          ),
          IconButton(
            icon: unreadCount > 0
                ? Badge(
                    label: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: const Color(0xFFEF4444),
                    child: const Icon(Icons.notifications_none_rounded, size: 23, color: Colors.white),
                  )
                : const Icon(Icons.notifications_none_rounded, size: 23, color: Colors.white),
            tooltip: 'Notifications',
            onPressed: () => context.push(AppRoutes.notifications),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            tooltip: 'Refresh Jobs',
            onPressed: _refreshAll,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: const Color(0xFF005965),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxl + 24,
            ),
            children: [
              // ── 1. "MY ORDERS & JOBS" CARD ────────────────────────────────────
              ModuleHeaderCard(
                title: 'My Orders & Jobs',
                subtitle: '${allJobs.length} ${allJobs.length == 1 ? 'Job' : 'Jobs'} Available & Assigned',
                icon: Icons.business_center_rounded,
                onTap: _refreshAll,
              ),
              const SizedBox(height: 12),

              // ── 2. NEW SERVICE OFFER ALERT BANNER ─────────────────────────────
              if (newOffersCount > 0)
                NewOfferBanner(
                  offerCount: newOffersCount,
                  onTap: () {
                    setState(() => _selectedStatus = JobStatusFilter.newOffers);
                  },
                ),

              // ── 3. STATUS FILTER ROW (Dropdown Chips) ────────────────────────
              JobStatusFilterBar(
                selectedFilter: _selectedStatus,
                allCount: allJobs.length,
                newOffersCount: newOffersCount,
                inProgressCount: inProgressCount,
                completedCount: completedCount,
                cancelledCount: cancelledCount,
                onFilterSelected: (filter) {
                  setState(() => _selectedStatus = filter);
                  if (filter == JobStatusFilter.completed) {
                    ref.read(completedJobsProvider.future);
                  }
                },
              ),
              const SizedBox(height: 10),

              // ── 4. CATEGORY FILTER ROW (Dropdown Chips) ──────────────────────
              JobCategoryFilterBar(
                selectedCategory: _selectedCategory,
                availableCategories: availableCategories.toList(),
                onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
              ),
              const SizedBox(height: 10),

              // ── 5. SEARCH FIELD ───────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _searchQuery.isNotEmpty
                        ? const Color(0xFF005965)
                        : AppColors.border,
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x04000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search jobs, location, or category...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 19,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              const SizedBox(height: 16),

              // ── 6. MAIN CONTENT AREA (JOB CARDS / SKELETON / EMPTY / ERROR) ───
              if (isLoading) ...[
                const JobCardSkeleton(),
                const JobCardSkeleton(),
                const JobCardSkeleton(),
              ] else if (hasError) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 44,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Unable to load workforce jobs',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please check your network connection and try again.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ElevatedButton.icon(
                          onPressed: _refreshAll,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.peacockNavy,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (statusFilteredJobs.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: EmptyState(
                    icon: _emptyIconForFilter(_selectedStatus),
                    title: _emptyTitleForFilter(_selectedStatus, isFiltering: _selectedCategory != null || _searchQuery.isNotEmpty),
                    message: _emptyMessageForFilter(_selectedStatus),
                  ),
                ),
                if (_selectedCategory != null || _searchQuery.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedCategory = null;
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                      label: const Text('Clear Filters & Search'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.isDark ? const Color(0xFF38BDF8) : AppColors.peacockBlue,
                        side: BorderSide(
                          color: AppColors.isDark ? const Color(0xFF028090) : AppColors.peacockBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ] else ...[
                for (final job in statusFilteredJobs)
                  JobCard(
                    job: job,
                    hasActiveJob: hasActiveJob,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _emptyIconForFilter(JobStatusFilter filter) {
    return switch (filter) {
      JobStatusFilter.all => Icons.work_off_outlined,
      JobStatusFilter.newOffers => Icons.bolt_outlined,
      JobStatusFilter.inProgress => Icons.play_disabled_outlined,
      JobStatusFilter.completed => Icons.task_alt_outlined,
      JobStatusFilter.cancelled => Icons.cancel_outlined,
    };
  }

  String _emptyTitleForFilter(JobStatusFilter filter, {bool isFiltering = false}) {
    if (isFiltering) {
      return 'No matching jobs found';
    }
    return switch (filter) {
      JobStatusFilter.all => 'No jobs found',
      JobStatusFilter.newOffers => 'No new offers available',
      JobStatusFilter.inProgress => 'No jobs in progress',
      JobStatusFilter.completed => 'No completed jobs yet',
      JobStatusFilter.cancelled => 'No cancelled jobs',
    };
  }

  String _emptyMessageForFilter(JobStatusFilter filter) {
    return switch (filter) {
      JobStatusFilter.all =>
        'New service opportunities and assigned jobs will appear here automatically.',
      JobStatusFilter.newOffers =>
        'When new exclusive job dispatches become available, you will receive an instant alert here.',
      JobStatusFilter.inProgress =>
        'Jobs that you accept and are actively working on will appear in this section.',
      JobStatusFilter.completed =>
        'Jobs you finish and confirm payment for will be recorded here.',
      JobStatusFilter.cancelled =>
        'Cancelled or declined service assignments will appear here.',
    };
  }
}
