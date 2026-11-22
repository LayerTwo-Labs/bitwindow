import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

Future<BuildContext> _pumpPage(WidgetTester tester) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    SailTheme(
      data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const Text('page');
            },
          ),
        ),
      ),
    ),
  );
  return pageContext;
}

Future<void> _openMenu(BuildContext context, WidgetTester tester, List<SailMenuItem> items) async {
  unawaited(
    showSailMenu(
      context: context,
      preferredAnchorPoint: const Offset(20, 20),
      menu: SailMenu(items: items),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a selected item closes the menu and keeps the page', (tester) async {
    final context = await _pumpPage(tester);
    var selected = 0;
    await _openMenu(context, tester, [SailMenuItem(onSelected: () => selected++, child: const Text('Freeze'))]);

    await tester.tap(find.text('Freeze'));
    await tester.pumpAndSettle();

    expect(selected, 1);
    expect(find.text('Freeze'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('a dialog from an item closes over the page, not over the menu', (tester) async {
    final context = await _pumpPage(tester);
    await _openMenu(context, tester, [
      SailMenuItem(
        onSelected: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Save'),
          ),
        ),
        child: const Text('Add Note'),
      ),
    ]);

    await tester.tap(find.text('Add Note'));
    await tester.pumpAndSettle();
    expect(find.text('Add Note'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    expect(find.text('Add Note'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('an item with closeOnSelect false keeps the menu', (tester) async {
    final context = await _pumpPage(tester);
    await _openMenu(context, tester, [
      SailMenuItem(closeOnSelect: false, onSelected: () {}, child: const Text('Stay')),
    ]);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    expect(find.text('Stay'), findsOneWidget);
  });
}
