import 'dart:io';

import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:connectrpc/connect.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as walletpb;

import 'test_utils.dart';

class _Transactions extends ChangeNotifier implements TransactionProvider {
  final saved = <String, String>{};
  Object? saveError;

  @override
  Future<void> saveNote(String txid, String note) async {
    if (saveError case final error?) {
      throw error;
    }
    saved[txid] = note;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallet implements OrchestratorWalletRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bmm implements OrchestratorBmmRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _Wallet();

  @override
  final OrchestratorBmmRPC bmm = _Bmm();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Transactions transactions;

  setUp(() async {
    await GetIt.I.reset();
    transactions = _Transactions();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<TransactionProvider>(transactions);
    await registerTestDependencies();
    GetIt.I.registerSingleton<AddressBookProvider>(AddressBookProvider());
    GetIt.I.registerSingleton<WalletReaderProvider>(
      WalletReaderProvider(Directory.systemTemp)..activeWalletId = 'wallet-1',
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<OverviewViewModel> openEditor(WidgetTester tester, walletpb.WalletTransaction tx) async {
    final model = OverviewViewModel();
    await tester.pumpSailPage(
      Builder(
        builder: (context) => SailButton(label: 'Open', onPressed: () => model.editNote(context, tx)),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return model;
  }

  Future<void> save(WidgetTester tester, String note) async {
    await tester.enterText(
      find.descendant(of: find.byType(SailCardEditValues), matching: find.byType(EditableText)),
      note,
    );
    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Save changes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a saved note closes the dialog', (tester) async {
    final model = await openEditor(tester, walletpb.WalletTransaction(txid: 'aa', note: 'old'));
    expect(find.text('Edit Note'), findsOneWidget);

    await save(tester, 'Rent 🏠');

    expect(transactions.saved, {'aa': 'Rent 🏠'});
    expect(find.byType(SailCardEditValues), findsNothing);
    model.dispose();
  });

  testWidgets('a note the server does not save shows the error and keeps the text', (tester) async {
    transactions.saveError = ConnectException(Code.unavailable, 'dial tcp 127.0.0.1:31301: connection refused');
    final model = await openEditor(tester, walletpb.WalletTransaction(txid: 'aa'));

    await save(tester, 'Rent');

    expect(find.text('Could not save the note. Check Daemon Status, then try again.'), findsOneWidget);
    expect(find.byType(SailCardEditValues), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    model.dispose();
  });

  testWidgets('a note the server refuses shows its reason', (tester) async {
    transactions.saveError = ConnectException(Code.invalidArgument, 'txid cannot be empty');
    final model = await openEditor(tester, walletpb.WalletTransaction(txid: 'aa'));

    await save(tester, 'Rent');

    expect(find.textContaining('Failed to save the note: '), findsOneWidget);
    expect(find.textContaining('txid cannot be empty'), findsOneWidget);
    expect(find.byType(SailCardEditValues), findsOneWidget);
    model.dispose();
  });
}
