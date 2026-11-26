import 'dart:io';

import 'package:bitwindow/pages/wallet/wallet_hd.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _xpub =
    'xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8';

const _descriptor = "wpkh([73c5da0a/84'/0'/0']$_xpub/<0;1>/*)#g8l47ngv";

class _FakeWallet implements OrchestratorWalletRPC {
  @override
  Future<wmpb.ExploreSeedResponse> exploreSeed({
    String mnemonic = '',
    String passphrase = '',
    String walletId = '',
    required String basePath,
    required int startIndex,
    required int count,
  }) async => wmpb.ExploreSeedResponse(
    seedHex: 'seed',
    xprv: 'xprv-master',
    xpub: _xpub,
    bip47PaymentCode: 'PM8code',
    watchDescriptor: _descriptor,
    keys: [wmpb.ExploredKey(path: '$basePath/0', address: 'addr-0', publicKey: 'pub-0', wif: 'wif-0')],
  );

  @override
  Future<String> generateMnemonic() async => _mnemonic;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _FakeWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  bool get usesMainnetParams => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpDerived(WidgetTester tester, {required bool phone}) async {
  SailStyleValues.phoneLayoutOverride = phone;
  await tester.pumpSailPage(const HDWalletTab());
  if (phone) {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
  } else {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
  }
  await tester.pump();
  await tester.tap(find.widgetWithText(SailButton, 'Random'));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.widgetWithText(SailButton, 'Derive Addresses'));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    GetIt.I.registerSingleton<WalletReaderProvider>(WalletReaderProvider(Directory.systemTemp));
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('on a phone each key has its label and Copy on one line and the value under it', (tester) async {
    await _pumpDerived(tester, phone: true);

    expect(tester.takeException(), isNull);
    expect(find.text('XPUB:'), findsNothing);
    final label = tester.getRect(find.text('XPUB'));
    final value = tester.getRect(find.text(_xpub));
    final row = find.ancestor(of: find.text('XPUB'), matching: find.byType(SailStackedValueRow));
    final copy = tester.getRect(find.descendant(of: row, matching: find.byType(SailButton)));
    expect(copy.center.dy, closeTo(label.center.dy, 4));
    expect(copy.left, greaterThanOrEqualTo(label.right));
    expect(value.top, greaterThan(label.bottom));
    expect(value.left, label.left);
    expect(find.byType(SailStackedValueRow), findsNWidgets(5));
  });

  testWidgets('on a phone the mnemonic field spans the card, with its buttons on rows around it', (tester) async {
    await _pumpDerived(tester, phone: true);

    final field = tester.getRect(find.byType(SailTextField).first);
    final random = tester.getRect(find.widgetWithText(SailButton, 'Random'));
    final copy = tester.getRect(find.widgetWithText(SailButton, 'Copy').first);
    final card = tester.getRect(find.byType(SailCard).first);
    expect(field.width, closeTo(card.width - 32 - 2, 2));
    expect(random.bottom, lessThan(field.top));
    expect(tester.getRect(find.widgetWithText(SailButton, 'Use Wallet')).left, closeTo(field.left, 1));
    expect(copy.top, greaterThan(field.bottom));
  });

  testWidgets('on a phone the page controls sit above the addresses', (tester) async {
    await _pumpDerived(tester, phone: true);

    final next = tester.getRect(find.widgetWithText(SailButton, 'Next'));
    final show = tester.getRect(find.widgetWithText(SailButton, 'Show Private Keys'));
    expect(next.center.dy, closeTo(show.center.dy, 1));
    expect(tester.getRect(find.text('addr-0')).top, greaterThan(next.bottom));
  });

  testWidgets('the desktop keeps the colon labels on one row with the value', (tester) async {
    await _pumpDerived(tester, phone: false);

    expect(find.byType(SailStackedValueRow), findsNothing);
    final label = tester.getRect(find.text('XPUB:'));
    final value = tester.getRect(find.text(_xpub));
    expect(value.left, greaterThanOrEqualTo(label.right));
    expect(value.center.dy, closeTo(label.center.dy, 2));
  });

  testWidgets('the Watch Descriptor row shows under XPUB', (tester) async {
    await _pumpDerived(tester, phone: false);

    final label = tester.getRect(find.text('Watch Descriptor:'));
    expect(label.top, greaterThan(tester.getRect(find.text('XPUB:')).bottom));
    expect(find.text(_descriptor), findsOneWidget);
  });

  testWidgets('Derive Addresses comes back on when a good path follows an empty one', (tester) async {
    await _pumpDerived(tester, phone: false);
    SailButton derive() => tester.widget<SailButton>(find.widgetWithText(SailButton, 'Derive Addresses'));

    await tester.enterText(find.byType(SailTextField).last, '');
    await tester.pump();
    expect(derive().onPressed, isNull);

    await tester.enterText(find.byType(SailTextField).last, "m/0'/0");
    await tester.pump();
    expect(derive().onPressed, isNotNull);
  });

  testWidgets('on a phone Show Private Keys shows the WIF of each address', (tester) async {
    await _pumpDerived(tester, phone: true);
    expect(find.text('wif-0'), findsNothing);

    await tester.tap(find.widgetWithText(SailButton, 'Show Private Keys').first);
    await tester.pump();

    expect(find.text('wif-0'), findsOneWidget);
    expect(find.text('pub-0'), findsNothing);
  });
}
