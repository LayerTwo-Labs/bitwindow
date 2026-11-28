import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sail_ui/sail_ui.dart';

import 'svg_finder.dart';

WalletMetadata _wallet(String id, String name) => WalletMetadata(
  id: id,
  name: name,
  gradient: WalletGradient(
    backgroundSvg: 'background_northern.svg',
    colors: const ['#000000', '#111111', '#222222'],
    stops: const [0, 0.5, 1],
    centerX: 0,
    centerY: 0,
    radius: 1.2,
    seed: 1,
  ),
  createdAt: DateTime(2026),
  lastUsed: DateTime(2026),
);

void main() {
  _editRouteTests();

  Widget host(Set<String> attention) => SailTheme(
    data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
    child: MaterialApp(
      home: Scaffold(
        body: WalletDropdown(
          currentWallet: _wallet('a', 'Main'),
          availableWallets: [_wallet('a', 'Main'), _wallet('b', 'Cold')],
          onWalletSelected: (_) {},
          onCreateWallet: () {},
          walletsNeedingAttention: attention,
        ),
      ),
    ),
  );

  for (final attention in [false, true]) {
    testWidgets('a long wallet name fits the closed button with attention $attention', (tester) async {
      const name = 'O3 isolated test wallet';
      final wallet = _wallet('a', name);
      await tester.pumpWidget(
        SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: MaterialApp(
            home: Scaffold(
              body: WalletDropdown(
                currentWallet: wallet,
                availableWallets: [wallet],
                onWalletSelected: (_) {},
                onCreateWallet: () {},
                onEditWallet: (_) async {},
                walletsNeedingAttention: attention ? {'a'} : {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final label = find.text(name);
      final arrow = find
          .descendant(
            of: find.byType(WalletDropdown),
            matching: find.byWidgetPredicate((widget) => widget is SvgPicture && widget.width == 13),
          )
          .last;
      expect(tester.getRect(label).right, lessThan(tester.getRect(arrow).left));

      await tester.tap(find.byType(WalletDropdown));
      await tester.pumpAndSettle();

      expect(find.text('Edit $name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // A wallet the user is not in can hold coins to claim, and the picker is the
  // only place that says so.
  testWidgets('a wallet with something to claim carries a dot', (tester) async {
    await tester.pumpWidget(host({'b'}));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(WalletDropdown));
    await tester.pumpAndSettle();

    final dots = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle && c.constraints?.maxWidth == 8;
    });
    expect(dots.length, 1, reason: 'exactly the wallet with a claim gets a dot');
  });

  testWidgets('no dot without a claim', (tester) async {
    await tester.pumpWidget(host(const {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(WalletDropdown));
    await tester.pumpAndSettle();

    final dots = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle && c.constraints?.maxWidth == 8;
    });
    expect(dots, isEmpty);
  });

  testWidgets('a hairline parts the other wallets from the actions, and the plus sits on a filled circle', (
    tester,
  ) async {
    await tester.pumpWidget(host(const {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(WalletDropdown));
    await tester.pumpAndSettle();

    final divider = tester.getRect(find.byKey(const Key('wallet_menu_divider')));
    expect(divider.top, greaterThan(tester.getRect(find.text('Cold')).bottom));
    expect(divider.bottom, lessThanOrEqualTo(tester.getRect(find.text('Create new wallet')).top));

    final theme = SailTheme.of(tester.element(find.text('Create new wallet')));
    final plus = tester.widget<Container>(
      find.ancestor(of: findSailSVG(SailSVGAsset.plus), matching: find.byType(Container)).first,
    );
    final decoration = plus.decoration! as BoxDecoration;
    expect(decoration.color, theme.colors.formField);
    expect(decoration.border, isNull);
  });

  testWidgets('one wallet has no hairline above the actions', (tester) async {
    await tester.pumpWidget(
      SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
        child: MaterialApp(
          home: Scaffold(
            body: WalletDropdown(
              currentWallet: _wallet('a', 'Main'),
              availableWallets: [_wallet('a', 'Main')],
              onWalletSelected: (_) {},
              onCreateWallet: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WalletDropdown));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet_menu_divider')), findsNothing);
  });
}

// A user with one wallet still has to reach Edit, or the picture and the name
// have no route at all.
void _editRouteTests() {
  testWidgets('the open wallet carries an Edit link', (tester) async {
    var edited = 0;

    await tester.pumpWidget(
      SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
        child: MaterialApp(
          home: Scaffold(
            body: WalletDropdown(
              currentWallet: _wallet('a', 'Main'),
              availableWallets: [_wallet('a', 'Main')],
              onWalletSelected: (_) {},
              onCreateWallet: () {},
              onEditWallet: (_) async => edited++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(WalletDropdown));
    await tester.pumpAndSettle();

    // The list hides the open wallet, so its route is the menu entry.
    expect(find.text('Edit Main'), findsOneWidget);

    await tester.tap(find.text('Edit Main'));
    await tester.pumpAndSettle();
    expect(edited, 1);
  });
}
