import 'dart:convert';

import 'package:bitwindow/pages/wallet/wallet_multisig_lounge.dart';
import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:bitwindow/widgets/import_txid_modal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/multisig/v1/multisig.pb.dart' as storage;
import 'package:sidechain_core/gen/multisiglounge/v1/multisiglounge.pb.dart' as lounge;

import 'mocks/api_mock.dart';
import 'test_utils.dart';

const _txid = 'AB12000000000000000000000000000000000000000000000000000000000000';

class _Misc extends MockMiscAPI {
  final requests = <ListOPReturnRequest>[];
  String? message = 'not a group';

  @override
  Future<List<OPReturn>> listOPReturns(ListOPReturnRequest request) async {
    requests.add(request);
    return request.search == _txid && message != null ? [OPReturn(txid: _txid.toLowerCase(), message: message)] : [];
  }
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? get activeWalletId => 'qa';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lounge implements OrchestratorMultisigLoungeRPC {
  String? walletId;
  String? requestedTxid;
  String? importWalletId;
  List<int> importedWalletKeys = [1];

  @override
  Future<lounge.ImportGroupFromTxidResponse> importGroupFromTxid({
    required String txid,
    required String walletId,
  }) async {
    requestedTxid = txid;
    importWalletId = walletId;
    return lounge.ImportGroupFromTxidResponse(
      group: lounge.GroupData(
        id: 'qa-group',
        name: 'Group',
        m: 2,
        n: 2,
        keys: [
          lounge.GroupKey(owner: 'Alice', xpub: 'alice-key', isWallet: true),
          lounge.GroupKey(owner: 'Bob', xpub: 'bob-key'),
        ],
      ),
      walletKeyIndices: importedWalletKeys,
    );
  }

  @override
  Future<lounge.FindWalletKeysResponse> findWalletKeys({
    required lounge.GroupData group,
    required String walletId,
  }) async {
    this.walletId = walletId;
    expect(group.keys.map((key) => key.owner), ['Alice', 'Bob']);
    return lounge.FindWalletKeysResponse(walletKeyIndices: [1]);
  }

  @override
  Future<lounge.SyncGroupResponse> syncGroup({required lounge.GroupData group, required String walletId}) async =>
      lounge.SyncGroupResponse();

  @override
  Future<lounge.RestoreHistoryResponse> restoreHistory({
    required lounge.GroupData group,
    required String walletId,
  }) async => lounge.RestoreHistoryResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final _Lounge multisigLounge = _Lounge();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups extends MockMultisigAPI {
  final groups = <storage.MultisigGroup>[];

  @override
  Future<List<storage.MultisigGroup>> listGroups() async => groups;

  @override
  Future<storage.MultisigGroup> saveGroup(storage.MultisigGroup group) async {
    groups.removeWhere((saved) => saved.id == group.id);
    groups.add(group);
    return group;
  }
}

class _API extends MockAPI {
  _API(this._misc) : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _Misc _misc;

  final _groups = _Groups();

  @override
  _Groups get multisig => _groups;

  @override
  _Misc get misc => _misc;
}

void main() {
  late _Misc misc;
  late _API api;
  late _Orchestrator orchestrator;

  setUp(() async {
    await GetIt.I.reset();
    misc = _Misc();
    api = _API(misc);
    orchestrator = _Orchestrator();
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    await registerTestDependencies();
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<HDWalletProvider>(HDWalletProvider());
  });
  tearDown(() => GetIt.I.reset());

  testWidgets('the import asks the server for its own txid', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final vm = ImportTxidModalViewModel()..txidController.text = _txid;
    addTearDown(vm.dispose);

    await vm.importFromTxid(context);

    expect(misc.requests.single.search, _txid);
    expect(vm.modalError, 'Invalid OP_RETURN format - not a BitDrive transaction', reason: 'the lookup found the tx');
  });

  testWidgets('TXID import stores keys for the selected wallet', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());
    final payload = {
      'id': 'qa-group',
      'name': 'Group',
      'm': 2,
      'n': 2,
      'created': 0,
      'keys': [
        {'owner': 'Alice', 'xpub': 'alice-key', 'path': "m/84'/1'/8000'", 'is_wallet': true},
        {'owner': 'Bob', 'xpub': 'bob-key', 'path': "m/84'/1'/8000'", 'is_wallet': false},
      ],
    };
    final flags = base64.encode([2, 0, 0, 0, 0, 0, 0, 0, 0]);
    misc.message = '$flags|${base64.encode(utf8.encode(jsonEncode(payload)))}';
    final vm = ImportTxidModalViewModel()..txidController.text = _txid;
    addTearDown(vm.dispose);

    await vm.importFromTxid(context);

    expect(vm.modalError, isNull);
    expect(orchestrator.multisigLounge.walletId, 'qa');
    expect(api.multisig.groups.first.keys.where((key) => key.isWallet).single.owner, 'Bob');
  });

  testWidgets('TXID import reads the chain when the index has no match', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());
    misc.message = null;
    final vm = ImportTxidModalViewModel()..txidController.text = _txid;
    addTearDown(vm.dispose);

    await vm.importFromTxid(context);

    expect(vm.modalError, isNull);
    expect(orchestrator.multisigLounge.requestedTxid, _txid.toLowerCase());
    expect(orchestrator.multisigLounge.importWalletId, 'qa');
    final group = api.multisig.groups.single;
    expect(group.txid, _txid.toLowerCase());
    expect(group.keys.where((key) => key.isWallet).single.owner, 'Bob');
  });

  testWidgets('TXID import rejects a group without a key for the selected wallet', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    misc.message = null;
    orchestrator.multisigLounge.importedWalletKeys = [];
    final vm = ImportTxidModalViewModel()..txidController.text = _txid;
    addTearDown(vm.dispose);

    await vm.importFromTxid(context);

    expect(vm.modalError, contains('this wallet cannot derive any of the 2 keys'));
    expect(api.multisig.groups, isEmpty);
  });

  testWidgets('the lounge reloads ownership for the selected wallet', (tester) async {
    api.multisig.groups.add(
      storage.MultisigGroup(
        id: 'native-group',
        name: 'Group',
        m: 2,
        n: 2,
        keys: [
          storage.MultisigKey(owner: 'Alice', xpub: 'alice-key', derivationPath: "m/84'/1'/8000'", isWallet: true),
          storage.MultisigKey(owner: 'Bob', xpub: 'bob-key', derivationPath: "m/84'/1'/8000'", isWallet: true),
        ],
      ),
    );
    final model = MultisigLoungeViewModel();
    addTearDown(model.dispose);

    await model.initialize();

    expect(model.errorMessage, isNull);
    expect(orchestrator.multisigLounge.walletId, 'qa');
    expect(api.multisig.groups.single.keys.where((key) => key.isWallet).single.owner, 'Bob');
  });
}
