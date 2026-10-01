// Developer tool (not a regression test): renders the Vendor Directory to PNGs
// with the real Roboto + Material Icons fonts so the design can be reviewed.
//   FLUTTER_ROOT=<sdk> flutter test tool/screenshot_vendor_directory.dart  (writes build/shots/*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_motion.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/domain/auth_user.dart';
import 'package:mobile/features/auth/presentation/auth_controller.dart';
import 'package:mobile/features/superadmin/vendors/domain/platform_vendor.dart';
import 'package:mobile/features/superadmin/vendors/presentation/superadmin_vendor_directory_screen.dart';
import 'package:mobile/features/superadmin/vendors/presentation/superadmin_vendor_providers.dart';

class _FakeAuth extends StateNotifier<AuthState> implements AuthController {
  _FakeAuth(AuthUser u) : super(AuthState.authenticated(u));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _loadFont(String family, List<String> files) async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? r'F:\flutter_windows_3.47.0-stable\flutter'}/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File('$dir/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  const out = String.fromEnvironment('SHOT_DIR', defaultValue: 'build/shots');

  Future<void> shoot(WidgetTester t, String name,
      {required bool dark, double width = 390, bool empty = false, bool cover = false}) async {
    AppColors.configure(brightness: dark ? Brightness.dark : Brightness.light, highContrast: false);
    addTearDown(() => AppColors.configure(brightness: Brightness.light, highContrast: false));
    final key = GlobalKey();
    t.view.physicalSize = Size(width * 2, 1500 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.resetPhysicalSize);
    const user = AuthUser(
      id: 1, username: 'sa', email: 'admin@caltrack.com', firstName: 'Admin', lastName: '',
      role: 'superadmin', companyId: 1, companyName: 'SEVO', isSuperuser: true, isPlatformAdmin: true,
      userType: 'platform_admin', employeeId: null, registrationStatus: 'approved',
    );
    final vendors = empty ? <PlatformVendor>[] : [
      const PlatformVendor(
        id: 12, companyName: 'Apex Engineering Ltd', slug: 'apex-eng', city: 'Bangalore', address: '',
        ownerName: 'John Doe', ownerEmail: 'john@apex.com', ownerPhone: '9876543210',
        tiedWorkersCount: 1, pendingInvitationsCount: 2,
      ),
      const PlatformVendor(
        id: 15, companyName: 'Pioneer Works', slug: 'pioneer-chennai', city: 'Chennai', address: '',
        ownerName: 'Priya Sharma', ownerEmail: 'priya@pioneer.com', ownerPhone: '9123456780',
        tiedWorkersCount: 4, pendingInvitationsCount: 0,
      ),
    ];
    await t.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FakeAuth(user)),
        platformVendorsDataProvider.overrideWith(
            (ref) async => PlatformVendorsResponse(vendors: vendors, totalCount: vendors.length)),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto', brightness: dark ? Brightness.dark : Brightness.light),
          home: const SuperAdminVendorDirectoryScreen(),
        ),
      ),
    ));
    await t.pump();
    await t.runAsync(() async {
      for (final a in ['sevo_name_white', 'sevo_wordmark_letters', 'sevo_wordmark_bar']) {
        await precacheImage(AssetImage('assets/images/$a.png'), t.element(find.byType(MaterialApp)));
      }
    });
    await t.pump();
    if (cover) {
      // Step the clock in frames so animations progress like on a device.
      for (var i = 0; i < 46; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
    } else {
      await t.pump(const Duration(milliseconds: 1600));
      await t.pump(const Duration(milliseconds: 600));
    }
    await t.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      Directory(out).createSync(recursive: true);
      File('$out/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
    });
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-light.ttf', 'roboto-black.ttf']);
    await _loadFont('MaterialIcons', ['materialicons-regular.otf']);
    final poppins = FontLoader('Poppins');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/Poppins-$f.ttf').readAsBytesSync();
      poppins.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await poppins.load();
  });

  testWidgets('shot light', (t) async {
    AppMotion.configure(reducedMotion: true);
    addTearDown(() => AppMotion.configure(reducedMotion: false));
    await shoot(t, 'vendor_light', dark: false);
  });

  testWidgets('shot dark', (t) async {
    AppMotion.configure(reducedMotion: true);
    addTearDown(() => AppMotion.configure(reducedMotion: false));
    await shoot(t, 'vendor_dark', dark: true);
  });

  testWidgets('shot empty', (t) async {
    AppMotion.configure(reducedMotion: true);
    addTearDown(() => AppMotion.configure(reducedMotion: false));
    await shoot(t, 'vendor_empty', dark: false, empty: true);
  });

  testWidgets('shot cover', (t) async {
    AppMotion.configure(reducedMotion: false);
    await shoot(t, 'vendor_cover', dark: false, cover: true);
  });
}
