import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const firstId = '0008c2a1';
const secondId = '0008c2a2';
const firstLabel = '$firstId · QA Shared Label (pending)';
const secondLabel = '$secondId · QA Shared Label (pending)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerTestDependencies();
    final provider = GetIt.I<NewsProvider>();
    await provider.fetch();
    provider.topics = [
      Topic(topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true),
      Topic(topic: 'a2a2a2a2', name: 'Japan Weekly', confirmed: true),
      Topic(topic: firstId, name: 'QA Shared Label'),
      Topic(topic: secondId, name: 'QA Shared Label'),
    ];
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the Coin News card shows the identifier of the selected topic', (tester) async {
    await loadBundledFonts();
    final model = FeeCoinNewsLargeViewModel();
    await tester.pumpSailPage(
      ViewModelBuilder<FeeCoinNewsLargeViewModel>.reactive(
        viewModelBuilder: () => model,
        builder: (context, model, child) => const FeeCoinNewsLargeView(),
      ),
    );
    await tester.tap(find.text('US Weekly'));
    await tester.pumpAndSettle();

    expect(find.text(firstLabel), findsOneWidget);
    expect(find.text(secondLabel), findsOneWidget);
    await tester.tap(find.text(secondLabel));
    await tester.pumpAndSettle();

    expect(model.leftTopic, secondId);
    expect(find.text(secondLabel), findsOneWidget);
    expect(find.text('Japan Weekly'), findsOneWidget);
  });

  testWidgets('the topic filter lets the user clear one of two topics with the same name', (tester) async {
    await loadBundledFonts();
    final model = CoinNewsViewModel();
    await model.setSelectedTopics([firstId, secondId]);
    await tester.pumpSailPage(
      ViewModelBuilder<CoinNewsViewModel>.reactive(
        viewModelBuilder: () => model,
        builder: (context, model, child) => const CoinNewsView(),
      ),
    );
    await tester.tap(find.text('2 topics'));
    await tester.pumpAndSettle();

    expect(find.text(firstLabel), findsOneWidget);
    expect(find.text(secondLabel), findsOneWidget);
    expect(find.text('US Weekly'), findsOneWidget);
    await tester.tap(find.text(firstLabel));
    await tester.pumpAndSettle();

    expect(model.selectedTopicIds, [secondId]);
    expect(find.text('1 topic'), findsOneWidget);
  });
}
