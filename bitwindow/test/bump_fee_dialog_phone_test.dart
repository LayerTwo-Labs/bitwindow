import 'dart:io';

import 'package:bitwindow/pages/wallet/bump_fee_dialog.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

class _FakeWalletRPC implements OrchestratorWalletRPC {
  @override
  Future<wmpb.PreviewBumpFeeResponse> previewBumpFee({
    required String walletId,
    required String txid,
    int? newFeeRate,
    int? feeFromVout,
  }) async {
    return wmpb.PreviewBumpFeeResponse(
      inputCount: 1,
      vsizeVbytes: Int64(141),
      oldFeeSats: Int64(141),
      oldFeeRateSatVb: 1,
      suggestedFeeRate: Int64(5),
      canReplace: true,
      outputs: [wmpb.BumpFeeOutput(vout: 0, address: 'tb1qpayment', amountSats: Int64(100000))],
      reason: 'The transaction has no change output',
      cancel: wmpb.CancelPlan(feeSats: Int64(500), recoveredSats: Int64(99500)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final _FakeWalletRPC wallet = _FakeWalletRPC();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends WalletReaderProvider {
  _WalletReader() : super(Directory.systemTemp) {
    activeWalletId = 'wallet-1';
  }
}

Finder _button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);

Future<void> _pumpDialog(WidgetTester tester, {bool phone = false}) async {
  await tester.pumpSailPage(const BumpFeeDialog(txid: 'ab12'));
  if (phone) {
    await tester.usePhoneSize();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<TransactionProvider>(TransactionProvider());
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
  }

  testWidgets('Replace is the one button; Cancel and RBF sit in "…"; no Close', (tester) async {
    await _pumpDialog(tester);

    expect(find.byType(SailButton), findsOneWidget);
    expect(_button('Replace transaction'), findsOneWidget);
    expect(_button('Close'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x), findsOneWidget);

    await openMenu(tester);
    expect(find.text('Cancel transaction'), findsOneWidget);
    expect(find.text('I want to RBF it'), findsOneWidget);
  });

  testWidgets('I want to RBF it shows the outputs to take the fee from', (tester) async {
    await _pumpDialog(tester);
    await openMenu(tester);
    await tester.tap(find.text('I want to RBF it'));
    await tester.pumpAndSettle();

    expect(find.text('Take the fee from'), findsOneWidget);
    expect(find.text('Output 0 · payment'), findsOneWidget);
    expect(find.text('tb1qpayment'), findsOneWidget);
  });

  testWidgets('Cancel transaction has a ← back and one destructive button', (tester) async {
    await _pumpDialog(tester);
    await openMenu(tester);
    await tester.tap(find.text('Cancel transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel the transaction'), findsOneWidget);
    expect(find.text('Returns to this wallet'), findsOneWidget);
    expect(find.byType(SailButton), findsOneWidget);
    expect(tester.widget<SailButton>(_button('Cancel transaction')).variant, ButtonVariant.destructive);
    expect(_button('Back'), findsNothing);

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.arrowLeft));
    await tester.pumpAndSettle();
    expect(find.text('Bump the fee'), findsOneWidget);
  });

  testWidgets('on a phone the dialog fits with no overflow', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pumpDialog(tester, phone: true);

    expect(find.text('This transaction'), findsOneWidget);
    expect(find.text('New fee'), findsOneWidget);
    expect(_button('Replace transaction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
