import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:flutter/gestures.dart';
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
  final priced = <(String, int)>[];
  bool failTopics = false;
  bool failNews = false;

  @override
  Future<NewsFeeEstimate> estimateNewsFee(
    NewsAction action, {
    String body = '',
    String headline = '',
    String url = '',
    int subtype = 0,
    bool nsfw = false,
    String topicName = '',
    int retentionDays = 0,
  }) async {
    expect(action, NewsAction.NEWS_ACTION_TOPIC);
    priced.add((topicName, retentionDays));
    if (topicName == 'No Fee Topic') {
      throw BitwindowException('insufficient funds');
    }
    final vsize = 140 + topicName.length;
    return NewsFeeEstimate(vsize: vsize, feeSatPerVbyte: 21, feeSats: 21 * vsize);
  }

  final chain = [
    Topic(topic: 'a1a1a1a1', name: 'Saved Topic', confirmed: true),
    Topic(topic: 'a3a3a3a3', name: 'Waiting Topic'),
    Topic(topic: 'c3c3c3c3', name: 'Other Topic', confirmed: true),
  ];
  final subscribed = {'a1a1a1a1', 'a3a3a3a3'};
  final subscriptions = <(String, bool)>[];
  bool failSubscribe = false;

  @override
  Future<List<Topic>> listTopics() async {
    if (failTopics) {
      throw StateError('Topics unavailable');
    }
    return [
      for (final topic in chain)
        if (subscribed.contains(topic.topic)) topic.deepCopy()..subscribed = true,
    ];
  }

  @override
  Future<List<Topic>> listChainTopics() async {
    if (failTopics) {
      throw StateError('Topics unavailable');
    }
    return [for (final topic in chain) topic.deepCopy()..subscribed = subscribed.contains(topic.topic)];
  }

  @override
  Future<void> setTopicSubscribed(String topic, bool subscribed) async {
    if (failSubscribe) {
      throw BitwindowException('could not leave topic $topic: database is locked');
    }
    subscriptions.add((topic, subscribed));
    subscribed ? this.subscribed.add(topic) : this.subscribed.remove(topic);
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
    if (name == 'Refused Topic' || name == 'Japan Weekly') {
      throw StateError('title cannot be longer than 64 bytes');
    }
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

/// Pumps until a dialog shows. The button that opened it spins until it closes.
Future<void> openDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Pumps past the toast of a finished action.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

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

  testWidgets('Your Topics shows Pending in the readable orange of the theme', (tester) async {
    await open(tester);

    final pending = tester.widget<SailTableCell>(
      find.byWidgetPredicate((widget) => widget is SailTableCell && widget.value == 'Pending'),
    );
    final colors = SailTheme.of(tester.element(find.text('Pending'))).colors;
    expect(pending.textColor, colors.orange);
    expect(pending.textColor, isNot(colors.orangeLight));
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
    await settle(tester);

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
    await openDialog(tester);
    await tester.tap(button('Create 1 topic'));
    await settle(tester);

    expect(api.sent, [('ba042002', 0)]);
  });

  testWidgets('Import shows why a topic failed', (tester) async {
    final api = await open(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '7{ba042003}Refused Topic\n0{ba042002}Valid Topic'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(button('Import'));
    await openDialog(tester);
    await tester.tap(button('Create 2 topics'));
    await settle(tester);

    expect(api.sent, [('ba042002', 0)]);
    expect(
      find.textContaining(
        'Failed to import 1 topic(s): Refused Topic: Bad state: title cannot be longer than 64 bytes',
      ),
      findsOneWidget,
    );
  });

  Future<void> typeUrl(WidgetTester tester, String url) async {
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).hitTestable(), url);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('Subscribe to a topic in Your Topics sends nothing and says so', (tester) async {
    final api = await open(tester);
    await typeUrl(tester, '7{A1A1A1A1}Other Name');

    expect(find.text('Saved Topic (a1a1a1a1) is already in Your Topics. It costs nothing.'), findsOneWidget);
    expect(tester.widget<SailButton>(button('Add')).onPressed, isNull);
    expect(api.priced, isEmpty);
    expect(find.textContaining('already exists'), findsNothing);
  });

  testWidgets('Subscribe to a topic that is not on the chain shows the fee before Add', (tester) async {
    final api = await open(tester);
    await typeUrl(tester, '3{$topicId}QA Daily');

    expect(api.priced, [('QA Daily', 3)]);
    expect(api.sent, isEmpty);
    expect(
      find.text(
        'No topic $topicId is on the chain. Add creates it.  Network fee: ≈ 0.0000,3108 BTC  ·  148 vB at 21.0 sat/vB',
      ),
      findsOneWidget,
    );

    await tester.tap(button('Add'));
    await settle(tester);
    expect(api.sent, [(topicId, 3)]);
  });

  testWidgets('Subscribe uses the Create Topic rules for the name', (tester) async {
    final api = await open(tester);
    await typeUrl(tester, '7{$topicId}A name of more than twenty characters');
    await tester.tap(button('Add'));
    await settle(tester);

    expect(api.sent, isEmpty);
    expect(api.priced, isEmpty);
    expect(find.textContaining('Name must be 20 characters or less'), findsOneWidget);
  });

  testWidgets('Create Topic shows the fee of the topic under the button', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('Create Topic'));
    await tester.pumpAndSettle();
    final fields = find.byType(EditableText).hitTestable();
    await tester.enterText(fields.at(0), 'Nyheter æøå');
    await tester.enterText(fields.at(1), topicId);
    await tester.enterText(fields.at(2), '0');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(api.priced.last, ('Nyheter æøå', 0));
    expect(find.text('Network fee: ≈ 0.0000,3171 BTC  ·  151 vB at 21.0 sat/vB'), findsOneWidget);
    expect(api.sent, isEmpty);
  });

  testWidgets('Import lists the new topics with their fees and sends nothing on Cancel', (tester) async {
    final api = await open(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '5{e5e5e5e5}QA Imported\n7{a1a1a1a1}Saved Topic'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(button('Import'));
    await openDialog(tester);

    expect(find.text('Create 1 topic?'), findsOneWidget);
    expect(find.text('QA Imported (e5e5e5e5), 5 days  ·  ≈ 0.0000,3171 BTC'), findsOneWidget);
    expect(find.text('Network fee: ≈ 0.0000,3171 BTC. 1 topic is already in Your Topics.'), findsOneWidget);

    await tester.tap(button('Cancel'));
    await settle(tester);
    expect(api.sent, isEmpty);
    expect(find.textContaining('Imported'), findsNothing);
  });

  testWidgets('Restore Defaults asks first and shows a failed create', (tester) async {
    final api = await open(tester);
    await tester.tap(button('Restore Defaults'));
    await openDialog(tester);

    expect(find.textContaining('Japan Weekly (a2a2a2a2), 7 days'), findsOneWidget);
    await tester.tap(button('Create 1 topic'));
    await settle(tester);

    expect(api.sent, isEmpty);
    expect(
      find.text('Failed to restore 1 default topic(s): Japan Weekly: Bad state: title cannot be longer than 64 bytes'),
      findsOneWidget,
    );
  });

  testWidgets('Import shows an unknown total when a topic has no fee', (tester) async {
    await open(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '5{e5e5e5e5}QA Imported\n5{e6e6e6e6}No Fee Topic'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(button('Import'));
    await openDialog(tester);

    expect(find.text('No Fee Topic (e6e6e6e6): Insufficient funds'), findsOneWidget);
    expect(find.text('Network fee: unknown.'), findsOneWidget);
    await tester.tap(button('Cancel'));
    await settle(tester);
  });
  testWidgets('Your Topics lists only subscribed topics and Leave removes one', (tester) async {
    final api = await open(tester);
    expect(find.text('Saved Topic'), findsOneWidget);
    expect(find.text('Other Topic'), findsNothing);

    await tester.tap(button('Leave').first);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(api.subscriptions, [('a1a1a1a1', false)]);
    expect(api.sent, isEmpty);
    expect(find.text('Saved Topic'), findsNothing);
    expect(find.text('Waiting Topic'), findsOneWidget);
    expect(GetIt.I<NewsProvider>().topics.map((t) => t.topic), ['a3a3a3a3']);
  });

  testWidgets('Leave shows why it failed and keeps the topic', (tester) async {
    final api = await open(tester);
    api.failSubscribe = true;

    await tester.tap(button('Leave').first);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not leave topic a1a1a1a1: database is locked'),
      findsOneWidget,
    );
    expect(find.text('Saved Topic'), findsOneWidget);
  });

  testWidgets('Subscribe adds a topic on the chain at no cost', (tester) async {
    final api = await open(tester);
    await typeUrl(tester, '7{C3C3C3C3}Other Topic');

    expect(find.text('Other Topic (c3c3c3c3) is on the chain. Add subscribes to it at no cost.'), findsOneWidget);
    expect(api.priced, isEmpty);

    await tester.tap(button('Add'));
    await settle(tester);

    expect(api.subscriptions, [('c3c3c3c3', true)]);
    expect(api.sent, isEmpty);
    expect(GetIt.I<NewsProvider>().topics.map((t) => t.topic), contains('c3c3c3c3'));
    expect(find.text('Other topics on the chain:'), findsNothing);
  });

  testWidgets('Subscribe lists the other topics on the chain, each with Subscribe', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    expect(find.text('Other topics on the chain:'), findsOneWidget);
    expect(find.text('Other Topic'), findsOneWidget);
    expect(find.text('Saved Topic'), findsNothing);

    await tester.tap(button('Subscribe').last);
    await settle(tester);

    expect(api.subscriptions, [('c3c3c3c3', true)]);
    expect(api.sent, isEmpty);
    expect(find.text('Other topics on the chain:'), findsNothing);
  });

  testWidgets('Import subscribes to a topic on the chain and creates only the new one', (tester) async {
    final api = await open(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '7{c3c3c3c3}Other Topic\n5{e5e5e5e5}QA Imported'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(button('Import'));
    await openDialog(tester);

    expect(find.text('Create 1 topic?'), findsOneWidget);
    expect(find.textContaining('Other Topic'), findsNothing);
    await tester.tap(button('Create 1 topic'));
    await settle(tester);

    expect(api.subscriptions, [('c3c3c3c3', true)]);
    expect(api.sent, [('e5e5e5e5', 5)]);
  });

  testWidgets('Import of topics on the chain asks nothing', (tester) async {
    final api = await open(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '7{c3c3c3c3}Other Topic'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(button('Import'));
    await settle(tester);

    expect(find.textContaining('Create 1'), findsNothing);
    expect(api.subscriptions, [('c3c3c3c3', true)]);
    expect(api.priced, isEmpty);
    expect(api.sent, isEmpty);
  });
}
