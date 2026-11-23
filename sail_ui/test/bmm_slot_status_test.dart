import 'package:flutter/foundation.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/sidechains/bmm_tab.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/bmm/v1/bmm.pb.dart' as bmmpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

class _Bmm extends ChangeNotifier implements BMMProvider {
  @override
  double maxBidAmount = 0.0002;

  @override
  int get suggestedBidSats => 188;

  @override
  bool running = false;

  @override
  bmmpb.Bid? liveBid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
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
    model = BMMViewModel(provider: bmm);
  });

  tearDown(() async {
    model.dispose();
    sync.dispose();
    bmm.dispose();
    mode.dispose();
    await GetIt.I.reset();
  });

  test('a manual bid shows as placed while auto-bidding is off', () {
    bmm.liveBid = bmmpb.Bid(bidSats: Int64(10001), criticalHash: 'ab' * 32, state: 'live');

    expect(model.slotStatus, 'Bid placed');
    expect(model.slotTone, SailBadgeTone.success);
    expect(model.slotHint, startsWith('Waiting for a miner'));
  });

  test('no bid and no auto-bidding shows not bidding', () {
    expect(model.slotStatus, 'Not bidding');
  });

  test('auto-bidding with no bid out yet shows assembling', () {
    bmm.running = true;

    expect(model.slotStatus, 'Assembling');
  });
}
