import 'package:bitassets/pages/tabs/reserve_register_page.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/rpc_mock_bitassets.dart';
import 'screen_capture.dart';
import 'test_utils.dart';

final _gold = BitAssetEntry(
  sequenceID: 14,
  hash: '7d3e91a0c4${'b' * 54}',
  plaintextName: 'GOLD',
  details: BitAssetDetails(commitment: 'c' * 64, socketAddrV4: '203.0.113.7:6004'),
);
final _silver = BitAssetEntry(
  sequenceID: 15,
  hash: 'c05b2e8f71${'a' * 54}',
  plaintextName: 'SILVER',
  details: BitAssetDetails(),
);

class _RPC extends MockBitAssetsRPC {
  @override
  Future<List<BitAssetEntry>> listBitAssets() async => [_gold, _silver];

  @override
  Future<List<SidechainUTXO>> listUTXOs() async => [];
}

void main() {
  setUpAll(loadFontsForScreens);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    GetIt.I.registerSingleton<BitAssetsRPC>(_RPC());
    GetIt.I.registerSingleton<BitAssetsProvider>(BitAssetsProvider());
    GetIt.I.registerSingleton<NotificationProvider>(NotificationProvider());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpSailPage(const RepaintBoundary(key: screenKey, child: BitAssetsTabPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Finder detailsPanel() => find.byWidgetPredicate((w) => w is SailSidePanel && w.title == 'BitAsset Details');

  testWidgets('a row click opens BitAsset Details in a 380 px panel', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('All Assets'));
    await tester.pump();
    expect(detailsPanel(), findsNothing);

    await tester.tap(find.text('GOLD'));
    await tester.pump();

    expect(detailsPanel(), findsOneWidget);
    expect(tester.getSize(detailsPanel()).width, SailSidePanel.width);
    expect(find.descendant(of: detailsPanel(), matching: find.text(_gold.hash)), findsOneWidget);
    expect(find.descendant(of: detailsPanel(), matching: find.text('203.0.113.7:6004')), findsOneWidget);
    expect(find.text('All BitAssets'), findsOneWidget, reason: 'the open panel keeps the selected tab');
    await captureScreen(tester, 'all_assets');
  });

  testWidgets('× and a tab change close the panel', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('All Assets'));
    await tester.pump();
    await tester.tap(find.text('GOLD'));
    await tester.pump();

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pump();
    expect(detailsPanel(), findsNothing);

    await tester.tap(find.text('SILVER'));
    await tester.pump();
    expect(detailsPanel(), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(detailsPanel(), findsNothing);
  });

  testWidgets('Reserve and Register sit side by side, and a reserve with no name shows the error', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('Register').first);
    await tester.pump();

    final reserveTitle = find.text('Reserve a name before registering');
    final registerTitle = find.text('Register a reserved name with data');
    expect(tester.getTopLeft(reserveTitle).dy, tester.getTopLeft(registerTitle).dy);
    expect(tester.getTopLeft(registerTitle).dx, greaterThan(tester.getTopRight(reserveTitle).dx));

    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Reserve'));
    await tester.pump();
    final field = find.byWidgetPredicate((w) => w is SailTextField && w.hintText == 'Enter name to reserve');
    expect(tester.widget<SailTextField>(field).errorText, isNotNull);
    await captureScreen(tester, 'register');
  });

  testWidgets('the Send form keeps a readable width with a full-width Send button', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('Send'));
    await tester.pump();

    final card = find.widgetWithText(SailCard, 'Send BitAsset');
    expect(tester.getSize(card.first).width, lessThanOrEqualTo(560));
    final send = find.byWidgetPredicate((w) => w is SailButton && w.label == 'Send');
    expect(tester.getSize(send).width, greaterThan(400));
  });
}
