import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/pages/tabs/zside/zside_melt_cast_page.dart';

Future<void> _pump(WidgetTester tester, {required bool phone}) async {
  SailStyleValues.phoneLayoutOverride = phone;
  addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
  await tester.binding.setSurfaceSize(Size(phone ? 390 : 1200, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
        child: Scaffold(
          body: Column(
            children: [
              MeltButton(onPressed: () async {}),
              CastButton(onPressed: () async {}),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a phone shows Melt and Cast as plain cards with a 16 px title at the left', (tester) async {
    await _pump(tester, phone: true);

    expect(tester.takeException(), isNull);
    for (final (title, line) in [
      ('Melt', 'Click here to Melt ALL of your transparent Coins'),
      ('Cast', 'Click here to Cast 95-100% of your z-value as 4 new Coins'),
    ]) {
      final text = tester.widget<Text>(find.text(title));
      expect(text.style!.fontSize, 16);
      expect(tester.getRect(find.text(title)).left, lessThan(60));
      expect(tester.widget<Text>(find.text(line)).style!.fontSize, 12);
      expect(tester.getRect(find.text(line)).left, closeTo(17, 1));
    }
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient != null,
      ),
      findsNothing,
    );
  });

  testWidgets('the desktop card holds one Melt button and moves the rest into its "…" menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var melts = 0;
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: Scaffold(
            body: MeltCastCard(
              title: 'Pending melts',
              action: 'Melt',
              line: 'Click here to Melt ALL of your transparent Coins',
              subtitle: 'See list of ongoing melts and their status',
              onAction: () async => melts++,
              showAction: true,
              menuItems: () => [
                for (final label in ['Melt help', 'Do everything for me', 'Consolidate Transparent'])
                  SailMenuItem(onSelected: () => picked.add(label), child: SailText.primary12(label)),
              ],
              table: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SailButton), findsOneWidget);
    expect(find.text('Click here to Melt ALL of your transparent Coins'), findsOneWidget);
    expect(find.text('See list of ongoing melts and their status'), findsOneWidget);

    await tester.tap(find.byType(SailButton));
    await tester.pump();
    expect(melts, 1);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Melt help'), findsOneWidget);
    expect(find.text('Do everything for me'), findsOneWidget);
    await tester.tap(find.text('Consolidate Transparent'));
    await tester.pumpAndSettle();
    expect(picked, ['Consolidate Transparent']);
  });
}
