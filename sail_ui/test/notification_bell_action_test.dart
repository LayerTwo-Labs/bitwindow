import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  late NotificationProvider notifications;
  late List<String> ran;

  setUp(() {
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    notifications = NotificationProvider();
    GetIt.I.registerSingleton<NotificationProvider>(notifications);
    ran = [];
    GetIt.I.registerSingleton<NotificationActions>(
      NotificationActions({
        'open-tab': (context, item) async {
          ran.add(item.data['tab']!);
          return true;
        },
      }),
    );
  });

  tearDown(() async => GetIt.I.reset());

  Future<void> openPanel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: const Scaffold(
            body: Align(alignment: Alignment.topRight, child: NotificationBell()),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(NotificationBell));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a click on a row runs its action, closes the panel and marks it read', (tester) async {
    notifications.add(
      id: 'deposit',
      title: 'Deposit received on Thunder',
      content: '1 BTC',
      dialogType: DialogType.success,
      action: 'open-tab',
      data: const {'tab': 'ParentChainRoute'},
    );
    await openPanel(tester);

    await tester.tap(find.text('Deposit received on Thunder').last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(ran, ['ParentChainRoute']);
    expect(notifications.history.single.read, isTrue);
    expect(find.text('Notifications'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a row without an action stays open on a click', (tester) async {
    notifications.add(id: 'info', title: 'Block found', content: 'x', dialogType: DialogType.info);
    await openPanel(tester);

    await tester.tap(find.text('Block found').last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(ran, isEmpty);
    expect(find.text('Notifications'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('each row shows the icon of its type and a × that dismisses it', (tester) async {
    notifications.add(id: 'found', title: 'Block found', content: 'x', dialogType: DialogType.success);
    notifications.add(id: 'down', title: 'Migration status unavailable', content: 'y', dialogType: DialogType.error);
    notifications.add(id: 'net', title: 'betanet is out', content: 'z', dialogType: DialogType.info);
    await openPanel(tester);

    final theme = SailTheme.of(tester.element(find.text('Notifications')));
    for (final type in DialogType.values) {
      final icon = find.byWidgetPredicate(
        (w) =>
            w is SvgPicture &&
            w.colorFilter == ColorFilter.mode(notificationTypeColor(theme.colors, type), BlendMode.srcIn),
      );
      expect(icon, findsOneWidget, reason: type.name);
    }
    expect(notificationTypeIcon(DialogType.success), SailSVGAsset.circleCheck);
    expect(notificationTypeIcon(DialogType.error), SailSVGAsset.circleAlert);
    expect(notificationTypeIcon(DialogType.info), SailSVGAsset.info);

    await tester.tap(find.byWidgetPredicate((w) => w is SailTooltip && w.message == 'Dismiss').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(notifications.history, hasLength(2));
    await tester.pump(const Duration(seconds: 6));
  });
}
