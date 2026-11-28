import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _theme(SailThemeStyle style, {bool light = true}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style)
    : SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter, style);

class _Harness {
  final taps = <String>[];
  final picked = <String>[];
  final sorts = <(int, bool)>[];
}

Widget _table(
  SailThemeData theme,
  _Harness h, {
  String? selected,
  bool menu = true,
  bool Function(String rowId)? rowHasMenu,
  bool drawGrid = false,
  double width = 700,
}) => MaterialApp(
  home: SailTheme(
    data: theme,
    child: Scaffold(
      body: SizedBox(
        width: width,
        height: 400,
        child: SailTable(
          getRowId: (index) => 'row$index',
          selectedRowId: selected,
          drawGrid: drawGrid,
          altBackgroundColor: const Color(0xff123456),
          cellHeight: 48,
          onRowTap: h.taps.add,
          onSort: (column, ascending) => h.sorts.add((column, ascending)),
          headerBuilder: (context) => const [
            SailTableHeaderCell(name: 'Transaction'),
            SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight),
          ],
          rowBuilder: (context, row, selected) => [
            SailTableCell(value: 'Title $row', secondaryValue: 'txid$row'),
            SailTableCell(value: '0.$row', secondaryValue: 'ECX', alignment: Alignment.centerRight),
          ],
          contextMenuItems: menu
              ? (rowId) => [
                  SailMenuItem(onSelected: () => h.picked.add('copy $rowId'), child: Text('Copy $rowId')),
                ]
              : null,
          rowHasMenu: rowHasMenu,
          rowCount: 3,
        ),
      ),
    ),
  ),
);

Finder _row(int index) => find.ancestor(of: find.text('Title $index'), matching: find.byType(DecoratedBox)).first;

BoxDecoration _rowDecoration(WidgetTester tester, int index) {
  final boxes = tester
      .widgetList<DecoratedBox>(find.ancestor(of: find.text('Title $index'), matching: find.byType(DecoratedBox)))
      .map((b) => b.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.border != null || d.color != null || d.borderRadius != null);
  return boxes.first;
}

void main() {
  for (final light in [true, false]) {
    final mode = light ? 'light' : 'dark';

    testWidgets('BitWindow v2 rows are square with a hairline and no zebra in $mode mode', (tester) async {
      final theme = _theme(SailThemeStyle.bitwindowV2, light: light);
      await tester.pumpWidget(_table(theme, _Harness(), selected: 'row2'));
      await tester.pumpAndSettle();

      final odd = _rowDecoration(tester, 1);
      expect(odd.color, isNull);
      expect(odd.borderRadius, isNull);
      expect((odd.border! as Border).bottom.color, theme.colors.divider);

      final selectedRow = _rowDecoration(tester, 2);
      expect(selectedRow.color, theme.colors.formField);
    });
  }

  testWidgets('BitWindow v2 draws no vertical grid lines', (tester) async {
    await tester.pumpWidget(_table(_theme(SailThemeStyle.bitwindowV2), _Harness(), drawGrid: true));
    await tester.pumpAndSettle();

    final rightBorders = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border is Border && (d.border! as Border).right != BorderSide.none);
    expect(rightBorders, isEmpty);
  });

  testWidgets('a BitWindow v2 header is 12 px medium grey', (tester) async {
    final theme = _theme(SailThemeStyle.bitwindowV2);
    await tester.pumpWidget(_table(theme, _Harness()));
    await tester.pumpAndSettle();

    final header = tester.widget<Text>(find.text('Transaction'));
    expect(header.style!.fontSize, 12);
    expect(header.style!.fontWeight, FontWeight.w500);
    expect(header.style!.color, theme.colors.textSecondary);
  });

  testWidgets('a cell shows its second line under the first, centered in the row', (tester) async {
    await tester.pumpWidget(_table(_theme(SailThemeStyle.bitwindowV2), _Harness()));
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Title 0'));
    final txid = tester.getRect(find.text('txid0'));
    final row = tester.getRect(_row(0));
    expect(txid.top, greaterThanOrEqualTo(title.bottom));
    expect(txid.left, title.left);
    expect((title.top - row.top) - (row.bottom - txid.bottom), closeTo(0, 2));
    expect(tester.widget<Text>(find.text('txid0')).style!.fontSize, 12);

    final amount = tester.getRect(find.text('0.0'));
    final unit = tester.getRect(find.text('ECX').first);
    expect(unit.right, closeTo(amount.right, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the "…" of a row opens its context menu and does not select the row', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(_table(_theme(SailThemeStyle.bitwindowV2), h));
    await tester.pumpAndSettle();

    expect(find.byType(SailRowMenuButton), findsNWidgets(3));
    await tester.tap(find.byType(SailRowMenuButton).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Copy row1'), findsOneWidget);
    expect(find.text('Copy value'), findsNothing);
    expect(h.taps, isEmpty);

    await tester.tap(find.text('Copy row1'));
    await tester.pumpAndSettle();
    expect(h.picked, ['copy row1']);
  });

  testWidgets('a right click keeps its menu with "Copy value"', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(_table(_theme(SailThemeStyle.bitwindowV2), h));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Title 0'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Copy value'), findsOneWidget);
    expect(find.text('Copy row0'), findsOneWidget);
  });

  testWidgets('the "…" column keeps the table inside its width and sorting still works', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(_table(_theme(SailThemeStyle.bitwindowV2), h));
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.byType(SailRowMenuButton).first);
    expect(menu.right, lessThanOrEqualTo(700));
    expect(tester.getRect(find.text('0.0')).right, lessThan(menu.left));

    await tester.tap(find.text('Amount'));
    await tester.pump();
    expect(h.sorts, [(1, true)]);
  });

  testWidgets('a row that rowHasMenu turns down keeps the column but shows no "…"', (tester) async {
    await tester.pumpWidget(
      _table(_theme(SailThemeStyle.bitwindowV2), _Harness(), rowHasMenu: (rowId) => rowId != 'row1'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SailRowMenuButton), findsNWidgets(2));
    expect(tester.getRect(find.text('0.1')).right, closeTo(tester.getRect(find.text('0.0')).right, 0.1));
  });

  testWidgets('a table with no context menu has no "…" column', (tester) async {
    await tester.pumpWidget(_table(_theme(SailThemeStyle.bitwindowV2), _Harness(), menu: false));
    await tester.pumpAndSettle();

    expect(find.byType(SailRowMenuButton), findsNothing);
  });

  testWidgets('a sail table keeps the zebra, the round rows and no "…"', (tester) async {
    await tester.pumpWidget(_table(_theme(SailThemeStyle.sail), _Harness()));
    await tester.pumpAndSettle();

    expect(find.byType(SailRowMenuButton), findsNothing);
    final odd = _rowDecoration(tester, 1);
    expect(odd.color, const Color(0xff123456));
    expect(odd.borderRadius, isNotNull);
  });

  testWidgets('the row menu builds its items only on a tap', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: _theme(SailThemeStyle.bitwindowV2),
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 300,
              child: SailTable(
                getRowId: (index) => 'row$index',
                headerBuilder: (context) => const [SailTableHeaderCell(name: 'Name')],
                rowBuilder: (context, row, selected) => [SailTableCell(value: 'value $row')],
                contextMenuItems: (rowId) {
                  builds++;
                  return const [];
                },
                rowCount: 2,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, 0);

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(find.byType(SailMenu), findsNothing);
  });
}
