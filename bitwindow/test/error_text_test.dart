import 'package:bitwindow/utils/error_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  test('a server error gives its message as a sentence, with no class name', () {
    expect(
      errorText(BitwindowException('could not create topic: topic already exists')),
      'Could not create topic: topic already exists',
    );
  });

  test('another error gives its text', () {
    expect(errorText(StateError('no wallet')), 'Bad state: no wallet');
  });

  test('an empty message stays empty', () {
    expect(errorText(BitwindowException('')), '');
  });
}
