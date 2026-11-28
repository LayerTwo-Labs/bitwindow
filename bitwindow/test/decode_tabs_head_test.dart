import 'package:bitwindow/pages/explorer/load_transaction_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as walletpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

class _WalletRPC implements OrchestratorWalletRPC {
  @override
  Future<DecodedTransaction> decodeTransaction({
    required String input,
    String walletId = '',
    String blockHash = '',
    bool checkOwnership = false,
  }) async => DecodedTransaction(
    form: wmpb.DecodedForm.DECODED_FORM_TXID,
    isPsbt: false,
    signedInputs: 0,
    hasFee: false,
    hasTotalInput: false,
    changeOutputIndexes: {},
    details: walletpb.GetTransactionDetailsResponse(txid: 'ab' * 32),
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
  WalletData? get activeWallet => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the result tabs sit at the top right of the result card, in line with its title', (tester) async {
    await tester.pumpSailPage(
      SailTheme(
        data: SailThemeData.lightTheme(
          SailColorScheme.orange,
          false,
          SailFontValues.inter,
          SailThemeStyle.bitwindowV2,
        ),
        child: const SizedBox(width: 1200, height: 700, child: LoadTransactionDialog()),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'ab' * 32);
    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Decode'));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byType(SailCard).last);
    final title = tester.getRect(find.text('Transaction (by id)'));
    final bytes = tester.getRect(find.text('Bytes'));
    expect(bytes.center.dy, closeTo(title.center.dy, 4));
    expect(bytes.right, greaterThan(card.right - 40));
    expect(title.left, lessThan(card.left + 40));
    expect(tester.takeException(), isNull);
  });
}
