// Developer tool: renders every Platform Governance illustration.
//   FLUTTER_ROOT=<sdk> flutter test tool/screenshot_module_art.dart  (writes build/shots/art.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_motion.dart';
import 'package:mobile/shared/widgets/sevo/sevo_module_art.dart';

void main() {
  testWidgets('art sheet', (t) async {
    AppMotion.configure(reducedMotion: true);
    final key = GlobalKey();
    t.view.physicalSize = const Size(900, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Row(children: [
            Expanded(
              child: Container(
                color: const Color(0xFF005965),
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final m in SevoModule.values) SevoModuleArt(module: m, size: 250),
                ]),
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.white,
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final m in SevoModule.values) SevoModuleArt(module: m, size: 250, onDark: false),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ));
    await t.pump();
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      Directory('build/shots').createSync(recursive: true);
      File('build/shots/art.png').writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
