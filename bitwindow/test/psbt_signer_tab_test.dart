import 'dart:convert';
import 'dart:io';

import 'package:bitwindow/pages/wallet/psbt_signer_tab.dart';
import 'package:bitwindow/signing/psbt_text.dart';
import 'package:bitwindow/widgets/airgap_sign_step.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as walletpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _unsignedPsbt =
    'cHNidP8BAHECAAAAAfrxs4O1d0Fw5EbFFqHZ9aOjCXx5s2pPYl5wL9QcF2u6AAAAAAD9////AoCWmAAAAAAAFgAUdBPeN7LqUbDX2iYcJ+JkHLvS4bbYxdQXAAAAABYAFM8A+FQwFOsNOo+uKP0jlUk25DxZAAAAAAAAAAA=';

class _FakeWallet implements OrchestratorWalletRPC {
  final decodes = <(String, String, bool)>[];
  Object? decodeError;
  var morePayments = 0;

  @override
  Future<DecodedTransaction> decodeTransaction({
    required String input,
    String walletId = '',
    String blockHash = '',
    bool checkOwnership = false,
  }) async {
    decodes.add((input, walletId, checkOwnership));
    if (decodeError != null) {
      throw decodeError!;
    }
    return DecodedTransaction(
      form: wmpb.DecodedForm.DECODED_FORM_PSBT,
      isPsbt: true,
      signedInputs: 0,
      hasFee: true,
      hasTotalInput: true,
      changeOutputIndexes: {0},
      details: walletpb.GetTransactionDetailsResponse(
        inputs: [walletpb.TransactionInput(index: 0, prevTxid: 'aa' * 32, valueSats: Int64(410000000))],
        outputs: [
          walletpb.TransactionOutput(index: 0, valueSats: Int64(399999718), address: 'bcrt1qchange'),
          walletpb.TransactionOutput(index: 1, valueSats: Int64(10000000), address: 'bcrt1qpayment'),
          for (var i = 0; i < morePayments; i++)
            walletpb.TransactionOutput(index: 2 + i, valueSats: Int64(1000 + i), address: 'bcrt1qmore$i'),
        ],
        feeSats: Int64(282),
      ),
    );
  }

  @override
  Future<String> combinePsbt({required List<String> psbtsBase64}) async => 'combined';

  @override
  Future<String> finalizePsbt({required String psbtBase64}) async => 'raw';

  @override
  Future<String> broadcastTransaction({required String walletId, required String txHex}) async => 'txid1';

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
  String ecashNetworkId = '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications extends ChangeNotifier implements NotificationProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _FakeWallet wallet;

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    wallet = _FakeWallet();
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator(wallet));
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<NotificationProvider>(_Notifications());
    GetIt.I.registerSingleton<WalletReaderProvider>(WalletReaderProvider(Directory.systemTemp)..activeWalletId = 'w1');
  });

  test('isBase64Psbt accepts a PSBT and rejects other base64', () {
    expect(isBase64Psbt(_unsignedPsbt), isTrue);
    expect(isBase64Psbt(base64.encode(utf8.encode('hello world'))), isFalse);
    expect(isBase64Psbt(base64.encode([0x70, 0x73, 0x62, 0x74])), isFalse);
    expect(isBase64Psbt('not base64 !!'), isFalse);
  });

  testWidgets('base64 that is not a PSBT shows the error and opens no dialog', (tester) async {
    await tester.pumpSailPage(const PsbtSignerTab());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), base64.encode(utf8.encode('hello world')));
    await tester.tap(find.text('Sign with external signer').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Not a valid base64 PSBT'), findsOneWidget);
    expect(find.text('External signer (airgap)'), findsNothing);
  });

  testWidgets('a PSBT with line breaks opens the signer with the same bytes', (tester) async {
    await tester.pumpSailPage(const PsbtSignerTab());

    final wrapped = '  ${_unsignedPsbt.substring(0, 64)}\r\n${_unsignedPsbt.substring(64)}\n';
    await tester.enterText(find.byType(EditableText), wrapped);
    await tester.tap(find.text('Sign with external signer').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Not a valid base64 PSBT'), findsNothing);
    expect(tester.widget<AirgapSignStep>(find.byType(AirgapSignStep)).unsignedPsbtBase64, _unsignedPsbt);
  });

  testWidgets('a pasted PSBT shows what it pays before the signer starts', (tester) async {
    await tester.pumpSailPage(const PsbtSignerTab());

    await tester.enterText(find.byType(EditableText), _unsignedPsbt);
    await tester.pump(const Duration(milliseconds: 400));

    expect(wallet.decodes, [(_unsignedPsbt, 'w1', true)]);
    expect(find.text('External signer (airgap)'), findsNothing);
    final formatter = GetIt.I<FormatterProvider>();
    expect(find.text('${formatter.formatSats(10000000)} to bcrt1qpayment'), findsOneWidget);
    expect(find.text('${formatter.formatSats(399999718)} to bcrt1qchange'), findsOneWidget);
    expect(find.text(formatter.formatSats(282)), findsOneWidget);
    expect(find.text('0 of 1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Pays')).dy, lessThan(tester.getTopLeft(find.text('Change')).dy));

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pays'), findsNothing);
  });

  testWidgets('a PSBT that the wallet cannot read opens no signer', (tester) async {
    wallet.decodeError = Exception('decode psbt: unexpected EOF');
    await tester.pumpSailPage(const PsbtSignerTab());

    await tester.enterText(find.byType(EditableText), _unsignedPsbt);
    await tester.tap(find.text('Sign with external signer').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Could not read the PSBT'), findsOneWidget);
    expect(find.text('External signer (airgap)'), findsNothing);
  });

  testWidgets('a broadcast leaves the txid on the card and empties the field', (tester) async {
    await tester.pumpSailPage(const PsbtSignerTab());

    await tester.enterText(find.byType(EditableText), _unsignedPsbt);
    await tester.tap(find.text('Sign with external signer').hitTestable());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Next: import signed'));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(EditableText).last, _unsignedPsbt);
    await tester.tap(find.text('Confirm signed'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('External signer (airgap)'), findsNothing);
    expect(find.text('txid1'), findsOneWidget);
    expect(find.text('Pays'), findsNothing);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
  });

  testWidgets('a PSBT with many payments keeps the sign button in reach', (tester) async {
    wallet.morePayments = 60;
    await tester.pumpSailPage(const PsbtSignerTab());
    await tester.binding.setSurfaceSize(const Size(1024, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.enterText(find.byType(EditableText), _unsignedPsbt);
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    final button = find.text('Sign with external signer');
    await tester.ensureVisible(button);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(button.hitTestable());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('External signer (airgap)'), findsOneWidget);
  });

  testWidgets('a change of wallet reads the PSBT again for the new wallet', (tester) async {
    await tester.pumpSailPage(const PsbtSignerTab());
    await tester.enterText(find.byType(EditableText), _unsignedPsbt);
    await tester.pump(const Duration(milliseconds: 400));

    final reader = GetIt.I.get<WalletReaderProvider>();
    reader.activeWalletId = 'w2';
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    reader.notifyListeners();
    await tester.pump(const Duration(milliseconds: 400));

    expect(wallet.decodes, [(_unsignedPsbt, 'w1', true), (_unsignedPsbt, 'w2', true)]);
    expect(find.text('Pays'), findsOneWidget);
  });
}
