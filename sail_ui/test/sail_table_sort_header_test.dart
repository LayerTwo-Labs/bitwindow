import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

const _headers = ['Vote', 'SC #', 'Replacement', 'Title', 'Description', 'Age', 'Height', 'Hash'];

Widget _narrowTable(int sortColumn) {
  return MaterialApp(
    home: SailTheme(
      data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
      child: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: SailTable(
            getRowId: (index) => 'row$index',
            headerBuilder: (context) => [for (final h in _headers) SailTableHeaderCell(name: h)],
            rowBuilder: (context, index, selected) => const [
              SailTableCell(value: '0'),
              SailTableCell(value: '9'),
              SailTableCell(value: 'No'),
              SailTableCell(value: 'QA one'),
              SailTableCell(value: 'A long description of the sidechain'),
              SailTableCell(value: '1'),
              SailTableCell(value: '102'),
              SailTableCell(value: 'c8f3d7fd112f1a19627eab490c2148774e3fef6e9affdbbbba360344cc8e1936'),
            ],
            rowCount: 1,
            sortColumnIndex: sortColumn,
            drawGrid: false,
          ),
        ),
      ),
    ),
  );
}

bool _headerIsCut(WidgetTester tester, String name) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
  return paragraph.didExceedMaxLines || paragraph.size.width < paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5;
}

void main() {
  for (final (index, name) in _headers.indexed) {
    testWidgets('a table sorted by "$name" shows the full header name next to the arrow', (tester) async {
      await tester.pumpWidget(_narrowTable(index));
      await tester.pumpAndSettle();

      expect(_headerIsCut(tester, name), isFalse);
    });
  }

  testWidgets('a tap on a short header shows its full name next to the arrow', (tester) async {
    await tester.pumpWidget(_narrowTable(3));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SC #'));
    await tester.pumpAndSettle();

    expect(_headerIsCut(tester, 'SC #'), isFalse);
  });
}
