import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

class _WalletApi extends Fake implements WalletAPI {
  bool encrypted = false;
  String? refusal;
  final List<String> restores = [];

  @override
  Future<ValidateBackupResponse> validateBackup(List<int> backupData, String filename) async =>
      ValidateBackupResponse(valid: true, encrypted: encrypted);

  @override
  Future<void> restoreBackup(List<int> backupData, String filename, {String password = ''}) async {
    restores.add(password);
    if (refusal != null) {
      throw WalletException(refusal!);
    }
  }
}

class _Api extends Fake implements BitwindowRPC {
  @override
  final _WalletApi wallet = _WalletApi();
}

class _OrchestratorWallet extends Fake implements OrchestratorWalletRPC {
  @override
  Future<wmpb.ListWalletBackupsResponse> listWalletBackups() async => wmpb.ListWalletBackupsResponse();
}

class _Orchestrator extends Fake implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _OrchestratorWallet();
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  _WalletReader({required this.hasNoWallet});

  @override
  final bool hasNoWallet;

  int reloads = 0;

  @override
  Future<void> init() async => reloads++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.file);

  final File file;

  @override
  String get name => file.uri.pathSegments.last;

  @override
  String? get path => file.path;

  @override
  Uri get uri => file.uri;

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => file.lengthSync();

  @override
  Future<int?> length() => file.length();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => throw UnimplementedError();
}

class _Picker extends FilePickerPlatform {
  _Picker(this.file);

  final File file;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _PickedFile(file);
}

File _backupFile() {
  final dir = Directory.systemTemp.createTempSync('restore_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/backup.zip')..writeAsBytesSync([1, 2, 3]);
}

void main() {
  late _Api api;

  setUp(() async {
    await GetIt.I.reset();
    api = _Api();
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
  });

  tearDown(() => GetIt.I.reset());

  group('restoreWalletBackupFile', () {
    test('writes the backup when the install has no wallet', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader(hasNoWallet: true));

      expect(await restoreWalletBackupFile(_backupFile()), BackupFileRestore.replaced);
      expect(api.wallet.restores, ['']);
    });

    test('adds the wallets when the install has a wallet', () async {
      final reader = _WalletReader(hasNoWallet: false);
      GetIt.I.registerSingleton<WalletReaderProvider>(reader);

      expect(await restoreWalletBackupFile(_backupFile()), BackupFileRestore.added);
      expect(api.wallet.restores, ['']);
      expect(reader.reloads, 1);
    });

    test('sends the password of an encrypted backup', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader(hasNoWallet: false));
      api.wallet.encrypted = true;
      String? asked;

      final result = await restoreWalletBackupFile(
        _backupFile(),
        askPassword: (filename) async {
          asked = filename;
          return 'backup horse';
        },
      );

      expect(result, BackupFileRestore.added);
      expect(asked, 'backup.zip');
      expect(api.wallet.restores, ['backup horse']);
    });

    test('restores nothing when the user gives no password', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader(hasNoWallet: false));
      api.wallet.encrypted = true;

      final result = await restoreWalletBackupFile(_backupFile(), askPassword: (_) async => null);

      expect(result, BackupFileRestore.cancelled);
      expect(api.wallet.restores, isEmpty);
    });
  });

  group('Restore from backup with a wallet in the install', () {
    var boots = 0;

    Future<void> openAndRestore(WidgetTester tester, Size size) async {
      GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader(hasNoWallet: false));
      final file = await tester.runAsync(() async => _backupFile());
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _Picker(file!);
      addTearDown(() => FilePickerPlatform.instance = previous);
      SailStyleValues.phoneLayoutOverride = false;
      addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      boots = 0;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SailTheme(
            data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
            child: child!,
          ),
          home: WalletBackupRestoreOptions(
            bootBinaries: (_) async => boots++,
            binariesToStop: const [],
            showScaffold: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Click to choose backup file...'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Restore selected backup'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    List<String> stepNames(WidgetTester tester) =>
        tester.widgetList<ProgressStepTile>(find.byType(ProgressStepTile)).map((t) => t.name).toList();

    for (final size in const [Size(1200, 800), Size(1024, 700)]) {
      testWidgets('adds the wallets of the backup at ${size.width.toInt()}', (tester) async {
        await openAndRestore(tester, size);

        expect(api.wallet.restores, ['']);
        expect(boots, 0);
        expect(stepNames(tester), ['Validating backup file', 'Adding the wallets of the backup', 'Restore complete']);
        expect(
          tester.widgetList<ProgressStepTile>(find.byType(ProgressStepTile)).every((t) => t.isCompleted),
          isTrue,
        );
        expect(find.text('Restored the backup. Your other wallets stay.'), findsOneWidget);
        expect(find.textContaining('Previous wallet backed up to'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows the refusal on the step that failed', (tester) async {
      api.wallet.refusal = 'every wallet of the backup is here already';
      await openAndRestore(tester, const Size(1024, 700));

      final failed = tester.widget<ProgressStepTile>(
        find.byWidgetPredicate((w) => w is ProgressStepTile && w.name == 'Adding the wallets of the backup'),
      );
      expect(failed.isFailed, isTrue);
      expect(find.text('Restore failed: every wallet of the backup is here already'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Close'), findsOneWidget);
      expect(boots, 0);
    });
  });
}
