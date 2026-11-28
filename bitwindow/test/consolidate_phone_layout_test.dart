import 'package:bitwindow/pages/wallet/wallet_consolidate.dart';
import 'package:bitwindow/providers/coin_selection_provider.dart';
import 'package:bitwindow/providers/consolidation_provider.dart';
import 'package:bitwindow/providers/psbt_draft_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/widgets/v2_details.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'test_utils.dart';

final _wallet = WalletData(
  version: 1,
  master: MasterWallet(mnemonic: '', seedHex: '', masterKey: '', chainCode: ''),
  l1: L1Wallet(mnemonic: ''),
  sidechains: const [],
  id: 'wallet',
  name: 'wallet',
  gradient: WalletGradient.fromWalletId('wallet'),
  createdAt: DateTime(2026),
  walletType: BinaryType.BINARY_TYPE_ENFORCER,
);

class _FakeTransactions extends ChangeNotifier implements TransactionProvider {
  @override
  List<UnspentOutput> utxos = [
    for (var i = 0; i < 3; i++)
      UnspentOutput(output: '${'$i' * 64}:0', valueSats: Int64(4000 + i), address: 'bcrt1q${'x' * 30}$i'),
  ];

  @override
  String? error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoinSelection extends ChangeNotifier implements CoinSelectionProvider {
  @override
  bool isFrozen(String outpoint) => false;

  Map<String, String> labels = {};

  @override
  String getLabel(String outpoint) => labels[outpoint] ?? '';

  @override
  Set<String> get frozenOutpoints => {};

  @override
  String? error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConsolidation extends ChangeNotifier implements ConsolidationProvider {
  @override
  List<ConsolidationRun> runs = [
    ConsolidationRun(
      index: 0,
      outpoints: const ['a:0'],
      coinCount: 12,
      vbytes: 900,
      outputSats: 50000,
      status: ConsolidationRunStatus.pending,
    )..txid = 'ab' * 32,
    ConsolidationRun(index: 1, outpoints: const ['b:0'], coinCount: 8, vbytes: 600, outputSats: 30000),
  ];

  @override
  bool running = true;

  @override
  int get sentCount => 1;

  @override
  int get confirmedCount => 0;

  @override
  String? startBlockReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? activeWalletId = 'wallet';

  @override
  WalletData? get activeWallet => _wallet;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDrafts extends ChangeNotifier implements PsbtDraftProvider {
  @override
  Set<String> get lockedOutpoints => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_ECASH;

  @override
  String ecashNetworkId = 'ecash';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {required bool phone}) async {
  SailStyleValues.phoneLayoutOverride = phone;
  await tester.pumpSailPage(const ConsolidateTab());
  if (phone) {
    await tester.binding.setSurfaceSize(const Size(390, 844));
  }
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<CoinSelectionProvider>(_FakeCoinSelection());
    GetIt.I.registerSingleton<ConsolidationProvider>(_FakeConsolidation());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());
    GetIt.I.registerSingleton<PsbtDraftProvider>(_FakeDrafts());
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('on a phone the cards stack and the slider spans the card without step dots', (tester) async {
    await _pump(tester, phone: true);

    expect(tester.takeException(), isNull);
    final limit = tester.getRect(find.text('Coin size limit'));
    final coins = tester.getRect(find.text('Coins').first);
    final plan = tester.getRect(find.text('Plan'));
    expect(coins.top, greaterThan(limit.bottom));
    expect(plan.top, greaterThan(coins.bottom));

    final slider = find.byType(SailSlider);
    expect(tester.widget<SailSlider>(slider).showSteps, isFalse);
    expect(tester.widget<SailSlider>(slider).trackColor, isNotNull);
    final value = tester.getRect(find.text(GetIt.I<FormatterProvider>().formatSats(100000)));
    expect(value.top, greaterThan(tester.getRect(slider).bottom), reason: 'the limit shows under the slider');
    final hide = tester.getRect(find.widgetWithText(SailButton, 'Hide frozen (0)'));
    final clear = tester.getRect(find.widgetWithText(SailButton, 'Clear'));
    final coinsCard = tester.getRect(find.ancestor(of: find.text('Hide frozen (0)'), matching: find.byType(SailCard)));
    expect(hide.left, closeTo(coinsCard.left + 17, 1));
    expect(clear.right, closeTo(coinsCard.right - 17, 1));
    expect(find.byType(SailCheckbox), findsNWidgets(3), reason: 'one per coin, none in the card head');
    final runs = tester.getRect(find.text('Consolidation runs'));
    expect(runs.top, greaterThan(coins.bottom));
    expect(plan.top, greaterThan(runs.bottom));
    final card = tester.getRect(find.ancestor(of: slider, matching: find.byType(SailCard)).first);
    expect(tester.getSize(slider).width, closeTo(card.width - 32 - 2, 2));
  });

  testWidgets('on a phone each run is a two-line row with Show at the right', (tester) async {
    await _pump(tester, phone: true);

    final formatter = GetIt.I<FormatterProvider>();
    final amount = tester.getRect(find.text('1 of 2 · 12 coins'));
    final detail = tester.getRect(find.text('${formatter.formatSats(50000)} · In the mempool'));
    expect(detail.top, greaterThan(amount.bottom - 1));
    expect(detail.left, amount.left);
    expect(tester.getRect(find.widgetWithText(SailButton, 'Show')).left, greaterThan(amount.right));
    expect(find.widgetWithText(SailButton, 'Stop'), findsOneWidget);
  });

  testWidgets('the desktop keeps the plan at the side and the run columns', (tester) async {
    await _pump(tester, phone: false);

    final limit = tester.getRect(find.text('Coin size limit'));
    final plan = tester.getRect(find.text('Plan'));
    expect(plan.left, greaterThan(limit.right));
    expect(tester.widget<SailSlider>(find.byType(SailSlider)).showSteps, isTrue);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('the desktop Coins card shows the value column, a short address and a failed read', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, phone: false);

    final card = tester.getRect(find.ancestor(of: find.text('Coins').first, matching: find.byType(SailCard)).first);
    final value = tester.getRect(find.text(splitAmountUnit(GetIt.I<FormatterProvider>().formatSats(4000)).$1).last);
    expect(value.right, lessThanOrEqualTo(card.right), reason: 'the value column shows in the card');
    expect(find.text('bcrt1q${'x' * 30}0'), findsNothing);
    expect(find.text(shortenId('bcrt1q${'x' * 30}0')), findsOneWidget);

    (GetIt.I<TransactionProvider>() as _FakeTransactions)
      ..error = 'list unspent: connection refused'
      ..notifyListeners();
    await tester.pump();
    expect(find.textContaining('connection refused'), findsOneWidget);
  });

  testWidgets('a long label ends in its column and the value column stays in the card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final label = 'Salary ${'x' * 80}';
    (GetIt.I<CoinSelectionProvider>() as _FakeCoinSelection).labels['${'0' * 64}:0'] = label;
    await _pump(tester, phone: false);

    final card = tester.getRect(find.ancestor(of: find.text('Coins').first, matching: find.byType(SailCard)).first);
    final value = tester.getRect(find.text(splitAmountUnit(GetIt.I<FormatterProvider>().formatSats(4000)).$1).last);
    expect(value.right, lessThanOrEqualTo(card.right));
    expect(tester.getSize(find.text(label)).width, lessThan(260));
  });

  testWidgets('a coin with no own label shows the label of its address', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transactions = GetIt.I<TransactionProvider>() as _FakeTransactions;
    transactions.utxos.first.label = 'Address label';
    transactions.utxos[1].label = 'Hidden address label';
    (GetIt.I<CoinSelectionProvider>() as _FakeCoinSelection).labels['${'1' * 64}:0'] = 'Own label';
    await _pump(tester, phone: false);

    expect(find.text('Address label'), findsOneWidget);
    expect(find.text('Own label'), findsOneWidget);
    expect(find.text('Hidden address label'), findsNothing);
  });

