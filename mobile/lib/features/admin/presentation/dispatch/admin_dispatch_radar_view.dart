import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/admin_dashboard_api.dart';
import '../../domain/admin_dispatch_radar.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _time(DateTime? d) =>
    d == null ? '' : '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Web `formatRemainingTime`: `mm:ss` until the offer expires.
String formatOfferCountdown(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return '00:00';
  final diff = expiresAt.difference(now);
  if (diff.inMilliseconds <= 0) return 'Expired';
  final total = diff.inSeconds;
  return '${_two(total ~/ 60)}:${_two(total % 60)}';
}

/// Web `getStatusBadgeClass` colour families.
Color radarStatusColor(String? status) {
  final s = (status ?? '').toUpperCase();
  if (s.contains('OFFER')) return const Color(0xFFB45309);
  if (s.contains('SEARCH') ||
      s.contains('DISPATCH') ||
      s.contains('RETRY') ||
      s.contains('WAITING')) {
    return const Color(0xFF0369A1);
  }
  if (s.contains('ASSIGN') || s.contains('ACCEPT'))
    return const Color(0xFF047857);
  if (s.contains('ROUTE') || s.contains('WAY')) return const Color(0xFF4338CA);
  if (s.contains('PROGRESS') || s.contains('ARRIV'))
    return const Color(0xFF7E22CE);
  if (s.contains('COMPLET')) return const Color(0xFF065F46);
  if (s.contains('DECLIN') ||
      s.contains('CANCEL') ||
      s.contains('FAIL') ||
      s.contains('EXPIRE') ||
      s.contains('SUPERSEDED')) {
    return const Color(0xFFBE123C);
  }
  return const Color(0xFF475569);
}

Widget _badge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: 0.2,
      ),
    ),
  );
}

Widget _statusBadge(String text) {
  final upper = text.toUpperCase();
  final (bg, border, fg) = switch (upper) {
    'COMPLETED' || 'ACCEPTED' || 'ASSIGNED' => (
      const Color(0xFFDCFCE7),
      const Color(0xFF86EFAC),
      const Color(0xFF15803D),
    ),
    'OFFERED' || 'OFFER ACTIVE' => (
      const Color(0xFFFEF3C7),
      const Color(0xFFFCD34D),
      const Color(0xFFB45309),
    ),
    'SEARCHING' || 'DISPATCHING' => (
      const Color(0xFFE0F2FE),
      const Color(0xFF7DD3FC),
      const Color(0xFF0369A1),
    ),
    'EN ROUTE' || 'ON THE WAY' => (
      const Color(0xFFE0E7FF),
      const Color(0xFFA5B4FC),
      const Color(0xFF4338CA),
    ),
    'IN PROGRESS' || 'ARRIVED' => (
      const Color(0xFFF3E8FF),
      const Color(0xFFD8B4FE),
      const Color(0xFF7E22CE),
    ),
    'CANCELLED' || 'DECLINED' || 'EXPIRED' || 'FAILED' || 'SUPERSEDED' => (
      const Color(0xFFFFE4E6),
      const Color(0xFFFDA4AF),
      const Color(0xFFBE123C),
    ),
    _ => (
      const Color(0xFFF1F5F9),
      const Color(0xFFCBD5E1),
      const Color(0xFF475569),
    ),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: border),
    ),
    child: Text(
      upper,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        color: fg,
        letterSpacing: 0.3,
      ),
    ),
  );
}

/// Read-only dispatch radar (Web parity: `AdminDispatchRadar.jsx`, the first
/// tab of `/workforce/admin/dispatch`).
class AdminDispatchRadarView extends ConsumerStatefulWidget {
  const AdminDispatchRadarView({super.key});

