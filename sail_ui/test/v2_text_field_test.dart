import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _theme(SailThemeStyle style, {bool light = true}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style)
    : SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter, style);

Widget _app(SailThemeData theme, Widget child) => MaterialApp(
  home: SailTheme(
    data: theme,
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, child: child),
      ),
    ),
  ),
);

InputDecoration _decoration(WidgetTester tester) =>
    tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

void main() {
  for (final light in [true, false]) {
    final mode = light ? 'light' : 'dark';

    testWidgets('a BitWindow v2 text field is 40 px tall with the form field fill in $mode mode', (tester) async {
      final theme = _theme(SailThemeStyle.bitwindowV2, light: light);
      await tester.pumpWidget(_app(theme, SailTextField(controller: TextEditingController(), hintText: 'Address')));

      expect(tester.getSize(find.byType(InputDecorator)).height, sailV2FieldHeight);
      final decoration = _decoration(tester);
      expect(decoration.fillColor, theme.colors.formField);
      expect((decoration.enabledBorder! as OutlineInputBorder).borderRadius, theme.chrome.radius);
      expect(theme.chrome.radius, const BorderRadius.all(Radius.circular(6)));
    });

    testWidgets('a BitWindow v2 form field is 40 px tall with the form field fill in $mode mode', (tester) async {
      final theme = _theme(SailThemeStyle.bitwindowV2, light: light);
      await tester.pumpWidget(_app(theme, Form(child: SailTextFormField(controller: TextEditingController()))));

      expect(tester.getSize(find.byType(InputDecorator)).height, sailV2FieldHeight);
      expect(_decoration(tester).fillColor, theme.colors.formField);
    });
  }

  testWidgets('a multi-line BitWindow v2 text field still grows', (tester) async {
    await tester.pumpWidget(
      _app(
        _theme(SailThemeStyle.bitwindowV2),
        SailTextField(
          controller: TextEditingController(text: 'a\nb\nc\nd'),
          hintText: '',
          minLines: 1,
          maxLines: null,
        ),
      ),
    );

    expect(tester.getSize(find.byType(InputDecorator)).height, greaterThan(sailV2FieldHeight));
  });

  testWidgets('a sail text field keeps its page fill and has no height floor', (tester) async {
    final theme = _theme(SailThemeStyle.sail);
    await tester.pumpWidget(_app(theme, SailTextField(controller: TextEditingController(), hintText: 'Address')));

    final decoration = _decoration(tester);
    expect(decoration.fillColor, theme.colors.background);
    expect(decoration.constraints, isNull);
  });
}
