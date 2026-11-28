import 'package:bitwindow/widgets/hardware_device_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

class _FakeWallet implements OrchestratorWalletRPC {
  List<wmpb.HardwareDevice> devices = [];
  int scans = 0;

  @override
  Future<List<wmpb.HardwareDevice>> enumerateHardwareDevices({String? passphrase}) async {
    scans++;
    return devices;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final _FakeWallet wallet = _FakeWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);
final _close = find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x);

void main() {
  setUpAll(loadBundledFonts);

  late _FakeOrchestrator orchestrator;

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    orchestrator = _FakeOrchestrator();
    GetIt.I.registerSingleton<OrchestratorRPC>(orchestrator);
  });

  tearDown(() => GetIt.I.reset());

  group('the device picker', () {
    testWidgets('Rescan is the one button and the × closes it', (tester) async {
      orchestrator.wallet.devices = [
        wmpb.HardwareDevice(type: 'trezor', model: 'Trezor Safe 3', path: 'p1', fingerprint: '3f2a9c1e'),
        wmpb.HardwareDevice(type: 'bitbox02', model: 'BitBox02', path: 'p2', error: 'busy', errorCode: -12),
      ];
      wmpb.HardwareDevice? picked;
      var closed = false;
      await tester.pumpSailPage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showHardwareDevicePicker(context);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Connect hardware wallet'), findsOneWidget);
      expect(find.byType(SailButton), findsOneWidget);
      expect(_button('Rescan'), findsOneWidget);
      expect(_button('Cancel'), findsNothing);
      expect(find.text('Trezor Safe 3'), findsOneWidget);
      expect(find.text('Busy — reconnect, then Rescan'), findsOneWidget);

      final scans = orchestrator.wallet.scans;
      await tester.tap(_button('Rescan'));
      await tester.pumpAndSettle();
      expect(orchestrator.wallet.scans, scans + 1);

      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked, isNull);
    });

    testWidgets('a click on a ready device picks it', (tester) async {
      final device = wmpb.HardwareDevice(type: 'trezor', model: 'Trezor Safe 3', path: 'p3', fingerprint: 'aa11bb22');
      orchestrator.wallet.devices = [device];
      wmpb.HardwareDevice? picked;
      await tester.pumpSailPage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showHardwareDevicePicker(context),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trezor Safe 3'));
      await tester.pumpAndSettle();
      expect(picked?.path, 'p3');
    });
  });

  group('the PIN dialog', () {
    testWidgets('Unlock is the one button, Clear sits in the PIN field, and Unlock returns the positions', (
      tester,
    ) async {
      String? pin;
      await tester.pumpSailPage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                pin = await showThemedDialog<String>(context: context, builder: (_) => const TrezorPinDialog()),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.widget<SailButton>(_button('Unlock')).disabled, isTrue);
      expect(_button('Cancel'), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('pin_field')), matching: _button('Clear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pin_position_9')));
      await tester.pump();
      await tester.tap(_button('Clear'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pin_position_7')));
      await tester.tap(find.byKey(const Key('pin_position_1')));
      await tester.pump();
      expect(find.text('••'), findsOneWidget);

      await tester.tap(_button('Unlock'));
      await tester.pumpAndSettle();
      expect(pin, '71');
    });
  });

  group('the passphrase dialog', () {
    testWidgets('Confirm is the one button and returns the passphrase', (tester) async {
      String? passphrase;
      await tester.pumpSailPage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => passphrase = await showThemedDialog<String>(
              context: context,
              builder: (_) => const DevicePassphraseDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SailButton), findsOneWidget);
      expect(_close, findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'hidden');
      await tester.tap(_button('Confirm'));
      await tester.pumpAndSettle();
      expect(passphrase, 'hidden');
    });
  });
}
