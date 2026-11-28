import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

final _topics = [
  Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true),
  Topic(id: Int64(2), topic: 'a2a2a2a2', name: 'Japan Weekly', confirmed: true),
];

CoinNews _story(String topic, String headline, int fee) => CoinNews(
  topic: topic,
  headline: headline,
  feeSats: Int64(fee),
  createTime: Timestamp.fromDateTime(DateTime.now()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final v2 = SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);
  final v2Dark = SailThemeData.darkTheme(
    SailColorScheme.orange,
    false,
    SailFontValues.inter,
    SailThemeStyle.bitwindowV2,
  );

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<BitwindowRPC>(MockAPI(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD));
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  Future<void> pumpCard(WidgetTester tester, {bool dark = false}) async {
    await loadBundledFonts();
    final provider = GetIt.I.get<NewsProvider>();
    await tester.runAsync(provider.fetch);
    provider.topics = _topics;
    provider.news = [
      _story('a1a1a1a1', 'Drivechain upgrade successfully completed', 412),
      _story('a1a1a1a1', 'Bitcoin price hits new all-time high', 96),
      _story('a2a2a2a2', 'New DeFi protocol launches with 100M TVL', 150),
    ];
    provider.initialized = true;
    await tester.pumpSailPage(
      SailTheme(
        data: dark ? v2Dark : v2,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 1400,
            child: ViewModelBuilder<FeeCoinNewsLargeViewModel>.reactive(
              viewModelBuilder: () => FeeCoinNewsLargeViewModel(),
              builder: (context, model, child) => const FeeCoinNewsLargeView(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('each topic has its own card, with Broadcast News as the one primary button', (tester) async {
    await pumpCard(tester);

    final cards = find.byType(SailCard);
    expect(cards, findsNWidgets(2));
    expect(tester.getRect(cards.last).left, greaterThan(tester.getRect(cards.first).right));
    for (final card in [cards.first, cards.last]) {
      expect(find.descendant(of: card, matching: find.byType(SailDropdownButton<String>)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(SailTable)), findsOneWidget);
    }
    final primaries = tester
        .widgetList<SailButton>(find.byType(SailButton))
        .where((button) => button.variant == ButtonVariant.primary)
        .map((button) => button.label);
    expect(primaries, ['Broadcast News']);
    expect(find.text('Manage Topics'), findsNothing);
    expect(find.text('Graffiti Explorer'), findsNothing);
  });

  testWidgets('the left head has the title, then its topic at the right', (tester) async {
    await pumpCard(tester);

    final left = find.byType(SailCard).first;
    final title = tester.getRect(find.descendant(of: left, matching: find.text('Coin News')));
    final topic = tester.getRect(find.descendant(of: left, matching: find.byType(SailDropdownButton<String>)));
    expect(topic.left, greaterThan(title.right));
    expect(topic.right, closeTo(tester.getRect(left).right - 17, 1));
    expect(find.descendant(of: left, matching: find.byType(SailButton)), findsNothing);
  });

  testWidgets('the right head has its topic at the left, then Broadcast News and "…" at the right', (tester) async {
    await pumpCard(tester);

    final right = find.byType(SailCard).last;
    final card = tester.getRect(right);
    final topic = tester.getRect(find.descendant(of: right, matching: find.byType(SailDropdownButton<String>)));
    final broadcast = tester.getRect(find.widgetWithText(SailButton, 'Broadcast News'));
    final menu = tester.getRect(
      find.descendant(
        of: right,
        matching: find.byWidgetPredicate((widget) => widget is SailRowMenuButton && widget.filled),
      ),
    );
    expect(topic.left, closeTo(card.left + 17, 1));
    expect(broadcast.left, greaterThan(topic.right));
    expect(menu.left, greaterThan(broadcast.right));
    expect(menu.right, closeTo(card.right - 17, 1));
    expect(find.descendant(of: right, matching: find.text('Coin News')), findsNothing);
  });

  testWidgets('each row "…" shows inside its card', (tester) async {
    await pumpCard(tester);

    for (final card in [find.byType(SailCard).first, find.byType(SailCard).last]) {
      final rowMenus = find.descendant(
        of: card,
        matching: find.byWidgetPredicate((widget) => widget is SailRowMenuButton && !widget.filled),
      );
      expect(rowMenus, findsWidgets);
      for (final menu in tester.widgetList(rowMenus)) {
        expect(tester.getRect(find.byWidget(menu)).right, lessThanOrEqualTo(tester.getRect(card).right));
      }
    }
  });

  testWidgets('the head "…" holds Manage Topics and Graffiti Explorer', (tester) async {
    await pumpCard(tester);

    final headMenu = find.byWidgetPredicate((widget) => widget is SailRowMenuButton && widget.filled);
    expect(headMenu, findsOneWidget);
    expect(find.descendant(of: find.byType(SailCard).last, matching: headMenu), findsOneWidget);

    await tester.tap(headMenu);
    await tester.pumpAndSettle();

    expect(find.text('Manage Topics'), findsOneWidget);
    expect(find.text('Graffiti Explorer'), findsOneWidget);
  });

  testWidgets('the two cards have the same height when the topics hold different story counts', (tester) async {
    await pumpCard(tester);

    expect(find.text('Bitcoin price hits new all-time high'), findsOneWidget, reason: 'the left topic has two stories');
    expect(find.text('New DeFi protocol launches with 100M TVL'), findsOneWidget, reason: 'the right topic has one');
    final left = tester.getRect(find.byType(SailCard).first);
    final right = tester.getRect(find.byType(SailCard).last);
    expect(left.top, right.top);
    expect(left.height, right.height);
  });

  for (final dark in [false, true]) {
    testWidgets('the two cards lay out in the ${dark ? 'dark' : 'light'} theme', (tester) async {
      await pumpCard(tester, dark: dark);

      expect(tester.takeException(), isNull);
      expect(find.byType(SailCard), findsNWidgets(2));
      final theme = SailTheme.of(tester.element(find.byType(SailCard).first));
      expect(theme.isLightMode(), !dark);
      final title = tester.widget<Text>(find.text('Coin News'));
      expect(title.style?.color, theme.colors.text);
    });
  }
}
