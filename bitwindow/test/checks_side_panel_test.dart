import 'package:bitwindow/pages/wallet/wallet_checks.dart';
import 'package:bitwindow/providers/check_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as bwpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _address = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _wif = 'cVt4o7BGAig1UXywgGSmARhxMdzP5qvQsxKkSsc1XEkw3tDTQFpy';

final _unfunded = bwpb.Cheque(
  id: Int64(1),
  address: _address,
  expectedAmountSats: Int64(1000000),
  createdAt: Timestamp.fromDateTime(DateTime(2026, 11, 20, 9, 14)),
);

final _funded = bwpb.Cheque(
  id: Int64(2),
  address: _address,
  expectedAmountSats: Int64(2500000),
  actualAmountSats: Int64(2500000),
  funded: true,
  fundedTxids: ['ab' * 32],
  privateKeyWif: _wif,
  createdAt: Timestamp.fromDateTime(DateTime(2026, 11, 18, 16, 2)),
);

class _FakeCheckProvider extends ChangeNotifier implements CheckProvider {
  @override
  final List<bwpb.Cheque> checks = [_unfunded, _funded];

  @override
  bool get isLoading => false;

  @override
  String? modelError;

  @override
  Future<void> fetch() async {}

  @override
  Future<bwpb.Cheque> getCheck(int id) async => checks.firstWhere((c) => c.id.toInt() == id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactions extends ChangeNotifier implements TransactionProvider {
  @override
  String address = _address;

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
  int sends = 0;

  @override
  Future<wmpb.SendTransactionResponse> sendTransaction({
    required String walletId,
    required Map<String, int> destinations,
    double? feeRateSatPerVbyte,
    int? fixedFeeSats,
    bool subtractFeeFromAmount = false,
    String? opReturnMessage,
    String? opReturnHex,
    List<bwpb.UnspentOutput>? requiredInputs,
    bwpb.UnspentOutput? notificationInput,
    bool allowReplay = false,
  }) async {
    sends++;
    return wmpb.SendTransactionResponse(txid: 'cd' * 32);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBitcoinConf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String get ecashNetworkId => '';

  @override
  String get ecashEsploraUrl => '';

  @override
  String get ecashExplorerHost => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final _FakeOrchestratorWallet wallet = _FakeOrchestratorWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  GetIt.I.registerSingleton<CheckProvider>(_FakeCheckProvider());
  GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactions());
  GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader());
  GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
  final theme = SailThemeData.lightTheme(
    SailColorScheme.orange,
    false,
    SailFontValues.inter,
    SailThemeStyle.bitwindowV2,
  );
  await tester.pumpSailPage(SailTheme(data: theme, child: const ChecksTab()));
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  await tester.pump();
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('the rows hold no buttons and end with one "…"', (tester) async {
    await _pump(tester);

    expect(find.byType(SailSidePanel), findsNothing);
    expect(find.text('Actions'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Fund Check'), findsNothing);
    expect(find.widgetWithText(SailButton, 'View Details'), findsNothing);
    expect(find.byType(SailRowMenuButton), findsNWidgets(2));
  });

  testWidgets('a row click opens the check in the side panel, and × closes it', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(formatChequeDate(_funded.createdAt)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final panel = find.byType(SailSidePanel);
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Check for 0.02500000 ${activeTicker.symbol}')),
      findsOneWidget,
    );
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailStatusPill, 'Funded')), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'Sweep Check to Wallet')),
      findsOneWidget,
    );
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'Fund with Wallet')), findsNothing);
    expect(find.descendant(of: panel, matching: find.text('Private Key (WIF)')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Expected Amount')), findsOneWidget);

    await tester.tap(find.descendant(of: panel, matching: find.byType(SailIconBoxButton)).last);
    await tester.pump();
    expect(find.byType(SailSidePanel), findsNothing);
  });

  testWidgets('an unfunded check offers Fund with Wallet and its address QR', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(formatChequeDate(_unfunded.createdAt)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final panel = find.byType(SailSidePanel);
    expect(
      find.descendant(of: panel, matching: find.widgetWithText(SailStatusPill, 'Awaiting funding')),
      findsOneWidget,
    );
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'Fund with Wallet')), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'Sweep Check to Wallet')),
      findsNothing,
    );
    expect(find.descendant(of: panel, matching: find.text('Address')), findsWidgets);
  });

  testWidgets('a sent funding closes the panel, so Fund with Wallet cannot send twice', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(formatChequeDate(_unfunded.createdAt)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    GetIt.I.registerSingleton<BitcoinConfProvider>(_FakeBitcoinConf());
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    }
    GetIt.I.registerSingleton<NotificationProvider>(NotificationProvider());

    final fund = find.descendant(
      of: find.byType(SailSidePanel),
      matching: find.widgetWithText(SailButton, 'Fund with Wallet'),
    );
    await tester.tap(fund);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final wallet = (GetIt.I<OrchestratorRPC>() as _FakeOrchestrator).wallet;
    expect(wallet.sends, 1);
    expect(find.byType(SailSidePanel), findsNothing);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('the row "…" holds Fund Check, mempool.space and Delete', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Fund Check'), findsOneWidget);
    expect(find.text('View on mempool.space'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Fund Check'));
    await tester.pumpAndSettle();
    expect(find.byType(SailSidePanel), findsOneWidget);
  });

  testWidgets('on the desktop Create New Check and Cash Check open dialogs with a ×', (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(SailButton, 'Create New Check'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.widgetWithText(SailDialog, 'Create Check'), findsOneWidget);
    expect(find.text('How much should the check be for?'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Cancel'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(SailDialog), matching: find.byType(SailIconBoxButton)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SailDialog), findsNothing);

    await tester.tap(find.widgetWithText(SailButton, 'Cash Check'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SailDialog), findsOneWidget);
    expect(find.text('Enter the private key (WIF)'), findsOneWidget);
  });
}
