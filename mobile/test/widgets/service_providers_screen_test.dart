import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../support/dev_shot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/auth/domain/auth_user.dart';
import 'package:mobile/features/auth/presentation/auth_controller.dart';
import 'package:mobile/features/superadmin/providers/data/service_providers_repository.dart';
import 'package:mobile/features/superadmin/providers/domain/service_provider.dart';
import 'package:mobile/features/superadmin/providers/presentation/service_providers_screen.dart';

class _FakeAuth extends StateNotifier<AuthState> implements AuthController {
  _FakeAuth(AuthUser u) : super(AuthState.authenticated(u));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _superAdmin = AuthUser(
  id: 1, username: 'sa', email: 'sa@x.in', firstName: 'Super', lastName: 'Admin', role: 'superadmin',
  companyId: 1, companyName: 'SEVO', isSuperuser: true, isPlatformAdmin: true, userType: 'platform_admin',
  employeeId: null, registrationStatus: 'approved',
);
const _vendorAdmin = AuthUser(
  id: 2, username: 'va', email: 'va@x.in', firstName: 'Vendor', lastName: 'Admin', role: 'admin',
  companyId: 9, companyName: 'Cool Care', isSuperuser: false, isPlatformAdmin: false, isVendorAdmin: true,
  userType: 'vendor_admin', employeeId: null, registrationStatus: 'approved',
);

class _Repo extends ServiceProvidersRepository {
  _Repo() : super(Dio());

  final calls = <String>[];
  Object? failWith;
  NewServiceProvider? created;

  @override
  Future<List<ServiceProvider>> list({String q = '', bool? isActive}) async {
    calls.add('list:$q:${isActive ?? 'all'}');
    if (failWith != null) throw failWith!;
    return [
      ServiceProvider.fromJson({
        'id': 4,
        'company_name': 'Apex Electrical Solutions',
        'display_id': 'APEX',
        'industry': 'HVAC',
        'address': '100 Main Street',
        'website': 'https://apex.example',
        'is_active': true,
        'employee_count': 12,
        'created_at': '2026-08-01T10:00:00Z',
        'primary_admin': {'full_name': 'John Doe', 'username': 'apex_admin', 'email': 'john@apex.example', 'phone': '9876543210'},
      }),
      ServiceProvider.fromJson({'id': 5, 'company_name': 'Dormant Works', 'is_active': false, 'employee_count': 0}),
    ];
  }

  @override
  Future<String?> create(NewServiceProvider provider) async {
    calls.add('create:${provider.companyName}');
    created = provider;
    return 'Service Provider created.';
  }
}

Future<void> _pump(WidgetTester t, _Repo repo, {AuthUser user = _superAdmin}) async {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FakeAuth(user)),
      serviceProvidersRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(home: ServiceProvidersScreen()),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 1500));
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  test('model reads the Web payload', () {
    final p = ServiceProvider.fromJson({
      'id': 7, 'company_name': 'X', 'is_active': true, 'employee_count': '3',
      'primary_admin': {'username': 'x_admin'},
    });
    expect(p.identifier, 'ID: 7'); // no display id → "ID: {id}"
    expect(p.employeeCount, 3);
    expect(p.primaryAdmin!.displayName, 'x_admin');
  });

  testWidgets('shows title once, providers, technician counts and status', (t) async {
    final repo = _Repo();
    await _pump(t, repo);
    expect(find.text('Service Providers'), findsOneWidget);
    expect(find.text('Apex Electrical Solutions'), findsOneWidget);
    expect(find.text('APEX • HVAC'), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('12 Technicians'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('ID: 5'), findsOneWidget);
    expect(find.text('No admin assigned'), findsOneWidget);
    expect(repo.calls.first, 'list::all');
  });

  testWidgets('status chips and search re-query with the Web parameters', (t) async {
    final repo = _Repo();
    await _pump(t, repo);
    await t.tap(find.text('Active Only'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(repo.calls.last, 'list::true');
    await t.tap(find.text('Inactive Only'));
    await t.pump();
    expect(repo.calls.last, 'list::false');
    await t.enterText(find.byType(TextField), 'apex');
    await t.pump();
    expect(repo.calls.last, 'list:apex:false');
  });

  testWidgets('Inspect opens the provider dossier', (t) async {
    final repo = _Repo();
    await _pump(t, repo);
    await t.tap(find.text('Inspect').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Identifier: APEX'), findsOneWidget);
    expect(find.text('Primary Administrator'), findsOneWidget);
    expect(find.text('100 Main Street'), findsOneWidget);
    expect(find.text('View Technicians (12)'), findsOneWidget);
  });

  testWidgets('create validates like the Web, then posts and refreshes', (t) async {
    final repo = _Repo();
    await _pump(t, repo);
    await t.tap(find.byTooltip('Create Service Provider'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    await t.tap(find.text('Create Provider'));
    await t.pump();
    expect(find.text('Company Name is required.'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('create')), isEmpty);

    Finder field(String label) => find.widgetWithText(TextField, label);
    await t.enterText(field('Company Name *'), 'New Co');
    await t.tap(find.text('Create Provider'));
    await t.pump();
    expect(find.text('Admin Username is required.'), findsOneWidget);

    await t.enterText(field('Admin Username *'), 'new_admin');
    await t.enterText(field('Admin Email *'), 'a@new.co');
    await t.enterText(field('Initial Password *'), '123');
    await t.tap(find.text('Create Provider'));
    await t.pump();
    expect(find.text('Admin Password must be at least 6 characters.'), findsOneWidget);

    await t.enterText(field('Initial Password *'), '123456');
    await t.tap(find.text('Create Provider'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(repo.created!.companyName, 'New Co');
    expect(repo.created!.adminUsername, 'new_admin');
    expect(find.text('Service Provider created.'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('list')).length, 2); // reloaded
  });

  testWidgets('a 404 from the server shows a clear "not available" state', (t) async {
    final repo = _Repo()
      ..failWith = ServiceProvidersException.fromDio(
        DioException(requestOptions: RequestOptions(path: '/x'), response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: 404)),
        'fallback',
      );
    await _pump(t, repo);
    expect(find.text('Service Providers is not available on this server yet.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsNothing);
  });

  testWidgets('non-superadmins see the access-required state and no API call', (t) async {
    final repo = _Repo();
    await _pump(t, repo, user: _vendorAdmin);
    expect(find.text('Superadmin Access Required'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('dev screenshots', (t) async {
    await loadShotFonts();
    shotSurface(t, width: 360, height: 1500);
    await t.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FakeAuth(_superAdmin)),
        serviceProvidersRepositoryProvider.overrideWithValue(_Repo()),
      ],
      child: const MaterialApp(home: ServiceProvidersScreen()),
    ));
    await shoot(t, 'providers_360');
  }, skip: !shotsEnabled);
}
