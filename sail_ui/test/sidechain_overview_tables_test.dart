import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

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

class _FakeTransactionsProvider extends ChangeNotifier implements SidechainTransactionsProvider {
  @override
  List<CoreTransaction> sidechainTransactions = [
    CoreTransaction(
      address: '',
      category: 'receive',
      amount: 25000000,
      label: '',
      vout: 0,
      fee: 0,
      confirmations: 6,
      trusted: true,
      blockhash: '',
      blockindex: 0,
      blocktime: 1000,
      txid: '8f3c1a7e2d9b04c6a5f18e3d7b2c90a4e6f1d8b3c5a7092e4f6b1d8c3a5e7f90',
      time: DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      timereceived: DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      comment: '',
      bip125Replaceable: 'no',
      abandoned: false,
      raw: '',
    ),
  ];

  @override
  Future<void> fetch() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUtxoModel extends ChangeNotifier implements LatestUTXOsViewModel {
  @override
  bool get loading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2),
        child: Scaffold(body: SizedBox(width: 800, height: 400, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _inOrder(WidgetTester tester, List<String> labels) {
  final found = [for (final label in labels) (label, tester.getTopLeft(find.text(label)).dx)]
    ..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (label, _) in found) label];
}

void main() {
  setUp(() async {
    final log = Logger();
    GetIt.I.registerSingleton<Logger>(log);
    GetIt.I.registerSingleton<ClientSettings>(ClientSettings(store: _Store(), log: log));
    GetIt.I.registerSingleton<BitwindowClientSettings>(BitwindowClientSettings(store: _Store(), log: log));
    final settings = await SettingsProvider.create();
    GetIt.I.registerSingleton<SettingsProvider>(settings);
    GetIt.I.registerSingleton<FormatterProvider>(FormatterProvider(settings));
    GetIt.I.registerSingleton<SidechainTransactionsProvider>(_FakeTransactionsProvider());
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the history reads TxID, Date, Confirmations, Amount and a row tap opens the side panel', (
    tester,
  ) async {
    await _pump(tester, TransactionTable(model: LatestWalletTransactionsViewModel(), searchWidget: const SizedBox()));

    expect(_inOrder(tester, ['TxID', 'Date', 'Confirmations', 'Amount']), ['TxID', 'Date', 'Confirmations', 'Amount']);
    expect(find.byType(SailStatusDot), findsOneWidget);

    await tester.tap(find.text('8f3c1a..:0'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionDetailsPanel), findsOneWidget);
    expect(find.text('Confirmations 6'), findsOneWidget);
    expect(tester.getSize(find.byType(SailSidePanel)).width, SailSidePanel.width);

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.tooltip == 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailsPanel), findsNothing);
  });

  testWidgets('the UTXO table reads Output, Type, Address, Amount and shows Status only when asked', (tester) async {
    final entries = [
      SidechainUTXO(outpoint: 'a1b2c3d4e5f6:0', address: '4L1Zvh', valueSats: 25000000, type: OutpointType.regular),
    ];
    await _pump(tester, UTXOTable(entries: entries, model: _FakeUtxoModel(), showStatus: false));

    expect(_inOrder(tester, ['Output', 'Type', 'Address', 'Amount']), ['Output', 'Type', 'Address', 'Amount']);
    expect(find.text('Status'), findsNothing);

    await _pump(tester, UTXOTable(entries: entries, model: _FakeUtxoModel()));
    expect(find.text('Status'), findsOneWidget);
  });
}
