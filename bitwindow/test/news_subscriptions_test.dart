import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

const overflowDays = '999999999999999999999999';
const topicId = 'ba042001';

class RecordingMisc extends MockMiscAPI {
  final sent = <(String, int)>[];
  bool failTopics = false;
  bool failNews = false;

  @override
  Future<List<Topic>> listTopics() async {
    if (failTopics) {
      throw StateError('Topics unavailable');
    }
    return [Topic(topic: 'a1a1a1a1', name: 'Saved Topic', confirmed: true)];
  }

  @override
  Future<List<CoinNews>> listCoinNews() async {
    if (failNews) {
      throw StateError('News unavailable');
    }
    return [];
  }

  @override
  Future<CreateTopicResponse> createTopic(String topic, String name, {int retentionDays = 7}) async {
    sent.add((topic, retentionDays));
    return CreateTopicResponse(txid: 'ab' * 32);
  }
}

class TopicAPI extends MockAPI {
  final _misc = RecordingMisc();

  @override
  RecordingMisc get misc => _misc;

  TopicAPI() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);
}

Finder button(String label) =>
    find.byWidgetPredicate((widget) => widget is SailButton && widget.label == label).hitTestable();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GetIt.I.reset());

  Future<RecordingMisc> open(WidgetTester tester) async {
    final api = TopicAPI();
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    await tester.pumpSailPage(const SizedBox(width: 700, child: ManageNewsSubscriptionsView()));
    await tester.pumpAndSettle();
    return api.misc;
  }

  testWidgets('Your Topics shows a failed topic read and keeps the last list', (tester) async {
    final api = await open(tester);
    final provider = GetIt.I<NewsProvider>();
    expect(find.text('Saved Topic'), findsOneWidget);
    api.failTopics = true;
    await provider.fetch();
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read the topics'), findsOneWidget);
    expect(find.text('Saved Topic'), findsOneWidget);

    api.failTopics = false;
    api.failNews = true;
    await provider.fetch();
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read the topics'), findsNothing);
    expect(find.text('Saved Topic'), findsOneWidget);
  });

  testWidgets('Create Topic rejects invalid retention text', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('Create Topic'));
    await tester.pumpAndSettle();
    final fields = find.byType(EditableText).hitTestable();
    await tester.enterText(fields.at(0), 'Test Topic');
    await tester.enterText(fields.at(1), topicId);
    await tester.enterText(fields.at(2), 'seven');
    await tester.pump();
    await tester.tap(button('Create Topic'));
    await tester.pumpAndSettle();

    expect(api.sent, isEmpty);
    expect(find.textContaining('Retention days must be between 0 and 255'), findsOneWidget);
  });

  testWidgets('Subscribe rejects a retention value too large to parse', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).hitTestable(), '$overflowDays{$topicId}Test Topic');
    await tester.pump();
    await tester.tap(button('Add'));
    await tester.pumpAndSettle();

    expect(api.sent, isEmpty);
    expect(find.textContaining('Invalid URL format'), findsOneWidget);
  });

  testWidgets('Import rejects invalid retention and keeps the valid topic', (tester) async {
    final api = await open(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '$overflowDays{$topicId}Invalid Topic\n0{ba042002}Valid Topic'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(button('Import'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(api.sent, [('ba042002', 0)]);
  });
}
