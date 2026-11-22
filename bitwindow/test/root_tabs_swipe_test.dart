import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/pages/root_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _first = PageInfo('First', builder: (_) => const SizedBox.expand(child: Text('first')));
final _second = PageInfo('Second', builder: (_) => const SizedBox.expand(child: Text('second')));
final _tabs = PageInfo(
  'Tabs',
  builder: (_) => rootTabsRouter(
    routes: const [PageRouteInfo('First'), PageRouteInfo('Second')],
    builder: (context, child, _) => child,
  ),
);

class _Router extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: _tabs,
      initial: true,
      children: [
        AutoRoute(page: _first, initial: true),
        AutoRoute(page: _second),
      ],
    ),
  ];
}

void main() {
  testWidgets('a trackpad swipe does not change the top tab', (tester) async {
    final router = _Router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    final center = tester.getCenter(find.text('first'));
    final swipe = await tester.startGesture(center, kind: PointerDeviceKind.trackpad);
    for (var i = 1; i <= 20; i++) {
      await swipe.panZoomUpdate(center, pan: Offset(-30.0 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await swipe.panZoomEnd();
    await tester.pumpAndSettle();

    expect(AutoTabsRouter.of(tester.element(find.text('first'))).activeIndex, 0);
    expect(find.text('second'), findsNothing);
  });
}
