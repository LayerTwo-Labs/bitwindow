import 'dart:math';

import 'package:bitwindow/pages/wallet/wallet_receive.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _first = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _second = 'bcrt1qc862dcz4ellepph35s0lmjg0nn5tt84zte54lw';

class _FakeBitwindow extends ChangeNotifier implements BitwindowRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddressBook extends ChangeNotifier implements AddressBookProvider {
  final List<AddressBookEntry> saved = [];
  String? failWith;

  @override
  List<AddressBookEntry> get receiveEntries => saved;

  @override
  Future<void> createEntry(String label, String address, Direction direction) async {
    if (failWith != null) {
      throw Exception(failWith);
    }
    saved
      ..removeWhere((e) => e.address == address)
      ..add(AddressBookEntry(id: Int64(saved.length + 1), label: label, address: address, direction: direction));
    notifyListeners();
  }

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
  String? addressError;

  @override
  String? error;

  @override
  String address = _first;

  @override
  String addressDerivationPath = "m/84'/1'/0'/0/0";

  @override
  List<wmpb.AddressType> get addressTypes => const [wmpb.AddressType.ADDRESS_TYPE_SEGWIT];

  @override
  wmpb.AddressType get addressType => wmpb.AddressType.ADDRESS_TYPE_SEGWIT;

  @override
  List<ReceiveAddress> receiveAddresses = [];

  @override
  Future<void> fetch() async {}

  void moveTo(String next) {
    address = next;
    notifyListeners();
  }

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  OrchestratorWalletRPC get wallet => _FakeOrchestratorWallet();

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

late _FakeAddressBook _book;
late _FakeTransactions _transactions;

Future<void> _pumpReceiveTab(WidgetTester tester) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });
  _book = _FakeAddressBook();
  _transactions = _FakeTransactions();
  GetIt.I.registerSingleton<BitwindowRPC>(_FakeBitwindow());
  GetIt.I.registerSingleton<AddressBookProvider>(_book);
  GetIt.I.registerSingleton<HDWalletProvider>(_FakeHDWallet());
  GetIt.I.registerSingleton<TransactionProvider>(_transactions);
  GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());
  GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
  GetIt.I.registerSingleton<BitcoinConfProvider>(_FakeConf());

  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpSailPage(
    Theme(
      data: ThemeData(fontFamily: SailFonts.inter),
      child: const ReceiveTab(),
    ),
  );
  await tester.pump();
}

Finder _field(String label) => find.ancestor(of: find.text(label), matching: find.byType(SailTextField)).first;

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.descendant(of: _field(label), matching: find.byType(TextField)), text);
  await tester.pump();
}

