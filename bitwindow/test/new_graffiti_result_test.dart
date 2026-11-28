import 'package:bitwindow/pages/overview_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as bwpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _txid = 'f948b0cd4d013fbc345d1460ca3cbb0d9b26cb2c260780dd6b61b9821e757513';

class _Wallet implements OrchestratorWalletRPC {
  bool reject = false;

  @override
  Future<wmpb.GetNewAddressResponse> getNewAddress(String walletId, {wmpb.AddressType? addressType}) async =>
      wmpb.GetNewAddressResponse(address: 'bcrt1-test');

  @override
  Future<wmpb.SendTransactionResponse> sendTransaction({
    required String walletId,
    required Map<String, int> destinations,
    double? feeRateSatPerVbyte,
    int? fixedFeeSats,
    bool subtractFeeFromAmount = false,
    String subtractFeeFromAddress = '',
    String? opReturnMessage,
    String? opReturnHex,
    List<bwpb.UnspentOutput>? requiredInputs,
    bwpb.UnspentOutput? notificationInput,
    bool allowReplay = false,
  }) async {
    if (reject) {
      throw StateError('Insufficient funds');
    }
    return wmpb.SendTransactionResponse(txid: _txid);
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
  late _Wallet wallet;
  late NotificationProvider notifications;

  setUpAll(loadBundledFonts);
  setUp(() async {
    await registerTestDependencies();
    wallet = _Wallet();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator(wallet));
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<BitcoinConfProvider>(_BitcoinConf());
    notifications = GetIt.I.registerSingleton(NotificationProvider());
  });
  tearDown(() => GetIt.I.reset());

  testWidgets('the broadcast result stays in the dialog until the next send', (tester) async {
    await tester.pumpSailPage(const NewGraffitiView());
    final field = find.byType(EditableText);
    final button = find.widgetWithText(SailButton, 'Broadcast');
    final result = find.descendant(of: find.byType(NewGraffitiView), matching: find.byType(NotificationLinkText));

    await tester.enterText(field, 'First draft');
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(notifications.history.single.content, _txid);
    expect(tester.widget<EditableText>(field).controller.text, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    expect(notifications.notifications, isEmpty);
    expect(find.text('Graffiti broadcast'), findsOneWidget);
    expect(result.hitTestable(), findsOneWidget);
    expect(tester.widget<NotificationLinkText>(result).link.url, endsWith('/tx/$_txid'));

    wallet.reject = true;
    await tester.enterText(field, 'Second draft');
    await tester.pump();
    expect(result, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, findsNothing);
    expect(find.textContaining('Insufficient funds'), findsOneWidget);
    expect(tester.widget<EditableText>(field).controller.text, 'Second draft');
    expect(notifications.history.single.content, _txid);
  });

  testWidgets('large text keeps the transaction link in the phone dialog', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpSailPage(
      Builder(
        builder: (context) => SailButton(
          label: 'Open',
          skipLoading: true,
          onPressed: () => widgetDialog<void>(
            context: context,
            title: 'New Graffiti',
            child: const NewGraffitiView(),
          ),
        ),
      ),
    );
    await tester.usePhoneSize();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'Graffiti');
    await tester.pump();
    await tester.tap(find.widgetWithText(SailButton, 'Broadcast'));
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Graffiti broadcast'));
    final link = find.byType(NotificationLinkText);
    final linkRect = tester.getRect(link);
    final dialog = tester.getRect(find.byType(NewGraffitiView));
    expect(tester.takeException(), isNull);
    expect(linkRect.top, greaterThan(title.bottom));
    expect(linkRect.right, lessThanOrEqualTo(dialog.right));
    expect(link.hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
