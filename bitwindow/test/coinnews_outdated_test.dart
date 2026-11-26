import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GetIt.I.reset());

  final time = DateTime.utc(2026, 11, 16, 16, 32);
  final topics = [Topic(topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true, retentionDays: 30)];

  CoinNews story({
    String headline = 'Headline',
    int subtype = 0,
    bool nsfw = false,
    String url = '',
    String content = '',
  }) => CoinNews(
    headline: headline,
    topic: 'a1a1a1a1',
    subtype: subtype,
    nsfw: nsfw,
    url: url,
    content: content,
    createTime: Timestamp.fromDateTime(time),
  );

  group('outdated stories', () {
    final current = story(headline: 'Current story');
    final outdated = story(headline: 'Outdated story')..outdated = true;

    Future<NewsProvider> seed() async {
      await registerTestDependencies();
      final provider = GetIt.I.get<NewsProvider>();
      await provider.fetch();
      provider.topics = topics;
      provider.news = [outdated, current];
      provider.initialized = true;
      return provider;
    }

    test('the news cards without a switch show only current stories', () async {
      final provider = await seed();
      final fee = FeeCoinNewsLargeViewModel();
      addTearDown(fee.dispose);
      final table = CoinNewsViewModel();
      addTearDown(table.dispose);
      await table.setSelectedTopics(['a1a1a1a1']);

      expect(provider.currentNews, [current]);
      expect(fee.leftEntries, [current]);
      expect(table.entries, [current]);
    });

    testWidgets('Show Outdated shows the stories that the server marks as outdated', (tester) async {
      await loadBundledFonts();
      await tester.pumpSailPage(
        ViewModelBuilder<CoinNewsLargeViewModel>.reactive(
          viewModelBuilder: () => CoinNewsLargeViewModel(),
          builder: (context, model, child) => const SizedBox(width: 1400, child: CoinNewsLargeView()),
        ),
      );
      final provider = GetIt.I.get<NewsProvider>();
      await tester.runAsync(provider.fetch);
      provider.topics = topics;
      provider.news = [outdated, current];
      provider.initialized = true;
      provider.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('Current story'), findsWidgets);
      expect(find.text('Outdated story'), findsNothing);

      await tester.tap(find.text('Show Outdated').first);
      await tester.pumpAndSettle();

      expect(find.text('Outdated story'), findsWidgets);
      expect(find.text('Hide Outdated'), findsWidgets);
    });
  });
}
