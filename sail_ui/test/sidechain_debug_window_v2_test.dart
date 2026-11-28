import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

class _Rpc implements SidechainRPC {
  @override
  Future<dynamic> callRAW(String method, [List<dynamic>? params]) async => [
    {'address': '203.0.113.7:4009', 'status': 'Connected'},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('offline');
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<BinaryProvider>(
      BinaryProvider.test(appDir: Directory.systemTemp, binaries: [BitcoinCore(), Enforcer()]),
    );
  });

  tearDown(() async => GetIt.I.reset());

  Future<void> pumpWindow(WidgetTester tester, SailThemeStyle style) async {
    await tester.binding.setSurfaceSize(const Size(960, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style),
        child: MaterialApp(
          home: Scaffold(
            body: SidechainDebugWindow(rpc: _Rpc(), sidechainName: 'Thunder'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the v2 debug window shows its tabs as one segmented control with no card around it', (tester) async {
    await pumpWindow(tester, SailThemeStyle.bitwindowV2);

    expect(find.byType(SailSegments), findsOneWidget);
    expect(find.byType(InlineTabBar), findsNothing);
    expect(find.byType(SailCard), findsNothing);
    expect(find.text('Debug Information'), findsOneWidget);
    expect(find.text('Failed to load information'), findsOneWidget);

    await tester.tap(find.text('Processes'));
    await tester.pump();
    expect(find.text('Binaries'), findsOneWidget);
    expect(find.byType(SailStatusDot), findsNWidgets(2));

    await tester.tap(find.text('Peers'));
    await tester.pump();
    await tester.pump();
    expect(find.text('203.0.113.7:4009'), findsOneWidget);
    final title = tester.getRect(find.text('Peer Information'));
    final connect = tester.getRect(find.widgetWithText(SailButton, 'Connect Peer'));
    expect(connect.center.dy, closeTo(title.bottom, 12), reason: 'the actions sit in the tab head');
  });

  testWidgets('Connect to Peer opens with × and one Connect button in v2', (tester) async {
    await pumpWindow(tester, SailThemeStyle.bitwindowV2);
    await tester.tap(find.text('Peers'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(SailButton, 'Connect Peer'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to Peer'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(find.widgetWithText(SailButton, 'Cancel'), findsNothing);
    expect(find.byType(SailIconBoxButton), findsOneWidget);
  });

  testWidgets('the older styles keep the tab bar in a card', (tester) async {
    await pumpWindow(tester, SailThemeStyle.sail);

    expect(find.byType(InlineTabBar), findsOneWidget);
    expect(find.byType(SailSegments), findsNothing);
  });
}
