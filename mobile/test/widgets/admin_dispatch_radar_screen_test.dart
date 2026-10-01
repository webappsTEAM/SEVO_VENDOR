import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/data/admin_dashboard_api.dart';
import 'package:mobile/features/admin/domain/admin_dashboard_metrics.dart';
import 'package:mobile/features/admin/domain/eligible_technician.dart';
import 'package:mobile/features/admin/domain/fleet_member.dart';
import 'package:mobile/features/admin/presentation/admin_dashboard_providers.dart';
import 'package:mobile/features/admin/presentation/dispatch/admin_dispatch_screen.dart';
import 'package:mobile/features/jobs/domain/job.dart';

class FakeAdminDashboardApi implements AdminDashboardApi {
  @override
  Future<Map<String, dynamic>> fetchDispatchRadar({int? jobId, String? status, String? search}) async {
    return {
      'summary': {
        'total_active': 1,
        'searching': 0,
        'offered': 0,
        'assigned': 1,
        'en_route': 0,
        'in_progress': 0,
        'completed_today': 1,
      },
      'jobs': [
        {
          'id': 6980,
          'reference': 'PA6980',
          'service': 'Ceiling (Site Consultation)',
          'status_label': 'COMPLETED',
          'scheduled_date': '2026-09-29',
          'scheduled_time': '11:00 AM',
          'created_at': '2026-09-29T10:03:30.000Z',
          'customer_name': 'Admin s',
          'address': '05, Bagalur Rd, KCC Nagar, Nallur, Tamil Nadu 635109, India',
          'assigned_technician_name': 'Ramesh Komaru · EMP #8539',
          'timeline': [
            {
              'title': 'Booking Created',
              'description': 'Booking #PA6980 created for Ceiling (Site Consultation).',
              'timestamp': '2026-09-29T10:03:30.000Z',
              'actor': 'Admin s',
              'badge': 'info',
            },
            {
              'title': 'Dispatch Started (Attempt #1)',
              'description': 'Searching eligible technicians for paintings.',
              'timestamp': '2026-09-29T10:03:32.000Z',
              'actor': 'Dispatch Engine',
              'badge': 'info',
            },
            {
              'title': 'Candidates Evaluated (Attempt #1)',
              'description': 'Discovered 1 eligible ranked technician(s).',
              'timestamp': '2026-09-29T10:03:34.000Z',
              'actor': 'Dispatch Engine',
              'badge': 'info',
            },
            {
              'title': 'Offer Sent → Ramesh Komaru · EMP #8539',
              'description': 'Exclusive offer #16034 delivered (Score: 81.3).',
              'timestamp': '2026-09-29T10:03:34.000Z',
              'actor': 'Dispatch Engine',
              'badge': 'info',
            },
            {
              'title': 'Job Accepted by Ramesh Komaru · EMP #8539',
              'description': 'Ramesh Komaru · EMP #8539 accepted booking #PA6980.',
              'timestamp': '2026-09-29T10:04:00.000Z',
              'actor': 'Ramesh Komaru · EMP #8539',
              'badge': 'success',
            },
          ],
          'candidate_evaluations': [
            {
              'rank': 1,
              'technician_name': 'Ramesh Komaru · EMP #8539',
              'distance_km': 0.0,
              'score': 81.3,
              'result': 'ACCEPTED',
            }
          ],
        }
      ],
      'selected_job': {
        'id': 6980,
        'reference': 'PA6980',
        'service': 'Ceiling (Site Consultation)',
        'status_label': 'COMPLETED',
        'scheduled_date': '2026-09-29',
        'scheduled_time': '11:00 AM',
        'created_at': '2026-09-29T10:03:30.000Z',
        'customer_name': 'Admin s',
        'address': '05, Bagalur Rd, KCC Nagar, Nallur, Tamil Nadu 635109, India',
        'assigned_technician_name': 'Ramesh Komaru · EMP #8539',
        'timeline': [
          {
            'title': 'Booking Created',
            'description': 'Booking #PA6980 created for Ceiling (Site Consultation).',
            'timestamp': '2026-09-29T10:03:30.000Z',
            'actor': 'Admin s',
            'badge': 'info',
          },
          {
            'title': 'Dispatch Started (Attempt #1)',
            'description': 'Searching eligible technicians for paintings.',
            'timestamp': '2026-09-29T10:03:32.000Z',
            'actor': 'Dispatch Engine',
            'badge': 'info',
          },
          {
            'title': 'Candidates Evaluated (Attempt #1)',
            'description': 'Discovered 1 eligible ranked technician(s).',
            'timestamp': '2026-09-29T10:03:34.000Z',
            'actor': 'Dispatch Engine',
            'badge': 'info',
          },
          {
            'title': 'Offer Sent → Ramesh Komaru · EMP #8539',
            'description': 'Exclusive offer #16034 delivered (Score: 81.3).',
            'timestamp': '2026-09-29T10:03:34.000Z',
            'actor': 'Dispatch Engine',
            'badge': 'info',
          },
          {
            'title': 'Job Accepted by Ramesh Komaru · EMP #8539',
            'description': 'Ramesh Komaru · EMP #8539 accepted booking #PA6980.',
            'timestamp': '2026-09-29T10:04:00.000Z',
            'actor': 'Ramesh Komaru · EMP #8539',
            'badge': 'success',
          },
        ],
        'candidate_evaluations': [
          {
            'rank': 1,
            'technician_name': 'Ramesh Komaru · EMP #8539',
            'distance_km': 0.0,
            'score': 81.3,
            'result': 'ACCEPTED',
          }
        ],
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    AppColors.configure(brightness: Brightness.light, highContrast: false);
  });

  final sampleFleet = [
    const FleetMember(
      id: 1,
      name: 'Ramesh Kumar',
      employeeId: 'CALS-0001',
      phone: '9876543210',
      isOnline: true,
      currentAvailability: 'available',
      registrationStatus: 'approved',
      hasLocation: true,
      latitude: 12.9716,
      longitude: 77.5946,
      locationStatus: 'LIVE',
    ),
    const FleetMember(
      id: 2,
      name: 'Suresh Raina',
      employeeId: 'CALS-0002',
      phone: '9876543211',
      isOnline: false,
      currentAvailability: 'off_duty',
      registrationStatus: 'approved',
      hasLocation: false,
    ),
  ];

  final sampleJobs = [
    Job(
      id: 5259,
      requestId: 'PA5259',
      customerName: 'Priya Rajan',
      serviceTitle: 'AC Inspection & Gas Charge',
      status: 'unassigned',
      address: '123 MG Road, Bengaluru',
      latitude: 12.9720,
      longitude: 77.5950,
      totalAmount: 3650.0,
      paymentMethod: 'ONLINE',
      paymentStatus: 'pending',
      preferredDate: '2026-09-09',
      preferredTime: '10:00 AM',
      createdAt: DateTime(2026, 9, 9, 10, 0),
      isOffer: false,
      isAcceptedByCurrentEmployee: false,
      isAssignedToCurrentEmployee: false,
      canCancel: true,
    ),
  ];

  const sampleCandidates = [
    EligibleTechnician(
      id: 1,
      name: 'Ramesh Kumar',
      employeeId: 'CALS-0001',
      phone: '9876543210',
      isOnline: true,
      currentAvailability: 'available',
      registrationStatus: 'approved',
      distanceKm: 2.4,
      distanceBand: '2-5km',
      score: 50.0,
      isDispatchReady: true,
      gpsFreshness: 'LIVE',
      gateAudit: [
        GateAuditItem(gate: '1', name: 'Account Active', passed: true),
        GateAuditItem(gate: '2', name: 'Registration Approved', passed: true),
        GateAuditItem(gate: '3', name: 'Required Documents Approved', passed: true),
        GateAuditItem(gate: '4', name: 'Mandatory Compliance Valid', passed: true),
        GateAuditItem(gate: '5', name: 'Working Schedule Active', passed: true),
        GateAuditItem(gate: '6', name: 'Service / Skill Match', passed: true),
        GateAuditItem(gate: '7', name: 'Online & Available Presence', passed: true),
        GateAuditItem(gate: '8', name: 'Not On Leave', passed: true),
        GateAuditItem(gate: '9', name: 'Single-Job Concurrency Free', passed: true),
      ],
    ),
  ];

  Widget buildTestWidget({
    List<Job>? jobs,
    List<FleetMember>? fleet,
    List<EligibleTechnician>? candidates,
    String? jobId,
  }) {
    final dashboardData = AdminDashboardData(
      fleet: fleet ?? sampleFleet,
      jobs: jobs ?? sampleJobs,
    );

    return ProviderScope(
      overrides: [
        adminDashboardApiProvider.overrideWithValue(FakeAdminDashboardApi()),
        adminDashboardDataProvider.overrideWith((ref) => Future.value(dashboardData)),
        adminFleetListProvider.overrideWith((ref) => Future.value(fleet ?? sampleFleet)),
        adminPendingExtensionsProvider.overrideWith((ref) => Future.value([])),
        adminPendingServicesProvider.overrideWith((ref) => Future.value([])),
        adminLocationsProvider.overrideWith((ref) => Future.value([])),
        adminEligibleTechniciansProvider(5259).overrideWith(
          (ref) => Future.value(candidates ?? sampleCandidates),
        ),
      ],
      child: MaterialApp(
        home: AdminDispatchScreen(jobId: jobId),
      ),
    );
  }

  group('AdminDispatchRadarScreen Widget Tests', () {
    testWidgets('renders header title, subtitle, refresh fleet data, and live metric cards', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Main header
      expect(find.text('Dynamic Dispatch & Fleet Operations'), findsOneWidget);
      expect(
        find.text('Skill-based technician matching and real-time GPS telemetry radar'),
        findsOneWidget,
      );
      expect(find.text('Refresh Fleet Data'), findsOneWidget);

      // Metrics
      expect(find.text('Total Fleet'), findsOneWidget);
      expect(find.text('Total technicians/workforce tracked by dispatch.'), findsOneWidget);
      expect(find.text('Online & Ready'), findsOneWidget);
      expect(find.text('Available for work'), findsOneWidget);
      expect(find.text('Offline Fleet'), findsOneWidget);
      expect(find.text('Off duty / break'), findsOneWidget);
      expect(find.text('Active Bookings'), findsOneWidget);
      expect(find.text('In queue / assigned'), findsOneWidget);
    });

    testWidgets('renders Customer Service Requests section and request card details', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(jobId: 'PA5259'));
      await tester.pumpAndSettle();

      expect(find.text('1. Customer Service Requests (1)'), findsOneWidget);
      expect(find.text('PA5259'), findsOneWidget);
      expect(find.text('Priya Rajan'), findsOneWidget);
      expect(find.text('AC Inspection & Gas Charge'), findsOneWidget);
      expect(find.text('123 MG Road, Bengaluru'), findsOneWidget);
      expect(find.text('Auto-Dispatch Active'), findsWidgets);
    });

