import 'package:bitwindow/widgets/airgap_psbt_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _unsigned =
    'cHNidP8BAHECAAAAAfrxs4O1d0Fw5EbFFqHZ9aOjCXx5s2pPYl5wL9QcF2u6AAAAAAD9////AoCWmAAAAAAAFgAUdBPeN7LqUbDX2iYcJ+JkHLvS4bbYxdQXAAAAABYAFM8A+FQwFOsNOo+uKP0jlUk25DxZAAAAAAAAAAA=';
const _signed = 'cHNidP8Bsigned';

class _FakeWallet implements OrchestratorWalletRPC {
  final broadcasts = <(String, String)>[];
  Object? broadcastError;

  @override
  Future<String> combinePsbt({required List<String> psbtsBase64}) async => 'combined:${psbtsBase64.join('+')}';

  @override
  Future<String> finalizePsbt({required String psbtBase64}) async => 'raw($psbtBase64)';

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

  Future<void> confirmSigned(WidgetTester tester) async {
    await tester.pumpSailPage(const AirgapPsbtDialog(walletId: 'w1', unsignedPsbtBase64: _unsigned));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Next: import signed'));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(EditableText), _signed);
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
}
