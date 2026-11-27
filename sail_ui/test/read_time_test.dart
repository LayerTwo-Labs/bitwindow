import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  String words(int count, String separator) => List.generate(count, (i) => 'word$i').join(separator);

  test('the read time counts words between line breaks', () {
    expect(readTimeMinutes(words(600, '\n')), 3);
    expect(expectedReadTime(words(600, '\n\n')), '3 min');
  });

  test('the read time counts words between spaces', () {
    expect(readTimeMinutes(words(201, ' ')), 2);
    expect(readTimeMinutes('one  two   three'), 1);
  });

  test('a text with no words reads in 1 minute', () {
    expect(readTimeMinutes(''), 1);
  });
}
