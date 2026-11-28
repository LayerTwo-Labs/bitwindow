import 'dart:async';

import 'package:bitwindow/pages/wallet/bump_fee_dialog.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:connectrpc/connect.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

class _FakeWallet implements OrchestratorWalletRPC {
  final rates = <int?>[];
  final replies = <Completer<wmpb.PreviewBumpFeeResponse>>[];

  @override
  Future<wmpb.PreviewBumpFeeResponse> previewBumpFee({
    required String walletId,
    required String txid,
    int? newFeeRate,
    int? feeFromVout,
  }) {
    rates.add(newFeeRate);
    final reply = Completer<wmpb.PreviewBumpFeeResponse>();
    replies.add(reply);
    return reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _FakeWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactions extends ChangeNotifier implements TransactionProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? activeWalletId = 'wallet-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

wmpb.PreviewBumpFeeResponse _preview() => wmpb.PreviewBumpFeeResponse(suggestedFeeRate: Int64(5), canReplace: true);

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('the fee preview points to Daemon Status when Core stops', (tester) async {
    final orchestrator = _FakeOrchestrator();
    final wallet = orchestrator.wallet as _FakeWallet;
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());

    await tester.pumpSailPage(const BumpFeeDialog(txid: 'aa'));
    wallet.replies.single.completeError(
      ConnectException(Code.failedPrecondition, 'Transaction waits in no mempool: connection refused'),
    );
    await tester.pump();

    expect(find.text('Could not read the mempool. Check Daemon Status, then try again.'), findsOneWidget);
    expect(find.byType(LoadingIndicator), findsNothing);
    final replace = tester.widget<SailButton>(
      find.byWidgetPredicate((w) => w is SailButton && w.label == 'Replace transaction'),
    );
    expect(replace.disabled, isTrue);
  });

  testWidgets('a typed rate asks for its preview at once', (tester) async {
    final orchestrator = _FakeOrchestrator();
    final wallet = orchestrator.wallet as _FakeWallet;
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());

    await tester.pumpSailPage(const BumpFeeDialog(txid: 'aa'));
    wallet.replies.single.complete(_preview());
    await tester.pump();

    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();

    expect(wallet.rates, [null, 9]);
  });

  testWidgets('each typed rate asks for its own preview', (tester) async {
    final orchestrator = _FakeOrchestrator();
    final wallet = orchestrator.wallet as _FakeWallet;
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());

    await tester.pumpSailPage(const BumpFeeDialog(txid: 'aa'));
    wallet.replies.single.complete(_preview());
    await tester.pump();

    final field = find.byType(TextField);
    await tester.enterText(field, '9');
    await tester.enterText(field, '8');
    await tester.enterText(field, '9');
    await tester.pump();

    expect(wallet.rates, [null, 9, 8, 9]);
  });

  testWidgets('a typed rate shows a spinner under the plan while its preview loads', (tester) async {
    final orchestrator = _FakeOrchestrator();
    final wallet = orchestrator.wallet as _FakeWallet;
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());

    await tester.pumpSailPage(const BumpFeeDialog(txid: 'aa'));
    wallet.replies.single.complete(_preview());
    await tester.pump();
    expect(find.byType(LoadingIndicator), findsNothing);

    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    wallet.replies.last.complete(_preview());
    await tester.pump();
    expect(find.byType(LoadingIndicator), findsNothing);
  });

  testWidgets('the reason no replacement works reads as an inline error', (tester) async {
    final orchestrator = _FakeOrchestrator();
    final wallet = orchestrator.wallet as _FakeWallet;
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());

    await tester.pumpSailPage(const BumpFeeDialog(txid: 'aa'));
    wallet.replies.single.complete(
      wmpb.PreviewBumpFeeResponse(
        suggestedFeeRate: Int64(5),
        reason: 'this transaction does not signal replacement, so no replacement can follow it',
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(SailInlineError),
        matching: find.textContaining('this transaction does not signal replacement'),
      ),
      findsOneWidget,
    );
  });
}
