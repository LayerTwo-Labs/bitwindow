import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/mocks/mocks.dart';

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

void main() {
  late AddressProvider addresses;
  late SidechainTransactionsProvider transactions;
  late SidechainBalanceProvider balance;

  setUpAll(() async {
    final loader = FontLoader(SailFonts.inter);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('packages/sail_ui/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    await GetIt.I.reset();
    final rpc = MockThunderRPC();
    final log = Logger(level: Level.off);
    GetIt.I.registerSingleton<Logger>(log);
    GetIt.I.registerSingleton<ClientSettings>(ClientSettings(store: _Store(), log: log));
    GetIt.I.registerSingleton<BitwindowClientSettings>(BitwindowClientSettings(store: _Store(), log: log));
    GetIt.I.registerSingleton<SettingsProvider>(await SettingsProvider.create());
    GetIt.I.registerSingleton<BinaryProvider>(MockBinaryProvider());
    GetIt.I.registerSingleton<SidechainRPC>(rpc);
    addresses = AddressProvider(rpc: rpc);
    transactions = SidechainTransactionsProvider(rpc: rpc);
    balance = SidechainBalanceProvider(sidechain: rpc);
    GetIt.I.registerSingleton<AddressProvider>(addresses);
    GetIt.I.registerSingleton<SidechainTransactionsProvider>(transactions);
    GetIt.I.registerSingleton<SidechainBalanceProvider>(balance);
  });

  tearDown(() async {
    addresses.dispose();
    balance.dispose();
    await GetIt.I.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1416, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SailTheme(
          data: SailThemeData.lightTheme(
            SailColorScheme.orange,
            true,
            SailFontValues.inter,
            SailThemeStyle.bitwindowV2,
          ),
          child: child!,
        ),
        home: const Scaffold(body: ParentChainPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('deposit and withdraw sit side by side, each half the width', (tester) async {
    await pump(tester);

    final deposit = tester.getTopLeft(find.text('Deposit from Parent Chain'));
    final withdraw = tester.getTopLeft(find.text('Withdraw to Parent Chain'));
    expect(deposit.dy, withdraw.dy);
    expect(withdraw.dx, greaterThan(700));
    expect(find.text('Scan QR code or copy address below:'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Send is the one full-width button, and Clear All moved into the "…" menu', (tester) async {
    await pump(tester);

    final send = find.byWidgetPredicate((w) => w is SailButton && w.label == 'Send');
    expect(send, findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Clear All'), findsNothing);
    final fieldWidth = tester.getSize(find.byType(TextField).at(1)).width;
    expect(tester.getSize(send).width, greaterThanOrEqualTo(fieldWidth));

    await tester.enterText(find.byType(TextField).at(1), 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh');
    await tester.enterText(find.byType(TextField).last, 'rent');
    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Clear All'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh'), findsNothing);
    expect(find.text('rent'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the fee rows stay, with the total last', (tester) async {
    await pump(tester);

    for (final label in ['Withdrawal Amount', 'Sidechain Fee', 'Mainchain Fee', 'Total Cost']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('Total Cost')).dy,
      greaterThan(tester.getTopLeft(find.text('Mainchain Fee')).dy),
    );
    await unmount(tester);
  });
}
