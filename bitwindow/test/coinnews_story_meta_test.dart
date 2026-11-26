import 'dart:io';

import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GetIt.I.reset());

  final time = DateTime.utc(2026, 11, 16, 16, 32);
  final topics = [Topic(topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true, retentionDays: 30)];

  CoinNews story({
    String headline = 'Headline',
    int subtype = 0,
    bool nsfw = false,
    String url = '',
    String content = '',
  }) => CoinNews(
    headline: headline,
    topic: 'a1a1a1a1',
    subtype: subtype,
    nsfw: nsfw,
    url: url,
    content: content,
    createTime: Timestamp.fromDateTime(time),
  );

  Future<List<String>> pumpPanel(WidgetTester tester, CoinNews news) async {
    final opened = <String>[];
    openUrlProcessRunner = (executable, arguments) async {
      opened.addAll(arguments);
      return ProcessResult(0, 0, '', '');
    };
    addTearDown(() => openUrlProcessRunner = Process.run);
    await tester.pumpSailPage(
      SizedBox(
        width: 1000,
        height: 600,
        child: CoinNewsArticlePanel(news: news, onClose: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final provider = GetIt.I.get<NewsProvider>();
    provider.topics = topics;
    provider.notifyListeners();
    await tester.pumpAndSettle();
    return opened;
  }

  test('the story line names each kind but a link, and marks NSFW', () {
    expect(storyMeta(story(), topicName: 'US Weekly', date: 'today'), 'US Weekly · today');
    expect(storyMeta(story(subtype: 2), topicName: 'US Weekly', date: 'today'), 'US Weekly · Ask · today');
    expect(storyMeta(story(subtype: 5, nsfw: true), topicName: null, date: 'today'), 'Job · NSFW · today');
    expect(storyMeta(story(subtype: 99), topicName: null, date: 'today'), 'today');
  });

  testWidgets('the article shows the kind and the NSFW mark of the story', (tester) async {
    await pumpPanel(tester, story(subtype: 2, nsfw: true));

    expect(find.text('US Weekly  ·  Ask  ·  NSFW  ·  ${formatDate(time)}'), findsOneWidget);
  });
}
