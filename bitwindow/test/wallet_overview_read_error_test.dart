import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:fixnum/fixnum.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _Stats extends MockWalletAPI {
  Object? failure;

  @override
  Future<GetStatsResponse> getStats(String walletId) async {
    if (failure != null) {
      throw failure!;
    }
    return GetStatsResponse(utxosCurrent: Int64(6), transactionCountTotal: Int64(14));
  }
}

class _Bitwindow extends MockAPI {
  _Bitwindow() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _Stats _stats = _Stats();

  @override
  _Stats get wallet => _stats;
}

class _Transactions extends ChangeNotifier implements TransactionProvider {
  @override
  String? error;

  @override
  List<WalletTransaction> get walletTransactions => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OrchestratorWallet implements OrchestratorWalletRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bmm implements OrchestratorBmmRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _OrchestratorWallet();

  @override
  final OrchestratorBmmRPC bmm = _Bmm();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? get activeWalletId => 'qa';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bitwindow bitwindow;
  late _Transactions transactions;

  setUp(() async {
    await GetIt.I.reset();
    bitwindow = _Bitwindow();
    transactions = _Transactions();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<BitwindowRPC>(bitwindow);
    GetIt.I.registerSingleton<TransactionProvider>(transactions);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  test('a failed stats read is an error, not the last numbers', () async {
    final model = OverviewViewModel();
    await model.getStats();
    expect(model.stats!.utxosCurrent.toInt(), 6);
    expect(model.historyError, isNull);

    bitwindow.wallet.failure = Exception('connection refused');
    await expectLater(model.getStats(), completes);
    expect(model.statsError, contains('connection refused'));
    expect(model.historyError, 'Could not read the wallet: Exception: connection refused');

    bitwindow.wallet.failure = null;
    await model.getStats();
    expect(model.statsError, isNull);
    expect(model.historyError, isNull);
    model.dispose();
  });

  test('a failed history read shows on the history card', () async {
    final model = OverviewViewModel();
    await model.getStats();
    var notified = 0;
    model.addListener(() => notified++);

    transactions.error = 'list transactions: connection refused';
    transactions.notifyListeners();

    expect(model.historyError, 'Could not read the wallet: list transactions: connection refused');
    expect(notified, greaterThan(0));
    model.dispose();
  });

  testWidgets('the tiles show no number while the stats read fails', (tester) async {
    final model = OverviewViewModel();
    bitwindow.wallet.failure = Exception('connection refused');
    await tester.runAsync(model.getStats);
    await tester.pumpSailPage(
      ViewModelBuilder<OverviewViewModel>.nonReactive(
        viewModelBuilder: () => model,
        disposeViewModel: false,
        builder: (context, model, child) => const Row(
          children: [
            Expanded(
              child: WalletStats(
                title: 'Number of UTXOs',
                subtitle: '5 unique addresses',
                value: '6',
                icon: SailSVGAsset.coins,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('-'), findsOneWidget);
    expect(find.text('6'), findsNothing);
    expect(find.text('5 unique addresses'), findsNothing);
    model.dispose();
  });
}
