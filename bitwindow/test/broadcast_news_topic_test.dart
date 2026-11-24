import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the dialog keeps its topic when a read gives new topic values', (tester) async {
    await loadBundledFonts();
    final provider = GetIt.I.get<NewsProvider>();
    await tester.runAsync(provider.fetch);
    provider.topics = [
      Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true),
      Topic(id: Int64(9), topic: 'c0ffee01', name: 'QA Topic', confirmed: false),
    ];
    await tester.runAsync(() => GetIt.I.get<ClientSettings>().setValue(LastUsedTopicSetting(newValue: 'c0ffee01')));

    await tester.pumpSailPage(const SizedBox(width: 700, height: 700, child: BroadcastNewsView()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();
    expect(find.text('QA Topic (pending)'), findsOneWidget);

    provider.topics = [
      Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true),
      Topic(id: Int64(4), topic: 'c0ffee01', name: 'QA Topic', confirmed: true),
    ];
    provider.notifyListeners();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('QA Topic'), findsOneWidget);
    expect(find.text('Select a topic'), findsNothing);
  });
}
