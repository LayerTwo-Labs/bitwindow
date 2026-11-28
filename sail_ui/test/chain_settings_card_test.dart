import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/sidechain_settings_page.dart';

void main() {
  testWidgets('chain settings sit in one card at most 720 px wide, the sections in a segmented control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(
            SailColorScheme.orange,
            true,
            SailFontValues.inter,
            SailThemeStyle.bitwindowV2,
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ChainSettingsCard(
                subtitle: 'Manage your Thunder settings',
                selectedIndex: selected,
                onSectionSelected: (index) => setState(() => selected = index),
                sections: [
                  for (final label in ['Appearance', 'Reset', 'About'])
                    SailSettingsSection(label: label, builder: (_) => Text('$label body')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SideNav), findsNothing);
    expect(find.byType(SailSegments), findsOneWidget);
    expect(tester.getSize(find.byType(SailCard)).width, 720);
    expect(find.text('Appearance body'), findsOneWidget);
    final segments = tester.getRect(find.byType(SailSegments));
    expect(segments.top, greaterThan(tester.getRect(find.text('Manage your Thunder settings')).bottom));

    await tester.tap(find.text('About'));
    await tester.pump();
    expect(selected, 2);
    expect(find.text('About body'), findsOneWidget);
  });
}
