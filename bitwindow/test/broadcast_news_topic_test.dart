import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
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
  final fees = <int?>[];

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
    fees.add(feeSats);
    throw StateError('Test broadcast stopped');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NewsAPI api;

  setUp(() async {
    await GetIt.I.reset();
    api = _NewsAPI();
    GetIt.I.registerSingleton<BitwindowRPC>(api);
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

  testWidgets('a nonpositive or malformed fee stops the broadcast', (tester) async {
    await loadBundledFonts();
    final provider = GetIt.I.get<NewsProvider>();
    await tester.runAsync(provider.fetch);
    provider.topics = [Topic(topic: 'a1a1a1a1', name: 'QA Topic', confirmed: true)];
    await tester.runAsync(() => GetIt.I.get<ClientSettings>().setValue(LastUsedTopicSetting(newValue: 'a1a1a1a1')));

    const viewport = ValueKey('broadcast viewport');
    await tester.pumpSailPage(const SizedBox(key: viewport, width: 700, height: 350, child: BroadcastNewsView()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final message = find.byType(EditableText).first;
    final fee = find.byType(EditableText).last;
    final broadcast = find.widgetWithText(SailButton, 'Broadcast');
    tester.state<EditableTextState>(message).widget.controller.text = 'QA headline';
    await tester.pump();
    for (final invalid in ['abc', '0', '0.000000001', '-0.00002000']) {
      tester.state<EditableTextState>(fee).widget.controller.text = invalid;
      await tester.pump();
      await tester.ensureVisible(broadcast);
      await tester.pump();
      await tester.widget<SailButton>(broadcast).onPressed!();
      await tester.pump();
      final error = find.text('Enter a fee greater than zero.');
      expect(error, findsOneWidget);
      expect(tester.getBottomLeft(error).dy, lessThanOrEqualTo(tester.getBottomLeft(find.byKey(viewport)).dy));
      expect(api.misc.fees, isEmpty);
    }

    for (final (input, expected) in [('0.00002001', 2001), ('', null)]) {
      tester.state<EditableTextState>(fee).widget.controller.text = input;
      await tester.pump();
      await tester.ensureVisible(broadcast);
      await tester.pump();
      await tester.widget<SailButton>(broadcast).onPressed!();
      await tester.pump();
      expect(api.misc.fees.last, expected);
    }
    expect(api.misc.fees, [2001, null]);
  });
}