  testWidgets('the button is off, with the reason above it, while the last run waits', (tester) async {
    const reason =
        'The last consolidation still waits. Let it confirm, or unfreeze its coins, before you start another.';
    final consolidation = GetIt.I<ConsolidationProvider>() as _FakeConsolidation
      ..running = false
      ..startBlockReason = reason;
    await _pump(tester, phone: false);

    final button = find.widgetWithText(SailButton, 'Consolidate 3 coins');
    expect(tester.widget<SailButton>(button).disabled, isTrue);
    expect(tester.getRect(find.text(reason)).bottom, lessThanOrEqualTo(tester.getRect(button).top));

    consolidation
      ..startBlockReason = null
      ..notifyListeners();
    await tester.pump();
    expect(tester.widget<SailButton>(button).disabled, isFalse);
    expect(find.text(reason), findsNothing);
  });

  testWidgets('the desktop plan is the side panel, and Select all, Clear, Stop and Show sit in "…" menus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, phone: false);

    expect(find.widgetWithText(SailSidePanel, 'Plan'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Select all'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Clear'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Stop'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Show'), findsNothing);

    final coinsMenu = find.descendant(
      of: find.ancestor(of: find.text('Hide frozen (0)'), matching: find.byType(SailCard)).first,
      matching: find.byType(SailRowMenuButton),
    );
    await tester.tap(coinsMenu.first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Select all'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('0 of 3 coins selected'), findsOneWidget);

    final runsMenu = find.descendant(
      of: find.ancestor(of: find.text('Consolidation runs'), matching: find.byType(SailCard)).first,
      matching: find.byType(SailRowMenuButton),
    );
    await tester.tap(runsMenu.first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('the fee rate shows the unit of the active ticker', (tester) async {
    GetIt.I.registerSingleton<BitcoinConfProvider>(_FakeConf());
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, phone: false);

    expect(find.text('1 szat/vB'), findsOneWidget);
    expect(find.text('1 sat/vB'), findsNothing);
  });
}