String _qrData(WidgetTester tester) {
  final key = tester.widget<QrImageView>(find.byType(QrImageView)).key! as ValueKey<String>;
  return key.value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadBundledFonts();
  });

  setUp(() async {
    await GetIt.I.reset();
  });

  testWidgets('with no request fields the QR code holds the plain address', (tester) async {
    await _pumpReceiveTab(tester);

    expect(_qrData(tester), _first);
    expect(find.text('Payment request'), findsNothing);
  });

  testWidgets('the QR code and the copy field hold the amount, the label and the message', (tester) async {
    await _pumpReceiveTab(tester);

    await _enter(tester, 'Amount', '0.25');
    await _enter(tester, 'Label', 'Invoice 42');
    await _enter(tester, 'Message', 'Thanks for the coffee');

    const request = 'bitcoin:$_first?amount=0.25&label=Invoice%2042&message=Thanks%20for%20the%20coffee';
    expect(_qrData(tester), request);
    expect(find.text('Payment request'), findsOneWidget);
    expect(tester.widget<CopyButton>(find.byType(CopyButton).at(1)).text, request);
  });

  testWidgets('the three request fields have the same height', (tester) async {
    await _pumpReceiveTab(tester);

    final heights = ['Amount', 'Label', 'Message']
        .map((label) => tester.getSize(find.descendant(of: _field(label), matching: find.byType(TextField))).height)
        .toList();
    expect(heights.reduce(max) - heights.reduce(min), lessThan(1));
  });

  testWidgets('an amount in sats goes into the request in whole coins', (tester) async {
    await _pumpReceiveTab(tester);
    await GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.sats);
    addTearDown(() => GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.btc));
    await tester.pump();

    await _enter(tester, 'Amount', '12345');

    expect(_qrData(tester), 'bitcoin:$_first?amount=0.00012345');
  });

  testWidgets('a unit change keeps the request amount', (tester) async {
    await _pumpReceiveTab(tester);
    await GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.sats);
    addTearDown(() => GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.btc));
    await tester.pump();
    await _enter(tester, 'Amount', '1');

    await GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.btc);
    _transactions.notifyListeners();
    await tester.pump();

    expect(_qrData(tester), 'bitcoin:$_first?amount=0.00000001');
  });

  testWidgets('the first unit change keeps an amount entered in BTC', (tester) async {
    await _pumpReceiveTab(tester);
    await _enter(tester, 'Amount', '1');
    addTearDown(() => GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.btc));

    await GetIt.I<SettingsProvider>().updateBitcoinUnit(BitcoinUnit.sats);
    _transactions.notifyListeners();
    await tester.pump();

    expect(_qrData(tester), 'bitcoin:$_first?amount=1');
  });

  testWidgets('a zero amount shows a field error and the QR code keeps the plain address', (tester) async {
    await _pumpReceiveTab(tester);

    await _enter(tester, 'Label', 'Invoice 42');
    await _enter(tester, 'Amount', '0');

    expect(find.text('Enter an amount above zero, or leave the field empty'), findsOneWidget);
    expect(_qrData(tester), _first);
    expect(find.text('Payment request'), findsNothing);
  });

  testWidgets('an amount above 21 million shows a field error', (tester) async {
    await _pumpReceiveTab(tester);

    await _enter(tester, 'Amount', '21000000.00000001');

    expect(find.textContaining('more than 21 million'), findsOneWidget);
    expect(_qrData(tester), _first);
  });

  testWidgets('the request label saves as the address label on submit', (tester) async {
    await _pumpReceiveTab(tester);

    await _enter(tester, 'Label', '  Invoice 42 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(_book.saved.map((e) => '${e.address}=${e.label}'), ['$_first=Invoice 42']);
  });

  testWidgets('a failed label save shows the error on the card', (tester) async {
    await _pumpReceiveTab(tester);
    _book.failWith = 'label taken';

    await _enter(tester, 'Label', 'Invoice 42');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('Could not save the label: Exception: label taken'), findsOneWidget);
  });

  testWidgets('a new address clears the amount and the message and loads its own label', (tester) async {
    await _pumpReceiveTab(tester);
    await _book.createEntry('Old invoice', _second, Direction.DIRECTION_RECEIVE);

    await _enter(tester, 'Amount', '0.25');
    await _enter(tester, 'Label', 'Invoice 42');
    await _enter(tester, 'Message', 'Thanks');
    _transactions.moveTo(_second);
    await tester.pump();

    expect(_qrData(tester), 'bitcoin:$_second?label=Old%20invoice');
    TextField input(String label) =>
        tester.widget<TextField>(find.descendant(of: _field(label), matching: find.byType(TextField)));
    expect(input('Amount').controller!.text, '');
    expect(input('Message').controller!.text, '');
    expect(input('Label').controller!.text, 'Old invoice');
  });

  testWidgets('a saved label that loads later fills the label field', (tester) async {
    await _pumpReceiveTab(tester);

    await _book.createEntry('From the book', _first, Direction.DIRECTION_RECEIVE);
    await tester.pump();

    expect(_qrData(tester), 'bitcoin:$_first?label=From%20the%20book');
  });
}
