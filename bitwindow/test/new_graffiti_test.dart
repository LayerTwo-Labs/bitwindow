import 'dart:async';

import 'package:bitwindow/pages/overview_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as bwpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

class _WalletRPC implements OrchestratorWalletRPC {
  final address = Completer<wmpb.GetNewAddressResponse>();
  final messages = <String?>[];

  @override
  Future<wmpb.GetNewAddressResponse> getNewAddress(String walletId, {wmpb.AddressType? addressType}) => address.future;

  @override
  Future<wmpb.SendTransactionResponse> sendTransaction({
    required String walletId,
    required Map<String, int> destinations,
    int? feeRateSatPerVbyte,
    int? fixedFeeSats,
    bool subtractFeeFromAmount = false,
    String? opReturnMessage,
    String? opReturnHex,
    List<bwpb.UnspentOutput>? requiredInputs,
    bwpb.UnspentOutput? notificationInput,
    bool allowReplay = false,
  }) async {
    messages.add(opReturnMessage);
    return wmpb.SendTransactionResponse(txid: 'tx-${messages.length}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet;

  _Orchestrator(this.wallet);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader implements WalletReaderProvider {
  @override
  String get activeWalletId => 'wallet';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BitcoinConf implements BitcoinConfProvider {
  @override
  BitcoinNetwork get network => BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final field = find.byType(EditableText);
  final broadcast = find.byWidgetPredicate((widget) => widget is SailButton && widget.label == 'Broadcast');

  setUp(() async {
    await registerTestDependencies();
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<BitcoinConfProvider>(_BitcoinConf());
    GetIt.I.registerSingleton<NotificationProvider>(NotificationProvider());
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('Broadcast sends the submitted text and keeps the next draft', (tester) async {
    final wallet = _WalletRPC();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator(wallet));
    await tester.pumpSailPage(const NewGraffitiView());
    await tester.enterText(field, 'First 🧪');
    await tester.pump();
    await tester.tap(broadcast);
    await tester.enterText(field, 'Next draft');
    wallet.address.complete(wmpb.GetNewAddressResponse(address: 'own-address'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(wallet.messages, ['First 🧪']);
    expect(tester.widget<EditableText>(field).controller.text, 'Next draft');
  });
}
