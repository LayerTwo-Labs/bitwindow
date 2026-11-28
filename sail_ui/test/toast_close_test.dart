import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

import 'svg_finder.dart';

Widget _app(SailThemeData theme, void Function(BuildContext context) onOpen) => SailTheme(
  data: theme,
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(onPressed: () => onOpen(context), child: const Text('open')),
      ),
    ),
  ),
);

SailThemeData _v2() =>
    SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2);

void main() {
  testWidgets('a snackbar toast has a × that closes it', (tester) async {
    await tester.pumpWidget(_app(_v2(), (context) => showSnackBar(context, 'Copied address', duration: 30)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Copied address'), findsOneWidget);
    final close = findSailSVG(SailSVGAsset.x);
    expect(tester.widget<SvgPicture>(close).colorFilter, tint(_v2().colors.textSecondary));

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Copied address'), findsNothing);
  });

  testWidgets('a BitWindow v2 toast keeps its × and takes the control radius', (tester) async {
    await tester.pumpWidget(
      _app(_v2(), (context) => showSailToast(context, 'Saved', duration: const Duration(seconds: 30))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final card = tester
        .widgetList<Container>(find.ancestor(of: find.text('Saved'), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(card.borderRadius, const BorderRadius.all(Radius.circular(6)));

    await tester.tap(find.text(String.fromCharCode(0x00D7)));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });
}
