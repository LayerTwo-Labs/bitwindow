import 'package:bitwindow/models/multisig_group.dart';
import 'package:bitwindow/models/multisig_transaction.dart';
import 'package:bitwindow/widgets/create_multisig_modal.dart';
import 'package:bitwindow/providers/multisig_provider.dart';
import 'package:connectrpc/connect.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/multisig/v1/multisig.pb.dart' as multisigpb;
import 'package:sidechain_core/gen/multisiglounge/v1/multisiglounge.pb.dart' as mlpb;

import 'mocks/api_mock.dart';

const _sentTxid = 'aa00000000000000000000000000000000000000000000000000000000000000';
const _depositTxid = 'bb00000000000000000000000000000000000000000000000000000000000000';

class _FakeMultisigAPI extends MockMultisigAPI {
  final stored = <String, multisigpb.MultisigTransaction>{};

  @override
  Future<multisigpb.MultisigTransaction> getTransactionByTxid(String txid) async {
    final tx = stored[txid];
    if (tx == null) {
      throw ConnectException(Code.notFound, 'transaction not found');
    }
    return tx;
  }

  @override
  Future<multisigpb.MultisigTransaction> saveTransaction(multisigpb.MultisigTransaction transaction) async {
    stored[transaction.txid] = transaction;
    return transaction;
  }
}

class _FakeLounge implements OrchestratorMultisigLoungeRPC {
  List<mlpb.MultisigHistoryTx> history = [];

  @override
  Future<mlpb.RestoreHistoryResponse> restoreHistory({required mlpb.GroupData group, required String walletId}) async =>
      mlpb.RestoreHistoryResponse(transactions: history);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  _FakeOrchestrator(this.multisigLounge);

  @override
  final OrchestratorMultisigLoungeRPC multisigLounge;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBitwindow implements BitwindowRPC {
  _FakeBitwindow(this.multisig);

  @override
  final MultisigAPI multisig;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? get activeWalletId => 'w1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _group = MultisigGroup(
  id: 'g1',
  name: 'group',
  n: 3,
  m: 2,
  keys: [
    for (final x in ['a', 'b', 'c'])
      MultisigKey(owner: x, xpub: 'xpub-$x', derivationPath: "m/48'/1'/0'/2'", isWallet: false),
  ],
  created: 0,
);

mlpb.MultisigHistoryTx _history(String txid, {required int confirmations, required String status}) =>
    mlpb.MultisigHistoryTx(
      txid: txid,
      confirmations: confirmations,
      status: status,
      amountSats: Int64(50000000),
      time: Int64(1700000000),
    );

void main() {
  late _FakeMultisigAPI api;
  late _FakeLounge lounge;

  setUp(() async {
    await GetIt.I.reset();
    api = _FakeMultisigAPI();
    lounge = _FakeLounge();
    GetIt.I.registerSingleton<BitwindowRPC>(_FakeBitwindow(api));
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator(lounge));
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
  });
  tearDown(() => GetIt.I.reset());

  test('a stored tx takes the status and confirmations of the node', () async {
    api.stored[_sentTxid] = multisigpb.MultisigTransaction(
      id: 'local-id',
      groupId: 'g1',
      txid: _sentTxid,
      status: multisigpb.TxStatus.TX_STATUS_BROADCASTED,
      type: multisigpb.TxType.TX_TYPE_WITHDRAWAL,
      requiredSignatures: 2,
    );
    lounge.history = [
      _history(_sentTxid, confirmations: 7, status: 'confirmed'),
      _history(_depositTxid, confirmations: 8, status: 'confirmed'),
    ];
    var notifications = 0;
    void count() => notifications++;
    TransactionStorage.notifier.addListener(count);
    addTearDown(() => TransactionStorage.notifier.removeListener(count));

    await MultisigStorage.restoreTransactionHistory(_group);
    expect(notifications, 1, reason: 'one restore starts one refresh');

    await MultisigStorage.restoreTransactionHistory(_group);
    expect(notifications, 1, reason: 'no change, no refresh');

    final tx = await TransactionStorage.getTransactionByTxid(_sentTxid);
    expect(tx!.status, TxStatus.confirmed);
    expect(tx.confirmations, 7);
    expect(tx.id, 'local-id', reason: 'the local row stays the same row');
  });

  test('a new tx from the node needs m signatures, not n', () async {
    lounge.history = [_history(_depositTxid, confirmations: 1, status: 'broadcasted')];

    await MultisigStorage.restoreTransactionHistory(_group);

    final tx = await TransactionStorage.getTransactionByTxid(_depositTxid);
    expect(tx!.requiredSignatures, 2);
    expect(tx.confirmations, 1);
  });
}
