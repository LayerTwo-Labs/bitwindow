import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/pages/wallet/cash_check_page.dart';
import 'package:bitwindow/pages/wallet/cash_check_success_page.dart';
import 'package:bitwindow/pages/wallet/check_detail_page.dart';
import 'package:bitwindow/pages/wallet/create_check_page.dart';
import 'package:bitwindow/providers/check_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as bwpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _address = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _txid = 'f3a1c09e5b7d2468ace013579bdf2468ace013579bdf2468ace013579bdf2468';
const _phone = Size(390, 844);

class _FakeCheckProvider extends ChangeNotifier implements CheckProvider {
  _FakeCheckProvider({this.funded = false, this.swept = false});

  final bool funded;
  final bool swept;

  @override
  Future<bwpb.Cheque> getCheck(int id) async => bwpb.Cheque(
    id: Int64(1),
    address: _address,
    expectedAmountSats: Int64(1000000),
    funded: funded,
    sweptTxid: swept ? _txid : null,
    fundedTxids: funded ? [_txid] : [],
    privateKeyWif: funded ? 'cVt4o7BGAig1UXywgGSmARhxMdzP5qvQsxKkSsc1XEkw3tDTQFpy' : null,
  );

  @override
  List<bwpb.Cheque> get checks => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProviders extends ChangeNotifier implements TransactionProvider, WalletReaderProvider {
  @override
  String? activeWalletId = 'wallet-1';

  @override
  String address = _address;

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

class _FakeWalletAPI implements WalletAPI {
  _FakeWalletAPI({this.keyAmountSats = 123456});

  final int keyAmountSats;
  String? previewDestination;
  (String, int)? sweep;

  @override
  Future<SweepPreview> previewSweep(
    String privateKeyWif, {
    int feeSatPerVbyte = 0,
    String destinationAddress = '',
  }) async {
    previewDestination = destinationAddress;
    return SweepPreview(
      address: _address,
      addressKind: bwpb.SweepAddressKind.SWEEP_ADDRESS_KIND_P2WPKH,
      amountSats: keyAmountSats,
      outputCount: keyAmountSats == 0 ? 0 : 1,
      feeSatPerVbyte: 2,
      feeSats: 220,
      receiveSats: keyAmountSats == 0 ? 0 : keyAmountSats - 220,
    );
  }

  @override
  Future<SweepChequeResult> sweepCheque(
    String walletId,
    String privateKeyWif,
    String destinationAddress,
    int feeSatPerVbyte,
  ) async {
    sweep = (destinationAddress, feeSatPerVbyte);
    return SweepChequeResult(txid: _txid, amountSats: 123456, receiveSats: 123236);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBitwindow implements BitwindowRPC {
  _FakeBitwindow({int keyAmountSats = 123456}) : wallet = _FakeWalletAPI(keyAmountSats: keyAmountSats);

  @override
  final _FakeWalletAPI wallet;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CashCheckRouter extends AppRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(path: '/', page: CashCheckRoute.page),
    AutoRoute(path: '/cash-check-success/:txid', page: CashCheckSuccessRoute.page),
  ];
}

void _registerFakes({bool funded = false, bool swept = false, int keyAmountSats = 123456}) {
  final providers = _FakeProviders();
  GetIt.I.registerSingleton<CheckProvider>(_FakeCheckProvider(funded: funded, swept: swept));
  GetIt.I.registerSingleton<TransactionProvider>(providers);
  GetIt.I.registerSingleton<WalletReaderProvider>(providers);
  GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
  GetIt.I.registerSingleton<BitwindowRPC>(_FakeBitwindow(keyAmountSats: keyAmountSats));
}

Future<void> _pump(WidgetTester tester, Widget page, {required bool phone}) async {
  SailStyleValues.phoneLayoutOverride = phone;
  await tester.pumpSailPage(page);
  if (phone) {
    await tester.binding.setSurfaceSize(_phone);
  }
  await tester.pump();
  await tester.pump();
}

bool _inCard(String text) =>
    find.descendant(of: find.byType(SailCard), matching: find.text(text)).evaluate().isNotEmpty;

double? _fontSize(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!.fontSize;

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  group('Create Check and Cash Check', () {
    for (final (name, page, heading) in [
      ('Create Check', const CreateCheckPage(), 'How much should the check be for?'),
      ('Cash Check', const CashCheckPage(), 'Enter the private key (WIF)'),
    ]) {
      testWidgets('$name puts its content in one panel with a 15 px heading on a phone', (tester) async {
        _registerFakes();
        await _pump(tester, page, phone: true);

        expect(tester.takeException(), isNull);
        expect(_inCard(heading), isTrue);
        expect(_fontSize(tester, heading), 15);
      });

      testWidgets('$name keeps the large heading and no panel on the desktop', (tester) async {
        _registerFakes();
        await _pump(tester, page, phone: false);

        expect(_inCard(heading), isFalse);
        expect(_fontSize(tester, heading), 24);
      });
    }
  });

  testWidgets('Create Check refuses an amount above the money supply', (tester) async {
    _registerFakes();
    await _pump(tester, const CreateCheckPage(), phone: false);

    await tester.enterText(find.byType(TextField), '21000001');
    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.text('Please enter a valid amount'), findsOneWidget);
  });

  testWidgets('Create Check refuses an amount that the wallet cannot send', (tester) async {
    _registerFakes();
    await _pump(tester, const CreateCheckPage(), phone: false);

    await tester.enterText(find.byType(TextField), '0.00000545');
    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.text('Please enter a valid amount'), findsOneWidget);
  });

  group('Cash Check before the sweep', () {
    Future<void> typeKey(WidgetTester tester) async {
      await tester.enterText(find.byType(EditableText), 'qa-check-key');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    bool cashOff(WidgetTester tester) => tester
        .widget<SailButton>(find.byWidgetPredicate((widget) => widget is SailButton && widget.label == 'Cash Check'))
        .disabled;

    for (final phone in [false, true]) {
      testWidgets('shows the amount, the fee and the received amount (phone: $phone)', (tester) async {
        _registerFakes();
        await _pump(tester, const CashCheckPage(), phone: phone);
        expect(cashOff(tester), isTrue);

        await typeKey(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('0.00123456 ${activeTicker.symbol}'), findsOneWidget);
        expect(find.text('0.00000220 ${activeTicker.symbol}'), findsOneWidget);
        expect(find.text('0.00123236 ${activeTicker.symbol}'), findsOneWidget);
        expect(cashOff(tester), isFalse);
        final wallet = (GetIt.I.get<BitwindowRPC>() as _FakeBitwindow).wallet;
        expect(wallet.previewDestination, _address);
        expect(wallet.sweep, isNull);
      });
    }

    testWidgets('a key with no coins shows the reason and keeps Cash Check off', (tester) async {
      _registerFakes(keyAmountSats: 0);
      await _pump(tester, const CashCheckPage(), phone: false);

      await typeKey(tester);

      expect(find.text('This key holds no coins.'), findsOneWidget);
      expect(find.text('Network fee:'), findsNothing);
      expect(cashOff(tester), isTrue);
    });

    testWidgets('a changed key removes the numbers of the old key', (tester) async {
      _registerFakes();
      await _pump(tester, const CashCheckPage(), phone: false);
      await typeKey(tester);

      await tester.enterText(find.byType(EditableText), 'qa-check-key-2');
      await tester.pump();

      expect(find.text('Network fee:'), findsNothing);
      expect(cashOff(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('check details', () {
    testWidgets('an unfunded check on a phone shows a dot, the address on one line and a full-width button', (
      tester,
    ) async {
      _registerFakes();
      await _pump(tester, const CheckDetailPage(checkId: 1), phone: true);

      expect(tester.takeException(), isNull);
      expect(_inCard('Awaiting funding'), isTrue);
      final card = tester.getRect(find.byType(SailCard));
      expect(tester.getCenter(find.text('Awaiting funding')).dx, greaterThan(card.center.dx));
      expect(find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 8), findsOneWidget);

      final address = tester.getRect(find.text(_address));
      final copy = tester.getRect(find.byType(CopyButton));
      expect(address.height, lessThan(24), reason: 'the address stays on one line');
      expect(copy.left, greaterThanOrEqualTo(address.right));
      expect(copy.center.dy, closeTo(address.center.dy, 2));

      final button = tester.getRect(find.widgetWithText(SailButton, 'Fund with Wallet'));
      expect(button.width, closeTo(card.width - 32 - 2, 2));
    });

    testWidgets('a funded check on a phone shows a full-width sweep button', (tester) async {
      _registerFakes(funded: true);
      await _pump(tester, const CheckDetailPage(checkId: 1), phone: true);

      expect(tester.takeException(), isNull);
      expect(_inCard('Funded'), isTrue);
      final card = tester.getRect(find.byType(SailCard));
      final button = tester.getRect(find.widgetWithText(SailButton, 'Sweep Check to Wallet'));
      expect(button.width, closeTo(card.width - 32 - 2, 2));
    });

    testWidgets('the desktop keeps the rings and the 400 px button', (tester) async {
      _registerFakes();
      await _pump(tester, const CheckDetailPage(checkId: 1), phone: false);

      expect(find.byType(SailCard), findsNothing);
      expect(tester.getSize(find.widgetWithText(SailButton, 'Fund with Wallet')).width, 400);
    });
  });

  group('swept check detail', () {
    for (final (size, funded) in [
      (const Size(1200, 720), true),
      (const Size(1024, 700), true),
      (const Size(1024, 700), false),
    ]) {
      testWidgets('shows Swept at ${size.width.toInt()} px with funding record $funded', (tester) async {
        _registerFakes(funded: funded, swept: true);
        await _pump(tester, const CheckDetailPage(checkId: 1), phone: false);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Swept'), findsOneWidget);
        expect(find.text('Fund with Wallet'), findsNothing);
        expect(find.text('Sweep Check to Wallet'), findsNothing);
      });
    }
  });

  group('check cashed', () {
    for (final size in [const Size(1200, 720), const Size(1024, 700)]) {
      testWidgets('cash check shows the amount paid at ${size.width.toInt()} px', (tester) async {
        _registerFakes();
        final router = _CashCheckRouter();
        addTearDown(router.dispose);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          SailTheme(
            data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
            child: MaterialApp.router(routerConfig: router.config()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(EditableText), 'qa-check-key');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.tap(find.byWidgetPredicate((widget) => widget is SailButton && widget.label == 'Cash Check'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('0.00123236 ${activeTicker.symbol}'), findsOneWidget);
        expect(find.text('0.00123456 ${activeTicker.symbol}'), findsNothing);
        expect((GetIt.I.get<BitwindowRPC>() as _FakeBitwindow).wallet.sweep, (_address, 2));
      });
    }

    testWidgets('on a phone the amount and the transaction are label and value rows, Done at the right', (
      tester,
    ) async {
      await _pump(tester, const CashCheckSuccessPage(txid: _txid, amountSats: 1000000), phone: true);

      expect(tester.takeException(), isNull);
      expect(_inCard('Your Check was Cashed'), isTrue);
      expect(_fontSize(tester, 'Your Check was Cashed'), 15);

      final label = tester.getRect(find.text('Amount'));
      final value = tester.getRect(find.text('0.01000000 ${activeTicker.symbol}'));
      expect(value.left, greaterThan(label.right));
      expect(value.center.dy, closeTo(label.center.dy, 1));
      expect(find.text('Transaction'), findsOneWidget);

      final card = tester.getRect(find.byType(SailCard));
      final done = tester.getRect(find.widgetWithText(SailButton, 'Done'));
      expect(_inCard('Done'), isTrue);
      expect(done.right, closeTo(card.right - 16 - 1, 1));
    });

    testWidgets('the desktop keeps the large title and the colon labels', (tester) async {
      await _pump(tester, const CashCheckSuccessPage(txid: _txid, amountSats: 1000000), phone: false);

      expect(_fontSize(tester, 'Your Check was Cashed'), 40);
      expect(find.text('Amount:'), findsOneWidget);
    });
  });
}
