// Developer-only screenshot helper. Every hook using it is skipped unless the
// suite is run with --dart-define=SHOTS=true, so it never affects normal runs.
//   FLUTTER_ROOT=<sdk> flutter test --dart-define=SHOTS=true <file>   → build/shots/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_theme.dart';

const shotsEnabled = bool.fromEnvironment('SHOTS');

/// Overrides the screenshot width (e.g. `--dart-define=SHOT_W=320`).
const _shotWidth = int.fromEnvironment('SHOT_W');

/// `--dart-define=SHOT_DARK=true` renders the dark theme.
const _shotDark = bool.fromEnvironment('SHOT_DARK');

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// Loads Roboto, Material Icons and Poppins so screenshots use the real fonts.
Future<void> loadShotFonts() async {
  AppColors.configure(brightness: _shotDark ? Brightness.dark : Brightness.light, highContrast: false);
  addTearDown(() => AppColors.configure(brightness: Brightness.light, highContrast: false));
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'F:/flutter_windows_3.47.0-stable/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  await _font('Roboto', ['$dir/roboto-regular.ttf', '$dir/roboto-medium.ttf', '$dir/roboto-bold.ttf']);
  await _font('MaterialIcons', ['$dir/materialicons-regular.otf']);
  await _font('Poppins', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Poppins-$w.ttf']);
}

/// Sizes the test surface like a phone (`width` logical px) for a screenshot.
void shotSurface(WidgetTester t, {double width = 390, double height = 2000}) {
  if (_shotWidth > 0) width = _shotWidth.toDouble();
  t.view.physicalSize = Size(width * 2, height * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// Steps the clock in frames (so animations progress like on a device), then
/// writes `build/shots/<name>.png`.
Future<void> shoot(WidgetTester t, String name, {int frames = 130}) async {
  for (final img in ['sevo_name_white', 'sevo_wordmark_letters', 'sevo_wordmark_bar']) {
    await t.runAsync(() => precacheImage(AssetImage('assets/images/$img.png'), t.element(find.byType(MaterialApp))));
  }
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/$name${_shotWidth > 0 ? '_w$_shotWidth' : ''}${_shotDark ? '_dark' : ''}.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
