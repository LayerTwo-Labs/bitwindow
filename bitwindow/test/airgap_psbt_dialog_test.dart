import 'package:bitwindow/widgets/airgap_psbt_dialog.dart';
import 'package:connectrpc/connect.dart' show Code, ConnectException;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _unsigned =
    'cHNidP8BAHECAAAAAfrxs4O1d0Fw5EbFFqHZ9aOjCXx5s2pPYl5wL9QcF2u6AAAAAAD9////AoCWmAAAAAAAFgAUdBPeN7LqUbDX2iYcJ+JkHLvS4bbYxdQXAAAAABYAFM8A+FQwFOsNOo+uKP0jlUk25DxZAAAAAAAAAAA=';
const _signed = 'cHNidP8BAHEC';

class _FakeWallet implements OrchestratorWalletRPC {
  final broadcasts = <(String, String)>[];
  var combines = 0;
  Object? combineError;
  Object? finalizeError;
  Object? broadcastError;

  @override
  Future<String> combinePsbt({required List<String> psbtsBase64}) async {
    combines++;
    if (combineError != null) {
      throw combineError!;
    }
    return 'combined:${psbtsBase64.join('+')}';
  }

  @override
  Future<String> finalizePsbt({required String psbtBase64}) async {
    if (finalizeError != null) {
      throw finalizeError!;
    }
    return 'raw($psbtBase64)';
  }

  @override
  Future<String> broadcastTransaction({required String walletId, required String txHex}) async {
    broadcasts.add((walletId, txHex));
    if (broadcastError != null) {
      throw broadcastError!;
    }
    return 'txid1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  _FakeOrchestrator(this.wallet);

  @override
  final OrchestratorWalletRPC wallet;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications extends ChangeNotifier implements NotificationProvider {
  final titles = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #add) {
      titles.add(invocation.namedArguments[#title] as String);
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late _FakeWallet wallet;
  late _Notifications notifications;

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    wallet = _FakeWallet();
    notifications = _Notifications();
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator(wallet));
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<NotificationProvider>(notifications);
  });

  Future<void> confirmSigned(WidgetTester tester, {String signed = _signed}) async {
    await tester.pumpSailPage(const AirgapPsbtDialog(walletId: 'w1', unsignedPsbtBase64: _unsigned));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Next: import signed'));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(EditableText), signed);
    await tester.tap(find.text('Confirm signed'));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('broadcasts over the chain of the wallet', (tester) async {
    await confirmSigned(tester);

    expect(wallet.broadcasts, [('w1', 'raw(combined:$_unsigned+$_signed)')]);
    expect(notifications.titles, ['Transaction broadcast']);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('shows why the wallet refused the broadcast', (tester) async {
    wallet.broadcastError = Exception('the output aa:0 is frozen; unfreeze it to spend it');

    await confirmSigned(tester);

    expect(wallet.broadcasts, hasLength(1));
    expect(find.textContaining('is frozen'), findsOneWidget);
    expect(notifications.titles, isEmpty);
  });

  void expectImportStepWith(WidgetTester tester, String error, {String signed = _signed}) {
    expect(find.text(error), findsOneWidget);
    expect(find.text('Confirm signed'), findsOneWidget);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, signed);
    expect(wallet.broadcasts, isEmpty);
    expect(notifications.titles, isEmpty);
  }

  testWidgets('a PSBT of another transaction stays in the import step', (tester) async {
    wallet.combineError = ConnectException(Code.invalidArgument, 'the psbts describe different transactions');

    await confirmSigned(tester);

    expectImportStepWith(tester, 'This PSBT is for another transaction');
  });

  testWidgets('a PSBT with too few signatures stays in the import step', (tester) async {
    wallet.finalizeError = ConnectException(Code.invalidArgument, 'the psbt is not fully signed');

    await confirmSigned(tester);

    expectImportStepWith(tester, 'The signer did not sign every input');
  });

  testWidgets('a failed combine that is not about the PSBT shows its cause', (tester) async {
    wallet.combineError = ConnectException(Code.unavailable, 'connection refused');

    await confirmSigned(tester);

    expectImportStepWith(tester, 'Failed to broadcast: connection refused');
  });

  testWidgets('text that is no PSBT does not reach the wallet', (tester) async {
    await confirmSigned(tester, signed: 'hello');

    expectImportStepWith(tester, 'Not a valid base64 PSBT', signed: 'hello');
    expect(wallet.combines, 0);
  });
}
