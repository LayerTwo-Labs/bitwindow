import 'package:bitwindow/providers/check_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';

const _txid = 'aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11';

Cheque _check({bool funded = false, int? actual, List<String> txids = const [], String? swept}) => Cheque(
  id: Int64(1),
  address: 'bcrt1qcheck',
  expectedAmountSats: Int64(1000),
  funded: funded,
  actualAmountSats: actual == null ? null : Int64(actual),
  fundedTxids: txids,
  privateKeyWif: funded ? 'cWif' : null,
  sweptTxid: swept,
);

CheckChequeFundingResponse _chain({int amount = 0, List<String> txids = const []}) =>
    CheckChequeFundingResponse(funded: amount >= 1000, actualAmountSats: Int64(amount), fundedTxids: txids);

class _WalletAPI extends MockWalletAPI {
  List<Cheque> cheques = [];
  CheckChequeFundingResponse chain = CheckChequeFundingResponse();
  Object? chainError;
  List<Cheque>? afterChainRead;
  final chainReads = <int>[];

  @override
  Future<ListChequesResponse> listCheques(String walletId) async => ListChequesResponse(cheques: cheques);

  @override
  Future<CheckChequeFundingResponse> checkChequeFunding(String walletId, int id) async {
    chainReads.add(id);
    if (chainError != null) {
      throw chainError!;
    }
    cheques = afterChainRead ?? cheques;
    return chain;
  }
}

class _BitwindowRPC implements BitwindowRPC {
  @override
  final _WalletAPI wallet = _WalletAPI();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? activeWalletId = 'wallet-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SyncProvider extends ChangeNotifier implements SyncProvider {
  @override
  bool get isSynced => false;

  @override
  SyncInfo? chainSourceSyncInfo;

  void showChainTip(double height) {
    chainSourceSyncInfo = SyncInfo(progressCurrent: height, progressGoal: height, lastBlockAt: null);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LightNodeMode implements NodeModeProvider {
  @override
  bool get needsChoice => false;

  @override
  bool get isFull => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _WalletAPI wallet;
  late _SyncProvider sync;

  setUp(() async {
    await GetIt.I.reset();
    final rpc = _BitwindowRPC();
    wallet = rpc.wallet;
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    sync = _SyncProvider();
    GetIt.I.registerSingleton<SyncProvider>(sync);
  });

  tearDown(() => GetIt.I.reset());

  group('fundingChanged', () {
    test('an unfunded check with no coins is the same', () {
      expect(fundingChanged(_check(), _chain()), isFalse);
    });

    test('a first payment is a change', () {
      expect(fundingChanged(_check(), _chain(amount: 1000, txids: [_txid])), isTrue);
    });

    test('a funded check with the same coins is the same', () {
      final check = _check(funded: true, actual: 1000, txids: [_txid]);
      expect(fundingChanged(check, _chain(amount: 1000, txids: [_txid])), isFalse);
    });

    test('a second payment is a change', () {
      final check = _check(actual: 400, txids: [_txid]);
      expect(fundingChanged(check, _chain(amount: 900, txids: [_txid, 'bb22'])), isTrue);
    });

    test('a funded check with no coins left is a change', () {
      expect(fundingChanged(_check(funded: true, actual: 1000, txids: [_txid]), _chain()), isTrue);
    });

    test('a swept check with no coins is the same', () {
      expect(fundingChanged(_check(funded: true, actual: 1000, txids: [_txid], swept: 'cc33'), _chain()), isFalse);
    });

    test('a payment to a swept check is a change', () {
      final check = _check(funded: true, actual: 1000, txids: [_txid], swept: 'cc33');
      expect(fundingChanged(check, _chain(amount: 500, txids: ['dd44'])), isTrue);
    });
  });

  test('a new chain tip in light mode refreshes a swept check', () {
    fakeAsync((async) {
      GetIt.I.registerSingleton<NodeModeProvider>(_LightNodeMode());
      wallet.cheques = [
        _check(actual: 800, txids: [_txid], swept: 'swept'),
      ];
      final provider = CheckProvider();
      async.flushMicrotasks();
      sync.showChainTip(100);
      async.flushMicrotasks();
      expect(provider.checks.single.sweptTxid, 'swept');

      wallet.chain = _chain(amount: 700, txids: ['new-payment']);
      wallet.afterChainRead = [
        _check(actual: 700, txids: ['new-payment']),
      ];
      sync.showChainTip(101);
      async.flushMicrotasks();

      expect(provider.checks.single.sweptTxid, isEmpty);
      expect(provider.checks.single.actualAmountSats, Int64(700));
      final reads = wallet.chainReads.length;

      sync.showChainTip(101);
      async.flushMicrotasks();
      expect(wallet.chainReads, hasLength(reads));
      provider.dispose();
    });
  });

  test('a funded check that another wallet cashed shows as swept', () async {
    wallet.cheques = [
      _check(funded: true, actual: 1000, txids: [_txid]),
    ];
    wallet.afterChainRead = [
      _check(funded: true, actual: 1000, txids: [_txid], swept: 'swept_externally'),
    ];
    final provider = CheckProvider();
    addTearDown(provider.dispose);

    await provider.fetch();

    expect(wallet.chainReads, contains(1));
    expect(provider.checks.single.sweptTxid, 'swept_externally');
  });

  test('a check that gets its coins keeps the private key from the server', () async {
    wallet.cheques = [_check()];
    wallet.chain = _chain(amount: 1000, txids: [_txid]);
    wallet.afterChainRead = [
      _check(funded: true, actual: 1000, txids: [_txid]),
    ];
    final provider = CheckProvider();
    addTearDown(provider.dispose);

    await provider.fetch();

    expect(provider.checks.single.funded, isTrue);
    expect(provider.checks.single.privateKeyWif, 'cWif');
  });

  test('a failed chain read shows as an error, and a good read clears it', () async {
    wallet.cheques = [_check()];
    wallet.chainError = WalletException('query UTXOs of bcrt1qcheck: no wallet chain source');
    final provider = CheckProvider();
    addTearDown(provider.dispose);

    await provider.fetch();
    expect(provider.modelError, contains('no wallet chain source'));
    expect(provider.checks, hasLength(1));

    wallet.chainError = null;
    await provider.fetch();
    expect(provider.modelError, isNull);
  });

  test('the poll of an unfunded check shows a failed chain read', () {
    fakeAsync((async) {
      wallet.cheques = [_check()];
      final provider = CheckProvider();
      async.flushMicrotasks();
      expect(provider.modelError, isNull);

      wallet.chainError = WalletException('chain source is down');
      var notified = 0;
      provider.addListener(() => notified++);
      async.elapse(const Duration(seconds: 11));

      expect(provider.modelError, contains('chain source is down'));
      expect(notified, 1);
      provider.dispose();
    });
  });

  test('the poll does not read a funded or a swept check', () {
    fakeAsync((async) {
      wallet.cheques = [
        _check(funded: true, actual: 1000, txids: [_txid]),
      ];
      final provider = CheckProvider();
      async.flushMicrotasks();
      wallet.chainReads.clear();

      async.elapse(const Duration(seconds: 11));

      expect(wallet.chainReads, isEmpty);
      provider.dispose();
    });
  });
}
