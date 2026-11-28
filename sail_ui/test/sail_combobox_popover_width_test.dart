import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

Widget _app(Widget child) => MaterialApp(
  home: SailTheme(
    data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2),
    child: Scaffold(body: child),
  ),
);

SailCombobox<String> _combobox({double? popoverWidth, SailPopoverAlignment? alignment}) => SailCombobox<String>(
  items: const [SailComboboxItem(value: 'a', label: 'Alpha')],
  value: 'a',
  width: 200,
  popoverWidth: popoverWidth,
  popoverAlignment: alignment ?? SailPopoverAlignment.start,
  onChanged: (_) {},
);

Future<double> _listWidth(WidgetTester tester) async {
  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(ListView)).width;
}

void main() {
  testWidgets('the list is as wide as the field by default', (tester) async {
    await tester.pumpWidget(_app(Center(child: _combobox())));
    expect(await _listWidth(tester), 200);
  });

  testWidgets('popoverWidth sets the list width and end lines it up at the right edge', (tester) async {
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _combobox(popoverWidth: 480, alignment: SailPopoverAlignment.end),
          ),
        ),
      ),
    );
    final fieldRight = tester.getTopRight(find.byType(SailCombobox<String>)).dx;

    expect(await _listWidth(tester), 480);
    expect(tester.getTopRight(find.byType(ListView)).dx, closeTo(fieldRight, 1));
  });
}
