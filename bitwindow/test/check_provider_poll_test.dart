import 'package:bitwindow/providers/check_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';

class _WalletAPI extends MockWalletAPI {
  List<Cheque> cheques = [];
  String scanError = '';
  int listCalls = 0;

  @override
  Future<ListChequesResponse> listCheques(String walletId) async {
    listCalls++;
    return ListChequesResponse(cheques: cheques, scanError: scanError);
  }

  @override
  Future<CheckChequeFundingResponse> checkChequeFunding(String walletId, int id) async => CheckChequeFundingResponse(
    funded: true,
    actualAmountSats: Int64(1000),
  );
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _BitwindowRPC rpc;

  setUp(() async {
    await GetIt.I.reset();
    rpc = _BitwindowRPC();
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<SyncProvider>(_SyncProvider());
  });

  tearDown(() => GetIt.I.reset());

  test('a wallet with no checks is not polled', () {
    fakeAsync((async) {
      final provider = CheckProvider();
      async.elapse(const Duration(seconds: 30));

      expect(rpc.wallet.listCalls, 1);
      provider.dispose();
    });
  });

  test('a fetch with the same checks does not notify', () async {
    rpc.wallet.cheques = [
      Cheque(id: Int64(1), address: 'bcrt1qcheck', expectedAmountSats: Int64(1000), funded: true),
    ];
    final provider = CheckProvider();
    addTearDown(provider.dispose);
    await provider.fetch();
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.fetch();
    expect(notified, 0);

    rpc.wallet.cheques = [];
    await provider.fetch();
    expect(notified, 1);
  });

  test('a failed scan shows its error with the stored checks and runs again', () {
    fakeAsync((async) {
      rpc.wallet.cheques = [
        Cheque(id: Int64(1), address: 'bcrt1qcheck', expectedAmountSats: Int64(1000), funded: true),
      ];
      rpc.wallet.scanError = 'find the checks of this wallet on the chain: esplora down';
      final provider = CheckProvider();
      async.flushMicrotasks();

      expect(provider.checks, hasLength(1));
      expect(provider.modelError, contains('esplora down'));

      rpc.wallet.scanError = '';
      async.elapse(const Duration(seconds: 6));

      expect(rpc.wallet.listCalls, 2);
      expect(provider.modelError, isNull);
      expect(provider.checks, hasLength(1));
      provider.dispose();
    });
  });
}
