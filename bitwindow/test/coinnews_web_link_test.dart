import 'dart:io';

import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/utils/web_link.dart';
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

  test('only an http or https address is a web link', () {
    expect(webLink('https://example.com/a?b=c'), Uri.parse('https://example.com/a?b=c'));
    expect(webLink(' http://example.com '), Uri.parse('http://example.com'));
    expect(webLink('example.com/no-scheme'), isNull);
    expect(webLink('file:///System/Applications/Calculator.app'), isNull);
    expect(webLink('https:///no-host'), isNull);
    expect(webLink('not a url %%'), isNull);
    expect(webLink(''), isNull);
  });

  testWidgets('the article opens a web link', (tester) async {
    final opened = await pumpPanel(tester, story(url: 'https://example.com/job'));

    await tester.tap(find.text('https://example.com/job'));
    await tester.pumpAndSettle();

    expect(opened, ['https://example.com/job']);
  });

  testWidgets('the article opens no link that is not a web link', (tester) async {
    final opened = await pumpPanel(
      tester,
      story(url: 'file:///System/Applications/Calculator.app', content: '[read more](file:///etc/hosts)'),
    );

    await tester.tap(find.text('file:///System/Applications/Calculator.app'));
    await tester.tap(find.text('read more'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(opened, isEmpty);
  });

  testWidgets('the article shows a link with no scheme and stays silent on a tap', (tester) async {
    final opened = await pumpPanel(tester, story(url: 'example.com/no-scheme'));

    await tester.tap(find.text('example.com/no-scheme'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(opened, isEmpty);
  });
}
