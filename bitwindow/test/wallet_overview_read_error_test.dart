import 'dart:async';

import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:fixnum/fixnum.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _Stats extends MockWalletAPI {
  Object? failure;
  Future<GetStatsResponse> Function(String)? read;

  @override
  Future<GetStatsResponse> getStats(String walletId) async {
    if (read != null) {
      return read!(walletId);
    }
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
  String? activeWalletId = 'qa';

  void select(String? id) {
    activeWalletId = id;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bitwindow bitwindow;
  late _Transactions transactions;
  late _WalletReader reader;

  setUp(() async {
    await GetIt.I.reset();
    bitwindow = _Bitwindow();
    transactions = _Transactions();
    reader = _WalletReader();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<BitwindowRPC>(bitwindow);
    GetIt.I.registerSingleton<TransactionProvider>(transactions);
    GetIt.I.registerSingleton<WalletReaderProvider>(reader);
    await registerTestDependencies();
    GetIt.I.registerSingleton<AddressBookProvider>(AddressBookProvider());
  });

  tearDown(() => GetIt.I.reset());

  test('a wallet switch clears the previous stats before the next read', () async {
    final model = OverviewViewModel();
    addTearDown(model.dispose);
    await model.getStats();
    expect(model.stats!.utxosCurrent.toInt(), 6);

    final next = Completer<GetStatsResponse>();
    bitwindow.wallet.read = (_) => next.future;
    reader.select('second');
    expect(model.stats, isNull);
    next.complete(GetStatsResponse(utxosCurrent: Int64(2)));
    await Future<void>.delayed(Duration.zero);
    expect(model.stats!.utxosCurrent.toInt(), 2);
  });

  test('a late stats answer cannot replace the active wallet stats', () async {
    final model = OverviewViewModel();
    addTearDown(model.dispose);
    await model.getStats();
    final old = Completer<GetStatsResponse>();
    bitwindow.wallet.read = (id) => id == 'qa' ? old.future : Future.value(GetStatsResponse(utxosCurrent: Int64(2)));
    final previous = model.getStats();
    reader.select('second');
    await model.getStats();
    expect(model.stats!.utxosCurrent.toInt(), 2);
    old.complete(GetStatsResponse(utxosCurrent: Int64(99)));
    await previous;
    expect(model.stats!.utxosCurrent.toInt(), 2);
  });

  test('a late stats error cannot replace the active wallet result', () async {
    final model = OverviewViewModel();
    addTearDown(model.dispose);
    await model.getStats();
    final old = Completer<GetStatsResponse>();
    bitwindow.wallet.read = (id) => id == 'qa' ? old.future : Future.value(GetStatsResponse(utxosCurrent: Int64(2)));
    final previous = model.getStats();
    reader.select('second');
    await model.getStats();
    old.completeError(Exception('old wallet unavailable'));
    await previous;
    expect(model.statsError, isNull);
    expect(model.stats!.utxosCurrent.toInt(), 2);
  });

  test('no active wallet clears stats and the previous read error', () async {
    final model = OverviewViewModel();
    addTearDown(model.dispose);
    await model.getStats();
    bitwindow.wallet.failure = Exception('old wallet unavailable');
    await model.getStats();
    reader.select(null);
    await model.getStats();
    expect(model.stats, isNull);
    expect(model.statsError, isNull);
  });

  test('the last stats read keeps its result when an older read ends later', () async {
    final model = OverviewViewModel();
    addTearDown(model.dispose);
    await model.getStats();
    final old = Completer<GetStatsResponse>();
    bitwindow.wallet.read = (_) => old.future;
    final previous = model.getStats();
    bitwindow.wallet.read = (_) async => GetStatsResponse(utxosCurrent: Int64(2));
    await model.getStats();
    old.complete(GetStatsResponse(utxosCurrent: Int64(99)));
    await previous;
    expect(model.stats!.utxosCurrent.toInt(), 2);
  });

  test('a return to the first wallet rejects its old stats read', () async {
    final model = OverviewViewModel();
    addTearDown(model.dispose);
    await model.getStats();
    final old = Completer<GetStatsResponse>();
    bitwindow.wallet.read = (_) => old.future;
    final previous = model.getStats();
    bitwindow.wallet.read = (_) async => GetStatsResponse(utxosCurrent: Int64(2));
    reader.select('second');
    reader.select('qa');
    await model.getStats();
    old.complete(GetStatsResponse(utxosCurrent: Int64(99)));
    await previous;
    expect(model.stats!.utxosCurrent.toInt(), 2);
  });

  test('a stats read ends after disposal without a notification', () async {
    final model = OverviewViewModel();
    await model.getStats();
    final next = Completer<GetStatsResponse>();
    bitwindow.wallet.read = (_) => next.future;
    final read = model.getStats();
    model.dispose();
    next.complete(GetStatsResponse(utxosCurrent: Int64(2)));
    await expectLater(read, completes);
    expect(model.stats!.utxosCurrent.toInt(), 6);
    reader.select('second');
  });

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

  testWidgets('the last activity age moves on while the stats stay the same', (tester) async {
    var now = DateTime.utc(2026, 11, 28, 12);
    final model = OverviewViewModel();
    bitwindow.wallet.read = (_) async => GetStatsResponse(
      lastTxAt: Timestamp.fromDateTime(now.subtract(const Duration(seconds: 59))),
      lastTxBlockHeight: 103,
    );
    await tester.runAsync(model.getStats);
    await tester.pumpSailPage(
      ViewModelBuilder<OverviewViewModel>.reactive(
        viewModelBuilder: () => model,
        disposeViewModel: false,
        builder: (context, model, child) => Row(
          children: [
            Expanded(
              child: LastActivityStats(stats: model.stats, now: () => now),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59 seconds ago'), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('1 minute ago'), findsOneWidget);
    expect(find.text('at block 103'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
