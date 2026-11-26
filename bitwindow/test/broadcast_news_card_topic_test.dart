import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _NewsAPI extends MockAPI {
  _NewsAPI() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _BroadcastAPI _misc = _BroadcastAPI();

  @override
  _BroadcastAPI get misc => _misc;
}

class _BroadcastAPI extends MockMiscAPI {
  final topics = <String>[];

  @override
  Future<BroadcastNewsResponse> broadcastNews(
    String topic,
    String headline,
    String content, {
    String? url,
    String? lang,
    int? subtype,
    bool? nsfw,
    int? feeSatPerVbyte,
    int? feeSats,
  }) async {
    topics.add(topic);
    return BroadcastNewsResponse();
  }
}

final _topics = [
  Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true),
  Topic(id: Int64(2), topic: 'a2a2a2a2', name: 'Japan Weekly', confirmed: true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NewsAPI api;

  setUp(() async {
    await GetIt.I.reset();
    api = _NewsAPI();
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    await registerTestDependencies();
    GetIt.I.registerLazySingleton<NotificationProvider>(() => NotificationProvider());
  });

  tearDown(() => GetIt.I.reset());

  Future<void> loadTopics(WidgetTester tester, {required String lastUsed}) async {
    await loadBundledFonts();
    final provider = GetIt.I.get<NewsProvider>();
    await tester.runAsync(provider.fetch);
    provider.topics = _topics;
    provider.initialized = true;
    await tester.runAsync(() => GetIt.I.get<ClientSettings>().setValue(LastUsedTopicSetting(newValue: lastUsed)));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> broadcast(WidgetTester tester, String text) async {
    tester.state<EditableTextState>(find.byType(EditableText).first).widget.controller.text = text;
    await tester.pump();
    await tester.runAsync(
      () => tester.widget<SailButton>(find.widgetWithText(SailButton, 'Broadcast').last).onPressed!(),
    );
    await settle(tester);
  }

  Future<String> lastUsed(WidgetTester tester) async {
    final setting = await tester.runAsync(() => GetIt.I.get<ClientSettings>().getValue(LastUsedTopicSetting()));
    return setting!.value;
  }

  testWidgets('the dialog of a card selects the topic of the card, not the last used topic', (tester) async {
    await loadTopics(tester, lastUsed: 'a1a1a1a1');
    await tester.pumpSailPage(
      const SizedBox(width: 700, height: 700, child: BroadcastNewsView(topic: 'a2a2a2a2')),
    );
    await settle(tester);

    expect(find.text('Japan Weekly'), findsOneWidget);
    expect(find.text('US Weekly'), findsNothing);

    await broadcast(tester, 'QA story');
    expect(api.misc.topics, ['a2a2a2a2']);
  });

  testWidgets('a broadcast sets the last used topic, a pick with no broadcast does not', (tester) async {
    await loadTopics(tester, lastUsed: 'a1a1a1a1');
    await tester.pumpSailPage(const SizedBox(width: 700, height: 700, child: BroadcastNewsView()));
    await settle(tester);
    expect(find.text('US Weekly'), findsOneWidget);

    getParentViewModel<BroadcastNewsViewModel>(
      tester.element(find.byType(SailDropdownButton<String>)),
      listen: false,
    ).setTopic('a2a2a2a2');
    await settle(tester);
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    expect(find.text('Japan Weekly'), findsOneWidget);
    expect(await lastUsed(tester), 'a1a1a1a1');

    await broadcast(tester, 'QA story');
    expect(api.misc.topics, ['a2a2a2a2']);
    expect(await lastUsed(tester), 'a2a2a2a2');
  });

  testWidgets('Broadcast News on the right card of the large Coin News opens on that topic', (tester) async {
    await loadTopics(tester, lastUsed: 'a1a1a1a1');
    await tester.pumpSailPage(
      SizedBox(
        width: 1400,
        height: 800,
        child: ViewModelBuilder<FeeCoinNewsLargeViewModel>.reactive(
          viewModelBuilder: () => FeeCoinNewsLargeViewModel(),
          builder: (context, model, child) => const FeeCoinNewsLargeView(),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.widgetWithText(SailButton, 'Broadcast News'));
    await openDialog(tester);

    expect(
      find.descendant(of: find.byType(BroadcastNewsView), matching: find.text('Japan Weekly')),
      findsOneWidget,
    );
  });

  testWidgets('Broadcast on the Coin News card opens on the topic of the card', (tester) async {
    await loadTopics(tester, lastUsed: 'a1a1a1a1');
    late FeeCoinNewsViewModel model;
    await tester.pumpSailPage(
      SizedBox(
        width: 700,
        height: 800,
        child: ViewModelBuilder<FeeCoinNewsViewModel>.reactive(
          viewModelBuilder: () => model = FeeCoinNewsViewModel(),
          builder: (context, model, child) => const FeeCoinNewsView(),
        ),
      ),
    );
    await tester.runAsync(() => model.setTopic('a2a2a2a2'));
    await settle(tester);

    await tester.tap(find.widgetWithText(SailButton, 'Broadcast'));
    await openDialog(tester);

    expect(
      find.descendant(of: find.byType(BroadcastNewsView), matching: find.text('Japan Weekly')),
      findsOneWidget,
    );
  });

  testWidgets('Broadcast on Hacker Coin News with one topic opens on that topic', (tester) async {
    await loadTopics(tester, lastUsed: 'a1a1a1a1');
    late CoinNewsViewModel model;
    await tester.pumpSailPage(
      SizedBox(
        width: 900,
        height: 800,
        child: ViewModelBuilder<CoinNewsViewModel>.reactive(
          viewModelBuilder: () => model = CoinNewsViewModel(),
          builder: (context, model, child) => const CoinNewsView(),
        ),
      ),
    );
    await tester.runAsync(() => model.setSelectedTopics(['a2a2a2a2']));
    await settle(tester);
    expect(model.broadcastTopic, 'a2a2a2a2');

    await tester.tap(find.widgetWithText(SailButton, 'Broadcast'));
    await openDialog(tester);

    expect(
      find.descendant(of: find.byType(BroadcastNewsView), matching: find.text('Japan Weekly')),
      findsOneWidget,
    );

    await tester.runAsync(() => model.setSelectedTopics(['a1a1a1a1', 'a2a2a2a2']));
    expect(model.broadcastTopic, isNull);
  });
}
