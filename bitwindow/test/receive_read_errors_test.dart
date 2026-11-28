import 'package:bitwindow/pages/wallet/wallet_receive.dart';
import 'package:bitwindow/pages/wallet/widgets/wallet_v2_parts.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _address = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

class _FakeBitwindow extends ChangeNotifier implements BitwindowRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddressBook extends ChangeNotifier implements AddressBookProvider {
  @override
  List<AddressBookEntry> get receiveEntries => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHDWallet extends ChangeNotifier implements HDWalletProvider {
  @override
  bool get isInitialized => true;

  @override
  String get bip47PaymentCode => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactions extends ChangeNotifier implements TransactionProvider {
  @override
  String address = '';

  @override
  String addressDerivationPath = '';

  @override
  String? addressError;

  @override
  String? error;

  @override
  List<wmpb.AddressType> get addressTypes => const [wmpb.AddressType.ADDRESS_TYPE_SEGWIT];

  @override
  wmpb.AddressType get addressType => wmpb.AddressType.ADDRESS_TYPE_SEGWIT;

  @override
  List<ReceiveAddress> receiveAddresses = [];

  @override
  Future<void> fetch() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? activeWalletId = 'wallet-1';

  @override
  WalletData? get activeWallet => null;

  @override
  bool get isWalletLocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestratorWallet implements OrchestratorWalletRPC {
  @override
  Future<wmpb.GetNewAddressResponse> getNewAddress(String walletId, {wmpb.AddressType? addressType}) async =>
      wmpb.GetNewAddressResponse(address: _address);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  OrchestratorWalletRPC wallet = _FakeOrchestratorWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String ecashNetworkId = '';

  @override
  String currentNetworkOptionId = 'regtest';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeTransactions> _pumpReceiveTab(WidgetTester tester) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });
  final transactions = _FakeTransactions();
  GetIt.I.registerSingleton<BitwindowRPC>(_FakeBitwindow());
  GetIt.I.registerSingleton<AddressBookProvider>(_FakeAddressBook());
  GetIt.I.registerSingleton<HDWalletProvider>(_FakeHDWallet());
  GetIt.I.registerSingleton<TransactionProvider>(transactions);
  GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());
  GetIt.I.registerSingleton<BitcoinConfProvider>(_FakeConf());
  GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());

  await tester.pumpSailPage(const ReceiveTab());
  await tester.pump();
  return transactions;
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  testWidgets('a failed address read shows on the address strip in place of the loading hint', (tester) async {
    final transactions = await _pumpReceiveTab(tester);
    transactions
      ..addressError = 'no chain source'
      ..notifyListeners();
    await tester.pump();

    final strip = find.byType(ReceiveAddressStrip);
    expect(
      find.descendant(of: strip, matching: find.text('Could not get a receive address: no chain source')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: strip, matching: find.text('Waiting for enforcer to start and wallet to sync..')),
      findsNothing,
    );
    expect(find.text('Generate new address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed address read keeps the last address beside the error', (tester) async {
    final transactions = await _pumpReceiveTab(tester);
    transactions
      ..address = _address
      ..addressError = 'connection refused'
      ..notifyListeners();
    await tester.pump();

    expect(find.text('Could not get a receive address: connection refused'), findsOneWidget);
    expect(find.text('Generate new address'), findsNothing);
  });

  testWidgets('a failed wallet read shows on the address table in place of the skeleton', (tester) async {
    final transactions = await _pumpReceiveTab(tester);
    transactions
      ..error = 'bitcoind is down'
      ..notifyListeners();
    await tester.pump();

    final card = find.widgetWithText(WalletTableCard, 'Addresses');
    expect(
      find.descendant(of: card, matching: find.text('Could not read the wallet: bitcoind is down')),
      findsOneWidget,
    );
    final skeleton = tester.widget<SailSkeletonizer>(
      find.descendant(of: card, matching: find.byType(SailSkeletonizer)),
    );
    expect(skeleton.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read that works again clears both errors', (tester) async {
    final transactions = await _pumpReceiveTab(tester);
    transactions
      ..addressError = 'no chain source'
      ..error = 'bitcoind is down'
      ..notifyListeners();
    await tester.pump();
    transactions
      ..addressError = null
      ..error = null
      ..address = _address
      ..notifyListeners();
    await tester.pump();

    expect(find.textContaining('Could not'), findsNothing);
  });
}