  static const filters = <(String, String)>[
    ('all', 'All Jobs'),
    ('offered', 'Offered'),
    ('searching', 'Searching'),
    ('assigned', 'Assigned'),
    ('en_route', 'En Route'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
  ];

  @override
  ConsumerState<AdminDispatchRadarView> createState() =>
      _AdminDispatchRadarViewState();
}

class _AdminDispatchRadarViewState
    extends ConsumerState<AdminDispatchRadarView> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _status = 'all';
  DispatchRadarData? _data;
  int? _selectedJobId;
  DispatchRadarJob? _detailJob;
  bool _loading = true;
  bool _loadingDetail = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final raw = await ref
          .read(adminDashboardApiProvider)
          .fetchDispatchRadar(
            jobId: _selectedJobId,
            status: _status,
            search: _search.text,
          );
      if (!mounted || seq != _seq) return;
      final parsed = DispatchRadarData.fromJson(raw);
      setState(() {
        _data = parsed;
        if (parsed.selectedJob != null) {
          _detailJob = parsed.selectedJob;
          _selectedJobId = parsed.selectedJob!.id;
        } else if (parsed.jobs.isNotEmpty) {
          if (_selectedJobId == null ||
              !parsed.jobs.any((j) => j.id == _selectedJobId)) {
            _selectedJobId = parsed.jobs.first.id;
            _detailJob = parsed.jobs.first;
          } else {
            _detailJob = parsed.jobs
                .where((j) => j.id == _selectedJobId)
                .firstOrNull;
          }
        } else {
          _selectedJobId = null;
          _detailJob = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load dispatch radar telemetry.';
      });
    }
  }

  Future<void> _onSelectJob(DispatchRadarJob job) async {
    if (_selectedJobId == job.id &&
        _detailJob != null &&
        _detailJob!.timeline.isNotEmpty)
      return;
    setState(() {
      _selectedJobId = job.id;
      _detailJob = job;
      _loadingDetail = true;
    });
    try {
      final raw = await ref
          .read(adminDashboardApiProvider)
          .fetchDispatchRadar(
            jobId: job.id,
            status: _status,
            search: _search.text,
          );
      if (!mounted) return;
      final parsed = DispatchRadarData.fromJson(raw);
      setState(() {
        _detailJob = parsed.selectedJob ?? job;
        _loadingDetail = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  void _openJobModal(DispatchRadarJob job) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) =>
          _RadarJobSheet(jobId: job.id, status: _status, search: _search.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final s = data?.summary;
    final jobs = data?.jobs ?? [];
    final currentSelected =
        _detailJob ??
        (jobs.isNotEmpty && _selectedJobId != null
            ? jobs.where((j) => j.id == _selectedJobId).firstOrNull
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Telemetry Metrics Strip ───────────────────────────────────────
        _metrics(s),
        const SizedBox(height: 10),

        // ── 2. Filter Chips ──────────────────────────────────────────────────
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AdminDispatchRadarView.filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final (key, label) = AdminDispatchRadarView.filters[i];
              final selected = key == _status;
              return ChoiceChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                selectedColor: const Color(0xFF2563EB),
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: selected ? const Color(0xFF2563EB) : AppColors.border,
                ),
                onSelected: (_) {
                  if (key == _status) return;
                  setState(() => _status = key);
                  _load();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // ── 3. Search Bar ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search by Job #, Service, Tech...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), _load);
                },
              ),
            ),
            IconButton(
              tooltip: 'Refresh Telemetry',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── 4. Active Queue Section Header ───────────────────────────────────
        Row(
          children: [
            Text(
              'ACTIVE QUEUE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 6),
            _badge('${jobs.length}', const Color(0xFF475569)),
            const Spacer(),
            Flexible(
              child: Text(
                'Read-Only Telemetry',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2.5),
                  SizedBox(height: 10),
                  Text(
                    'Streaming dispatch telemetry...',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          )
        else if (_error != null && data == null)
          _message(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFBE123C),
            title: 'DISPATCH RADAR UNAVAILABLE',
            body: _error!,
            action: ('Retry Radar Telemetry', _load),
          )
        else if (data == null || jobs.isEmpty)
          _status == 'all' && _search.text.isEmpty
              ? _message(
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF059669),
                  title: 'NO ACTIVE DISPATCH JOBS',
                  body:
                      'No bookings are currently in an active dispatch state.',
                )
              : _message(
                  icon: Icons.filter_alt_off_outlined,
                  color: AppColors.textMuted,
                  title: 'NO MATCHING JOBS',
                  body: 'No active jobs match the selected filter.',
                  action: (
                    'Reset Filters',
                    () {
                      _search.clear();
                      setState(() => _status = 'all');
                      _load();
                    },
                  ),
                )
        else ...[
          // Queue list
          for (final job in jobs)
            _queueRow(
              job: job,
              isSelected: job.id == _selectedJobId,
              onTap: () => _onSelectJob(job),
              onDoubleTap: () => _openJobModal(job),
            ),

          // ── 5. Selected Job Control Tower (Full High-Fidelity UI) ──────────
          if (currentSelected != null) ...[
            const SizedBox(height: 14),
            SelectedJobControlTower(
              job: currentSelected,
              isLoading: _loadingDetail,
            ),
          ],
        ],
      ],
    );
  }

  Widget _metrics(DispatchRadarSummary? s) {
    final items = [
      ('Active', s?.totalActive, const Color(0xFF0F172A)),
      ('Searching', s?.searching, const Color(0xFF0284C7)),
      ('Offered', s?.offered, const Color(0xFFD97706)),
      ('Assigned', s?.assigned, const Color(0xFF059669)),
      ('En Route', s?.enRoute, const Color(0xFF4F46E5)),
      ('In Progress', s?.inProgress, const Color(0xFF9333EA)),
      ('Completed', s?.completedToday, const Color(0xFF0F172A)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = availableWidth >= 330 ? 3 : 2;
        const spacing = 6.0;
        final itemWidth = (availableWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final (label, value, color) in items)
              Container(
                width: itemWidth.floorToDouble(),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      '${value ?? '—'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _message({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    (String, VoidCallback)? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: action.$2, child: Text(action.$1)),
          ],
        ],
      ),
    );
  }

  Widget _queueRow({
    required DispatchRadarJob job,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onDoubleTap,
  }) {
    final offer = job.currentOffer;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFF2563EB) : AppColors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: isSelected
            ? const [
                BoxShadow(
                  color: Color(0x182563EB),
                  blurRadius: 5,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${job.reference}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _badge(job.statusLabel, radarStatusColor(job.statusLabel)),
                  const Spacer(),
                  if (offer != null) _Countdown(expiresAt: offer.expiresAt),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                job.service,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Divider(height: 12, color: AppColors.border),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      offer != null
                          ? '→ ${offer.employeeName} (${offer.score?.toStringAsFixed(1) ?? '—'} pts)'
                          : job.assignedTechnicianName ??
                                'Attempt #${job.attemptCount ?? 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: offer != null
                            ? const Color(0xFFB45309)
                            : job.assignedTechnicianName != null
                            ? const Color(0xFF047857)
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    job.customerName ?? '',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live `mm:ss` offer countdown (ticks once a second while visible).
class _Countdown extends StatefulWidget {
  const _Countdown({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  @override
  void didUpdateWidget(covariant _Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) {
      _initTimer();
    }
  }

  void _initTimer() {
    _timer?.cancel();
    final exp = widget.expiresAt;
    if (exp == null || exp.isBefore(DateTime.now())) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.expiresAt == null ||
          widget.expiresAt!.isBefore(DateTime.now())) {
        _timer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _badge(
      '⏱ ${formatOfferCountdown(widget.expiresAt, DateTime.now())}',
      const Color(0xFFB45309),
    );
  }
}

/// Selected Job Control Tower: Unified header, DISPATCH JOURNEY vertical timeline,
/// and CANDIDATE EVALUATION SNAPSHOT table matching Web `AdminDispatchRadar.jsx`.
class SelectedJobControlTower extends StatefulWidget {
  const SelectedJobControlTower({
    super.key,
    required this.job,
    this.isLoading = false,
  });

  final DispatchRadarJob job;
  final bool isLoading;

  @override
  State<SelectedJobControlTower> createState() =>
      _SelectedJobControlTowerState();
}

class _SelectedJobControlTowerState extends State<SelectedJobControlTower> {
  int _attemptIndex = 0;
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant SelectedJobControlTower oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.id != widget.job.id) {
      _attemptIndex = 0;
      _isExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final offer = job.currentOffer;
    final attempts = job.attempts;
    final currentAttempt = attempts.isEmpty
        ? null
        : attempts[_attemptIndex.clamp(0, attempts.length - 1)];
    final candidates = currentAttempt?.candidates ?? job.candidateEvaluations;
    final shownCandidates = _isExpanded
        ? candidates
        : candidates.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Compact Selected Job Header Card ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Job # + Status Badge + Scheduled/Booked
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'JOB #${job.reference}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      _statusBadge(job.statusLabel),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                          children: [
                            const TextSpan(text: 'Scheduled: '),
                            TextSpan(
                              text:
                                  '${job.scheduledDate ?? 'Today'} ${job.scheduledTime ?? ''}'
                                      .trim(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Booked: ${job.createdAt != null ? _time(job.createdAt) : 'N/A'}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Service Title in Blue
              Text(
                job.service,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(height: 10),

              // Row 3: Assigned / Active Offer Info Banner
              if (offer != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (constraints.maxWidth - 20).clamp(
                                    80.0,
                                    double.infinity,
                                  ),
                                ),
                                child: Text(
                                  'Active Offer → ${offer.employeeName} (${offer.score?.toStringAsFixed(1) ?? '—'} pts)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Expires in: ',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF78350F),
                                ),
                              ),
                              _Countdown(expiresAt: offer.expiresAt),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                )
              else if (job.assignedTechnicianName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF16A34A),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Assigned: ${job.assignedTechnicianName}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF166534),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          job.unassignedReasonMessage ??
                              'Awaiting candidate ranking or retry schedule.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),

              // Row 4: Address + Customer
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          job.address ?? 'Textual address not specified',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                      children: [
                        const TextSpan(text: 'Customer: '),
                        TextSpan(
                          text: job.customerName ?? 'N/A',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 2. Primary Visual: DISPATCH JOURNEY Timeline ───────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Activity Icon + Title + Event count
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timeline_rounded,
                            size: 17,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 7),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (constraints.maxWidth - 28).clamp(
                                80.0,
                                double.infinity,
                              ),
                            ),
                            child: const Text(
                              'DISPATCH JOURNEY',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF334155),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${job.timeline.length} events',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),

              if (widget.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (job.timeline.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No dispatch journey events recorded yet.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: job.timeline.length,
                  itemBuilder: (context, i) {
                    final ev = job.timeline[i];
                    final isFirst = i == 0;
                    final isLast = i == job.timeline.length - 1;
                    return _TimelineEventTile(
                      event: ev,
                      isFirst: isFirst,
                      isLast: isLast,
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 3. CANDIDATE EVALUATION SNAPSHOT Section ─────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Purple icon + Title + "Captured at Dispatch Moment"
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 17,
                            color: Color(0xFF9333EA),
                          ),
                          const SizedBox(width: 7),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (constraints.maxWidth - 28).clamp(
                                80.0,
                                double.infinity,
                              ),
                            ),
                            child: const Text(
                              'CANDIDATE EVALUATION SNAPSHOT',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF334155),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Captured at Dispatch Moment',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),

              // Multi-attempt switcher chips (if multiple attempts exist)
              if (attempts.length > 1) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < attempts.length; i++)
                      ChoiceChip(
                        label: Text(
                          'Attempt #${attempts[i].attempt}${attempts[i].eligibleCount != null ? ' · ${attempts[i].eligibleCount} eligible' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: i == _attemptIndex
                                ? Colors.white
                                : const Color(0xFF475569),
                          ),
                        ),
                        selected: i == _attemptIndex,
                        selectedColor: const Color(0xFF9333EA),
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: BorderSide(
                          color: i == _attemptIndex
                              ? const Color(0xFF9333EA)
                              : const Color(0xFFE2E8F0),
                        ),
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _attemptIndex = i;
                          _isExpanded = false;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Table Content
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No candidate snapshot recorded for this attempt.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 440),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            color: const Color(0xFFF8FAFC),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    'RANK',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 170,
                                  child: Text(
                                    'TECHNICIAN',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    'DISTANCE',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 50,
                                  child: Text(
                                    'SCORE',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 74,
                                  child: Text(
                                    'RESULT',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),

                          // Table Body Rows
                          for (final (idx, c) in shownCandidates.indexed) ...[
                            if (idx > 0)
                              const Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                            Container(
                              color: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${c.rank}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 170,
                                    child: Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      c.distanceKm == null
                                          ? '—'
                                          : '${c.distanceKm} km',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      c.score?.toStringAsFixed(1) ?? '—',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 74,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _statusBadge(
                                        c.result ?? 'EVALUATED',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

              if (candidates.length > 5) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                    icon: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _isExpanded
                          ? 'Show fewer candidates'
                          : '+ ${candidates.length - 5} more candidates',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Timeline event tile with vertical connector line and color-coded dot.
class _TimelineEventTile extends StatelessWidget {
  const _TimelineEventTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final DispatchRadarEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isAccepted =
        event.eventType == 'EMPLOYEE_JOB_ACCEPTED' ||
        event.title.toLowerCase().contains('accepted');
    final isDeclined =
        event.eventType == 'OFFER_DECLINED' ||
        event.title.toLowerCase().contains('declined');
    final isExpired =
        event.eventType == 'OFFER_EXPIRED' ||
        event.title.toLowerCase().contains('expired');

    final dotColor = switch (event.badge) {
      'success' => const Color(0xFF10B981),
      'danger' => const Color(0xFFF43F5E),
      'warning' => const Color(0xFFF59E0B),
      _ =>
        isAccepted
            ? const Color(0xFF10B981)
            : isDeclined
            ? const Color(0xFFF43F5E)
            : isExpired
            ? const Color(0xFFF59E0B)
            : const Color(0xFF2563EB),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vertical connecting line and dot
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: isFirst ? 14 : 0,
                  bottom: isLast ? 14 : 0,
                  child: Container(width: 2, color: const Color(0xFFE2E8F0)),
                ),
                Positioned(
                  top: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.3),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Event Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        _time(event.timestamp),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF475569),
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (event.actor != null && event.actor!.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                        ),
                        children: [
                          const TextSpan(text: 'Actor: '),
                          TextSpan(
                            text: event.actor!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selected job "control tower" bottom sheet modal.
class _RadarJobSheet extends ConsumerStatefulWidget {
  const _RadarJobSheet({
    required this.jobId,
    required this.status,
    required this.search,
  });

  final int jobId;
  final String status;
  final String search;

  @override
  ConsumerState<_RadarJobSheet> createState() => _RadarJobSheetState();
}

class _RadarJobSheetState extends ConsumerState<_RadarJobSheet> {
  late final Future<DispatchRadarData> _future = ref
      .read(adminDashboardApiProvider)
      .fetchDispatchRadar(
        jobId: widget.jobId,
        status: widget.status,
        search: widget.search,
      )
      .then(DispatchRadarData.fromJson);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<DispatchRadarData>(
        future: _future,
        builder: (context, snap) {
          final job = snap.data?.selectedJob;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.hasError || job == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Failed to load dispatch radar telemetry.',
                    style: TextStyle(color: Color(0xFFBE123C)),
                  ),
                )
              else
                SelectedJobControlTower(job: job),
            ],
          );
        },
      ),
    );
  }
}
