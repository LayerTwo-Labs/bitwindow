import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/sidechains/bmm_tab.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/bmm/v1/bmm.pb.dart' as bmmpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

class _Chain implements SidechainRPC {
  @override
  Sidechain get chain => Thunder();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bmm extends ChangeNotifier implements BMMProvider {
  @override
  final SidechainRPC sidechainRPC = _Chain();

  @override
  double maxBidAmount = 0.0002;

  @override
  int get suggestedBidSats => 188;

  @override
  bool running = true;

  @override
  String? get fundingWalletId => 'wallet1';

  @override
  bool get fundingBalanceTooLow => false;

  @override
  bool get boundsPushPending => false;

  @override
  String? get error => null;

  @override
  String? get lastBidError => null;

  @override
  bmmpb.Bid? liveBid = bmmpb.Bid(bidSats: Int64(8000), criticalHash: '3fa91c02${'0' * 56}');

  @override
  bmmpb.Round? get current => bmmpb.Round(prevMainHash: 'cur', blockWorthSats: Int64(12400));

  @override
  List<bmmpb.Bid> currentBids = [
    bmmpb.Bid(
      bidSats: Int64(8000),
      isOurs: true,
      criticalHash: '3fa91c02${'0' * 56}',
      prevMainHash: '000000a3f19c42e1${'0' * 48}',
      txid: '7c41e0f9b2a8d3c6${'0' * 48}',
    ),
    bmmpb.Bid(
      bidSats: Int64(6500),
      criticalHash: '91be4d77${'0' * 56}',
      prevMainHash: '000000a3f19c42e1${'0' * 48}',
      txid: '2d9a7c13e5f04b88${'0' * 48}',
    ),
  ];

  @override
  List<bmmpb.Round> history = [
    bmmpb.Round(
      prevMainHash: 'r1',
      result: 'won',
      blockWorthSats: Int64(12000),
      profitSats: Int64(4200),
      includedInBlock: '000000c1e7a9b204${'0' * 48}',
      ourBids: [bmmpb.Bid(bidSats: Int64(7800), txid: '5b02c9e7a1f3d488${'0' * 48}')],
    ),
    bmmpb.Round(
      prevMainHash: 'r2',
      result: 'lost',
      blockWorthSats: Int64(9800),
      ourBids: [bmmpb.Bid(bidSats: Int64(7500), txid: 'e93a40d17c2b5f61${'0' * 48}')],
    ),
  ];

  bool cleared = false;

  @override
  Future<void> clearHistory() async => cleared = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallets extends ChangeNotifier implements WalletReaderProvider {
  @override
  List<WalletData> fundingWallets() => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork get network => BitcoinNetwork.BITCOIN_NETWORK_SIGNET;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bmm bmm;
  late SyncProvider sync;
  late NodeModeProvider mode;
  late BMMViewModel model;

  setUpAll(() async {
    final loader = FontLoader(SailFonts.inter);
    for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
      loader.addFont(rootBundle.load('packages/sail_ui/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    mode = NodeModeProvider()..mode = wmpb.NodeMode.NODE_MODE_FULL;
    sync = SyncProvider(startTimer: false)
      ..mainchainSyncInfo = SyncInfo(progressCurrent: 42, progressGoal: 42, lastBlockAt: null)
      ..enforcerSyncInfo = SyncInfo(progressCurrent: 42, progressGoal: 42, lastBlockAt: null);
    GetIt.I.registerSingleton<NodeModeProvider>(mode);
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<SyncProvider>(sync);
    GetIt.I.registerSingleton<WalletReaderProvider>(_Wallets());
    bmm = _Bmm();
    model = BMMViewModel(provider: bmm);
    SailStyleValues.phoneLayoutOverride = false;
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    model.dispose();
    sync.dispose();
    mode.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpBody(WidgetTester tester, {Size size = const Size(1416, 860), bool light = true}) async {
    await tester.binding.setSurfaceSize(size);
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
              key: const ValueKey('bmm-screen'),
              child: QtPage(child: BmmPageBody(viewModel: model)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the head holds the bid controls on one row, the manual bid in its "…"', (tester) async {
    await pumpBody(tester);
    await _capture(tester, 'bmm');

    expect(tester.takeException(), isNull);
    final wallet = tester.getRect(find.text('Wallet:'));
    expect(tester.getCenter(find.text('Min bid:')).dy, closeTo(wallet.center.dy, 1));
    expect(tester.getCenter(find.text('Max bid:')).dy, closeTo(wallet.center.dy, 1));
    expect(tester.getRect(find.text('BMM')).right, lessThan(wallet.left));
    expect(find.widgetWithText(SailButton, 'Bid manually'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Clear history'), findsNothing);

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Bid manually'), findsOneWidget);
  });

  testWidgets('the two tables fill the page, the current slot shows its stats at the right', (tester) async {
    await pumpBody(tester);

    final page = tester.getRect(find.byType(BmmPageBody));
    final historic = tester.getRect(find.text('Historic bids'));
    final bids = tester.getRect(find.text('Bids on next block'));
    expect(historic.top, greaterThan(bids.bottom + 150));
    expect(historic.top, greaterThan(page.center.dy - 50));
    expect(find.byKey(const ValueKey('bmm-page-scroll')), findsNothing);

    final head = tester.getRect(find.text('Current slot'));
    final hint = tester.getRect(find.textContaining('Waiting for a miner'));
    expect(hint.top, greaterThan(head.bottom - 1));
    expect(tester.getRect(find.text('Block worth')).left, greaterThan(hint.right));
    expect(find.text('Leading'), findsOneWidget);
    expect(find.text('Outbid'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Not included'), findsOneWidget);
    expect(find.byType(SailStatusDot), findsNWidgets(5));
  });

  testWidgets('a short window scrolls the page and keeps every section', (tester) async {
    await pumpBody(tester, size: const Size(1416, 560));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('bmm-page-scroll')), findsOneWidget);
    expect(find.text('Historic bids'), findsOneWidget);
  });

  testWidgets('Clear history sits in the "…" of the historic bids', (tester) async {
    await pumpBody(tester, light: false);
    await _capture(tester, 'bmm-dark');

    final historic = tester.getRect(find.text('Historic bids'));
    final menu = find.byType(SailRowMenuButton).evaluate().map((e) => tester.getRect(find.byWidget(e.widget))).toList();
    final headMenu = menu.firstWhere((rect) => (rect.top - historic.top).abs() < 20);
    await tester.tapAt(headMenu.center);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();

    expect(bmm.cleared, isTrue);
  });

  testWidgets('the manual bid opens as a dialog with × and one Place bid button', (tester) async {
    await pumpBody(tester);
    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bid manually'));
    await tester.pumpAndSettle();

    expect(find.text('Manual bid'), findsOneWidget);
    expect(find.text('Place bid'), findsWidgets);
    expect(find.widgetWithText(SailButton, 'Cancel'), findsNothing);
    expect(find.byType(SailIconBoxButton), findsWidgets);
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('BMM_SCREEN_DIR');
  if (directory.isEmpty) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('bmm-screen')));
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
