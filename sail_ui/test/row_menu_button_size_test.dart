import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, SailRowMenuButton button) => tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2),
        child: Scaffold(body: Center(child: button)),
      ),
    ),
  );

  testWidgets('the filled "…" is a 28 px box by default', (tester) async {
    await pump(tester, SailRowMenuButton(items: () => []));
    expect(tester.getSize(find.byType(SailIconBoxButton)), const Size(28, 28));
  });

  testWidgets('the filled "…" takes the size it is given', (tester) async {
    await pump(tester, SailRowMenuButton(items: () => [], size: 36));
    expect(tester.getSize(find.byType(SailIconBoxButton)), const Size(36, 36));
  });
}
