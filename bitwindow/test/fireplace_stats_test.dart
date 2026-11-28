import 'dart:async';

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
  // ignore: close_sinks, the tearDown closes it
  final frames = StreamController<WatchFireplaceStatsResponse>.broadcast();

  @override
  Stream<WatchFireplaceStatsResponse> watchFireplaceStats() => frames.stream;
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

  tearDown(() async {
    await rpc.api.frames.close();
    await GetIt.I.reset();
  });

  WatchFireplaceStatsResponse frame(int blocks) =>
      WatchFireplaceStatsResponse(stats: GetFireplaceStatsResponse(blockCount24h: Int64(blocks)));

  test('each stats frame replaces the stats', () async {
    final model = FireplaceViewModel();
    addTearDown(model.dispose);
    await pumpEventQueue();
    expect(model.stats, isNull);

    rpc.api.frames.add(frame(1));
    await pumpEventQueue();
    expect(model.stats?.blockCount24h, Int64(1));

    rpc.api.frames.add(frame(0));
    await pumpEventQueue();
    expect(model.stats?.blockCount24h, Int64(0), reason: 'a block that left the window counts no more');
  });

  test('a heartbeat keeps the stats', () async {
    final model = FireplaceViewModel();
    addTearDown(model.dispose);
    rpc.api.frames.add(frame(2));
    await pumpEventQueue();
    var notified = 0;
    model.addListener(() => notified++);

    rpc.api.frames.add(WatchFireplaceStatsResponse(heartbeat: true));
    await pumpEventQueue();

    expect(model.stats?.blockCount24h, Int64(2));
    expect(notified, 0);
  });

  test('a stream that breaks marks the stats failed, and the next frame clears it', () async {
    final model = FireplaceViewModel();
    addTearDown(model.dispose);
    rpc.api.frames.add(frame(3));
    await pumpEventQueue();
    expect(model.statsFailed, isFalse);

    rpc.api.frames.addError(Exception('database is locked'));
    await pumpEventQueue();
    expect(model.statsFailed, isTrue);

    model.applyStatsFrame(frame(4));
    expect(model.statsFailed, isFalse);
    expect(model.stats?.blockCount24h, Int64(4));
  });

  test('an error before the first frame marks the stats failed', () async {
    final model = FireplaceViewModel();
    addTearDown(model.dispose);
    await pumpEventQueue();

    rpc.api.frames.addError(Exception('database is locked'));
    await pumpEventQueue();

    expect(model.statsFailed, isTrue);
    expect(model.stats, isNull);
  });

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

  testWidgets('in v2 the four stats share one strip card in one row', (tester) async {
    await loadBundledFonts();
    SailStyleValues.phoneLayoutOverride = false;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    await tester.pumpSailPage(
      SailTheme(
        data: SailThemeData.lightTheme(
          SailColorScheme.orange,
          false,
          SailFontValues.inter,
          SailThemeStyle.bitwindowV2,
        ),
        child: SizedBox(
          width: 1100,
          child: FireplaceStatsView(
            priceLastUpdated: () => '1 minute ago',
            price: r'$0.000031',
            priceTitle: 'ECX Price',
            stats: GetFireplaceStatsResponse(
              transactionCount24h: Int64(18402),
              coinnewsCount7d: Int64(37),
              blockCount24h: Int64(144),
            ),
            loading: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('FireplaceStrip')), findsOneWidget);
    expect(find.byType(SailCardStats), findsNothing);
    final tops = [
      'ECX Price',
      'New transactions',
      'New coinnews',
      'Number of blocks',
    ].map((title) => tester.getTopLeft(find.text(title))).toList();
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i].dy, tops[0].dy);
      expect(tops[i].dx, greaterThan(tops[i - 1].dx));
    }
    expect(find.text('18402'), findsOneWidget);
  });
}
