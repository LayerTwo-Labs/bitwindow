import 'package:bitwindow/pages/overview_page.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/providers/price_provider.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _StatsBitwindowdAPI extends MockBitwindowdAPI {
  int reads = 0;
  Object? error;
  int blocks = 1;

  @override
  Future<GetFireplaceStatsResponse> getFireplaceStats() async {
    reads++;
    if (error case final e?) {
      throw e;
    }
    return GetFireplaceStatsResponse(blockCount24h: Int64(blocks));
  }
}

class _StatsAPI extends MockAPI {
  _StatsAPI() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final api = _StatsBitwindowdAPI();

  @override
  BitwindowAPI get bitwindowd => api;
}

class _Price extends ChangeNotifier implements PriceProvider {
  @override
  String get priceAge => '1 minute ago';

  @override
  String get formattedPrice => r'$1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _StatsAPI rpc;
  late SyncProvider sync;

  setUp(() async {
    await GetIt.I.reset();
    rpc = _StatsAPI()..connected = true;
    sync = SyncProvider(startTimer: false);
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    GetIt.I.registerSingleton<SyncProvider>(sync);
    GetIt.I.registerSingleton<PriceProvider>(_Price());
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  void newTip(int height) {
    sync.bitwindowdSyncInfo = SyncInfo(
      progressCurrent: height.toDouble(),
      progressGoal: height.toDouble(),
      lastBlockAt: null,
    );
    sync.notifyListeners();
  }

  test(
    'a new processed block reads the stats again, with no price change',
    () async {
      final model = FireplaceViewModel();
      addTearDown(model.dispose);
      await pumpEventQueue();
      expect(model.stats?.blockCount24h, Int64(1));

      rpc.api.blocks = 2;
      newTip(102);
      await pumpEventQueue();

      expect(model.stats?.blockCount24h, Int64(2));
    },
  );

  test('the stats follow bitwindowd while the enforcer still syncs', () async {
    final model = FireplaceViewModel();
    addTearDown(model.dispose);
    sync.enforcerSyncInfo = SyncInfo(
      progressCurrent: 10,
      progressGoal: 900,
      lastBlockAt: null,
    );
    await pumpEventQueue();
    final reads = rpc.api.reads;

    rpc.api.blocks = 3;
    newTip(103);
    await pumpEventQueue();
    expect(rpc.api.reads, reads + 1);
    expect(model.stats?.blockCount24h, Int64(3));

    sync.notifyListeners();
    await pumpEventQueue();
    expect(rpc.api.reads, reads + 1, reason: 'the same tip reads nothing');
  });

  test(
    'a failed read sets the error and the next good read clears it',
    () async {
      rpc.api.error = Exception('database is locked');
      final model = FireplaceViewModel();
      addTearDown(model.dispose);
      await pumpEventQueue();

      expect(model.statsError, contains('database is locked'));
      expect(model.stats, isNull);

      rpc.api.error = null;
      newTip(102);
      await pumpEventQueue();
      expect(model.statsError, isNull);
      expect(model.stats?.blockCount24h, Int64(1));
    },
  );

  testWidgets(
    'the tiles show "-" and the cause, not a number, when no read worked',
    (tester) async {
      await loadBundledFonts();
      await tester.pumpSailPage(
        SizedBox(
          width: 1300,
          child: FireplaceStatsView(
            priceLastUpdated: () => '1 minute ago',
            price: r'$1',
            priceTitle: 'Bitcoin Price',
            stats: null,
            failed: true,
            loading: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('-'), findsNWidgets(3));
      expect(find.text('0'), findsNothing);
      expect(find.text('Could not read the stats'), findsNWidgets(3));
    },
  );
}
