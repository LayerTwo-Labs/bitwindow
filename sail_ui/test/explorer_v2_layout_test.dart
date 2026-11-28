import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/sidechains/explorer/transaction_broadcast.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/explorer/v1/explorer.pb.dart' as pb;
import 'package:sidechain_core/mocks/mocks.dart';

const _txid = '9a10c73e5b2d81f4a6c09e7d3b1f5a2c8e4d6b0a7f9c1e3d5b8a2c4e6f04471b';
const _deposit = 'fb4566127a3d9e0c1b2f4a6d8e0c2b4a6d8f0e2c4b6a8d0f2e4c6b8a9c0d1a77';

class _Explorer extends Fake implements OrchestratorExplorerRPC {
  bool missing = false;

  @override
  Future<pb.GetOverviewResponse> getOverview(String chain) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return pb.GetOverviewResponse(
      blocks: [
        for (var i = 0; i < 4; i++)
          pb.Block(
            height: 1284 - i,
            hash: 'hash${1284 - i}',
            mainchainHeight: 974512 - i,
            txCount: i,
            feesSats: Int64(188 * i),
            feesKnown: true,
            blockTime: Int64(now - 180 * (i + 1)),
          ),
      ],
      recent: [
        pb.Activity(
          id: _txid,
          kind: pb.Kind.KIND_TRANSFER,
          valueSats: Int64(24000000),
          feeSats: Int64(2400),
          confirmed: true,
          blockHeight: 1282,
        ),
        pb.Activity(id: _deposit, kind: pb.Kind.KIND_DEPOSIT, valueSats: Int64(100000000), confirmed: false),
      ],
      treasury: pb.Treasury(slot: 9, activationHeight: 971204, balanceSats: Int64(510000000), ctipTxid: _txid),
      pendingBundle: pb.WithdrawalBundle(
        present: true,
        totalValueSats: Int64(9000000),
        totalWeight: 832,
        maxWeight: 50000,
        heightCreated: 974401,
        withdrawals: [pb.Withdrawal(valueSats: Int64(5000000), mainAddress: 'bc1qdestination', cumulativeWeight: 208)],
      ),
    );
  }

  @override
  Future<pb.Transaction> getTransaction(String chain, String txid) async {
    if (missing) {
      throw StateError('block $txid not found');
    }
    return pb.Transaction(
      txid: txid,
      kind: pb.Kind.KIND_TRANSFER,
      confirmed: true,
      blockHeight: 1282,
      sizeBytes: Int64(226),
      feeSats: Int64(2400),
      inputs: [pb.Coin(address: 'inputaddress', valueSats: Int64(24240000))],
      outputs: [pb.Coin(address: 'outputaddress', valueSats: Int64(24000000))],
    );
  }

  @override
  Future<pb.GetBlockResponse> getBlock(String chain, {String? hash, int? height}) async {
    throw StateError('block $hash not found');
  }

  @override
  Future<pb.GetAddressResponse> getAddress(String chain, String address) async {
    throw StateError('address $address not found');
  }

  @override
  Future<List<pb.Block>> listBlocks(String chain, {int? beforeHeight, int limit = 20}) async => [];

  @override
  Future<pb.GetWithdrawalsResponse> getWithdrawals(String chain) async {
    return pb.GetWithdrawalsResponse(bundle: (await getOverview(chain)).pendingBundle);
  }
}

class _Store implements KeyValueStore {
  final _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> update(String key, String Function(String? current) change) async {
    await setString(key, change(await getString(key)));
  }
}

class _Orchestrator extends Fake implements OrchestratorRPC {
  @override
  final OrchestratorExplorerRPC explorer;

  _Orchestrator(this.explorer);
}

const _screen = ValueKey('explorer-screen');

