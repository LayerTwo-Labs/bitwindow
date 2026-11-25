import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

class _WalletRPC extends Fake implements OrchestratorWalletRPC {
  _WalletRPC({this.rejectPassword = false});

  final bool rejectPassword;
  String? restoredBackup;
  String? receivedPassword;

  @override
  Future<wmpb.ListWalletBackupsResponse> listWalletBackups() async {
    return wmpb.ListWalletBackupsResponse(
      backups: [
        wmpb.WalletBackup(
          backupId: 'local-backup',
          sourceName: 'Local backup',
          valid: true,
          encrypted: true,
        ),
      ],
    );
  }

  @override
  Stream<wmpb.RestoreWalletBackupProgressResponse> restoreWalletBackupStream({
    required String backupId,
    String password = '',
  }) async* {
    restoredBackup = backupId;
    receivedPassword = password;
    if (rejectPassword) {
      yield wmpb.RestoreWalletBackupProgressResponse(
        steps: [wmpb.RestoreWalletBackupStep(stepId: 'password', name: 'Verifying wallet password')],
      );
      yield wmpb.RestoreWalletBackupProgressResponse(
        status: wmpb.RestoreWalletBackupProgressStatus(
          stepId: 'password',
          state: wmpb.RestoreWalletBackupStepState.RESTORE_WALLET_BACKUP_STEP_STATE_FAILED,
          error: 'incorrect password',
        ),
      );
      return;
    }
    yield wmpb.RestoreWalletBackupProgressResponse(
      status: wmpb.RestoreWalletBackupProgressStatus(complete: true),
    );
  }
}

class _Orchestrator extends Fake implements OrchestratorRPC {
  _Orchestrator(this.wallet);

  @override
  final OrchestratorWalletRPC wallet;
}

Future<void> _openBackupPassword(WidgetTester tester, _WalletRPC rpc, Size size) async {
  GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator(rpc));
  GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
  SailStyleValues.phoneLayoutOverride = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
  addTearDown(() => GetIt.I.reset());

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => SailTheme(
        data: SailThemeData.lightTheme(
          SailColorScheme.orange,
          true,
          SailFontValues.inter,
        ),
        child: child!,
      ),
      home: WalletBackupRestoreOptions(
        bootBinaries: (_) async {},
        binariesToStop: const [],
        showScaffold: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Local backup'));
  await tester.pumpAndSettle();
  await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Restore selected backup'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final useKeyboard in [false, true]) {
    testWidgets(
      'backup password dialog closes after ${useKeyboard ? 'Enter' : 'Restore'}',
      (tester) async {
        final rpc = _WalletRPC();
        await _openBackupPassword(tester, rpc, useKeyboard ? const Size(1024, 700) : const Size(1200, 600));

        const password = 'backup-test-password';
        await tester.enterText(find.byType(SailTextField), password);
        await tester.pump();
        if (useKeyboard) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Restore'));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.text('Encrypted wallet backup'), findsNothing);
        expect(find.text('Wallet restored successfully!'), findsOneWidget);
        expect(rpc.restoredBackup, 'local-backup');
        expect(rpc.receivedPassword == password, isTrue);
      },
    );
  }
  testWidgets('restore marks a failed password step', (tester) async {
    await _openBackupPassword(tester, _WalletRPC(rejectPassword: true), const Size(1024, 700));
    await tester.enterText(find.byType(SailTextField), 'backup-test-password');
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Restore'));
    await tester.pumpAndSettle();

    final step = find.byWidgetPredicate((w) => w is ProgressStepTile && w.name == 'Verifying wallet password');
    final tile = tester.widget<ProgressStepTile>(step);
    final label = tester.widget<Text>(
      find.descendant(of: step, matching: find.text('Verifying wallet password')).first,
    );
    expect(tile.isCompleted, isFalse);
    expect(tile.isActive, isFalse);
    expect(label.style?.color, SailTheme.of(tester.element(step)).colors.error);
    expect(find.textContaining('incorrect password'), findsOneWidget);
  });
}
