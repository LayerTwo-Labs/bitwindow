import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

class _FakeConnection extends RPCConnection {
  _FakeConnection({required super.binaryType});

  @override
  Future<List<String>> binaryArgs() async => ['-signet'];

  @override
  Future<void> stopRPC() async {}

  @override
  Future<(double, double)> balance() async => (0.0, 0.0);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeConf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_SIGNET;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeEnforcerConf extends ChangeNotifier implements EnforcerConfProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader(SailFonts.inter);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('packages/sail_ui/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<Logger>(Logger(level: Level.off));
    getIt.registerSingleton<BitcoinConfProvider>(_FakeConf());
    getIt.registerSingleton<EnforcerConfProvider>(_FakeEnforcerConf());
    getIt.registerSingleton<BinaryProvider>(
      BinaryProvider.test(appDir: Directory.systemTemp, binaries: [BitcoinCore(), Enforcer()]),
    );
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> pumpCore(WidgetTester tester, {bool light = true}) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = light
        ? SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2)
        : SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2);
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: data,
          child: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('chain-settings-screen'),
              child: ChainSettingsModal(
                connection: _FakeConnection(binaryType: BinaryType.BINARY_TYPE_BITCOIND),
                onOpenConfConfigurator: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the head has the title, a "…" and a ×, the tabs are one segmented control', (tester) async {
    await pumpCore(tester);
    await _capture(tester, 'overview');

    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text(BitcoinCore().name));
    final menu = tester.getRect(find.byType(SailRowMenuButton));
    final close = tester.getRect(find.byType(SailIconBoxButton).last);
    expect(menu.center.dy, closeTo(title.center.dy, 2));
    expect(close.left, greaterThan(menu.right));
    expect(find.byType(SailSegments), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Close'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Wipe and reinstall'), findsNothing);
    expect(find.text('HASH VERIFICATION'), findsNothing, reason: 'the test binary has no hash data');

    await tester.tap(find.text('Paths'));
    await tester.pump();
    expect(find.text('Log path'), findsOneWidget);
    expect(find.text('Version'), findsNothing);
  });

  testWidgets('Reset to Block with no target marks the field', (tester) async {
    await pumpCore(tester, light: false);
    await tester.tap(find.text('Chain'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SailButton, 'Reset to Block'));
    await tester.pump();
    await _capture(tester, 'chain-no-target');

    final field = tester.widget<SailTextField>(find.byType(SailTextField));
    expect(field.errorText, 'Give a height or a block hash.');

    await tester.enterText(find.byType(TextField), '979400');
    await tester.pump();
    expect(tester.widget<SailTextField>(find.byType(SailTextField)).errorText, isNull);
  });

  testWidgets('the reset confirm has a × and one destructive Confirm', (tester) async {
    await pumpCore(tester);
    await tester.tap(find.text('Chain'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '979400');
    await tester.tap(find.widgetWithText(SailButton, 'Reset to Block'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Reset to block 979400?'), findsOneWidget);
    final confirm = tester.widget<SailButton>(find.widgetWithText(SailButton, 'Confirm').first);
    expect(confirm.variant, ButtonVariant.destructive);
    expect(find.widgetWithText(SailButton, 'Cancel'), findsNothing);
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('CHAIN_SETTINGS_SCREEN_DIR');
  if (directory.isEmpty) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('chain-settings-screen')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
