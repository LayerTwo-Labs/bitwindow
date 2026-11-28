import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/sidechains/bmm_tab.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

class _Bmm extends ChangeNotifier implements BMMProvider {
  @override
  double maxBidAmount = 0.0002;

  @override
  int get suggestedBidSats => 188;

  @override
  bool running = false;

  @override
  String? get fundingWalletId => 'wallet1';

  @override
  bool get fundingBalanceTooLow => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallets extends ChangeNotifier implements WalletReaderProvider {
  @override
  List<WalletData> fundingWallets() => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bmm bmm;
  late SyncProvider sync;
  late NodeModeProvider mode;
  late BMMViewModel model;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    mode = NodeModeProvider()..mode = wmpb.NodeMode.NODE_MODE_FULL;
    bmm = _Bmm();
    sync = SyncProvider(startTimer: false)
      ..mainchainSyncInfo = SyncInfo(progressCurrent: 42, progressGoal: 42, lastBlockAt: null)
      ..enforcerSyncInfo = SyncInfo(progressCurrent: 42, progressGoal: 42, lastBlockAt: null);
    GetIt.I.registerSingleton<NodeModeProvider>(mode);
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<SyncProvider>(sync);
    GetIt.I.registerSingleton<WalletReaderProvider>(_Wallets());
    model = BMMViewModel(provider: bmm);
  });

  tearDown(() async {
    model.dispose();
    sync.dispose();
    bmm.dispose();
    mode.dispose();
    await GetIt.I.reset();
  });

  // 894 px is the card content in a hosted chain at the default 1200 px window.
  testWidgets('the bid controls fit the card of a hosted chain', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 894, child: BmmControls(viewModel: model)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(BmmControls));
    final toggle = find.byWidgetPredicate((w) => w is SailButton && w.label == 'Start auto-bidding');
    expect(card.contains(tester.getRect(toggle).bottomRight - const Offset(1, 1)), isTrue);
    final menu = find.byType(SailRowMenuButton);
    expect(card.contains(tester.getRect(menu).bottomRight - const Offset(1, 1)), isTrue, reason: 'Bid manually');
    for (final label in ['Min bid:', 'Max bid:']) {
      expect(card.contains(tester.getRect(find.text(label)).center), isTrue, reason: label);
    }
  });
}
