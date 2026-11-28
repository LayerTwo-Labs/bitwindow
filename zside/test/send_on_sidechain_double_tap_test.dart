import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/providers/transactions_provider.dart';
import 'package:zside/widgets/containers/tabs/dashboard_tab_widgets.dart';

import 'mocks/rpc_mock_sidechain.dart';
import 'mocks/rpc_mock_zside.dart';
import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final sidechainRPC = MockSidechainRPC();
    GetIt.I.registerLazySingleton<SidechainRPC>(() => sidechainRPC);
    GetIt.I.registerLazySingleton<ZSideRPC>(() => MockZSideRPC());
    GetIt.I.registerLazySingleton<SidechainTransactionsProvider>(
      () => SidechainTransactionsProvider(),
    );
    GetIt.I.registerLazySingleton<TransactionsProvider>(
      () => TransactionsProvider(),
    );
    GetIt.I.registerLazySingleton<SidechainBalanceProvider>(
      () => SidechainBalanceProvider(sidechain: sidechainRPC),
    );
  });

  testWidgets(
    'a second tap on execute send during a send does not send again',
    (tester) async {
      final sendDone = Completer<String>();
      var sendCalls = 0;

      await tester.pumpSailPage(
        SendOnSidechainAction(
          customSendAction: (address, amount) {
            sendCalls++;
            return sendDone.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(0),
        'some-sidechain-address',
      );
      await tester.enterText(find.byType(TextField).at(1), '0.1');
      await tester.pump();

      final executeSend = tester.getCenter(find.text('Execute send').first);
      await tester.tapAt(executeSend);
      await tester.pump();
      expect(sendCalls, 1);

      await tester.tapAt(executeSend);
      await tester.pump();
      expect(sendCalls, 1);

      sendDone.complete('some-txid');
      await tester.pump();
      await tester.pump();
      expect(sendCalls, 1);
    },
  );

  Future<void> send(WidgetTester tester, Future<String> Function(String, double) action) async {
    await tester.pumpSailPage(SendOnSidechainAction(customSendAction: action));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'some-sidechain-address');
    await tester.enterText(find.byType(TextField).at(1), '0.1');
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('Execute send').first));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Finder inDialog(Finder finder) => find.descendant(of: find.byType(Dialog).last, matching: finder);

  testWidgets('a sent send shows the action in the head, the sent line and the txid', (tester) async {
    await send(tester, (address, amount) async => 'some-txid');

    expect(inDialog(find.text('Send on sidechain')), findsOneWidget);
    expect(inDialog(find.textContaining('You sent 0.1')), findsOneWidget);
    expect(inDialog(find.textContaining('to some-sidechain-address')), findsOneWidget);
    expect(inDialog(find.text('TXID: some-txid')), findsOneWidget);
  });

  testWidgets('a failed send shows the error row and the error', (tester) async {
    await send(tester, (address, amount) async => throw Exception('insufficient funds'));

    expect(inDialog(find.text('Send on sidechain')), findsOneWidget);
    expect(inDialog(find.byType(SailInlineError)), findsOneWidget);
    expect(inDialog(find.text('Could not execute withdrawal')), findsOneWidget);
    expect(inDialog(find.text('Exception: insufficient funds')), findsOneWidget);
  });
}
