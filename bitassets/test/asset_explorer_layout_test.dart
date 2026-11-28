import 'package:bitassets/pages/tabs/asset_explorer_page.dart';
import 'package:bitassets/providers/asset_analytics_provider.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:bitassets/providers/favorites_provider.dart';
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
  details: BitAssetDetails(commitment: 'c' * 64, socketAddrV4: '203.0.113.7:6004', encryptionPubkey: 'enc1qz4f8m'),
);
final _oil = BitAssetEntry(
  sequenceID: 22,
  hash: 'e81c5d2a9f${'a' * 54}',
  plaintextName: 'OIL',
  details: BitAssetDetails(),
);

class _RPC extends MockBitAssetsRPC {
  @override
  Future<List<BitAssetEntry>> listBitAssets() async => [_gold, _oil];

  @override
  Future<List<SidechainUTXO>> listUTXOs() async => [];
}

void main() {
  setUpAll(loadFontsForScreens);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    GetIt.I.registerSingleton<BitAssetsRPC>(_RPC());
    GetIt.I.registerSingleton<NotificationProvider>(NotificationProvider());
    GetIt.I.registerSingleton<BitAssetsProvider>(BitAssetsProvider());
    GetIt.I.registerSingleton<AssetAnalyticsProvider>(AssetAnalyticsProvider());
    GetIt.I.registerSingleton<FavoritesProvider>(FavoritesProvider());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpSailPage(const RepaintBoundary(key: screenKey, child: AssetExplorerTabPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Finder detailsPanel() => find.byWidgetPredicate((w) => w is SailSidePanel && w.title == 'Asset Details');

  testWidgets('the counts sit in a strip and the filters in one segmented control', (tester) async {
    await pumpPage(tester);

    expect(find.byType(SailStrip), findsOneWidget);
    expect(find.descendant(of: find.byType(SailStrip), matching: find.text('Total Assets')), findsOneWidget);
    final segments = tester.widget<SailSegments>(find.byType(SailSegments));
    expect(segments.labels, ['All', 'Favorites']);
    expect(find.text('Refresh'), findsNothing, reason: 'Refresh is an icon button');
  });

  testWidgets('a row click opens Asset Details with copy buttons in place of the old row expand', (tester) async {
    await pumpPage(tester);
    expect(detailsPanel(), findsNothing);

    await tester.tap(find.text('GOLD'));
    await tester.pump();

    expect(detailsPanel(), findsOneWidget);
    expect(tester.getSize(detailsPanel()).width, SailSidePanel.width);
    expect(find.descendant(of: detailsPanel(), matching: find.byType(CopyButton)), findsNWidgets(4));
    await captureScreen(tester, 'explorer');

    await tester.tap(find.byType(SailIconBoxButton).last);
    await tester.pump();
    expect(detailsPanel(), findsNothing);
  });

  testWidgets('the Favorites segment with no favorites shows its empty state', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Favorites').last);
    await tester.pump();

    expect(find.text('No favorite assets yet'), findsOneWidget);
    expect(find.text('Star assets to add them to your favorites'), findsOneWidget);
  });
}