Future<void> _pump(WidgetTester tester, {bool dark = false}) async {
  await tester.binding.setSurfaceSize(const Size(1416, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = dark
      ? SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2)
      : SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => SailTheme(data: theme, child: child!),
      home: const Scaffold(
        body: RepaintBoundary(
          key: _screen,
          child: QtPage(child: ChainExplorerTab()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('EXPLORER_SCREEN_DIR');
  if (directory.isEmpty) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_screen));
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

double _left(WidgetTester tester, String text) => tester.getTopLeft(find.text(text).first).dx;
double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text).first).dy;

void main() {
  late _Explorer explorer;

  setUpAll(() async {
    final loader = FontLoader(SailFonts.inter);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('packages/sail_ui/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    await GetIt.I.reset();
    final log = Logger(level: Level.off);
    GetIt.I.registerSingleton<Logger>(log);
    GetIt.I.registerSingleton<ClientSettings>(ClientSettings(store: _Store(), log: log));
    GetIt.I.registerSingleton<BitwindowClientSettings>(BitwindowClientSettings(store: _Store(), log: log));
    GetIt.I.registerSingleton<SettingsProvider>(await SettingsProvider.create());
    GetIt.I.registerSingleton<BinaryProvider>(MockBinaryProvider());
    GetIt.I.registerSingleton<SidechainRPC>(MockThunderRPC());
    explorer = _Explorer();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator(explorer));
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the bar holds the segments, the search and no broadcast menu on thunder', (tester) async {
    await _pump(tester);

    expect(find.text('Chain'), findsOneWidget);
    expect(find.text('Withdrawals'), findsOneWidget);
    expect(_top(tester, 'Chain'), lessThan(_top(tester, 'Recent transactions')));
    expect(
      _left(tester, 'Chain'),
      lessThan(_left(tester, 'Search a block height, a block hash, a transaction or an address')),
    );
    expect(find.byType(ExplorerBroadcastButton), findsNothing);
    await _capture(tester, 'chain');
  });

  testWidgets('treasury and pending withdrawals sit in a 380 px column at the right', (tester) async {
    await _pump(tester);

    expect(find.text('Treasury'), findsOneWidget);
    expect(find.text('Pending withdrawals'), findsOneWidget);
    expect(_left(tester, 'Treasury'), greaterThan(_left(tester, 'Recent transactions') + 900));
    expect(_top(tester, 'Treasury'), lessThan(_top(tester, 'Pending withdrawals')));
    expect(find.text('Deposits'), findsNothing);
  });

  testWidgets('the recent transactions table names the kind as text and the status with a dot', (tester) async {
    await _pump(tester);

    expect(find.text('Latest 2 · 1 unconfirmed'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Deposit'), findsOneWidget);
    expect(find.byType(SailBadge), findsNothing);
    expect(find.byType(SailStatusDot), findsAtLeastNWidgets(2));
    expect(find.text('Waits for a bid'), findsOneWidget);
  });

  testWidgets('a row click opens the transaction panel in place of the escrow column, and × closes it', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('9a10c73e…6f04471b'));
    await tester.pumpAndSettle();

    expect(find.byType(SailSidePanel), findsOneWidget);
    expect(find.text('Transaction'), findsWidgets);
    expect(find.text('Total value'), findsWidgets);
    expect(find.text('Inputs and outputs'), findsOneWidget);
    expect(find.text('Treasury'), findsNothing);
    await _capture(tester, 'transaction');

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.tooltip == 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SailSidePanel), findsNothing);
    expect(find.text('Treasury'), findsOneWidget);
  });

  testWidgets('a deposit row offers mempool.space and opens no panel', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('fb456612…9c0d1a77'));
    await tester.pumpAndSettle();
    expect(find.byType(SailSidePanel), findsNothing);
  });

  testWidgets('a search that finds nothing shows the Not found panel', (tester) async {
    explorer.missing = true;
    await _pump(tester);

    await tester.enterText(find.byType(TextField), '9f2c41e0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(SailSidePanel), findsOneWidget);
    expect(find.text('Not found'), findsNWidgets(2));
    expect(find.textContaining('9f2c41e0 not found'), findsOneWidget);
    await _capture(tester, 'not-found');
  });

  testWidgets('the Withdrawals segment shows the bundle strip and table, and keeps the escrow column', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Withdrawals'));
    await tester.pumpAndSettle();

    expect(find.text('The bundle now'), findsOneWidget);
    expect(find.text('In this bundle'), findsOneWidget);
    expect(find.text('Total amount'), findsOneWidget);
    expect(find.text('Treasury'), findsOneWidget);
    expect(find.text('Recent transactions'), findsNothing);
    await _capture(tester, 'withdrawals');
  });

  testWidgets('dark mode lays out with no errors', (tester) async {
    await _pump(tester, dark: true);

    expect(tester.takeException(), isNull);
    await _capture(tester, 'chain-dark');
  });
}
