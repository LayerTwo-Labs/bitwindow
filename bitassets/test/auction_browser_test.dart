import 'package:bitassets/pages/tabs/auction_browser_page.dart';
import 'package:bitassets/providers/asset_analytics_provider.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:bitassets/providers/favorites_provider.dart';
import 'package:bitassets/providers/price_alert_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/rpc_mock_bitassets.dart';
import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuctionRPC rpc;

  setUpAll(() async {
    final inter = FontLoader(SailFonts.inter);
    for (final weight in ['Regular', 'Bold']) {
      inter.addFont(rootBundle.load('packages/sail_ui/assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    rpc = AuctionRPC();
    GetIt.I.registerSingleton<BitAssetsRPC>(rpc);
    GetIt.I.registerLazySingleton<NotificationProvider>(() => NotificationProvider());
    GetIt.I.registerLazySingleton<BitAssetsProvider>(
      () => BitAssetsProvider(),
      dispose: (provider) => provider.dispose(),
    );
    GetIt.I.registerLazySingleton<AssetAnalyticsProvider>(
      () => AssetAnalyticsProvider(),
      dispose: (provider) => provider.dispose(),
    );
    GetIt.I.registerLazySingleton<FavoritesProvider>(
      () => FavoritesProvider(),
      dispose: (provider) => provider.dispose(),
    );
    GetIt.I.registerLazySingleton<PriceAlertProvider>(
      () => PriceAlertProvider(),
      dispose: (provider) => provider.dispose(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  for (final sort in [AuctionSort.priceAsc, AuctionSort.priceDesc]) {
    testWidgets('provider refresh updates prices and ${sort.name} order', (tester) async {
      GetIt.I.get<AssetAnalyticsProvider>().setAuctionSort(sort);
      await tester.pumpSailPage(const AuctionBrowserTabPage());
      await tester.pumpAndSettle();

      expect(find.text('Current Block: 101'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('79'), findsOneWidget);
      final firstAuction = find.text('aaaaaaaaaaaaaaaa...');
      final secondAuction = find.text('bbbbbbbbbbbbbbbb...');
      expect(
        tester.getTopLeft(firstAuction).dy < tester.getTopLeft(secondAuction).dy,
        sort == AuctionSort.priceDesc,
      );

      rpc.height = 105;
      await GetIt.I.get<BitAssetsProvider>().fetch();
      await tester.pumpAndSettle();

      expect(find.text('Current Block: 105'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('75'), findsOneWidget);
      expect(find.text('90'), findsNothing);
      expect(find.text('79'), findsNothing);
      expect(
        tester.getTopLeft(firstAuction).dy < tester.getTopLeft(secondAuction).dy,
        sort == AuctionSort.priceAsc,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.I.reset();
    });
  }

  testWidgets('the Upcoming badge fits its column on one line', (tester) async {
    rpc.upcoming = true;
    await tester.pumpSailPage(const AuctionBrowserTabPage());
    await tester.pumpAndSettle();

    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.descendant(of: find.text('Upcoming'), matching: find.byType(RichText)))
        .toList();
    expect(paragraphs, hasLength(1));
    expect(find.text('Upcoming 1'), findsOneWidget);
    for (final paragraph in paragraphs) {
      final oneLine = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      expect(paragraph.size.height, oneLine.height);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });

  testWidgets('a row click opens the auction panel with Bid as its one button', (tester) async {
    await tester.pumpSailPage(const AuctionBrowserTabPage());
    await tester.pumpAndSettle();
    expect(_panel(), findsNothing);

    await tester.tap(find.text('aaaaaaaaaaaaaaaa...'));
    await tester.pumpAndSettle();

    expect(_panel(), findsOneWidget);
    expect(tester.getSize(_panel()).width, SailSidePanel.width);
    final buttons = find.descendant(of: _panel(), matching: find.byType(SailButton));
    expect(buttons, findsOneWidget);
    expect(tester.widget<SailButton>(buttons).label, 'Bid');
    expect(find.text('Bid'), findsOneWidget, reason: 'the rows have no Bid button');
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });

  testWidgets('the row "…" holds the price alert, the favorite and the id copy', (tester) async {
    await tester.pumpSailPage(const AuctionBrowserTabPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Set Price Alert'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Copy auction ID'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });

  testWidgets('the filters are one segmented control with counts', (tester) async {
    await tester.pumpSailPage(const AuctionBrowserTabPage());
    await tester.pumpAndSettle();

    final segments = tester.widget<SailSegments>(find.byType(SailSegments));
    expect(segments.labels, ['All 2', 'Active 2', 'Upcoming 0', 'Ended 0']);
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });
}

Finder _panel() => find.byType(AuctionPanel);

class AuctionRPC extends MockBitAssetsRPC {
  int height = 101;
  bool upcoming = false;

  @override
  Future<int> getBlockCount() async => height;

  @override
  Future<List<DutchAuctionEntry>> dutchAuctions() async => [
    DutchAuctionEntry(
      id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      baseAsset: '11111111111111111111111111111111',
      quoteAsset: 'btc',
      baseAmount: 1,
      initialPrice: 100,
      finalPrice: 0,
      startBlock: 100,
      duration: 10,
      status: 'Active',
    ),
    DutchAuctionEntry(
      id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      baseAsset: '22222222222222222222222222222222',
      quoteAsset: 'btc',
      baseAmount: 1,
      initialPrice: 80,
      finalPrice: 70,
      startBlock: upcoming ? 200 : 100,
      duration: 10,
      status: 'Active',
    ),
  ];
}
