import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

/// Non-empty makes the layout tests write a PNG of each screen into this folder.
const screenDir = String.fromEnvironment('BITASSETS_SCREEN_DIR');

const screenKey = ValueKey('bitassets-screen');

/// Loads the real fonts when the tests write screens, so the PNGs show text.
Future<void> loadFontsForScreens() async {
  if (screenDir.isEmpty) {
    return;
  }
  for (final (family, file) in [(SailFonts.inter, 'Inter'), (SailFonts.mono, 'IBMPlexMono')]) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('packages/sail_ui/assets/fonts/$file-$weight.ttf'));
    }
    await loader.load();
  }
}

/// Writes the widget under [screenKey] to `<screenDir>/<name>.png`.
Future<void> captureScreen(WidgetTester tester, String name) async {
  if (screenDir.isEmpty) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(screenKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(screenDir).create(recursive: true);
      await File('$screenDir/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
