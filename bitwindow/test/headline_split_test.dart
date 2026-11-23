import 'dart:convert';

import 'package:bitwindow/widgets/headline_highlight_text_field.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  String headlineOf(String text) => text.substring(0, headlineEndIndex(text));

  test('an ASCII headline stops at 64 bytes or at the first newline', () {
    expect(headlineOf('E' * 64), 'E' * 64);
    expect(headlineOf('${'F' * 64}G tail'), 'F' * 64);
    expect(headlineOf('Short headline\nBody'), 'Short headline');
    expect(headlineOf(''), '');
  });

  test('a non-ASCII headline stops at 64 UTF-8 bytes', () {
    const text = 'Blåbærsyltetøy og rømmegrøt på fjellet i høst er en god norsk ting';
    final headline = headlineOf(text);

    expect(utf8.encode(headline).length, lessThanOrEqualTo(headlineMaxBytes));
    expect(text.startsWith(headline), isTrue);
    expect(utf8.encode(text.substring(0, headline.length + 1)).length, greaterThan(headlineMaxBytes));
  });

  test('a headline never splits an emoji', () {
    final text = '${'a' * 62}🚀 rest';
    final headline = headlineOf(text);

    expect(headline, 'a' * 62);
    expect(utf8.decode(utf8.encode(headline)), headline);
  });

  testWidgets('the counter shows the headline size in bytes', (tester) async {
    final controller = HeadlineHighlightController(text: 'Blåbær\nBody');
    addTearDown(controller.dispose);

    await tester.pumpSailPage(HeadlineHighlightTextField(controller: controller, hintText: 'Message'));

    expect(find.text('Headline: 8/64 bytes'), findsOneWidget);
  });
}
