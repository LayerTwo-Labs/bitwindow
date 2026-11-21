import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  testWidgets('each tap on a row reports it, also the tap that clears the selection', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SailTable(
                getRowId: (index) => 'row$index',
                headerBuilder: (context) => [const SailTableHeaderCell(name: 'Name')],
                rowBuilder: (context, row, selected) => [SailTableCell(value: 'value $row')],
                rowCount: 2,
                onRowTap: taps.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('value 1'));
    await tester.pump();
    await tester.tap(find.text('value 1'));
    await tester.pump();

    expect(taps, ['row1', 'row1']);
  });

  testWidgets('with no resize handles the cells line up under their headers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SailTable(
                getRowId: (index) => 'row$index',
                headerBuilder: (context) => [
                  const SailTableHeaderCell(name: 'A'),
                  const SailTableHeaderCell(name: 'B'),
                  const SailTableHeaderCell(name: 'C'),
                ],
                rowBuilder: (context, row, selected) => [
                  const SailTableCell(value: 'a'),
                  const SailTableCell(value: 'b'),
                  const SailTableCell(value: 'c'),
                ],
                rowCount: 1,
                resizableColumns: false,
              ),
            ),
          ),
        ),
      ),
    );

    for (final (header, cell) in [('A', 'a'), ('B', 'b'), ('C', 'c')]) {
      expect(tester.getRect(find.text(cell)).left, closeTo(tester.getRect(find.text(header)).left, 1), reason: cell);
    }
  });

  testWidgets('on a phone a row menu opens again after an item closed it', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    var picks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: Scaffold(
            body: SizedBox(
              width: 390,
              height: 300,
              child: SailTable(
                getRowId: (index) => 'row$index',
                headerBuilder: (context) => [const SailTableHeaderCell(name: 'Status')],
                rowBuilder: (context, row, selected) => [const SailTableCell(value: 'Confirmed')],
                rowCount: 1,
                contextMenuItems: (rowId) => [
                  SailMenuItem(onSelected: () => picks++, child: const Text('Add Note')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    for (var i = 1; i <= 2; i++) {
      await tester.longPress(find.text('Confirmed'));
      await tester.pumpAndSettle();
      expect(find.text('Add Note'), findsOneWidget, reason: 'press $i opens the menu');
      await tester.tap(find.text('Add Note'));
      await tester.pumpAndSettle();
      expect(find.text('Add Note'), findsNothing);
      expect(picks, i);
    }
  });

  testWidgets('on a phone a row menu opens again after its item showed an edit sheet', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: Scaffold(
            body: Builder(
              builder: (outer) => SailCard(
                title: 'History',
                child: SizedBox(
                  height: 300,
                  child: SailTable(
                    getRowId: (index) => 'row$index',
                    headerBuilder: (context) => [const SailTableHeaderCell(name: 'Status')],
                    rowBuilder: (context, row, selected) => [const SailTableCell(value: 'Confirmed')],
                    rowCount: 1,
                    contextMenuItems: (rowId) => [
                      SailMenuItem(
                        onSelected: () async {
                          await Future.microtask(() async {
                            await showThemedDialog(
                              context: outer,
                              builder: (context) => SailCardEditValues(
                                title: 'Add Note',
                                subtitle: '',
                                fields: [EditField(name: 'Note', currentValue: '')],
                                onSave: (fields) async {
                                  Navigator.of(context).pop();
                                  return null;
                                },
                              ),
                            );
                          });
                        },
                        child: const Text('Add Note'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (var i = 1; i <= 2; i++) {
      await tester.longPress(find.text('Confirmed'));
      await tester.pumpAndSettle();
      expect(find.text('Add Note'), findsOneWidget, reason: 'press $i opens the menu');
      await tester.tap(find.text('Add Note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'rent');
      await tester.tap(find.text('Save changes').last);
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsNothing);
    }
  });
}
