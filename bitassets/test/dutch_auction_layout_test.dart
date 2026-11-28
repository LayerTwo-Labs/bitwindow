import 'package:bitassets/pages/tabs/dutch_auction_page.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/rpc_mock_bitassets.dart';
import 'screen_capture.dart';
import 'test_utils.dart';

final _auction = DutchAuctionEntry(
  id: '6be2f09a1c${'d' * 54}',
  baseAsset: '7d3e91a0c4${'b' * 54}',
  quoteAsset: 'btc',
  baseAmount: 50000,
  initialPrice: 5000,
  finalPrice: 1000,
  startBlock: 1940,
  duration: 200,
  status: 'Active',
  currentPrice: 3200,
);

class _RPC extends MockBitAssetsRPC {
  final List<int> bids = [];

  @override
  Future<List<DutchAuctionEntry>> dutchAuctions() async => [_auction];

  @override
  Future<int> dutchAuctionBid({required String dutchAuctionId, required int bidSize}) async {
    bids.add(bidSize);
    return 10;
  }
}

void main() {
  late _RPC rpc;

  setUpAll(loadFontsForScreens);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    rpc = _RPC();
    GetIt.I.registerSingleton<BitAssetsRPC>(rpc);
    GetIt.I.registerSingleton<SidechainBalanceProvider>(SidechainBalanceProvider(sidechain: rpc));
    GetIt.I.registerSingleton<BitAssetsProvider>(BitAssetsProvider());
    GetIt.I.registerSingleton<NotificationProvider>(NotificationProvider());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpSailPage(const RepaintBoundary(key: screenKey, child: DutchAuctionTabPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Finder panel(String title) => find.byWidgetPredicate((w) => w is SailSidePanel && w.title == title);

  testWidgets('the Create form sits in a side panel beside the auctions table', (tester) async {
    await pumpTab(tester);

    expect(panel('Create Dutch Auction'), findsOneWidget);
    expect(tester.getSize(panel('Create Dutch Auction')).width, SailSidePanel.width);
    expect(find.text('Estimated creation fee: ~1,000 sats (network fee)'), findsOneWidget);
    await captureScreen(tester, 'dutch_create');
  });

  testWidgets('a row click shows the auction with Place Bid as its one button', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('6be2f09a1c..'));
    await tester.pump();

    expect(panel('Dutch Auction Details'), findsOneWidget);
    expect(panel('Create Dutch Auction'), findsNothing);
    final details = panel('Dutch Auction Details');
    expect(find.descendant(of: details, matching: find.text('3200')), findsWidgets);
    expect(find.descendant(of: details, matching: find.byType(SailStatusPill)), findsOneWidget);
    expect(find.descendant(of: details, matching: find.byType(SailButton)), findsOneWidget);
    await captureScreen(tester, 'dutch_details');
  });

  testWidgets('Place Bid opens a dialog with one Place Bid button that sends the bid', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('6be2f09a1c..'));
    await tester.pump();

    await tester.tap(find.descendant(of: panel('Dutch Auction Details'), matching: find.byType(SailButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Auction: 6be2f09a1c...'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is SailTextField && w.hintText == 'Amount to bid'),
        matching: find.byType(EditableText),
      ),
      '25',
    );
    await tester.tap(find.descendant(of: find.byType(SailDialogActionButton), matching: find.text('Place Bid')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(rpc.bids, [25]);
    expect(find.text('Auction: 6be2f09a1c...'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('× closes the panel and Create New Auction opens the form again', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pump();
    expect(find.byType(SailSidePanel), findsNothing);

    await tester.tap(find.text('Create New Auction'));
    await tester.pump();
    expect(panel('Create Dutch Auction'), findsOneWidget);
  });
}
