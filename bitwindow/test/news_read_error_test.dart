import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _MiscAPI extends MockMiscAPI {
  bool fail = true;

  @override
  Future<List<CoinNews>> listCoinNews() async {
    if (fail) {
      throw Exception('connection refused');
    }
    return [CoinNews(topic: 'a1a1a1a1', headline: 'Story after the restart')];
  }
}

class _API extends MockAPI {
  _API() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _MiscAPI fakeMisc = _MiscAPI();

  @override
  _MiscAPI get misc => fakeMisc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _API rpc;

  setUp(() async {
    await GetIt.I.reset();
    rpc = _API();
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  test('a failed first read ends the loading state with the reason', () async {
    final provider = NewsProvider();
    addTearDown(provider.dispose);
    await provider.fetch();

    expect(provider.loading, isFalse);
    expect(provider.readError, contains('connection refused'));
  });

  test('the next good read clears the reason', () async {
    final provider = NewsProvider();
    addTearDown(provider.dispose);
    await provider.fetch();

    var notified = 0;
    provider.addListener(() => notified++);
    rpc.misc.fail = false;
    await provider.fetch();

    expect(provider.readError, isNull);
    expect(provider.news.map((n) => n.headline), ['Story after the restart']);
    expect(notified, greaterThan(0));

    notified = 0;
    rpc.misc.fail = true;
    await provider.fetch();
    rpc.misc.fail = false;
    await provider.fetch();
    expect(provider.readError, isNull);
    expect(notified, 2);
  });

  testWidgets('the Coin News cards show the reason, not sample stories', (tester) async {
    await loadBundledFonts();
    await GetIt.I.unregister<NewsProvider>();
    final provider = NewsProvider();
    GetIt.I.registerSingleton<NewsProvider>(provider);
    await tester.runAsync(provider.fetch);

    await tester.pumpSailPage(
      SizedBox(
        width: 1400,
        child: ViewModelBuilder<FeeCoinNewsLargeViewModel>.reactive(
          viewModelBuilder: () => FeeCoinNewsLargeViewModel(),
          builder: (context, model, child) => const FeeCoinNewsLargeView(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not read the news.'), findsNWidgets(2));
    expect(find.text('Bitcoin price hits new all-time high'), findsNothing);
  });

  testWidgets('the Hacker Coin News card shows the reason, not Loading', (tester) async {
    await loadBundledFonts();
    await GetIt.I.unregister<NewsProvider>();
    final provider = NewsProvider();
    GetIt.I.registerSingleton<NewsProvider>(provider);
    await tester.runAsync(provider.fetch);

    await tester.pumpSailPage(
      SizedBox(
        width: 1400,
        child: ViewModelBuilder<CoinNewsLargeViewModel>.reactive(
          viewModelBuilder: () => CoinNewsLargeViewModel(),
          builder: (context, model, child) => const CoinNewsLargeView(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not read the news.'), findsNWidgets(2));
    expect(find.text('Loading…'), findsNothing);
  });
}