    testWidgets('renders Geo-Dispatch monitor, inspecting job, timeline, re-evaluate, banner, and candidate cards', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(jobId: 'PA5259'));
      await tester.pumpAndSettle();

      // Geo-Dispatch monitor header
      expect(find.text('2. Live Automated Geo-Dispatch Engine Monitor'), findsOneWidget);
      expect(find.textContaining('Inspecting Job: PA5259'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Re-evaluate Auto-Dispatch'), findsOneWidget);

      // Banner
      expect(
        find.textContaining('Autonomous Dispatch Active: Jobs are automatically assigned to nearest eligible technicians using the 9-Gate Employee Eligibility Engine'),
        findsOneWidget,
      );

      // Candidate Card
      expect(find.text('Ramesh Kumar'), findsWidgets);
      expect(find.text('CALS-0001 • 9876543210'), findsOneWidget);
      expect(find.text('GPS: LIVE'), findsOneWidget);
      expect(find.text('Match Score: 50'), findsOneWidget);
      expect(find.text('2.4 km away'), findsOneWidget);
      expect(find.text('✓ Qualified Candidate'), findsOneWidget);

      // 9 Gates
      expect(find.textContaining('Account Active'), findsOneWidget);
      expect(find.textContaining('Registration Approved'), findsOneWidget);
      expect(find.textContaining('Required Documents Approved'), findsOneWidget);
      expect(find.textContaining('Mandatory Compliance Valid'), findsOneWidget);
      expect(find.textContaining('Working Schedule Active'), findsOneWidget);
      expect(find.textContaining('Service / Skill Match'), findsOneWidget);
      expect(find.textContaining('Online & Available Presence'), findsOneWidget);
      expect(find.textContaining('Not On Leave'), findsOneWidget);
      expect(find.textContaining('Single-Job Concurrency Free'), findsOneWidget);
    });

