import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

Widget _app(Widget child) {
  return MaterialApp(
    home: SailTheme(
      data: SailThemeData.lightTheme(
        SailColorScheme.orange,
        true,
        SailFontValues.inter,
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('SailPopover', () {
    testWidgets('hidden initially', (tester) async {
      await tester.pumpWidget(
        _app(
          SailPopover(
            popover: SailText.primary12('popover-body'),
            child: SailText.primary12('trigger'),
          ),
        ),
      );
      expect(find.text('trigger'), findsOneWidget);
      expect(find.text('popover-body'), findsNothing);
    });

    testWidgets('tap on trigger opens popover', (tester) async {
      await tester.pumpWidget(
        _app(
          SailPopover(
            popover: SailText.primary12('popover-body'),
            child: SailText.primary12('trigger'),
          ),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      expect(find.text('popover-body'), findsOneWidget);
    });

    testWidgets('controller.show()/hide() drives visibility', (tester) async {
      final c = SailPopoverController();
      await tester.pumpWidget(
        _app(
          SailPopover(
            controller: c,
            popover: SailText.primary12('controlled'),
            child: SailText.primary12('btn'),
          ),
        ),
      );
      expect(find.text('controlled'), findsNothing);
      c.show();
      await tester.pumpAndSettle();
      expect(find.text('controlled'), findsOneWidget);
      c.hide();
      await tester.pumpAndSettle();
      expect(find.text('controlled'), findsNothing);
    });

    testWidgets('barrier tap closes popover', (tester) async {
      await tester.pumpWidget(
        _app(
          SailPopover(
            popover: SailText.primary12('barrier-body'),
            child: SailText.primary12('btn2'),
          ),
        ),
      );
      await tester.tap(find.text('btn2'));
      await tester.pumpAndSettle();
      expect(find.text('barrier-body'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('barrier-body'), findsNothing);
    });

    testWidgets('a nested coin menu opens and selects an output', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _app(
          SailPopover(
            alignment: SailPopoverAlignment.end,
            popover: SizedBox(
              width: 320,
              child: Align(
                alignment: Alignment.centerRight,
                child: SailMultiSelectDropdown(
                  items: [SailDropdownItem(value: 'outpoint', label: 'Coin output')],
                  selectedValues: const [],
                  onSelected: (value) => selected = value,
                  searchPlaceholder: 'Search UTXOs',
                  selectedCountText: 'Select UTXO(s)',
                ),
              ),
            ),
            child: SailText.primary12('Pay from'),
          ),
        ),
      );

      final trigger = find.text('Pay from');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final picker = find.text('Select UTXO(s)');
      expect(tester.getTopLeft(picker).dy, greaterThan(tester.getBottomLeft(trigger).dy));

      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final output = find.text('Coin output');
      expect(output.hitTestable(), findsOneWidget);

      await tester.tap(output);
      await tester.pumpAndSettle();
      expect(selected, 'outpoint');
    });

    testWidgets('supports custom side', (tester) async {
      await tester.pumpWidget(
        _app(
          SailPopover(
            side: SailPopoverSide.top,
            popover: SailText.primary12('top-pop'),
            child: SailText.primary12('btn3'),
          ),
        ),
      );
      await tester.tap(find.text('btn3'));
      await tester.pumpAndSettle();
      expect(find.text('top-pop'), findsOneWidget);
    });
  });
}
