import 'dart:async';

import 'package:bitwindow/pages/wallet/check_detail_page.dart';
import 'package:bitwindow/providers/check_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as bwpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _address = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _wif = 'cVt4o7BGAig1UXywgGSmARhxMdzP5qvQsxKkSsc1XEkw3tDTQFpy';
const _sweepTxid = 'c9aea9a2c6ff091e4d48104a56bb87eede57d6f0f76fb7507e3001714685b132';

bwpb.Cheque _check({int? onCheck, String? sweptTxid}) => bwpb.Cheque(
  id: Int64(1),
  derivationIndex: 1,
  address: _address,
  expectedAmountSats: Int64(200000),
  actualAmountSats: onCheck == null ? null : Int64(onCheck),
  funded: onCheck != null && onCheck >= 200000,
  fundedTxids: onCheck == null ? [] : ['ab' * 32],
  privateKeyWif: onCheck == null ? null : _wif,
  sweptTxid: sweptTxid,
);

class _FakeCheckProvider extends ChangeNotifier implements CheckProvider {
  _FakeCheckProvider(this.check);

  final bwpb.Cheque check;

  @override
  List<bwpb.Cheque> checks = [];

  @override
  Future<bwpb.Cheque> getCheck(int id) async => check;

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

class _FakeOrchestratorWallet implements OrchestratorWalletRPC {
  final sends = <(Map<String, int>, int?)>[];

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
  }) {
    sends.add((destinations, feeRateSatPerVbyte));
    return Completer<wmpb.SendTransactionResponse>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final _FakeOrchestratorWallet wallet = _FakeOrchestratorWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<_FakeOrchestrator> pumpCheck(WidgetTester tester, bwpb.Cheque check) async {
    final orchestrator = _FakeOrchestrator();
    GetIt.I.registerSingleton<CheckProvider>(_FakeCheckProvider(check));
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
    GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    await tester.pumpSailPage(const CheckDetailPage(checkId: 1));
    await tester.pump();
    await tester.pump();
    return orchestrator;
  }

  String rowValue(WidgetTester tester, String label) {
    final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
    final texts = find.descendant(of: row, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data);
    return texts.last!;
  }

  testWidgets('a partly funded check shows what it holds and funds only the rest', (tester) async {
    final orchestrator = await pumpCheck(tester, _check(onCheck: 50000));

    expect(rowValue(tester, 'On the check'), '0.00050000 BTC');
    expect(rowValue(tester, 'Still to fund'), '0.00150000 BTC');

    await tester.tap(find.text('Fund the Rest with Wallet'));
    await tester.pump();

    expect(orchestrator.wallet.sends.map((s) => s.$1), [
      {_address: 150000},
    ]);
  });

  testWidgets('an over-funded check shows the full amount it holds', (tester) async {
    await pumpCheck(tester, _check(onCheck: 210000));

    expect(rowValue(tester, 'On the check'), '0.00210000 BTC');
    expect(find.text('Still to fund'), findsNothing);
    expect(find.text('Fund the Rest with Wallet'), findsNothing);
    expect(find.text('Sweep Check to Wallet'), findsOneWidget);
  });

  testWidgets('an empty check funds the check amount at the wallet fee estimate', (tester) async {
    final orchestrator = await pumpCheck(tester, _check());

    await tester.tap(find.text('Fund with Wallet'));
    await tester.pump();

    expect(orchestrator.wallet.sends.map((s) => s.$1), [
      {_address: 200000},
    ]);
    expect(orchestrator.wallet.sends.single.$2, isNull);
  });

  testWidgets('a swept check shows the sweep and no private key', (tester) async {
    await pumpCheck(tester, _check(onCheck: 210000, sweptTxid: _sweepTxid));

    expect(rowValue(tester, 'Amount swept'), '0.00210000 BTC');
    expect(find.text('c9aea9a2c6…685b132'), findsOneWidget);
    expect(find.text('Private Key (WIF)'), findsNothing);
    expect(find.textContaining(_wif), findsNothing);
    expect(find.text('Sweep Check to Wallet'), findsNothing);
  });

  testWidgets('a check cashed outside this wallet says so', (tester) async {
    await pumpCheck(tester, _check(onCheck: 200000, sweptTxid: sweptOutsideTxid));

    expect(rowValue(tester, 'Sweep transaction'), 'Cashed outside this wallet');
  });
}
