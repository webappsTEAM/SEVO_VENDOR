import '../../../core/utils/json_parsing.dart';

/// Read-only dispatch observability from `GET /workforce/admin/dispatch-radar/`
/// (Web `AdminDispatchRadar.jsx`).
class DispatchRadarData {
  const DispatchRadarData({
    required this.summary,
    required this.jobs,
    this.selectedJob,
  });

  factory DispatchRadarData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const {};
    final selected = json['selected_job'];
    return DispatchRadarData(
      summary: DispatchRadarSummary(
        totalActive: parseInt(summary['total_active']) ?? 0,
        searching: parseInt(summary['searching']) ?? 0,
        offered: parseInt(summary['offered']) ?? 0,
        assigned: parseInt(summary['assigned']) ?? 0,
        enRoute: parseInt(summary['en_route']) ?? 0,
        inProgress: parseInt(summary['in_progress']) ?? 0,
        completedToday: parseInt(summary['completed_today']) ?? 0,
      ),
      jobs: _maps(json['jobs']).map(DispatchRadarJob.fromJson).toList(),
      selectedJob: selected is Map
          ? DispatchRadarJob.fromJson(Map<String, dynamic>.from(selected))
          : null,
    );
  }

  final DispatchRadarSummary summary;
  final List<DispatchRadarJob> jobs;
  final DispatchRadarJob? selectedJob;
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

class DispatchRadarSummary {
  const DispatchRadarSummary({
    required this.totalActive,
    required this.searching,
    required this.offered,
    required this.assigned,
    required this.enRoute,
    required this.inProgress,
    required this.completedToday,
  });

  final int totalActive;
  final int searching;
  final int offered;
  final int assigned;
  final int enRoute;
  final int inProgress;
  final int completedToday;
}

class DispatchRadarOffer {
  const DispatchRadarOffer({
    required this.employeeName,
    this.expiresAt,
    this.score,
  });

  final String employeeName;
  final DateTime? expiresAt;
  final double? score;
}

class DispatchRadarEvent {
  const DispatchRadarEvent({
    required this.eventType,
    required this.title,
    required this.description,
    this.timestamp,
    this.actor,
    this.badge,
  });

  final String eventType;
  final String title;
  final String description;
  final DateTime? timestamp;
  final String? actor;
  final String? badge;
}

class DispatchRadarCandidate {
  const DispatchRadarCandidate({
    required this.rank,
    required this.name,
    this.distanceKm,
    this.score,
    this.result,
  });

  factory DispatchRadarCandidate.fromJson(
    Map<String, dynamic> json,
    int index,
  ) {
    final name =
        parseString(json['display_name']) ??
        parseString(json['technician_name']) ??
        (json['employee_id'] != null
            ? '${parseString(json['employee_name']) ?? 'Technician'} · EMP #${json['employee_id']}'
            : parseString(json['employee_name']) ?? 'Technician');
    return DispatchRadarCandidate(
      rank: parseInt(json['rank']) ?? index + 1,
      name: name,
      distanceKm: parseDouble(json['distance_km']),
      score: parseDouble(json['score']),
      result: parseString(json['result']),
    );
  }

  final int rank;
  final String name;
  final double? distanceKm;
  final double? score;
  final String? result;
}

class DispatchRadarAttempt {
  const DispatchRadarAttempt({
    required this.attempt,
    this.eligibleCount,
    required this.candidates,
  });

  final int attempt;
  final int? eligibleCount;
  final List<DispatchRadarCandidate> candidates;
}

class DispatchRadarJob {
  const DispatchRadarJob({
    required this.id,
    this.requestId,
    required this.status,
    this.dispatchStatus,
    required this.service,
    this.customerName,
    this.assignedTechnicianName,
    this.attemptCount,
    this.currentOffer,
    this.address,
    this.createdAt,
    this.scheduledDate,
    this.scheduledTime,
    this.unassignedReasonMessage,
    this.timeline = const [],
    this.attempts = const [],
    this.candidateEvaluations = const [],
  });

  factory DispatchRadarJob.fromJson(Map<String, dynamic> json) {
    final offer = json['current_offer'];
    return DispatchRadarJob(
      id: parseInt(json['id']) ?? 0,
      requestId:
          parseString(json['request_id']) ?? parseString(json['reference']),
      status:
          parseString(json['status']) ??
          parseString(json['status_label']) ??
          '',
      dispatchStatus: parseString(json['dispatch_status']),
      service: parseString(json['service']) ?? 'Service Request',
      customerName: parseString(json['customer_name']),
      assignedTechnicianName: parseString(json['assigned_technician_name']),
      attemptCount: parseInt(json['attempt_count']),
      currentOffer: offer is Map
          ? DispatchRadarOffer(
              employeeName: parseString(offer['employee_name']) ?? 'Technician',
              expiresAt: parseDateTime(offer['expires_at']),
              score: parseDouble(offer['score']),
            )
          : null,
      address: parseString(json['address']),
      createdAt: parseDateTime(json['created_at']),
      scheduledDate: parseString(json['scheduled_date']),
      scheduledTime: parseString(json['scheduled_time']),
      unassignedReasonMessage: parseString(json['unassigned_reason_message']),
      timeline: [
        for (final e in _maps(json['timeline']))
          DispatchRadarEvent(
            eventType: parseString(e['event_type']) ?? '',
            title: parseString(e['title']) ?? '',
            description: parseString(e['description']) ?? '',
            timestamp: parseDateTime(e['timestamp']),
            actor: parseString(e['actor']),
            badge: parseString(e['badge']),
          ),
      ],
      attempts: [
        for (final (i, a) in _maps(json['attempts']).indexed)
          DispatchRadarAttempt(
            attempt: parseInt(a['attempt']) ?? i + 1,
            eligibleCount: parseInt(a['eligible_count']),
            candidates: [
              for (final (j, c) in _maps(a['candidates']).indexed)
                DispatchRadarCandidate.fromJson(c, j),
            ],
          ),
      ],
      candidateEvaluations: [
        for (final (j, c) in _maps(json['candidate_evaluations']).indexed)
          DispatchRadarCandidate.fromJson(c, j),
      ],
    );
  }

  final int id;
  final String? requestId;
  final String status;
  final String? dispatchStatus;
  final String service;
  final String? customerName;
  final String? assignedTechnicianName;
  final int? attemptCount;
  final DispatchRadarOffer? currentOffer;
  final String? address;
  final DateTime? createdAt;
  final String? scheduledDate;
  final String? scheduledTime;
  final String? unassignedReasonMessage;
  final List<DispatchRadarEvent> timeline;
  final List<DispatchRadarAttempt> attempts;
  final List<DispatchRadarCandidate> candidateEvaluations;

  String get reference => requestId ?? '$id';

  /// Web `normalizeStatusText`, with an active offer shown as OFFERED.
  String get statusLabel {
    if (currentOffer != null) return 'OFFERED';
    final s = (dispatchStatus ?? status).toUpperCase();
    if (s.isEmpty) return 'NEVER ATTEMPTED';
    return switch (s) {
      'OFFER_ACTIVE' => 'OFFERED',
      'DISPATCHING' || 'NEVER_ATTEMPTED' => 'SEARCHING',
      'RETRY_SCHEDULED' => 'RETRYING',
      _ => s.replaceAll('_', ' '),
    };
  }
}
