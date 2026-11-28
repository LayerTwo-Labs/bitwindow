import 'dart:io';
import 'dart:ui' as ui;

import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:bitwindow/pages/wallet/wallet_page.dart';
import 'package:bitwindow/pages/wallet/widgets/wallet_v2_parts.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _Stats extends MockWalletAPI {
  @override
  Future<GetStatsResponse> getStats(String walletId) async => GetStatsResponse(
    utxosCurrent: Int64(6),
    utxosUniqueAddresses: Int64(5),
    totalFeesSats: Int64(12840),
    sidechainDepositVolumeLast30Days: Int64(5000000),
    transactionCountTotal: Int64(14),
  );
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
  List<WalletTransaction> walletTransactions = [];

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  bool networkSupportsSidechains = true;

  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String ecashNetworkId = '';

  @override
  String currentNetworkOptionId = '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletTransaction _tx(String txid, {int received = 0, int sent = 0, int confirmations = 3, String note = ''}) =>
    WalletTransaction(
      txid: txid,
      receivedSatoshi: Int64(received),
      sentSatoshi: Int64(sent),
      feeSats: Int64(226),
      address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
      note: note,
      confirmations: confirmations,
      confirmationTime: Confirmation(height: 900, timestamp: Timestamp.fromDateTime(DateTime(2026, 10, 31, 18, 42))),
    );

/// Writes a PNG of the page when WALLET_SHOT_DIR is set, for a look by eye.
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['WALLET_SHOT_DIR'];
  if (dir == null) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  late _Transactions transactions;

  setUp(() async {
    await GetIt.I.reset();
    transactions = _Transactions();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<BitwindowRPC>(_Bitwindow());
    GetIt.I.registerSingleton<TransactionProvider>(transactions);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    await registerTestDependencies();
    GetIt.I.registerSingleton<AddressBookProvider>(AddressBookProvider());
  });

  tearDown(() => GetIt.I.reset());

  Future<OverviewViewModel> pumpOverview(WidgetTester tester) async {
    await loadBundledFonts();
    final model = OverviewViewModel();
    await tester.runAsync(model.getStats);
    await tester.pumpSailPage(
      Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: SizedBox(
            width: 1416,
            height: 820,
            child: ViewModelBuilder<OverviewViewModel>.reactive(
              viewModelBuilder: () => model,
              disposeViewModel: false,
              builder: (context, model, child) => WalletOverviewDesktop(model: model),
            ),
          ),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1440, 860));
    await tester.pump();
    return model;
  }

  testWidgets('the strip shows the stats and the Send and Receive buttons', (tester) async {
    final model = await pumpOverview(tester);

    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('Unconfirmed'), findsOneWidget);
    expect(find.text('Lifetime fees'), findsOneWidget);
    expect(find.text('6 on 5 addresses'), findsOneWidget);
    expect(find.text('Sidechain deposits, 30 days'), findsOneWidget);
    expect(find.text(walletAmountText(5000000)), findsOneWidget);
    expect(find.text('Last activity'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Send'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Receive'), findsOneWidget);
    model.dispose();
  });

  testWidgets('Send and Receive in the strip open their tabs', (tester) async {
    final model = await pumpOverview(tester);

    await tester.tap(find.widgetWithText(SailButton, 'Receive'));
    await tester.pump();
    expect(WalletPage.pendingSubtab, 'Receive');

    await tester.tap(find.widgetWithText(SailButton, 'Send'));
    await tester.pump();
    expect(WalletPage.pendingSubtab, 'Send');
    model.dispose();
  });

  testWidgets('a row click opens the side panel, and the × closes it', (tester) async {
    transactions.walletTransactions = [
      _tx('7c1e${'a' * 56}9f03', sent: 25000000, confirmations: 0, note: 'Rent'),
      _tx('3f9a${'b' * 56}c21e', received: 50000000, confirmations: 1204),
    ];
    final model = await pumpOverview(tester);
    expect(find.byType(SailSidePanel), findsNothing);
    await _shot(tester, 'overview');

    await tester.tap(find.text('Rent'));
    await tester.pump();

    expect(find.byType(SailSidePanel), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Bump fee'), findsOneWidget);
    expect(find.text('Unconfirmed · 0 confirmations'), findsOneWidget);
    await _shot(tester, 'overview-panel');

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x));
    await tester.pump();
    expect(find.byType(SailSidePanel), findsNothing);
    model.dispose();
  });

  testWidgets('a confirmed payment opens a panel with no main action', (tester) async {
    transactions.walletTransactions = [_tx('3f9a${'b' * 56}c21e', received: 50000000, confirmations: 1204)];
    final model = await pumpOverview(tester);

    await tester.tap(find.text('Received'));
    await tester.pump();

    expect(find.byType(SailSidePanel), findsOneWidget);
    expect(find.text('Confirmed · 1 204 confirmations'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Bump fee'), findsNothing);
    model.dispose();
  });
}
