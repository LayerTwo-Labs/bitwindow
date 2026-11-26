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
  final links = <String?>[];
  final estimated = <({String headline, String body, String url, int subtype, bool nsfw})>[];
  String? estimateError;

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
    estimated.add((headline: headline, body: body, url: url, subtype: subtype, nsfw: nsfw));
    if (estimateError case final error?) {
      throw BitwindowException(error);
    }
    final vsize = 150 + headline.length + body.length + url.length;
    return NewsFeeEstimate(vsize: vsize, feeSatPerVbyte: 21, feeSats: 21 * vsize);
  }

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
    links.add(url);
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
    for (final invalid in ['0.000021009', 'abc', '0', '0.000000001', '-0.00002000']) {
      tester.state<EditableTextState>(fee).widget.controller.text = invalid;
      await tester.pump();
      await tester.ensureVisible(broadcast);
      await tester.pump();
      await tester.widget<SailButton>(broadcast).onPressed!();
      await tester.pump();
      final error = find.text('Enter a fee greater than zero. Use up to 8 decimal places.');
      expect(error, findsOneWidget, reason: 'Fee input: $invalid');
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

  testWidgets('a link that is not a web link stops the broadcast', (tester) async {
    await loadBundledFonts();
    final provider = GetIt.I.get<NewsProvider>();
    await tester.runAsync(provider.fetch);
    provider.topics = [Topic(topic: 'a1a1a1a1', name: 'QA Topic', confirmed: true)];
    await tester.runAsync(() => GetIt.I.get<ClientSettings>().setValue(LastUsedTopicSetting(newValue: 'a1a1a1a1')));

    await tester.pumpSailPage(const SizedBox(width: 700, height: 700, child: BroadcastNewsView()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final fields = find.byType(EditableText);
    final broadcast = find.widgetWithText(SailButton, 'Broadcast');
    tester.state<EditableTextState>(fields.at(0)).widget.controller.text = 'QA headline';
    for (final invalid in ['example.com/no-scheme', 'not a url %%', 'file:///etc/hosts']) {
      tester.state<EditableTextState>(fields.at(1)).widget.controller.text = invalid;
      await tester.pump();
      await tester.widget<SailButton>(broadcast).onPressed!();
      await tester.pump();
      expect(find.text('Enter a link that starts with http:// or https://.'), findsOneWidget, reason: invalid);
      expect(api.misc.links, isEmpty);
    }

    tester.state<EditableTextState>(fields.at(1)).widget.controller.text = ' https://example.com/story ';
    await tester.pump();
    await tester.widget<SailButton>(broadcast).onPressed!();
    await tester.pump();
    expect(api.misc.links, ['https://example.com/story']);
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await loadBundledFonts();
    final provider = GetIt.I.get<NewsProvider>();
    await tester.runAsync(provider.fetch);
    provider.topics = [Topic(topic: 'a1a1a1a1', name: 'QA Topic', confirmed: true)];
    await tester.runAsync(() => GetIt.I.get<ClientSettings>().setValue(LastUsedTopicSetting(newValue: 'a1a1a1a1')));
    await tester.pumpSailPage(const SizedBox(width: 700, height: 700, child: BroadcastNewsView()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, Finder field, String text) async {
    tester.state<EditableTextState>(field).widget.controller.text = text;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets('the dialog shows the network fee of the story before the broadcast', (tester) async {
    await pumpDialog(tester);
    expect(find.textContaining('Network fee'), findsNothing);

    await type(tester, find.byType(EditableText).first, 'QA headline\nThe body');
    expect(api.misc.estimated.last, (headline: 'QA headline', body: 'The body', url: '', subtype: 0, nsfw: false));
    final line = find.text('Network fee: ≈ 3549 sats  ·  169 vB at 21.0 sat/vB');
    expect(line, findsOneWidget);
    final broadcast = find.widgetWithText(SailButton, 'Broadcast');
    expect(tester.getBottomLeft(line).dy, lessThan(tester.getTopLeft(broadcast).dy));
    expect(api.misc.fees, isEmpty, reason: 'An estimate broadcasts nothing');

    await tester.tap(find.byType(SailCheckbox));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(api.misc.estimated.last.nsfw, isTrue);

    await type(tester, find.byType(EditableText).at(1), 'https://example.com');
    expect(api.misc.estimated.last.url, 'https://example.com');
    expect(find.text('Network fee: ≈ 3948 sats  ·  188 vB at 21.0 sat/vB'), findsOneWidget);
  });

  testWidgets('a fee in the field replaces the estimate', (tester) async {
    await pumpDialog(tester);
    await type(tester, find.byType(EditableText).first, 'QA headline');
    expect(find.textContaining('Network fee'), findsOneWidget);
    final reads = api.misc.estimated.length;

    await type(tester, find.byType(EditableText).last, '0.00005');
    expect(find.textContaining('Network fee'), findsNothing);
    expect(api.misc.estimated, hasLength(reads));

    await type(tester, find.byType(EditableText).last, '');
    expect(find.textContaining('Network fee'), findsOneWidget);
  });

  testWidgets('the dialog gives the reason when the wallet has no fee for the story', (tester) async {
    await pumpDialog(tester);
    api.misc.estimateError = 'could not estimate news fee: insufficient funds';
    await type(tester, find.byType(EditableText).first, 'QA headline');
    expect(find.text('Could not estimate news fee: insufficient funds'), findsOneWidget);
    expect(find.textContaining('Network fee'), findsNothing);

    api.misc.estimateError = null;
    await type(tester, find.byType(EditableText).first, 'QA headline 2');
    expect(find.textContaining('Could not estimate'), findsNothing);
    expect(find.textContaining('Network fee'), findsOneWidget);
  });

  testWidgets('only the last input sets the fee line', (tester) async {
    await pumpDialog(tester);
    final message = tester.state<EditableTextState>(find.byType(EditableText).first).widget.controller;
    message.text = 'A';
    await tester.pump(const Duration(milliseconds: 100));
    message.text = 'A longer headline';
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(api.misc.estimated.map((e) => e.headline), ['A longer headline']);
  });

  testWidgets('a changed story does not keep the fee of the old story', (tester) async {
    await pumpDialog(tester);
    await type(tester, find.byType(EditableText).first, 'QA headline');
    expect(find.text('Network fee: ≈ 3381 sats  ·  161 vB at 21.0 sat/vB'), findsOneWidget);

    tester.state<EditableTextState>(find.byType(EditableText).first).widget.controller.text =
        'QA headline\n${'A long body. ' * 40}';
    await tester.pump();
    expect(find.textContaining('Network fee'), findsNothing);
    expect(find.text('Checking the fee…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Checking the fee…'), findsNothing);
    expect(find.textContaining('Network fee'), findsOneWidget);
    expect(find.text('Network fee: ≈ 3381 sats  ·  161 vB at 21.0 sat/vB'), findsNothing);
  });

  testWidgets('the dialog with the fee line fits a 1024x700 window', (tester) async {
    await pumpDialog(tester);
    await type(tester, find.byType(EditableText).first, 'QA headline');
    expect(find.textContaining('Network fee'), findsOneWidget);

    final content = find.descendant(of: find.byType(BroadcastNewsView), matching: find.byType(SailColumn)).first;
    // The window leaves 582 px for the content of the dialog.
    expect(tester.getSize(content).height, lessThanOrEqualTo(570));
  });

  testWidgets('Help is at the left edge and Broadcast at the right edge', (tester) async {
    await pumpDialog(tester);
    final help = tester.getTopLeft(find.widgetWithText(SailButton, 'Help'));
    final broadcast = tester.getTopRight(find.widgetWithText(SailButton, 'Broadcast'));
    final field = tester.getRect(find.byType(SailTextField).last);
    expect(help.dx, closeTo(field.left, 1));
    expect(broadcast.dx, closeTo(field.right, 1));
  });
}
