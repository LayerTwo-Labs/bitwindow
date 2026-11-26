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
const _taproot = 'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr';
const _publicKey = '0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c';
const _wif = 'KyZpNDKnfs94vbrwhJneDi77V6jF64PWPF8x5cdJb8ifgg2DUc9d';

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
    keys: longKeys
        ? [wmpb.ExploredKey(path: '$basePath/0', address: _taproot, publicKey: _publicKey, wif: _wif)]
        : [wmpb.ExploredKey(path: '$basePath/0', address: 'addr-0', publicKey: 'pub-0', wif: 'wif-0')],
  );

  bool longKeys = false;

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

Future<void> _pumpDerived(WidgetTester tester, {required bool phone, double width = 1200}) async {
  SailStyleValues.phoneLayoutOverride = phone;
  await tester.pumpSailPage(const HDWalletTab());
  if (phone) {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
  } else {
    await tester.binding.setSurfaceSize(Size(width, 1200));
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

  testWidgets('the desktop page controls sit above the addresses', (tester) async {
    await _pumpDerived(tester, phone: false);

    final next = tester.getRect(find.widgetWithText(SailButton, 'Next'));
    final show = tester.getRect(find.widgetWithText(SailButton, 'Show Private Keys'));
    expect(next.center.dy, closeTo(show.center.dy, 1));
    expect(tester.getRect(find.text('addr-0')).top, greaterThan(next.bottom));
  });

  for (final width in [1280.0, 1024.0]) {
    testWidgets('at $width px the four key columns fit the card, with and without the WIF', (tester) async {
      (GetIt.I.get<OrchestratorRPC>().wallet as _FakeWallet).longKeys = true;
      await _pumpDerived(tester, phone: false, width: width);
      await tester.pumpAndSettle();

      for (final shown in [false, true]) {
        if (shown) {
          await tester.tap(find.widgetWithText(SailButton, 'Show Private Keys'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byType(SailCard).last);
        expect(tester.getRect(find.text('Private Key (WIF)')).right, lessThanOrEqualTo(card.right));
        expect(tester.getRect(find.text(_taproot)).right, lessThanOrEqualTo(card.right));
        expect(tester.getRect(find.text(_publicKey)).right, lessThanOrEqualTo(card.right));
        if (shown) {
          expect(tester.getRect(find.text(_wif)).right, lessThanOrEqualTo(card.right));
        }
      }
    });
  }

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
