import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

final _theme = SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2);

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
  testWidgets('a stacked detail wraps a long value over more lines', (tester) async {
    final hash = 'a' * 200;
    await tester.pumpWidget(
      _app(
        SailDetailGroup(
          children: [SailStackedDetail(label: 'Hash', value: hash)],
        ),
      ),
    );

    expect(find.text('Hash'), findsOneWidget);
    expect(tester.getSize(find.text(hash)).height, greaterThan(40));
    expect(find.byType(CopyButton), findsNothing);
  });

  testWidgets('a stacked detail with a copy value shows a copy button', (tester) async {
    await tester.pumpWidget(
      _app(const SailStackedDetail(label: 'Commitment', value: 'abc', copyValue: 'abc')),
    );

    expect(find.byType(CopyButton), findsOneWidget);
  });

  testWidgets('a detail line puts the value at the right end', (tester) async {
    await tester.pumpWidget(_app(const SailDetailLine(label: 'Amount', value: '50.0k')));

    expect(tester.getTopRight(find.text('50.0k')).dx, closeTo(300, 1));
    expect(tester.getTopLeft(find.text('Amount')).dx, 0);
  });

  testWidgets('a sunken group draws the form field fill, a canvas group the background', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            SailDetailGroup(
              key: Key('sunken'),
              children: [SailDetailLine(label: 'A', value: '1')],
            ),
            SailDetailGroup(
              key: Key('canvas'),
              fill: SailDetailFill.canvas,
              children: [SailDetailLine(label: 'B', value: '2')],
            ),
          ],
        ),
      ),
    );

    Color fill(String key) =>
        ((tester
                    .widget<DecoratedBox>(
                      find.descendant(of: find.byKey(Key(key)), matching: find.byType(DecoratedBox)).first,
                    )
                    .decoration)
                as BoxDecoration)
            .color!;
    expect(fill('sunken'), _theme.colors.formField);
    expect(fill('canvas'), _theme.colors.background);
  });

  testWidgets('a group puts its title over the box and the spacing between two lines', (tester) async {
    await tester.pumpWidget(
      _app(
        const SailDetailGroup(
          title: 'Details',
          spacing: 20,
          children: [
            SailDetailLine(label: 'A', value: '1'),
            SailDetailLine(label: 'B', value: '2'),
          ],
        ),
      ),
    );

    expect(find.widgetWithText(SailDetailHeading, 'Details'), findsOneWidget);
    expect(tester.getTopLeft(find.text('B')).dy - tester.getBottomLeft(find.text('A')).dy, closeTo(20, 0.5));
  });

  testWidgets('a wrapped line puts a long value on more lines, a plain line keeps one', (tester) async {
    final long = 'word ' * 30;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            SailDetailLine(label: 'Wrap', value: long, wrap: true),
            SailDetailLine(label: 'Cut', value: long),
          ],
        ),
      ),
    );

    final wrapped = find.text(long).first;
    final cut = find.text(long).last;
    expect(tester.getSize(wrapped).height, greaterThan(tester.getSize(cut).height * 2));
  });

  testWidgets('a copyable line copies its value on a tap', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(_app(const SailDetailLine(label: 'Address', value: 'bc1qxyz', copyable: true)));

    await tester.tap(find.text('bc1qxyz'));
    await tester.pump();

    expect(copied, 'bc1qxyz');
  });

  testWidgets('a stacked detail with onCopy shows the small copy icon and runs it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(SailStackedDetail(label: 'TxID', value: 'abc', onCopy: () => taps++)));

    await tester.tap(find.byType(SailDetailCopyIcon));

    expect(taps, 1);
    expect(find.byType(CopyButton), findsNothing);
  });

  testWidgets('a page with a panel puts the panel at the right, and in a narrow width in place of the body', (
    tester,
  ) async {
    Widget page(double width) => MaterialApp(
      home: SailTheme(
        data: _theme,
        child: Center(
          child: SizedBox(
            width: width,
            height: 400,
            child: const SailPageWithPanel(
              narrowWidth: 600,
              panel: SizedBox(key: Key('panel'), width: 200),
              child: SizedBox(key: Key('body')),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(page(800));
    expect(find.byKey(const Key('body')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('body'))).width, 800 - 200 - SailStyleValues.padding12);

    await tester.pumpWidget(page(500));
    expect(find.byKey(const Key('body')), findsNothing);
    expect(tester.getSize(find.byKey(const Key('panel'))).width, 500);
  });

  testWidgets('opening and closing the panel keeps the state of the body', (tester) async {
    Widget page({required bool open, double width = 800}) => MaterialApp(
      home: SailTheme(
        data: _theme,
        child: Center(
          child: SizedBox(
            width: width,
            height: 400,
            child: SailPageWithPanel(
              narrowWidth: 600,
              panel: open ? const SizedBox(width: 200) : null,
              child: const _Counter(),
            ),
          ),
        ),
      ),
    );

    _CounterState state() => tester.state<_CounterState>(find.byType(_Counter, skipOffstage: false));

    await tester.pumpWidget(page(open: false));
    state().count = 3;

    await tester.pumpWidget(page(open: true));
    expect(state().count, 3);

    await tester.pumpWidget(page(open: true, width: 500));
    expect(state().count, 3);

    await tester.pumpWidget(page(open: false));
    expect(state().count, 3);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
