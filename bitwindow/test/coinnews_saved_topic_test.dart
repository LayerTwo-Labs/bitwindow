import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const otherNetworkTopic = 'b9b9b9b9';

CoinNews _story(String topic, String headline) => CoinNews(
  topic: topic,
  headline: headline,
  feeSats: Int64(3000),
  createTime: Timestamp.fromDateTime(DateTime.now()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NewsProvider provider;

  setUp(() async {
    await registerTestDependencies();
    provider = GetIt.I<NewsProvider>();
    await provider.fetch();
    provider.topics = [
      Topic(topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true),
      Topic(topic: 'a2a2a2a2', name: 'Japan Weekly', confirmed: true),
    ];
    provider.news = [_story('a1a1a1a1', 'US story'), _story('a2a2a2a2', 'Japan story')];
    provider.initialized = true;
  });

  tearDown(() => GetIt.I.reset());

  group('topicOnChain', () {
    test('keeps a saved topic of this chain', () {
      expect(provider.topicOnChain('a2a2a2a2'), 'a2a2a2a2');
    });

    test('gives the fallback topic for a topic of another network', () {
      expect(provider.topicOnChain(otherNetworkTopic), 'a1a1a1a1');
      expect(provider.topicOnChain(otherNetworkTopic, fallback: 1), 'a2a2a2a2');
      expect(provider.topicOnChain(null, fallback: 1), 'a2a2a2a2');
    });

    test('gives the first topic when the fallback is out of range', () {
      expect(provider.topicOnChain(otherNetworkTopic, fallback: 5), 'a1a1a1a1');
    });

    test('keeps the saved topic when no topic list exists', () {
      provider.topics = [];
      expect(provider.topicOnChain(otherNetworkTopic), otherNetworkTopic);
    });
  });

  group('topicsOnChain', () {
    test('drops the topics of another network', () {
      expect(provider.topicsOnChain(['a2a2a2a2', otherNetworkTopic]), ['a2a2a2a2']);
    });

    test('gives each topic when no saved topic is on this chain', () {
      expect(provider.topicsOnChain([otherNetworkTopic]), ['a1a1a1a1', 'a2a2a2a2']);
      expect(provider.topicsOnChain(null), ['a1a1a1a1', 'a2a2a2a2']);
    });

    test('keeps an empty choice', () {
      expect(provider.topicsOnChain([]), isEmpty);
    });

    test('keeps the saved topics when no topic list exists', () {
      provider.topics = [];
      expect(provider.topicsOnChain([otherNetworkTopic]), [otherNetworkTopic]);
      expect(provider.topicsOnChain(null), isEmpty);
    });
  });

  testWidgets('the Coin News card shows the stories of this chain for a topic of another network', (tester) async {
    await loadBundledFonts();
    final model = FeeCoinNewsLargeViewModel();
    await model.setLeftTopic(otherNetworkTopic);
    await model.setRightTopic('c8c8c8c8');
    await tester.pumpSailPage(
      ViewModelBuilder<FeeCoinNewsLargeViewModel>.reactive(
        viewModelBuilder: () => model,
        builder: (context, model, child) => const FeeCoinNewsLargeView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(model.leftTopic, 'a1a1a1a1');
    expect(model.rightTopic, 'a2a2a2a2');
    expect(find.text('US story'), findsOneWidget);
    expect(find.text('Japan story'), findsOneWidget);
    expect(find.text('No news articles yet'), findsNothing);
  });

  testWidgets('the Hacker Coin News card shows the stories of this chain for a topic of another network', (
    tester,
  ) async {
    await loadBundledFonts();
    await GetIt.I<ClientSettings>().mergeValue(
      SelectedTopicsSetting(),
      (config) => config.copyWith(leftTopic: otherNetworkTopic, rightTopic: 'c8c8c8c8'),
    );
    final model = CoinNewsLargeViewModel();
    await tester.pumpSailPage(
      ViewModelBuilder<CoinNewsLargeViewModel>.reactive(
        viewModelBuilder: () => model,
        builder: (context, model, child) => const CoinNewsLargeView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(model.leftTopic, 'a1a1a1a1');
    expect(model.rightTopic, 'a2a2a2a2');
    expect(find.text('US story'), findsOneWidget);
    expect(find.text('Japan story'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('a topic choice of another network keeps its saved value', (tester) async {
    final model = CoinNewsLargeViewModel();
    await tester.runAsync(() => model.setLeftTopic(otherNetworkTopic));

    expect(model.leftTopic, 'a1a1a1a1');
    final saved = await GetIt.I<ClientSettings>().getValue(SelectedTopicsSetting());
    expect(saved.value.leftTopic, otherNetworkTopic);

    provider.topics = [...provider.topics, Topic(topic: otherNetworkTopic, name: 'Signet Weekly', confirmed: true)];
    expect(model.leftTopic, otherNetworkTopic);
  });

  testWidgets('the topic filter counts and shows only the topics of this chain', (tester) async {
    await loadBundledFonts();
    final model = CoinNewsViewModel();
    await model.setSelectedTopics([otherNetworkTopic, 'c8c8c8c8']);
    await tester.pumpSailPage(
      ViewModelBuilder<CoinNewsViewModel>.reactive(
        viewModelBuilder: () => model,
        builder: (context, model, child) => const CoinNewsView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(model.selectedTopicIds, ['a1a1a1a1', 'a2a2a2a2']);
    expect(find.text('2 topics'), findsOneWidget);
    expect(find.text('US story'), findsOneWidget);
    expect(find.text('Japan story'), findsOneWidget);

    await model.setSelectedTopics(['a2a2a2a2', otherNetworkTopic]);
    await tester.pumpAndSettle();
    expect(find.text('1 topic'), findsOneWidget);
    expect(find.text('US story'), findsNothing);
    expect(find.text('Japan story'), findsOneWidget);
  });
}
