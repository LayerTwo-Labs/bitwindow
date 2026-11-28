import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/mocks/mocks.dart';

Widget _app(SailThemeData theme) => SailTheme(
  data: theme,
  child: const MaterialApp(
    home: LogPage(
      logPath: '/no/such/dir/bitwindow.log',
      title: 'Bitwindow Logs',
      binaryType: BinaryType.BINARY_TYPE_BITCOIND,
    ),
  ),
);

SailThemeData _theme({required bool light}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2)
    : SailThemeData.darkTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);

void main() {
  late LogProvider logs;

  setUp(() async {
    await GetIt.I.reset();
    logs = LogProvider();
    GetIt.I.registerSingleton<LogProvider>(logs);
    GetIt.I.registerSingleton<BinaryProvider>(MockBinaryProvider());
  });

  tearDown(() => GetIt.I.reset());

  for (final light in [true, false]) {
    final mode = light ? 'light' : 'dark';

    testWidgets('File Logs is a titled card with Open Log File and a not-found line in $mode mode', (tester) async {
      await tester.pumpWidget(_app(_theme(light: light)));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Bitwindow Logs'), findsOneWidget);
      final open = tester.widget<SailButton>(find.widgetWithText(SailButton, 'Open Log File'));
      expect(open.variant, ButtonVariant.secondary);
      expect(find.text('Log file not found.'), findsOneWidget);
    });

    testWidgets('a stderr line in Process Output shows a red ERR in $mode mode', (tester) async {
      final theme = _theme(light: light);
      logs.addLog(
        FullProcessLogEntry(
          timestamp: DateTime(2026, 11, 27, 9),
          message: 'bitcoind: UpdateTip height=945210',
          isStderr: false,
          binaryType: BinaryType.BINARY_TYPE_BITCOIND,
        ),
      );
      logs.addLog(
        FullProcessLogEntry(
          timestamp: DateTime(2026, 11, 27, 9, 1),
          message: 'enforcer: ZMQ address not reachable',
          isStderr: true,
          binaryType: BinaryType.BINARY_TYPE_BITCOIND,
        ),
      );
      await tester.pumpWidget(_app(theme));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Process Output'));
      await tester.pumpAndSettle();

      Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;
      expect(colorOf('ERR'), theme.colors.error);
      expect(colorOf('enforcer: ZMQ address not reachable'), theme.colors.error);
      expect(colorOf('bitcoind: UpdateTip height=945210'), theme.colors.text);
    });
  }
}
