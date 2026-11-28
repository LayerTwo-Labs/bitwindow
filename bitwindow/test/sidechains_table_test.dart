// ignore: drivechain_lints/avoid_material_import
import 'package:flutter/material.dart' show TextField;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bitwindow/pages/sidechains_page.dart';
import 'package:bitwindow/pages/wallet/wallet_overview.dart' show phoneHistoryAmount;
import 'package:bitwindow/providers/sidechain_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/mocks/mocks.dart';
import 'package:sidechain_core/providers/binaries/app_run_host.dart';

import 'mocks/store_mock.dart';
import 'test_utils.dart';

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_SIGNET;

  @override
  String ecashNetworkId = '';

  @override
  String? get detectedDataDir => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sidechains extends ChangeNotifier implements SidechainProvider {
  @override
  List<SidechainOverview?> sidechains = List.filled(256, null);

  @override
  String? error;

  void addChain(int slot, String title) {
    sidechains = List.of(sidechains);
    sidechains[slot] = SidechainOverview(
      ListSidechainsResponse_Sidechain(title: title, slot: slot, balanceSatoshi: Int64.ZERO),
      [],
      [],
    );
    notifyListeners();
  }

  @override
  Future<void> fetch() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallet extends ChangeNotifier implements WalletReaderProvider {
  @override
  List<WalletData> wallets = [];

  String? activeId;

  @override
  String? get activeWalletId => activeId;

  @override
  WalletData? get activeWallet => wallets.where((w) => w.id == activeId).firstOrNull;

  @override
  String? resolveFundingWalletId(String? walletId) => null;

  @override
  List<WalletData> fundingWallets() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletData _wallet(String id, String name) => WalletData(
  version: 1,
  master: MasterWallet(mnemonic: '', seedHex: '', masterKey: '', chainCode: ''),
  l1: L1Wallet(mnemonic: ''),
  sidechains: const [],
  id: id,
  name: name,
  gradient: WalletGradient.fromWalletId(id),
  createdAt: DateTime(2026),
  walletType: BinaryType.BINARY_TYPE_ENFORCER,
);

class _Transactions implements TransactionProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Binaries extends BinaryProvider {
  final updated = <Binary>[];

  // ignore: invalid_use_of_visible_for_testing_member
  _Binaries(List<Binary> binaries) : super.test(appDir: Directory.systemTemp, binaries: binaries);

  @override
  Future<void> update(Binary binary) async {
    updated.add(binary);
  }
}

class _Downloads extends DownloadProvider {
  final progress = <BinaryType, DownloadProgress>{};

  _Downloads() : super(startTimer: false);

  @override
  DownloadProgress? statusFor(BinaryType binary) => progress[binary];
}

class _NoRunner implements AppRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThunderRPC extends MockThunderRPC {
  (double, double) wallet = (0, 0);

  @override
  Future<(double, double)> balance() async => wallet;
}

class _CoinShiftRPC extends MockCoinShiftRPC {
  (double, double) wallet = (0, 0);

  @override
  Future<(double, double)> balance() async => wallet;
}

class _Orchestrator implements OrchestratorRPC {
  final balanceReads = <BinaryType>[];
  final starts = <(String, bool)>[];
  GetSidechainBalanceResponse balance = GetSidechainBalanceResponse();

  @override
  Future<GetSidechainBalanceResponse> getSidechainBalance(BinaryType sidechain) async {
    balanceReads.add(sidechain);
    return balance;
  }

  @override
  Future<GetBinaryVersionResponse> getBinaryVersion(String name, {bool forceBackend = false}) async =>
      GetBinaryVersionResponse(version: '$name 1.0');

  @override
  Future<StartWithL1Response> startWithL1(
    String target, {
    List<String>? targetArgs,
    Map<String, String>? targetEnv,
    List<String>? coreArgs,
    List<String>? enforcerArgs,
    bool immediate = false,
    bool forceBackend = false,
  }) async {
    starts.add((target, forceBackend));
    return StartWithL1Response();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Thunder _thunder({bool downloaded = true, bool updateAvailable = false}) {
  final base = Thunder();
  return base.copyWith(
    metadata: base.metadata.copyWith(
      remoteTimestamp: updateAvailable ? DateTime(2026, 2) : null,
      downloadedTimestamp: downloaded ? DateTime(2026, 1) : null,
      binaryPath: downloaded ? File('/tmp/thunder') : null,
      updateable: true,
    ),
  );
}

Finder _button(String label) => find.byWidgetPredicate((widget) => widget is SailButton && widget.label == label);

Future<void> registerSettings() async {
  GetIt.I.registerSingleton<BitwindowClientSettings>(
    BitwindowClientSettings(
      store: MockStore(),
      log: Logger(level: Level.off),
    ),
  );
  GetIt.I.registerSingleton<SettingsProvider>(await SettingsProvider.create());
}

void main() {
  late _ThunderRPC thunderRPC;
  late _Wallet walletReader;
  late _CoinShiftRPC coinShiftRPC;
  late _Downloads downloads;
  late BalanceProvider balances;
  late SyncProvider sync;
  late List<Sidechain> openedHere;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadBundledFonts();
  });

  _Binaries setUpChain(Thunder thunder) {
    final binaries = _Binaries([thunder]);
    GetIt.I.registerSingleton<BinaryProvider>(binaries);
    return binaries;
  }

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    openedHere = [];
    sync = SyncProvider(startTimer: false);
    thunderRPC = _ThunderRPC();
    downloads = _Downloads();
    final sidechains = _Sidechains();
    sidechains.sidechains[9] = SidechainOverview(
      ListSidechainsResponse_Sidechain(title: 'Thunder', slot: 9, balanceSatoshi: Int64(11000000)),
      [],
      [],
    );
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<SyncProvider>(sync);
    GetIt.I.registerSingleton<SidechainProvider>(sidechains);
    walletReader = _Wallet();
    GetIt.I.registerSingleton<WalletReaderProvider>(walletReader);
    GetIt.I.registerSingleton<TransactionProvider>(_Transactions());
    GetIt.I.registerSingleton<LogProvider>(LogProvider());
    GetIt.I.registerSingleton<DownloadProvider>(downloads);
    GetIt.I.registerSingleton<ThunderRPC>(thunderRPC);
    coinShiftRPC = _CoinShiftRPC();
    GetIt.I.registerSingleton<CoinShiftRPC>(coinShiftRPC);
    balances = BalanceProvider(connections: [thunderRPC, coinShiftRPC]);
    GetIt.I.registerSingleton<BalanceProvider>(balances);
    GetIt.I.registerSingleton<ClientSettings>(
      ClientSettings(
        store: MockStore(),
        log: Logger(level: Level.off),
      ),
    );
  });

  tearDown(() async {
    sync.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpTable(WidgetTester tester, {Size size = const Size(1440, 1024)}) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(
      ViewModelBuilder<SidechainsViewModel>.reactive(
        viewModelBuilder: () => SidechainsViewModel(openHere: (chain) async => openedHere.add(chain)),
        builder: (context, model, child) => RepaintBoundary(
          key: const ValueKey('sidechains-table-screen'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SailStyleValues.phoneLayout(context)
                ? const SingleChildScrollView(
                    child: Column(
                      children: [
                        SidechainsList(smallVersion: false),
                        SizedBox(height: 280, child: DepositWithdrawView()),
                      ],
                    ),
                  )
                : const SidechainsOverview(),
          ),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
  }

  Future<void> openRowMenu(WidgetTester tester, String rowText) async {
    final row = tester.getCenter(find.text(rowText).first).dy;
    final menu = find
        .byType(SailRowMenuButton)
        .evaluate()
        .firstWhere(
          (element) => (tester.getCenter(find.byWidget(element.widget)).dy - row).abs() < 12,
        );
    await tester.tap(find.byWidget(menu.widget));
    // The row waits for a double tap before the menu gets the tap.
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
  }

  Future<void> pickMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
  }

  Finder panelPrimary(int slot) => find.byKey(ValueKey('sidechain_panel_primary_$slot'));

  SailButton panelButton(WidgetTester tester, int slot) => tester.widget<SailButton>(panelPrimary(slot));

  testWidgets('on a phone the table shows slot, name and balance, with search under the title', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    setUpChain(_thunder());
    await pumpTable(tester, size: const Size(390, 844));

    expect(tester.takeException(), isNull);
    for (final header in ['Slot', 'Sidechain', 'Sidechain balance']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.text('Status'), findsNothing);
    expect(find.text('Your balance'), findsNothing);
    expect(find.byType(SidechainPanel), findsNothing);
    expect(find.textContaining('BTC'), findsNothing, reason: 'the balance has no unit');
    final title = tester.getRect(find.text('Sidechains').first);
    final search = tester.getRect(find.byKey(const ValueKey('sidechains_search')));
    expect(search.top, greaterThan(title.bottom));
    for (final header in ['Txid', 'Fee', 'Confirmations']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }

    await tester.tap(find.text('Thunder'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Deposit to Thunder'), findsOneWidget);
    final address = find.descendant(
      of: find.widgetWithText(SailTextField, 'Deposit Address'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(address).maxLines, 3, reason: 'a phone shows the whole deposit address');
  });

  testWidgets('the table shows the chain tile, version, status and balances on two lines', (tester) async {
    setUpChain(_thunder().copyWith(version: '0.12.1'));
    await pumpTable(tester);
    await _captureTable(tester, 'overview');

    for (final header in ['Slot', 'Sidechain', 'Status', 'Sidechain balance', 'Your balance']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.byType(SidechainIconTile), findsNWidgets(2), reason: 'Thunder and the empty slots');
    expect(find.text('v0.12.1'), findsOneWidget);
    expect(find.text('Not running'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text(phoneHistoryAmount(11000000, BitcoinUnit.btc)), findsOneWidget);
    expect(find.text('—'), findsOneWidget, reason: 'a stopped chain has no wallet balance');
    expect(find.byType(SidechainPanel), findsNothing, reason: 'no row is selected');
    expect(tester.takeException(), isNull);
  });

  group('empty slots', () {
    testWidgets('fold into one row that a tap opens and closes', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);

      expect(find.text('255 empty slots'), findsOneWidget);
      expect(find.text('0–8, 10–255'), findsOneWidget);
      expect(find.text('0'), findsNothing);

      await tapRow(tester, '255 empty slots');
      expect(find.text('0'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(_top(tester, '255 empty slots'), lessThan(_top(tester, '0')));
      expect(find.byType(SidechainPanel), findsNothing, reason: 'an empty slot has no panel');

      await tapRow(tester, '255 empty slots');
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a tap on an open empty slot opens no panel', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await tapRow(tester, '255 empty slots');

      await tapRow(tester, '3');
      expect(find.byType(SidechainPanel), findsNothing);
    });

    test('slotRanges joins runs of three or more', () {
      expect(slotRanges([0, 1, 3, 5, 6, 7, 8, 10, 11, 12, 14]), '0, 1, 3, 5–8, 10–12, 14');
      expect(slotRanges([4]), '4');
      expect(slotRanges([]), '');
    });
  });

  testWidgets('the search keeps the chains and slots that match', (tester) async {
    setUpChain(_thunder());
    (GetIt.I.get<SidechainProvider>() as _Sidechains).addChain(2, 'BitNames');
    await pumpTable(tester);

    await tester.enterText(find.byKey(const ValueKey('sidechains_search')), 'thun');
    await tester.pumpAndSettle();
    expect(find.text('Thunder'), findsOneWidget);
    expect(find.text('BitNames'), findsNothing);
    expect(find.textContaining('empty slot'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('sidechains_search')), '25');
    await tester.pumpAndSettle();
    expect(find.text('Thunder'), findsNothing);
    expect(find.text('9 empty slots'), findsOneWidget);
    expect(find.text('25, 125, 225, 250–255'), findsOneWidget);
  });

  group('panel', () {
    void addDeposits() {
      final provider = GetIt.I.get<SidechainProvider>() as _Sidechains;
      provider.sidechains = List.of(provider.sidechains);
      provider.sidechains[9] = SidechainOverview(
        ListSidechainsResponse_Sidechain(title: 'Thunder', slot: 9, balanceSatoshi: Int64(11000000)),
        [
          ListSidechainDepositsResponse_SidechainDeposit(
            txid: '9a41aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaae07c',
            amount: Int64(50000000),
            fee: Int64(2100),
            confirmations: 6,
          ),
        ],
        [WithdrawalBundle(m6id: 'm6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab1f', status: 'Pending')],
      );
      provider.sidechains[2] = SidechainOverview(
        ListSidechainsResponse_Sidechain(title: 'BitNames', slot: 2, balanceSatoshi: Int64(321000000)),
        [
          ListSidechainDepositsResponse_SidechainDeposit(
            txid: 'c3f8bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1b2d',
            amount: Int64(25000000),
            fee: Int64(1800),
            confirmations: 142,
          ),
        ],
        [],
      );
    }

    testWidgets('shows the deposits of the selected chain only, and closes with ×', (tester) async {
      setUpChain(_thunder());
      addDeposits();
      await pumpTable(tester);
      expect(find.byType(SidechainPanel), findsNothing);

      await tapRow(tester, 'Thunder');
      await _captureTable(tester, 'panel');
      expect(find.byType(SidechainPanel), findsOneWidget);
      expect(find.text('9a41…e07c'), findsOneWidget);
      expect(find.text('6 conf.'), findsOneWidget);
      expect(find.text('c3f8…1b2d'), findsNothing);
      expect(find.text('Pending'), findsOneWidget, reason: 'the withdrawal bundle in the details');

      await tester.tap(find.text('Withdrawals'));
      await tester.pumpAndSettle();
      expect(find.text('m6aa…ab1f'), findsOneWidget);
      expect(find.text('9a41…e07c'), findsNothing);

      await tapRow(tester, 'BitNames');
      expect(find.text('c3f8…1b2d'), findsOneWidget);
      expect(find.text('142 conf.'), findsOneWidget);
      expect(find.text('9a41…e07c'), findsNothing);
      expect(find.text('None pending'), findsOneWidget);

      await tester.tap(find.text('Withdrawals'));
      await tester.pumpAndSettle();
      expect(find.text('No withdrawal bundles found for this sidechain'), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x));
      await tester.pumpAndSettle();
      expect(find.byType(SidechainPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second tap on the selected row closes the panel', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);

      await tapRow(tester, 'Thunder');
      expect(find.byType(SidechainPanel), findsOneWidget);
      expect(find.text('No deposits yet'), findsOneWidget);
      await tapRow(tester, 'Thunder');
      expect(find.byType(SidechainPanel), findsNothing);
    });

    testWidgets('the panel is 380 px wide at the right of the table', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');

      final panel = tester.getRect(find.byType(SidechainPanel));
      expect(panel.width, SailSidePanel.width);
      expect(panel.left, greaterThan(tester.getRect(find.byType(SailTable)).right));
    });
  });

  group('primary action', () {
    testWidgets('a downloaded chain offers Start, and Deposit stays in the menu', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');

      expect(panelButton(tester, 9).label, 'Start');
      expect(panelButton(tester, 9).variant, ButtonVariant.primary);
      await openRowMenu(tester, 'Thunder');
      expect(find.text('Deposit'), findsWidgets);
    });

    testWidgets('a running chain offers Deposit and shows its wallet balance', (tester) async {
      setUpChain(_thunder());
      thunderRPC.wallet = (4.1, 0.0);
      thunderRPC.setConnected(true);
      await balances.fetch();
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');

      expect(panelButton(tester, 9).label, 'Deposit');
      expect(find.text(phoneHistoryAmount(410000000, BitcoinUnit.btc)), findsOneWidget, reason: 'the wallet column');
      expect(find.text(GetIt.I.get<FormatterProvider>().formatBTC(4.1)), findsOneWidget, reason: 'the panel');
      expect(find.text('Running'), findsWidgets);
      expect(panelButton(tester, 9).onPressed, isNotNull);
    });

    testWidgets('a chain that is not downloaded offers Download', (tester) async {
      setUpChain(_thunder(downloaded: false));
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');

      expect(panelButton(tester, 9).label, 'Download');
      expect(find.text('Not downloaded'), findsWidgets);
    });

    testWidgets('a download in progress shows its percent and a waiting Download', (tester) async {
      setUpChain(_thunder(downloaded: false));
      downloads.progress[BinaryType.BINARY_TYPE_THUNDER] = const DownloadProgress(
        binary: BinaryType.BINARY_TYPE_THUNDER,
        mbDownloaded: 62,
        mbTotal: 100,
      );
      await pumpTable(tester);
      await tester.tap(find.text('Thunder'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pump();

      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('Downloading · 62%'), findsOneWidget);
      expect(panelButton(tester, 9).loading, isTrue);
    });
  });

  testWidgets('a stopped chain shows a dash for Your balance', (tester) async {
    setUpChain(_thunder());
    await pumpTable(tester);

    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  group('row menu', () {
    testWidgets('a running chain offers Stop, Deposit, Settings and Pin to top', (tester) async {
      setUpChain(_thunder());
      thunderRPC.setConnected(true);
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      for (final label in ['Stop', 'Deposit', 'Settings', 'Pin to top']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Start'), findsNothing);
      expect(find.text('Show Chaintip Transaction'), findsNothing, reason: 'the chain has no chaintip');
    });

    testWidgets('an update adds Update to the menu, and it updates the chain', (tester) async {
      final binaries = setUpChain(_thunder(updateAvailable: true));
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      await pickMenuItem(tester, 'Update Thunder');
      expect(binaries.updated.single.type, BinaryType.BINARY_TYPE_THUNDER);
    });

    testWidgets('an update in progress shows Updating and a percent, and no Update item', (tester) async {
      setUpChain(_thunder(updateAvailable: true));
      downloads.progress[BinaryType.BINARY_TYPE_THUNDER] = const DownloadProgress(
        binary: BinaryType.BINARY_TYPE_THUNDER,
        mbDownloaded: 45,
        mbTotal: 100,
      );
      await pumpTable(tester);

      expect(find.text('Updating'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      await openRowMenu(tester, 'Thunder');
      expect(find.text('Update Thunder'), findsNothing);
      expect(find.textContaining('Start'), findsNothing);
    });

    testWidgets('group and empty slot rows have no "…"', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);

      expect(find.byType(SailRowMenuButton), findsOneWidget);
    });
  });

  group('a chain that the app runs on a phone', () {
    late _Orchestrator orchestrator;

    setUp(() async {
      SailStyleValues.phoneLayoutOverride = true;
      orchestrator = _Orchestrator();
      GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
      await registerSettings();
    });

    tearDown(() => SailStyleValues.phoneLayoutOverride = null);

    Future<void> openPhoneRowMenu(WidgetTester tester) async {
      await tester.longPress(find.text('Thunder'));
      await tester.pumpAndSettle();
    }

    void hostThunder() => GetIt.I.registerSingleton<AppRunHost>(
      AppRunHost(
        {'thunder': _NoRunner()},
        reportExit: (_, _) async {},
        log: Logger(level: Level.off),
      ),
    );

    testWidgets('the row menu starts the node and opens the chain', (tester) async {
      hostThunder();
      setUpChain(_thunder(downloaded: false));
      await pumpTable(tester, size: const Size(390, 844));
      await openPhoneRowMenu(tester);

      expect(find.text('Start Thunder'), findsOneWidget);
      await tester.tap(find.text('Start Thunder'));
      await tester.pumpAndSettle();

      expect(orchestrator.starts, [('thunder', true)]);
      expect(openedHere.map((chain) => chain.name), ['Thunder']);
    });

    testWidgets('a Start button on the row starts the node and opens the chain', (tester) async {
      hostThunder();
      setUpChain(_thunder(downloaded: false));
      await pumpTable(tester, size: const Size(390, 844));

      await tester.tap(find.widgetWithText(SailButton, 'Start'));
      // The row waits for a double tap before the button gets the tap.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(orchestrator.starts, [('thunder', true)]);
      expect(openedHere.map((chain) => chain.name), ['Thunder']);
    });

    testWidgets('an Open button on the row of a running node opens the chain', (tester) async {
      hostThunder();
      setUpChain(_thunder(downloaded: false));
      thunderRPC.setConnected(true);
      await pumpTable(tester, size: const Size(390, 844));

      expect(find.widgetWithText(SailButton, 'Start'), findsNothing);
      await tester.tap(find.widgetWithText(SailButton, 'Open'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(orchestrator.starts, isEmpty);
      expect(openedHere.map((chain) => chain.name), ['Thunder']);
    });

    testWidgets('a chain that the app runs hides the no-build line', (tester) async {
      GetIt.I.registerSingleton<NodeModeProvider>(NodeModeProvider()..localBuildsAvailable = false);
      addTearDown(() => GetIt.I.unregister<NodeModeProvider>());
      hostThunder();
      setUpChain(_thunder(downloaded: false));
      await pumpTable(tester, size: const Size(390, 844));

      expect(find.text('This platform has no sidechain build.'), findsNothing);
    });

    testWidgets('a phone with no chain to start keeps the no-build line', (tester) async {
      GetIt.I.registerSingleton<NodeModeProvider>(NodeModeProvider()..localBuildsAvailable = false);
      addTearDown(() => GetIt.I.unregister<NodeModeProvider>());
      setUpChain(_thunder(downloaded: false));
      await pumpTable(tester, size: const Size(390, 844));

      expect(find.text('This platform has no sidechain build.'), findsOneWidget);
      expect(find.widgetWithText(SailButton, 'Start'), findsNothing);
    });

    testWidgets('the row menu has no start for a chain that the app does not run', (tester) async {
      setUpChain(_thunder(downloaded: false));
      await pumpTable(tester, size: const Size(390, 844));
      await openPhoneRowMenu(tester);

      expect(find.text('Pin to top'), findsOneWidget, reason: 'the menu is open');
      expect(find.text('Start Thunder'), findsNothing);
    });
  });

  group('app window', () {
    late _Orchestrator orchestrator;

    setUp(() async {
      orchestrator = _Orchestrator();
      GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
      await registerSettings();
      await GetIt.I.get<SettingsProvider>().updateOpenSidechainsInWindow(true);
    });

    testWidgets('a running chain with its window open offers no Open window', (tester) async {
      setUpChain(_thunder());
      thunderRPC.setConnected(true);
      thunderRPC.windowOpen = true;
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Open window'), findsNothing);
    });

    testWidgets('a running chain with its window closed offers Open window before Stop', (tester) async {
      setUpChain(_thunder());
      thunderRPC.setConnected(true);
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      expect(_top(tester, 'Open window'), lessThan(_top(tester, 'Stop')));
      await pickMenuItem(tester, 'Open window');
      expect(orchestrator.starts, [('thunder', false)]);
    });

    testWidgets('a stopped chain lists the ways to start in its menu', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      expect(find.text('Start with window'), findsOneWidget);
      expect(find.text('Start in background'), findsOneWidget);
      expect(orchestrator.starts, isEmpty);
    });

    testWidgets('Start in background starts the node and opens no window', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');
      await pickMenuItem(tester, 'Start in background');

      expect(orchestrator.starts, [('thunder', true)]);
    });

    testWidgets('Start with window starts the chain with its window', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');
      await pickMenuItem(tester, 'Start with window');

      expect(orchestrator.starts, [('thunder', false)]);
    });

    testWidgets('the panel Start still opens the window', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');
      await tester.tap(panelPrimary(9));
      await tester.pumpAndSettle();

      expect(orchestrator.starts, [('thunder', false)]);
    });
  });

  group('inside BitWindow', () {
    late _Orchestrator orchestrator;

    setUp(() async {
      orchestrator = _Orchestrator();
      GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
      await registerSettings();
    });

    test('the window setting is off by default', () {
      expect(GetIt.I.get<SettingsProvider>().bitwindowSettings.openSidechainsInWindow, isFalse);
    });

    testWidgets('the panel Start runs the node in the background and opens the chain here', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');
      await tester.tap(panelPrimary(9));
      await tester.pumpAndSettle();

      expect(orchestrator.starts, [('thunder', true)]);
      expect(openedHere.map((chain) => chain.name), ['Thunder']);
    });

    testWidgets('the menu offers here, background and a separate window', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      expect(find.text('Start and open here'), findsOneWidget);
      expect(find.text('Start in background'), findsOneWidget);
      expect(find.text('Start in a separate window'), findsOneWidget);
      expect(find.text('Start with window'), findsNothing);

      await pickMenuItem(tester, 'Start in a separate window');
      expect(orchestrator.starts, [('thunder', false)]);
      expect(openedHere, isEmpty);
    });

    testWidgets('Start in background opens nothing', (tester) async {
      setUpChain(_thunder());
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');
      await pickMenuItem(tester, 'Start in background');

      expect(orchestrator.starts, [('thunder', true)]);
      expect(openedHere, isEmpty);
    });

    testWidgets('a running chain offers Open before Stop, and no Open window', (tester) async {
      setUpChain(_thunder());
      thunderRPC.setConnected(true);
      await pumpTable(tester);
      await openRowMenu(tester, 'Thunder');

      expect(_top(tester, 'Open'), lessThan(_top(tester, 'Stop')));
      expect(find.text('Open window'), findsNothing);
      await pickMenuItem(tester, 'Open');
      expect(openedHere.map((chain) => chain.name), ['Thunder']);
      expect(orchestrator.starts, isEmpty);
    });

    testWidgets('with the setting on, Start uses the window flow', (tester) async {
      await GetIt.I.get<SettingsProvider>().updateOpenSidechainsInWindow(true);
      setUpChain(_thunder());
      await pumpTable(tester);
      await tapRow(tester, 'Thunder');
      await tester.tap(panelPrimary(9));
      await tester.pumpAndSettle();

      expect(orchestrator.starts, [('thunder', false)]);
      expect(openedHere, isEmpty);
    });
  });

  testWidgets('a running CoinShift shows its balance, not a dash', (tester) async {
    final coinShift = CoinShift();
    GetIt.I.registerSingleton<BinaryProvider>(
      _Binaries([
        _thunder(),
        coinShift.copyWith(
          metadata: coinShift.metadata.copyWith(
            remoteTimestamp: null,
            downloadedTimestamp: DateTime(2026, 1),
            binaryPath: File('/tmp/coinshift'),
            updateable: true,
          ),
        ),
      ]),
    );
    GetIt.I.get<SidechainProvider>().sidechains[255] = SidechainOverview(
      ListSidechainsResponse_Sidechain(title: 'CoinShift', slot: 255, balanceSatoshi: Int64(5000000)),
      [],
      [],
    );
    coinShiftRPC.wallet = (0.25, 0.0);
    coinShiftRPC.setConnected(true);
    await balances.fetch();
    await pumpTable(tester);

    expect(find.text(phoneHistoryAmount(25000000, BitcoinUnit.btc)), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  test('progressPercent never reads 100% before the goal', () {
    expect(progressPercent(45, 100), '45%');
    expect(progressPercent(999, 1000), '99%');
    expect(progressPercent(100, 100), '100%');
    expect(progressPercent(5, 0), '—');
  });

  for (final (phase, label) in [
    (MainchainSyncPhase.MAINCHAIN_SYNC_PHASE_HEADERS, 'Fetching mainchain headers'),
    (MainchainSyncPhase.MAINCHAIN_SYNC_PHASE_WRITING, 'Writing mainchain headers'),
    (MainchainSyncPhase.MAINCHAIN_SYNC_PHASE_STATE, 'Syncing mainchain state'),
  ]) {
    testWidgets('a running chain in a mainchain phase shows "$label" and its percent', (tester) async {
      setUpChain(_thunder());
      thunderRPC.setConnected(true);
      sync.sidechains = {
        SidechainType.SIDECHAIN_TYPE_THUNDER: SyncInfo(
          progressCurrent: 412000,
          progressGoal: 997070,
          lastBlockAt: null,
          mainchainSyncPhase: phase,
          mainchainTipHeight: 997070,
        ),
      };
      await pumpTable(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(label), findsOneWidget);
      expect(find.text('41.3%'), findsOneWidget);
      // A sync must not take Stop away: the chain's own window may be closed.
      await openRowMenu(tester, 'Thunder');
      expect(find.text('Stop'), findsOneWidget);
    });
  }

  testWidgets('a running chain without a mainchain phase shows Syncing and the block percent', (tester) async {
    setUpChain(_thunder());
    thunderRPC.setConnected(true);
    sync.sidechains = {
      SidechainType.SIDECHAIN_TYPE_THUNDER: SyncInfo(progressCurrent: 100, progressGoal: 294, lastBlockAt: null),
    };
    await pumpTable(tester);

    expect(find.text('Syncing'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
  });

  testWidgets('a synced chain shows its block height', (tester) async {
    setUpChain(_thunder());
    thunderRPC.setConnected(true);
    sync.sidechains = {
      SidechainType.SIDECHAIN_TYPE_THUNDER: SyncInfo(progressCurrent: 294, progressGoal: 294, lastBlockAt: null),
    };
    await pumpTable(tester);

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('block 294'), findsOneWidget);
  });

  testWidgets('a header tap changes neither the row order nor the headers', (tester) async {
    setUpChain(_thunder());
    (GetIt.I.get<SidechainProvider>() as _Sidechains).addChain(2, 'BitNames');
    await pumpTable(tester);

    for (final header in ['Slot', 'Sidechain', 'Sidechain balance', 'Your balance']) {
      await tester.tap(find.text(header));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('2')).dy, lessThan(tester.getTopLeft(find.text('9')).dy));
      expect(
        tester.widgetList<SailTableHeaderCell>(find.byType(SailTableHeaderCell)).any((cell) => cell.isSorted),
        isFalse,
      );
    }
  });

  testWidgets('search and Add or remove sit in the card head', (tester) async {
    setUpChain(_thunder());
    await pumpTable(tester);

    expect(tester.widget<SailButton>(_button('Add or remove')).variant, ButtonVariant.ghost);
    final search = tester.getRect(find.byKey(const ValueKey('sidechains_search')));
    final button = tester.getRect(_button('Add or remove'));
    expect(button.left, greaterThan(search.right));
    expect(button.bottom, lessThan(tester.getTopLeft(find.text('Slot')).dy));
  });

  testWidgets('the balance header names the wallet the sidechain holds', (tester) async {
    setUpChain(_thunder());
    walletReader.wallets = [_wallet('a', 'Main wallet'), _wallet('b', 'Savings')];
    walletReader.activeId = 'a';
    thunderRPC.loadedWalletId = 'b';
    thunderRPC.setConnected(true);
    await balances.fetch();
    await pumpTable(tester);

    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Main wallet'), findsNothing);
    expect(find.text('Your balance'), findsNothing);
    expect(find.byType(WalletBlobAvatar), findsOneWidget);
  });

  testWidgets('sidechains on different wallets name no one wallet in the header', (tester) async {
    final coinShift = CoinShift();
    GetIt.I.registerSingleton<BinaryProvider>(
      _Binaries([
        _thunder(),
        coinShift.copyWith(
          metadata: coinShift.metadata.copyWith(
            remoteTimestamp: null,
            downloadedTimestamp: DateTime(2026, 1),
            binaryPath: File('/tmp/coinshift'),
            updateable: true,
          ),
        ),
      ]),
    );
    GetIt.I.get<SidechainProvider>().sidechains[255] = SidechainOverview(
      ListSidechainsResponse_Sidechain(title: 'CoinShift', slot: 255),
      [],
      [],
    );
    walletReader.wallets = [_wallet('a', 'Main wallet'), _wallet('b', 'Savings')];
    walletReader.activeId = 'b';
    thunderRPC.loadedWalletId = 'b';
    thunderRPC.setConnected(true);
    coinShiftRPC.loadedWalletId = 'a';
    coinShiftRPC.setConnected(true);
    await balances.fetch();
    await pumpTable(tester);

    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('Savings'), findsNothing);
    expect(find.text('Main wallet'), findsNothing);
  });

  testWidgets('a running sidechain with a wallet of its own names no wallet in the header', (tester) async {
    setUpChain(_thunder());
    walletReader.wallets = [_wallet('a', 'Main wallet')];
    walletReader.activeId = 'a';
    thunderRPC.setConnected(true);
    await balances.fetch();
    await pumpTable(tester);

    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('Main wallet'), findsNothing);
  });

  testWidgets('a stopped sidechain does not name the balance column', (tester) async {
    setUpChain(_thunder());
    walletReader.wallets = [_wallet('a', 'Main wallet'), _wallet('b', 'Savings')];
    walletReader.activeId = 'a';
    thunderRPC.loadedWalletId = 'b';
    await pumpTable(tester);

    expect(find.text('Main wallet'), findsOneWidget);
    expect(find.text('Savings'), findsNothing);
  });

  testWidgets('before a sidechain reports a wallet, the header names the active wallet', (tester) async {
    setUpChain(_thunder());
    walletReader.wallets = [_wallet('a', 'Main wallet')];
    walletReader.activeId = 'a';
    await pumpTable(tester);

    expect(find.text('Main wallet'), findsOneWidget);
    expect(find.text('External wallet'), findsNothing);
  });

  testWidgets('a sidechain that keeps an outside wallet shows the External wallet badge', (tester) async {
    setUpChain(_thunder());
    thunderRPC.hasExternalWallet = true;
    await pumpTable(tester);

    expect(find.text('External wallet'), findsOneWidget);
  });

  // Adding confirmed and pending into one figure made the cell disagree with
  // the bottom nav, which shows the two apart.
  testWidgets('Your balance shows the confirmed figure and holds pending in a tooltip', (tester) async {
    setUpChain(_thunder());
    thunderRPC.wallet = (2.01999, 1.0);
    thunderRPC.setConnected(true);
    await balances.fetch();
    await pumpTable(tester);

    final formatter = GetIt.I.get<FormatterProvider>();
    expect(find.text(phoneHistoryAmount(201999000, BitcoinUnit.btc)), findsOneWidget);
    expect(find.text(phoneHistoryAmount(301999000, BitcoinUnit.btc)), findsNothing);
    expect(_tooltip('Pending ${formatter.formatBTC(1.0)}'), findsOneWidget);
  });

  testWidgets('a chain with nothing pending shows one number and no tooltip', (tester) async {
    setUpChain(_thunder());
    thunderRPC.wallet = (2.01999, 0.0);
    thunderRPC.setConnected(true);
    await balances.fetch();
    await pumpTable(tester);

    final formatter = GetIt.I.get<FormatterProvider>();
    expect(find.text(phoneHistoryAmount(201999000, BitcoinUnit.btc)), findsOneWidget);
    expect(_tooltip('Pending ${formatter.formatBTC(0.0)}'), findsNothing);
  });

  group('pins', () {
    void addChains() {
      final provider = GetIt.I.get<SidechainProvider>() as _Sidechains;
      provider.addChain(2, 'BitNames');
      provider.addChain(3, 'RISCy');
      provider.addChain(13, 'Truthcoin');
    }

    Future<void> pin(int slot) => GetIt.I.get<ClientSettings>().setValue(PinnedSidechainsSetting(newValue: [slot]));

    testWidgets('a pinned chain and a chain with a balance go above Other slots', (tester) async {
      setUpChain(_thunder());
      addChains();
      walletReader.wallets = [_wallet('a', 'Main wallet')];
      thunderRPC.loadedWalletId = 'a';
      thunderRPC.wallet = (4.1, 0.0);
      thunderRPC.setConnected(true);
      await balances.fetch();
      await pin(13);
      await pumpTable(tester);

      expect(_top(tester, 'Your sidechains'), lessThan(_top(tester, 'Thunder')));
      expect(_top(tester, 'Thunder'), lessThan(_top(tester, 'Truthcoin')));
      expect(_top(tester, 'Truthcoin'), lessThan(_top(tester, 'Other slots')));
      expect(_top(tester, 'Other slots'), lessThan(_top(tester, 'BitNames')));
      expect(_top(tester, 'BitNames'), lessThan(_top(tester, 'RISCy')));
      expect(_top(tester, 'RISCy'), lessThan(_top(tester, '252 empty slots')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no pin and no balance the table shows no groups', (tester) async {
      setUpChain(_thunder());
      addChains();
      await pumpTable(tester);

      expect(find.text('Your sidechains'), findsNothing);
      expect(find.text('Other slots'), findsNothing);
      expect(_top(tester, 'BitNames'), lessThan(_top(tester, 'Thunder')));
    });

    testWidgets('Pin to top moves the chain to the top and saves the pin, Unpin moves it back', (tester) async {
      setUpChain(_thunder());
      addChains();
      await pumpTable(tester);

      await openRowMenu(tester, 'Truthcoin');
      expect(find.text('Unpin'), findsNothing);
      await pickMenuItem(tester, 'Pin to top');

      expect(_top(tester, 'Truthcoin'), lessThan(_top(tester, 'Other slots')));
      expect(_top(tester, 'Other slots'), lessThan(_top(tester, 'BitNames')));
      expect((await GetIt.I.get<ClientSettings>().getValue(PinnedSidechainsSetting())).value, [13]);

      await openRowMenu(tester, 'Truthcoin');
      expect(find.text('Pin to top'), findsNothing);
      await pickMenuItem(tester, 'Unpin');

      expect(find.text('Your sidechains'), findsNothing);
      expect((await GetIt.I.get<ClientSettings>().getValue(PinnedSidechainsSetting())).value, isEmpty);
    });

    testWidgets('a pin stays when the page opens again', (tester) async {
      setUpChain(_thunder());
      addChains();
      await pumpTable(tester);
      await openRowMenu(tester, 'RISCy');
      await pickMenuItem(tester, 'Pin to top');

      await tester.pumpWidget(const SizedBox());
      await pumpTable(tester);

      expect(_top(tester, 'RISCy'), lessThan(_top(tester, 'Other slots')));
    });
  });
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text).first).dy;

Future<void> _captureTable(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('SIDECHAIN_TABLE_SCREEN_DIR');
  if (directory.isEmpty) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('sidechains-table-screen')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Finder _tooltip(String message) =>
    find.byWidgetPredicate((widget) => widget is SailTooltip && widget.message == message);
