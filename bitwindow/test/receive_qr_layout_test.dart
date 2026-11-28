import 'dart:io';
import 'dart:ui' as ui;

import 'package:bitwindow/pages/wallet/wallet_receive.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/widgets/burn_ecx_card.dart';
import 'package:bitwindow/widgets/claim_ecx_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _address = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _cardTitle = 'Receive Bitcoin on L1';
const _derivationPath = "m/84'/1'/0'/0/0";
const _taprootAddress = 'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297';
const _taprootPath = "m/86'/0'/0'/0/0";

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
  String? addressError;

  @override
  String? error;

  _FakeTransactions(this.addressTypes, this.address, this.addressDerivationPath);

  @override
  String address;

  @override
  String addressDerivationPath;

  @override
  final List<wmpb.AddressType> addressTypes;

  @override
  wmpb.AddressType get addressType => addressTypes.first;

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
  Future<wmpb.GetNewAddressResponse> getNewAddress(String walletId, {wmpb.AddressType? addressType}) async {
    return wmpb.GetNewAddressResponse(address: _address);
  }

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

  void changeNetwork(BitcoinNetwork value, String id) {
    network = value;
    ecashNetworkId = value == BitcoinNetwork.BITCOIN_NETWORK_ECASH ? id : '';
    currentNetworkOptionId = id;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpReceiveTab(
  WidgetTester tester, {
  List<wmpb.AddressType> addressTypes = const [wmpb.AddressType.ADDRESS_TYPE_SEGWIT],
  _FakeConf? conf,
  String address = _address,
  String derivationPath = _derivationPath,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });
  GetIt.I.registerSingleton<BitwindowRPC>(_FakeBitwindow());
  GetIt.I.registerSingleton<AddressBookProvider>(_FakeAddressBook());
  GetIt.I.registerSingleton<HDWalletProvider>(_FakeHDWallet());
  GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions(addressTypes, address, derivationPath));
  GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());
  GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
  GetIt.I.registerSingleton<BitcoinConfProvider>(conf ?? _FakeConf());

  await tester.pumpSailPage(
    Theme(
      data: ThemeData(fontFamily: SailFonts.inter),
      child: const ReceiveTab(),
    ),
  );
  await tester.pump();
}

Finder _strip() => find.byType(ReceiveAddressStrip);

Finder _stripQr() => find.descendant(of: _strip(), matching: find.byType(QrImageView));

Finder _stripAddress() => find.descendant(of: _strip(), matching: find.text(_address));

Finder _addressCard() => find.widgetWithText(SailCard, _cardTitle);

Finder _qr() => find.descendant(of: _addressCard(), matching: find.byType(QrImageView));

Finder _addressField() => find.descendant(of: _addressCard(), matching: find.byType(SailTextField)).first;

RenderEditable _addressEditable() => find
    .descendant(of: _addressField(), matching: find.byWidgetPredicate((widget) => true))
    .evaluate()
    .map((element) => element.renderObject)
    .whereType<RenderEditable>()
    .first;

