import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

class _Provider extends HomepageProvider {
  final List<String> ids;

  _Provider(this.ids) : super(HomepageConfiguration(widgets: const []));

  @override
  final Map<String, HomepageWidgetInfo> catalog = {
    for (final (id, size) in [
      ('quotes', WidgetSize.bar),
      ('balance', WidgetSize.half),
      ('receive', WidgetSize.half),
      ('send', WidgetSize.half),
      ('swap', WidgetSize.half),
      ('history', WidgetSize.full),
      ('utxos', WidgetSize.full),
    ])
      id: HomepageWidgetInfo(
        id: id,
        name: id,
        sizes: [size],
        builder: (_) => SizedBox(height: 80, child: Text(id)),
      ),
  };

  @override
  Future<HomepageConfiguration> read() async =>
      HomepageConfiguration(widgets: [for (final id in ids) HomepageWidgetConfig(widgetId: id)]);

  @override
  Future<void> write(HomepageConfiguration configuration) async {}
}

Future<_Provider> _pump(
  WidgetTester tester,
  List<String> ids, {
  Size size = const Size(1400, 1000),
  bool halvesRight = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final provider = _Provider(ids);
  await provider.loaded;
  await tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2),
        child: Scaffold(
          body: HomepageView(provider: provider, sideColumns: true, halvesRight: halvesRight),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

void main() {
  testWidgets('half-width widgets stack in the left column and the tables fill the right', (tester) async {
    await _pump(tester, ['quotes', 'balance', 'receive', 'send', 'history', 'utxos']);

    final quotes = tester.getRect(find.text('quotes'));
    final balance = tester.getTopLeft(find.text('balance'));
    final send = tester.getTopLeft(find.text('send'));
    final history = tester.getTopLeft(find.text('history'));
    final utxos = tester.getTopLeft(find.text('utxos'));

    expect(balance.dy, greaterThan(quotes.bottom));
    expect(send.dx, balance.dx);
    expect(send.dy, greaterThan(balance.dy));
    expect(history.dx, closeTo(balance.dx + HomepageView.sideColumnWidth + SailStyleValues.padding12, 0.5));
    expect(history.dy, balance.dy);
    expect(utxos.dx, history.dx);
    expect(utxos.dy, greaterThan(history.dy));
  });

  testWidgets('a fourth half-width widget gets a middle column and the bar joins the left column', (tester) async {
    await _pump(tester, ['quotes', 'balance', 'receive', 'send', 'swap', 'history', 'utxos']);

    final quotes = tester.getTopLeft(find.text('quotes'));
    final balance = tester.getTopLeft(find.text('balance'));
    final swap = tester.getTopLeft(find.text('swap'));
    final history = tester.getTopLeft(find.text('history'));

    expect(balance.dx, quotes.dx);
    expect(balance.dy, greaterThan(quotes.dy));
    expect(swap.dy, quotes.dy);
    expect(swap.dx, greaterThan(quotes.dx + HomepageView.sideColumnWidth));
    expect(history.dy, quotes.dy);
    expect(history.dx, greaterThan(swap.dx));
  });

  testWidgets('a homepage without full-width widgets keeps the rows of pairs', (tester) async {
    await _pump(tester, ['balance', 'receive']);

    expect(tester.getTopLeft(find.text('receive')).dy, tester.getTopLeft(find.text('balance')).dy);
  });

  testWidgets('the tables share the page height and the page does not scroll for them', (tester) async {
    await _pump(tester, ['quotes', 'balance', 'receive', 'send', 'history', 'utxos']);

    final history = tester.getRect(find.byKey(const ValueKey('HomepageWidget-history')));
    final utxos = tester.getRect(find.byKey(const ValueKey('HomepageWidget-utxos')));

    expect(find.byKey(const Key('HomepageFilled')), findsOneWidget);
    expect(history.height, greaterThan(300));
    expect(utxos.height, closeTo(history.height, 0.5));
    expect(utxos.top, closeTo(history.bottom + SailStyleValues.padding12, 0.5));
    expect(utxos.bottom, closeTo(1000, 0.5));
    expect(find.byKey(const Key('HomepageEdit')), findsOneWidget);
  });

  testWidgets('a short page and edit mode keep the scrolled rows', (tester) async {
    final provider = await _pump(tester, ['balance', 'history', 'utxos'], size: const Size(1400, 400));
    expect(find.byKey(const Key('HomepageFilled')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('HomepageWidget-history'))).height, 80);

    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    provider.startEdit();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('HomepageFilled')), findsNothing);
    expect(find.byKey(const Key('HomepageEditBar')), findsOneWidget);
  });

  testWidgets('cards at the right: the tables fill the left and every card stacks at the right', (tester) async {
    await _pump(tester, ['quotes', 'balance', 'receive', 'send', 'swap', 'history'], halvesRight: true);

    final quotes = tester.getRect(find.byKey(const ValueKey('HomepageWidget-quotes')));
    final history = tester.getRect(find.byKey(const ValueKey('HomepageWidget-history')));
    final balance = tester.getRect(find.byKey(const ValueKey('HomepageWidget-balance')));
    final swap = tester.getRect(find.byKey(const ValueKey('HomepageWidget-swap')));

    expect(history.left, quotes.left);
    expect(history.top, balance.top);
    expect(history.bottom, closeTo(1000, 0.5));
    expect(balance.left, closeTo(history.right + SailStyleValues.padding12, 0.5));
    expect(balance.width, HomepageView.rightColumnWidth);
    expect(swap.left, balance.left);
    expect(swap.top, greaterThan(balance.top));
  });

  testWidgets('cards at the right on a short page keep the order in the scrolled rows', (tester) async {
    await _pump(tester, ['balance', 'receive', 'history'], size: const Size(1400, 400), halvesRight: true);

    final history = tester.getRect(find.byKey(const ValueKey('HomepageWidget-history')));
    final receive = tester.getRect(find.byKey(const ValueKey('HomepageWidget-receive')));

    expect(find.byKey(const Key('HomepageFilled')), findsNothing);
    expect(receive.left, greaterThan(history.right));
    expect(receive.width, HomepageView.rightColumnWidth);
  });
}