    testWidgets('renders Selected Job Control Tower with header, timeline, and candidate evaluation snapshot matching Web', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // 1. Header Card Details
      expect(find.text('JOB #PA6980'), findsOneWidget);
      expect(find.text('COMPLETED'), findsWidgets);
      expect(find.text('Ceiling (Site Consultation)'), findsWidgets);
      expect(find.text('Assigned: Ramesh Komaru · EMP #8539'), findsOneWidget);
      expect(find.textContaining('05, Bagalur Rd'), findsOneWidget);
      expect(find.text('Admin s'), findsWidgets);

      // 2. DISPATCH JOURNEY Vertical Timeline
      expect(find.text('DISPATCH JOURNEY'), findsOneWidget);
      expect(find.text('5 events'), findsOneWidget);
      expect(find.text('Booking Created'), findsOneWidget);
      expect(find.text('Dispatch Started (Attempt #1)'), findsOneWidget);
      expect(find.text('Candidates Evaluated (Attempt #1)'), findsOneWidget);
      expect(find.text('Offer Sent → Ramesh Komaru · EMP #8539'), findsOneWidget);
      expect(find.text('Job Accepted by Ramesh Komaru · EMP #8539'), findsOneWidget);
      expect(find.textContaining('Dispatch Engine'), findsWidgets);

      // 3. CANDIDATE EVALUATION SNAPSHOT Table
      expect(find.text('CANDIDATE EVALUATION SNAPSHOT'), findsOneWidget);
      expect(find.text('Captured at Dispatch Moment'), findsOneWidget);
      expect(find.text('RANK'), findsOneWidget);
      expect(find.text('TECHNICIAN'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('SCORE'), findsOneWidget);
      expect(find.text('RESULT'), findsOneWidget);
      expect(find.text('Ramesh Komaru · EMP #8539'), findsWidgets);
      expect(find.text('0.0 km'), findsOneWidget);
      expect(find.text('81.3'), findsWidgets);
      expect(find.text('ACCEPTED'), findsWidgets);
    });
  });

  group('Admin Dispatch Radar Responsive Layout Tests', () {
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      testWidgets('renders without overflow at ${width}px width', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Dynamic Dispatch & Fleet Operations'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