Future<void> _setWindowSize(WidgetTester tester, Size size) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadBundledFonts();
  });

  setUp(() async {
    await GetIt.I.reset();
  });

  testWidgets('the Receive tab shows the production burn below the claim on Betanet', (tester) async {
    final conf = _FakeConf()..changeNetwork(BitcoinNetwork.BITCOIN_NETWORK_ECASH, 'betanet');
    await _pumpReceiveTab(tester, conf: conf);

    final card = tester.widget<BurnEcxCard>(find.byType(BurnEcxCard));
    expect(card.burnAddress, '1BitcoinEaterAddressDontSendf59kuE');
    expect(card.minimumSats, 100000000000);
    final title = find
        .text('Burn Betanet Coins')
        .evaluate()
        .where((element) => element.findAncestorWidgetOfExactType<SailButton>() == null);
    expect(title, hasLength(1));
    expect(
      find.byWidgetPredicate((widget) => widget is SailButton && widget.label == 'Burn Transaction'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byType(BurnEcxCard)).dy,
      greaterThan(tester.getBottomLeft(find.byType(ClaimEcxCard)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Receive tab changes burn access with the network', (tester) async {
    final conf = _FakeConf();
    await _pumpReceiveTab(tester, conf: conf);
    void expectNoBurnGap() {
      expect(find.byType(BurnEcxCard), findsNothing);
      final actionCards = find.byWidgetPredicate(
        (widget) => widget is SailColumn && widget.children.any((child) => child is ClaimEcxCard),
      );
      expect(tester.getSize(actionCards).height, tester.getSize(find.byType(ClaimEcxCard)).height);
    }

    expectNoBurnGap();

    conf.changeNetwork(BitcoinNetwork.BITCOIN_NETWORK_ECASH, 'betanet');
    await tester.pump();
    expect(find.byType(BurnEcxCard), findsOneWidget);
    expect(find.text('Burn Betanet Coins'), findsOneWidget);

    conf.changeNetwork(BitcoinNetwork.BITCOIN_NETWORK_ECASH, 'ecash');
    await tester.pump();
    expectNoBurnGap();

    conf.changeNetwork(BitcoinNetwork.BITCOIN_NETWORK_MAINNET, 'betanet');
    await tester.pump();
    expectNoBurnGap();
    expect(find.byType(ClaimEcxCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Receive tab uses the catalog Betanet ID when the explicit ID is empty', (tester) async {
    final conf = _FakeConf()
      ..network = BitcoinNetwork.BITCOIN_NETWORK_ECASH
      ..currentNetworkOptionId = 'betanet';
    await _pumpReceiveTab(tester, conf: conf);

    expect(find.byType(BurnEcxCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the QR code sits inside the address strip', (tester) async {
    await _pumpReceiveTab(tester);

    expect(_strip(), findsOneWidget);
    expect(_stripQr(), findsOneWidget);
  });

  testWidgets('the QR code sits to the left of the address', (tester) async {
    await _pumpReceiveTab(tester);

    expect(tester.getTopRight(_stripQr()).dx, lessThanOrEqualTo(tester.getTopLeft(_stripAddress()).dx));
  });

  testWidgets('on a 390 px phone the address wraps beside the QR code', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    await _pumpReceiveTab(tester);
    await tester.usePhoneSize();
    await tester.pump();

    expect(_addressEditable().maxLines, isNull);
    expect(tester.getTopLeft(_qr()).dx, greaterThanOrEqualTo(tester.getTopRight(_addressField()).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the address type dropdown sits above the address', (tester) async {
    await _pumpReceiveTab(
      tester,
      addressTypes: const [wmpb.AddressType.ADDRESS_TYPE_SEGWIT, wmpb.AddressType.ADDRESS_TYPE_TAPROOT],
    );

    final dropdown = find.descendant(of: _strip(), matching: find.byType(SailDropdownButton<wmpb.AddressType>));
    expect(dropdown, findsOneWidget);
    expect(tester.getTopLeft(dropdown).dy, lessThan(tester.getTopLeft(_stripAddress()).dy));
  });

  testWidgets('a wallet with one address type shows no dropdown', (tester) async {
    await _pumpReceiveTab(tester);

    expect(find.byType(SailDropdownButton<wmpb.AddressType>), findsNothing);
  });

  for (final size in const [Size(1200, 600), Size(1024, 700)]) {
    testWidgets(
      'a Taproot address shows in full with the path below it at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpReceiveTab(tester, address: _taprootAddress, derivationPath: _taprootPath);
        await _setWindowSize(tester, size);

        expect(_taprootAddress, hasLength(62));
        final address = find.descendant(of: _strip(), matching: find.text(_taprootAddress));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: address, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width));

        final path = find.descendant(of: _strip(), matching: find.text(_taprootPath));
        expect(path, findsOneWidget);
        expect(tester.getTopLeft(path).dy, greaterThan(tester.getBottomLeft(address).dy));
        expect(tester.getTopLeft(path).dx, tester.getTopLeft(address).dx);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the path line is absent when the path is empty', (tester) async {
    await _pumpReceiveTab(tester, address: _taprootAddress, derivationPath: '');
    await _setWindowSize(tester, const Size(1200, 600));

    expect(find.descendant(of: _strip(), matching: find.textContaining(RegExp(r'^m/'))), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the narrowest window stacks the strip, the addresses and the claim card', (tester) async {
    await _pumpReceiveTab(tester);
    await _setWindowSize(tester, const Size(400, 900));

    final path = find.descendant(of: _strip(), matching: find.text(_derivationPath));
    expect(path, findsOneWidget);
    expect(tester.getTopLeft(path).dy, greaterThan(tester.getBottomLeft(_stripAddress()).dy));
    expect(
      tester.getTopLeft(find.byType(ReceiveAddressesTable)).dy,
      greaterThan(tester.getBottomLeft(_strip()).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the strip has Copy and New address, and the search filters the addresses', (tester) async {
    await _pumpReceiveTab(tester);
    await _setWindowSize(tester, const Size(1440, 900));
    final transactions = GetIt.I<TransactionProvider>() as _FakeTransactions;
    transactions
      ..receiveAddresses = [
        ReceiveAddress(address: _address, label: 'Exchange', derivationPath: _derivationPath),
        ReceiveAddress(address: 'bcrt1qcoldstorage0000000000000000000000000', isChange: true),
      ]
      ..notifyListeners();
    await tester.pump();

    expect(find.descendant(of: _strip(), matching: find.widgetWithText(SailButton, 'Copy')), findsOneWidget);
    expect(find.descendant(of: _strip(), matching: find.widgetWithText(SailButton, 'New address')), findsOneWidget);
    final table = find.byType(ReceiveAddressesTable);
    expect(find.descendant(of: table, matching: find.text('Exchange')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('No label')), findsOneWidget);
    await _shot(tester, 'receive');

    await tester.enterText(
      find.descendant(of: table, matching: find.byType(EditableText)),
      'exch',
    );
    await tester.pump();
    expect(find.descendant(of: table, matching: find.text('Exchange')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('No label')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['WALLET_SHOT_DIR'];
  if (dir == null) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
