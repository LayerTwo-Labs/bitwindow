import 'package:bitwindow/pages/wallet/wallet_utxos.dart';
import 'package:bitwindow/providers/coin_selection_provider.dart';
import 'package:bitwindow/providers/consolidation_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';
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
  Set<String> reserved = {};

  @override
  Set<String> get reservedOutpoints => reserved;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String ecashNetworkId = '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A metadata store that refuses every write while [down] is true.
class _MetadataWallet extends MockWalletAPI {
  bool down = false;
  final List<String> writes = [];
  final Map<String, UTXOMetadata> stored = {};

  @override
  Future<void> setUTXOMetadata(String outpoint, {bool? isFrozen, String? label}) async {
    if (down) {
      throw Exception('connection refused');
    }
    writes.add(outpoint);
    final entry = stored[outpoint] ?? UTXOMetadata(outpoint: outpoint);
    if (isFrozen != null) {
      entry.isFrozen_2 = isFrozen;
    }
    if (label != null) {
      entry.label = label;
    }
    stored[outpoint] = entry;
  }

  @override
  Future<Map<String, UTXOMetadata>> getUTXOMetadata(List<String> outpoints) async => Map.of(stored);
}

class _Bitwindow extends MockAPI {
  final _MetadataWallet metadata = _MetadataWallet();

  _Bitwindow() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  @override
  WalletAPI get wallet => metadata;
}

final _coin = UnspentOutput(
  output: '${'a' * 64}:0',
  address: 'bcrt1qcoin',
  valueSats: Int64(150000),
  confirmations: 3,
  derivationPath: "m/84'/1'/0'/0/7",
);

void main() {
  late _Bitwindow bitwindow;
  late _Consolidation consolidation;

  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    bitwindow = _Bitwindow();
    GetIt.I.registerSingleton<BitwindowRPC>(bitwindow);
    await registerTestDependencies();
    consolidation = _Consolidation();
    if (!GetIt.I.isRegistered<BitcoinConfProvider>()) {
      GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    }
    GetIt.I.registerSingleton<TransactionProvider>(_Transactions()..utxos = [_coin]);
    GetIt.I.registerSingleton<CoinSelectionProvider>(CoinSelectionProvider());
    GetIt.I.registerSingleton<WalletReaderProvider>(_Wallet());
    GetIt.I.registerSingleton<ConsolidationProvider>(consolidation);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> openRowMenu(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpSailPage(UTXOTable(entries: [_coin], model: LatestUTXOsViewModel()));
    await tester.pumpAndSettle();
    await tester.tap(find.text("m/84'/1'/0'/0/7"), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  testWidgets('a failed freeze from the row menu shows the error, and the coin stays unfrozen', (tester) async {
    bitwindow.metadata.down = true;
    await openRowMenu(tester);

    await tester.tap(find.text('Freeze UTXO'));
    await tester.pumpAndSettle();

    expect(find.textContaining('BitWindow could not freeze the coin'), findsOneWidget);
    expect(find.textContaining('connection refused'), findsOneWidget);
    expect(GetIt.I<CoinSelectionProvider>().isFrozen(_coin.output), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a freeze from the row menu shows on the row at once', (tester) async {
    await openRowMenu(tester);

    await tester.tap(find.text('Freeze UTXO'));
    await tester.pumpAndSettle();

    expect(bitwindow.metadata.writes, [_coin.output]);
    expect(GetIt.I<CoinSelectionProvider>().isFrozen(_coin.output), isTrue);
    expect(find.text('Hide frozen (1)'), findsOneWidget);
  });

  testWidgets('the row menu leaves a coin alone while a consolidation holds it', (tester) async {
    consolidation.reserved = {_coin.output};
    await openRowMenu(tester);

    await tester.tap(find.text('Held by a consolidation'));
    await tester.pumpAndSettle();

    expect(bitwindow.metadata.writes, isEmpty);
    expect(find.textContaining('A consolidation holds this coin'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a failed label save shows the error', (tester) async {
    await openRowMenu(tester);
    await tester.tap(find.text('Edit Label'));
    await tester.pumpAndSettle();
    bitwindow.metadata.down = true;

    await tester.enterText(find.byType(EditableText).last, 'Cold storage');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('BitWindow could not save the label'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  test('setFrozen throws when the write fails', () async {
    bitwindow.metadata.down = true;

    await expectLater(GetIt.I<CoinSelectionProvider>().setFrozen(_coin.output, true), throwsException);
  });
}
