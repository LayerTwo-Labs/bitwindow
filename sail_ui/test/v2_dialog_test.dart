import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _theme(SailThemeStyle style, {bool light = true}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, style)
    : SailThemeData.darkTheme(SailColorScheme.orange, false, SailFontValues.inter, style);

Widget _app(SailThemeData theme, Future<void> Function(BuildContext context) open) => SailTheme(
  data: theme,
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open')),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final light in [true, false]) {
    testWidgets(
      'a BitWindow v2 dialog has a × in the head and one full-width action in ${light ? 'light' : 'dark'} mode',
      (
        tester,
      ) async {
        var sent = 0;
        final theme = _theme(SailThemeStyle.bitwindowV2, light: light);
        await tester.pumpWidget(
          _app(
            theme,
            (context) => widgetDialog(
              context: context,
              title: 'Send',
              maxWidth: 440,
              action: SailDialogAction(label: 'Send now', onPressed: () async => sent++),
              child: const Text('Body'),
            ),
          ),
        );
        await _open(tester);

        final close = find.byType(SailIconBoxButton);
        expect(close, findsOneWidget);
        expect(tester.getCenter(close).dy, closeTo(tester.getCenter(find.text('Send')).dy, 4));

        final card = tester.getRect(find.byType(SailCard));
        final button = tester.getRect(find.byType(SailButton));
        expect(button.width, closeTo(card.width - 32, 1));
        expect(button.top, greaterThan(tester.getRect(find.text('Body')).bottom));

        final shape = tester.widget<Dialog>(find.byType(Dialog)).shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, const BorderRadius.all(Radius.circular(8)));

        await tester.tap(find.text('Send now'));
        await tester.pump();
        expect(sent, 1);

        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.text('Body'), findsNothing);
      },
    );
  }

  testWidgets('the head end of a dialog sits before the ×', (tester) async {
    await tester.pumpWidget(
      _app(
        _theme(SailThemeStyle.bitwindowV2),
        (context) => widgetDialog(
          context: context,
          title: 'Send',
          headerEnd: const Text('More'),
          child: const Text('Body'),
        ),
      ),
    );
    await _open(tester);

    final more = tester.getRect(find.text('More'));
    final close = tester.getRect(find.byType(SailIconBoxButton));
    expect(more.right, lessThanOrEqualTo(close.left));
    expect(more.center.dy, closeTo(close.center.dy, 4));
  });

  testWidgets('a BitWindow v2 info dialog drops Cancel for the ×', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      _app(
        _theme(SailThemeStyle.bitwindowV2),
        (context) => infoDialog(
          context: context,
          title: 'Heads up',
          subtitle: 'Something happened.',
          onConfirm: () async => confirmed++,
        ),
      ),
    );
    await _open(tester);

    expect(find.text('Cancel'), findsNothing);
    expect(find.byType(SailIconBoxButton), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(confirmed, 1);
  });

  testWidgets('a BitWindow v2 alert card closes with its × through onCancel', (tester) async {
    var cancelled = 0;
    var confirmed = 0;
    await tester.pumpWidget(
      _app(
        _theme(SailThemeStyle.bitwindowV2),
        (context) => showDialog<void>(
          context: context,
          builder: (_) => SailAlertCard(
            title: 'Delete',
            subtitle: 'Delete the wallet?',
            confirmText: 'Delete',
            confirmButtonVariant: ButtonVariant.destructive,
            onConfirm: () async => confirmed++,
            onCancel: () async => cancelled++,
          ),
        ),
      ),
    );
    await _open(tester);

    expect(find.text('Cancel'), findsNothing);
    final delete = find.widgetWithText(SailButton, 'Delete');
    expect(tester.widget<SailButton>(delete).variant, ButtonVariant.destructive);
    await tester.tap(delete);
    await tester.pump();
    expect(confirmed, 1);

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pump();
    expect(cancelled, 1);
  });

  testWidgets('a SailDialog puts its action under the other actions at full width', (tester) async {
    await tester.pumpWidget(
      _app(
        _theme(SailThemeStyle.bitwindowV2),
        (context) => showDialog<void>(
          context: context,
          builder: (_) => SailDialog(
            title: 'Rename',
            withCloseButton: true,
            action: SailDialogAction(label: 'Save', onPressed: () async {}),
            child: const Text('Body'),
          ),
        ),
      ),
    );
    await _open(tester);

    final card = tester.getRect(find.byType(SailCard));
    expect(tester.getRect(find.byType(SailButton)).width, closeTo(card.width - 32, 1));
  });

  testWidgets('a sail info dialog keeps Cancel and the round icon close', (tester) async {
    await tester.pumpWidget(
      _app(
        _theme(SailThemeStyle.sail),
        (context) => infoDialog(context: context, title: 'Heads up', subtitle: 'Text', onConfirm: () async {}),
      ),
    );
    await _open(tester);

    expect(find.text('Cancel'), findsWidgets);
    expect(find.byType(SailIconBoxButton), findsNothing);
  });

  testWidgets('the app dialog theme makes a plain AlertDialog square in BitWindow v2 only', (tester) async {
    for (final (style, square) in [(SailThemeStyle.bitwindowV2, true), (SailThemeStyle.sail, false)]) {
      final theme = _theme(style);
      expect(sailDialogTheme(theme) != null, square);
      await tester.pumpWidget(
        SailTheme(
          data: theme,
          child: MaterialApp(
            theme: ThemeData(dialogTheme: sailDialogTheme(theme)),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('Manual bid')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first,
      );
      final radius = (material.shape! as RoundedRectangleBorder).borderRadius;
      expect(radius == const BorderRadius.all(Radius.circular(8)), square);

      Navigator.of(tester.element(find.text('Manual bid'))).pop();
      await tester.pumpAndSettle();
    }
  });

  for (final style in [
    SailThemeStyle.bitwindowV2,
    SailThemeStyle.values.firstWhere((s) => s != SailThemeStyle.bitwindowV2),
  ]) {
    final v2 = style == SailThemeStyle.bitwindowV2;
    testWidgets('an edit card ends in a ${v2 ? 'full-width' : 'right-aligned'} save button in the $style theme', (
      tester,
    ) async {
      final theme = _theme(style);
      await tester.pumpWidget(
        _app(
          theme,
          (context) => showDialog(
            context: context,
            builder: (context) => SailTheme(
              data: theme,
              child: SailModal(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SailCardEditValues(
                  title: 'Add Note',
                  subtitle: 'Set a note',
                  fields: [EditField(name: 'Note', currentValue: '')],
                  onSave: (fields) => null,
                ),
              ),
            ),
          ),
        ),
      );
      await _open(tester);

      final card = tester.getRect(find.byType(SailCard));
      final button = tester.getRect(find.widgetWithText(SailButton, 'Save changes').first);
      if (v2) {
        expect(button.width, closeTo(card.width - 32, 1));
      } else {
        expect(button.width, lessThan(card.width / 2));
        expect(button.right, closeTo(card.right - 16, 1));
      }
    });
  }
}
