import 'dart:io';
import 'dart:ui' as ui;

import 'package:bitwindow/pages/wallet/wallet_page.dart';
import 'package:bitwindow/pages/wallet/wallet_send.dart';
import 'package:bitwindow/pages/wallet/wallet_utxos.dart';
import 'package:bitwindow/providers/coin_selection_provider.dart';
import 'package:bitwindow/providers/consolidation_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'test_utils.dart';

class _Transactions extends ChangeNotifier implements TransactionProvider {
  @override
  List<UnspentOutput> utxos = [];

  @override
  String? error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallet extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? activeWalletId = 'w1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Consolidation extends ChangeNotifier implements ConsolidationProvider {
  @override
  Set<String> get reservedOutpoints => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The send form, as far as the UTXO tab uses it.
class _Send extends ChangeNotifier implements SendPageViewModel {
  final selected = <List<String>>[];

  @override
  int selectOutpoints(Iterable<String> outpoints) {
    selected.add(outpoints.toList());
    return outpoints.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UnspentOutput _coin(String txid, int sats, {String label = '', int confirmations = 1204}) => UnspentOutput(
  output: '$txid:1',
  address: 'bcrt1qp0g7hx3s9vk2m4n6r8te0g2i4k7hx3',
  label: label,
  valueSats: Int64(sats),
  confirmations: confirmations,
  receivedAt: Timestamp.fromDateTime(DateTime(2026, 10, 30, 14, 2)),
  derivationPath: "m/84'/1'/0'/0/3",
);

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['WALLET_SHOT_DIR'];
  if (dir == null) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  late _Transactions transactions;

  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    transactions = _Transactions()
      ..utxos = [
        _coin('3f9a${'b' * 56}c21e', 50000000, label: 'Exchange'),
        _coin('e04d${'c' * 56}5b18', 6250000),
        _coin('7c1e${'d' * 56}9f03', 14000, confirmations: 0),
      ];
    GetIt.I.registerSingleton<TransactionProvider>(transactions);
    GetIt.I.registerSingleton<CoinSelectionProvider>(CoinSelectionProvider());
    GetIt.I.registerSingleton<WalletReaderProvider>(_Wallet());
    GetIt.I.registerSingleton<ConsolidationProvider>(_Consolidation());
  });

  tearDown(() async {
    WalletPage.sendViewModel = null;
    await GetIt.I.reset();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpSailPage(
      Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: const SizedBox(width: 1416, height: 820, child: UTXOsTab()),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1440, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  testWidgets('the strip shows the bucket bars and the totals', (tester) async {
    await pumpTab(tester);

    final strip = find.byType(UtxoDistributionStrip);
    expect(strip, findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('UTXO distribution')), findsOneWidget);
    for (final label in ['Total', 'UTXOs', 'Frozen', 'Largest']) {
      expect(
        find.descendant(of: strip, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.descendant(of: strip, matching: find.text('3')), findsOneWidget);
    expect(find.byKey(const ValueKey('utxo_bar_5')), findsOneWidget);
    await _shot(tester, 'utxos');
  });

  testWidgets('a click on a bar opens the bucket menu', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byKey(const ValueKey('utxo_bar_3')));
    await tester.pumpAndSettle();

    expect(find.text('Send This UTXO'), findsOneWidget);
    expect(find.text('Show Transaction'), findsOneWidget);
  });

  testWidgets('a row click opens the UTXO panel, and the × closes it', (tester) async {
    await pumpTab(tester);
    expect(find.byType(UtxoSidePanel), findsNothing);

    await tester.tap(find.text('Exchange'));
    await tester.pumpAndSettle();

    final panel = find.byType(UtxoSidePanel);
    expect(panel, findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Spendable · 1 204 confirmations')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'Send this UTXO')), findsOneWidget);
    await _shot(tester, 'utxos-panel');

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x));
    await tester.pumpAndSettle();
    expect(find.byType(UtxoSidePanel), findsNothing);
  });

  testWidgets('Send This UTXO puts the coin in Pay from and opens Send', (tester) async {
    final send = _Send();
    WalletPage.sendViewModel = send;
    await pumpTab(tester);

    await tester.tap(find.text('Exchange'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SailButton, 'Send this UTXO'));
    await tester.pumpAndSettle();

    expect(send.selected, [
      ['3f9a${'b' * 56}c21e:1'],
    ]);
    expect(WalletPage.pendingSubtab, 'Send');
    await tester.pump(const Duration(seconds: 5));
  });
}
