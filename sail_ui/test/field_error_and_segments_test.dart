import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

final _theme = SailThemeData.lightTheme(
  SailColorScheme.orange,
  true,
  SailFontValues.inter,
  SailThemeStyle.bitwindowV2,
);

Widget _app(Widget child) => MaterialApp(
  home: SailTheme(
    data: _theme,
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a field with an error shows the text under it and an error border',
    (tester) async {
      await tester.pumpWidget(
        _app(
          SailTextField(
            controller: TextEditingController(),
            hintText: 'Enter name to reserve',
            errorText: 'Name cannot be empty',
          ),
        ),
      );

      expect(find.text('Name cannot be empty'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Name cannot be empty')).dy,
        greaterThan(tester.getBottomLeft(find.byType(InputDecorator)).dy),
      );
      final decoration = tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
      expect(
        (decoration.enabledBorder! as OutlineInputBorder).borderSide.color,
        _theme.colors.error,
      );
    },
  );

  testWidgets('a field with no error keeps the resting border', (tester) async {
    await tester.pumpWidget(
      _app(
        SailTextField(controller: TextEditingController(), hintText: 'Name'),
      ),
    );

    final decoration = tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
    expect(
      (decoration.enabledBorder! as OutlineInputBorder).borderSide.color,
      isNot(_theme.colors.error),
    );
  });

  testWidgets('a tap on a segment selects its index', (tester) async {
    var active = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => SailSegments(
            labels: const ['Reserve', 'Register'],
            activeIndex: active,
            onSelect: (index) => setState(() => active = index),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(active, 1);
  });
}
