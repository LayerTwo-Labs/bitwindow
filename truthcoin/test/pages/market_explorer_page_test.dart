import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:sail_ui/sail_ui.dart'
    show SailColorScheme, SailFontValues, SailRowMenuButton, SailTheme, SailThemeData, SailThemeStyle;
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/mocks/mocks.dart';
import 'package:sidechain_core/rpcs/bitcoind_connection.dart';
import 'package:sidechain_core/rpcs/rpc_sidechain.dart';
import 'package:sidechain_core/rpcs/truthcoin_rpc.dart';
import 'package:sidechain_core/providers/balance_provider.dart';
import 'package:truthcoin/providers/market_provider.dart';
import 'package:truthcoin/providers/price_history_provider.dart';

import 'package:truthcoin/pages/market_explorer_page.dart';
import 'package:truthcoin/widgets/market_card.dart';

import '../fixtures/test_data.dart';
import '../mocks/mock_truthcoin_rpc.dart';
import '../test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestTruthcoinRPC mockRpc;

  setUpAll(() async {
    mockRpc = TestTruthcoinRPC();
    mockRpc.marketListResponse = TestData.sampleMarketList;
    mockRpc.marketGetResponse = TestData.sampleMarketDetail;

    GetIt.I.registerLazySingleton<SidechainRPC>(() => mockRpc);
    GetIt.I.registerLazySingleton<TruthcoinRPC>(() => mockRpc);
    GetIt.I.registerLazySingleton<BitcoindConnection>(() => MockBitcoindConnection());
    GetIt.I.registerLazySingleton<Logger>(() => Logger(level: Level.off));

    final marketProvider = MarketProvider();
    GetIt.I.registerLazySingleton<MarketProvider>(() => marketProvider);
    GetIt.I.registerLazySingleton<PriceHistoryProvider>(() => PriceHistoryProvider());

    final balanceProvider = SidechainBalanceProvider(sidechain: mockRpc);
    GetIt.I.registerLazySingleton<SidechainBalanceProvider>(() => balanceProvider);
    await balanceProvider.fetch();
  });

  tearDownAll(() async {
    await GetIt.I.reset();
  });

  group('MarketExplorerPage', () {
    testWidgets('draws one table row per market', (tester) async {
      await tester.pumpSailPage(const MarketExplorerPage());
      await tester.pumpAndSettle();

      expect(find.byType(MarketCard), findsNothing);
      expect(find.text('Prediction markets'), findsOneWidget);
      expect(find.text('US Presidential Election 2028 Winner'), findsOneWidget);
      expect(find.text('Will BTC reach \$100k by end of 2026?'), findsOneWidget);
      expect(find.text('Cancelled Market Example'), findsOneWidget);
      expect(find.text('Yes 65%'), findsWidgets);
    });

    testWidgets('one filter dropdown lists All, each tag and each state', (tester) async {
      await tester.pumpSailPage(const MarketExplorerPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      for (final label in ['bitcoin', 'crypto', 'price', 'Live', 'Cancelled', 'Invalid', 'Resolved']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('a row click opens the market panel with one Buy button', (tester) async {
      await tester.pumpSailPage(const MarketExplorerPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Will BTC reach \$100k by end of 2026?'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.byType(MarketSidePanel), findsOneWidget);
      expect(find.text('Buy Yes 65%'), findsWidgets);
      expect(find.text('Outcome prices'), findsOneWidget);
    });

    testWidgets('the row "…" holds Buy Yes, Buy No and Trade', (tester) async {
      await tester.pumpSailPage(const MarketExplorerPage());
      await tester.pumpAndSettle();

      final row = tester.getCenter(find.text('Will BTC reach \$100k by end of 2026?')).dy;
      final menu = find
          .byType(SailRowMenuButton)
          .evaluate()
          .firstWhere((element) => (tester.getCenter(find.byWidget(element.widget)).dy - row).abs() < 16);
      await tester.tap(find.byWidget(menu.widget));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.text('Buy Yes'), findsOneWidget);
      expect(find.text('Buy No'), findsOneWidget);
      expect(find.text('Trade'), findsOneWidget);
    });

    testWidgets('under the eCash theme a page button keeps its case and the regular weight', (tester) async {
      await tester.pumpSailPage(
        SailTheme(
          data: SailThemeData.darkTheme(SailColorScheme.orange, false, SailFontValues.ibmMono, SailThemeStyle.ecash),
          child: const MarketExplorerPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CREATE MARKET'), findsNothing);
      final label = tester.widgetList<Text>(find.text('Create market')).first;
      expect(label.style?.fontWeight, FontWeight.w400);
    });

    test('provider loads markets successfully', () async {
      final marketProvider = GetIt.I.get<MarketProvider>();
      await marketProvider.loadMarkets();

      expect(marketProvider.markets.length, 3);
      expect(marketProvider.markets.first.title, contains('BTC'));
    });

    test('provider handles filtering', () async {
      final marketProvider = GetIt.I.get<MarketProvider>();
      await marketProvider.loadMarkets();

      marketProvider.setSearchQuery('BTC');
      expect(marketProvider.filteredMarkets.length, 1);

      marketProvider.setSearchQuery('');
      expect(marketProvider.filteredMarkets.length, 3);
    });

    test('provider loads a price per listed market', () async {
      final marketProvider = GetIt.I.get<MarketProvider>();
      await marketProvider.loadMarkets();
      await marketProvider.loadMarketPrices(batchSize: 2);

      expect(marketProvider.marketDetails.length, 3);
      expect(marketProvider.priceError, null);
      expect(marketProvider.isLoadingPrices, false);

      final detail = marketProvider.marketDetails['market_001'];
      expect(detail, isNotNull);
      expect(detail!.outcomes.first.name, 'Yes');
    });

    test('a loaded price does not load again', () async {
      final marketProvider = GetIt.I.get<MarketProvider>();
      await marketProvider.loadMarkets();
      await marketProvider.loadMarketPrices();

      final before = mockRpc.marketGetCalls;
      await marketProvider.loadMarketPrices();
      expect(mockRpc.marketGetCalls, before);

      await marketProvider.loadMarketPrices(refresh: true);
      expect(mockRpc.marketGetCalls, before + 3);
    });

    test('the tag filter keeps the markets that carry the tag', () async {
      final marketProvider = GetIt.I.get<MarketProvider>();
      await marketProvider.loadMarkets();
      await marketProvider.loadMarketPrices();

      expect(marketProvider.availableTags, ['bitcoin', 'crypto', 'price']);

      marketProvider.setTagFilter('bitcoin');
      expect(marketProvider.filteredMarkets.length, 3);

      marketProvider.setTagFilter('football');
      expect(marketProvider.filteredMarkets, isEmpty);

      marketProvider.setTagFilter(null);
      expect(marketProvider.filteredMarkets.length, 3);
    });

    test('a price load failure lands in priceError', () async {
      final marketProvider = GetIt.I.get<MarketProvider>();
      await marketProvider.loadMarkets();

      mockRpc.shouldThrowOnMarketGet = true;
      await marketProvider.loadMarketPrices(refresh: true);
      mockRpc.shouldThrowOnMarketGet = false;

      expect(marketProvider.priceError, isNotNull);
    });
  });
}
