import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/sidechain_conf_editor_page.dart';
import 'package:sail_ui/shell/sidechain_conf_editor_viewmodel.dart';
import 'package:sail_ui/shell/sidechain_module.dart';

const _conf =
    'headless=true\nlog-level=DEBUG\nrpc-addr=127.0.0.1:6009\nnet-addr=0.0.0.0:4009\n'
    'mainchain-grpc-url=http://localhost:50051\n';

class _Module implements SidechainModule {
  @override
  Sidechain get chain => Thunder();

  @override
  String get appName => 'Thunder';

  @override
  String get fullName => 'Thunder';

  @override
  String defaultConf(String network) => _conf;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements GenericSidechainConfProvider {
  String content = _conf;
  bool fail = false;

  @override
  String get network => 'signet';

  @override
  String getCurrentConfigContent() {
    if (fail) {
      throw const FormatException('Unexpected character (at line 3)');
    }
    return content;
  }

  @override
  List<String> getCliArgs() => ['--headless', '--log-level', 'DEBUG'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Conf conf;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<SidechainModule>(_Module());
    conf = _Conf();
    GetIt.I.registerSingleton<GenericSidechainConfProvider>(conf);
    SailStyleValues.phoneLayoutOverride = false;
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  Future<SidechainConfEditorViewModel> pumpBody(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1416, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = SidechainConfEditorViewModel();
    addTearDown(model.dispose);
    await model.loadConfig();
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
            body: ListenableBuilder(
              listenable: model,
              builder: (context, _) => ConfEditorV2Body(viewModel: model),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return model;
  }

  testWidgets('the head has one Save button, Reset and Reset to Default sit in its "…"', (tester) async {
    await pumpBody(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Thunder Conf Configurator'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Save'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Reset'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Reset to Default'), findsNothing);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Reset to Default'), findsOneWidget);
  });

  testWidgets('the settings card lists each setting as a row with its control at the right', (tester) async {
    await pumpBody(tester);

    final config = tester.getRect(find.text('Configuration'));
    final settings = tester.getRect(find.text('Settings'));
    expect(settings.left, greaterThan(config.right));
    final headless = tester.getRect(find.text('Headless Mode'));
    expect(tester.getRect(find.byType(SailSwitch)).center.dy, closeTo(headless.center.dy, 2));
    expect(tester.getRect(find.byType(SailSwitch)).left, greaterThan(settings.left + 300));
    expect(find.text('CLI Preview:'), findsOneWidget);
  });

  testWidgets('a load error shows in the Configuration card with Retry, the settings stay', (tester) async {
    final model = await pumpBody(tester);
    conf.fail = true;
    await model.loadConfig();
    await tester.pump();

    expect(find.text('Error loading configuration'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Retry'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    conf.fail = false;
    await tester.tap(find.widgetWithText(SailButton, 'Retry'));
    await tester.pump();
    expect(find.text('Error loading configuration'), findsNothing);
  });
}
