import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/pages/explorer/widgets/transaction_flow_diagram.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as walletpb;

import 'test_utils.dart';

class _WalletRPC implements OrchestratorWalletRPC {
  @override
  Future<walletpb.GetTransactionDetailsResponse> getTransactionDetails({
    required String walletId,
    required String txid,
  }) async => walletpb.GetTransactionDetailsResponse(
    txid: txid,
    confirmations: 3,
    version: 2,
    sizeBytes: 222,
    vsizeVbytes: 141,
    weightWu: 561,
    feeSats: Int64(226),
    totalInputSats: Int64(100000226),
    totalOutputSats: Int64(100000000),
    inputs: [walletpb.TransactionInput(index: 0, prevTxid: 'cd' * 32, valueSats: Int64(100000226))],
    outputs: [walletpb.TransactionOutput(index: 0, valueSats: Int64(100000000), scriptType: 'witness_v0_keyhash')],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _WalletRPC();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? activeWalletId = 'wallet-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transactions extends ChangeNotifier implements TransactionProvider {
  @override
  List<walletpb.WalletTransaction> walletTransactions = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final v2 = SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<TransactionProvider>(_Transactions());
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpSailPage(
      SailTheme(
        data: v2,
        child: Center(
          child: SizedBox(width: 900, height: 700, child: TransactionDetailsDialog(txid: 'ab' * 32)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the overview shows four grey groups in two columns and a ×', (tester) async {
    await pumpDialog(tester);

    expect(find.byType(SailIconBoxButton), findsOneWidget);
    for (final heading in ['Transaction Info', 'Fee', 'Size', 'Totals']) {
      expect(find.widgetWithText(SailDetailHeading, heading), findsOneWidget);
    }
    expect(find.byType(SailDetailGroup), findsNWidgets(4));
    final info = tester.getTopLeft(find.widgetWithText(SailDetailHeading, 'Transaction Info'));
    final size = tester.getTopLeft(find.widgetWithText(SailDetailHeading, 'Size'));
    expect(size.dy, info.dy);
    expect(size.dx, greaterThan(info.dx));
    expect(find.byType(TransactionFlowDiagram), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Diagram tab keeps the flow diagram', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Diagram'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionDiagram), findsOneWidget);
    expect(find.byType(TransactionFlowDiagram), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the v2 overview keeps the In this wallet rows of a wallet transaction', (tester) async {
    await tester.pumpSailPage(
      SailTheme(
        data: v2,
        child: Center(
          child: SizedBox(
            width: 900,
            height: 700,
            child: TxOverviewGroups(
              details: walletpb.GetTransactionDetailsResponse(txid: 'ab' * 32, confirmations: 1),
              walletTx: walletpb.WalletTransaction(
                txid: 'ab' * 32,
                confirmations: 1,
                confirmationTime: walletpb.Confirmation(height: 6),
                receivedSatoshi: Int64(10000),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('In this wallet'), findsOneWidget);
    expect(find.text('Transaction Info'), findsOneWidget);
  });
}
