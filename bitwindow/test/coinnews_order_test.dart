import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GetIt.I.reset());

  final time = DateTime.utc(2026, 11, 27, 17, 12);
  final topics = [
    Topic(topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true, retentionDays: 30),
    Topic(topic: 'a2a2a2a2', name: 'Japan Weekly', confirmed: true, retentionDays: 30),
    Topic(topic: 'f0f0f0f0', name: 'Alpha News', confirmed: true, retentionDays: 30),
  ];

  String words(int count, String separator) => List.generate(count, (i) => 'word$i').join(separator);

  CoinNews story(String headline, {String topic = 'a1a1a1a1', String content = '', int fee = 3000}) => CoinNews(
    headline: headline,
    topic: topic,
    content: content,
    feeSats: Int64(fee),
    createTime: Timestamp.fromDateTime(time),
  );

  Future<NewsProvider> seed(List<CoinNews> news) async {
    await registerTestDependencies();
    final provider = GetIt.I.get<NewsProvider>();
    await provider.fetch();
    provider.topics = topics;
    provider.news = news;
    provider.initialized = true;
    return provider;
  }

  Future<CoinNewsViewModel> table() async {
    final model = CoinNewsViewModel();
    addTearDown(model.dispose);
    await model.setSelectedTopics(topics.map((t) => t.topic).toList());
    model.pageSize = 20;
    return model;
  }

  List<String> headlines(List<CoinNews> news) => news.map((n) => n.headline).toList();

  test('the table sorts the topic column by the topic name', () async {
    await seed([
      story('US story'),
      story('Japan story', topic: 'a2a2a2a2'),
      story('Alpha story', topic: 'f0f0f0f0'),
    ]);
    final model = await table();

    model.sortEntries('topic');

    expect(headlines(model.entries), ['Alpha story', 'Japan story', 'US story']);
  });

  test('the table sorts the read time column by minutes', () async {
    await seed([
      story('Two minutes', content: words(300, ' ')),
      story('Eleven minutes', content: words(2100, ' ')),
      story('Five minutes', content: words(900, ' ')),
    ]);
    final model = await table();

    model.sortEntries('readtime');
    expect(headlines(model.entries), ['Two minutes', 'Five minutes', 'Eleven minutes']);

    model.sortEntries('readtime');
    expect(headlines(model.entries), ['Eleven minutes', 'Five minutes', 'Two minutes']);
  });

  test('the table keeps the server rank between stories of one date', () async {
    final ranked = [for (var i = 0; i < 40; i++) story('Story $i', fee: 4000 - i)];
    await seed(ranked);
    final model = await table();

    expect(headlines(model.entries), headlines(ranked));
  });

  testWidgets('the table header shows the sorted column and its direction', (tester) async {
    await tester.pumpSailPage(
      CoinNewsTable(
        entries: [story('Story')],
        onSort: (_) {},
        sortColumn: 'readtime',
        sortAscending: true,
        loading: false,
      ),
    );
    await tester.pumpAndSettle();

    final sorted = tester.widgetList<SailTableHeaderCell>(find.byType(SailTableHeaderCell)).where((h) => h.isSorted);
    expect(sorted.map((h) => (h.name, h.isAscending)), [('Read time', true)]);
  });

  testWidgets('a header tap keeps the arrow of the view model after the rebuild', (tester) async {
    await seed([story('US story'), story('Japan story', topic: 'a2a2a2a2')]);
    final model = await table();
    await tester.pumpSailPage(
      ListenableBuilder(
        listenable: model,
        builder: (context, _) => CoinNewsTable(
          entries: model.paginatedEntries,
          onSort: model.sortEntries,
          sortColumn: model.sortColumn,
          sortAscending: model.sortAscending,
          loading: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();

    final sorted = tester.widgetList<SailTableHeaderCell>(find.byType(SailTableHeaderCell)).where((h) => h.isSorted);
    expect(sorted.map((h) => (h.name, h.isAscending)), [('Date', false)]);
  });
}
