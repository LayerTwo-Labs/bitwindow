import 'dart:io';

import 'package:bitwindow/main.dart' show restoreBitwindowWalletFromFile;
import 'package:bitwindow/pages/welcome/create_another_wallet_page.dart';
import 'package:bitwindow/pages/welcome/multisig_config_step.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'mocks/api_mock.dart';

class _FakeWallet implements OrchestratorWalletRPC {
  @override
  Future<wmpb.ListDerivationPathsResponse> listDerivationPaths({
    required String scriptType,
    required bool multisig,
    int account = 0,
  }) async => wmpb.ListDerivationPathsResponse(defaultPath: "m/84'/1'/0'");

  @override
  Future<List<wmpb.HardwareDevice>> enumerateHardwareDevices({String? passphrase}) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _FakeWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletApi extends MockWalletAPI {
  bool encrypted = false;
  final List<({bool keepWallets, String password})> restores = [];
  String? refusal;

  @override
  Future<ValidateBackupResponse> validateBackup(List<int> backupData, String filename) async =>
      ValidateBackupResponse(valid: true, encrypted: encrypted);

  @override
  Future<void> restoreBackup(
    List<int> backupData,
    String filename, {
    bool keepWallets = false,
    String password = '',
  }) async {
    restores.add((keepWallets: keepWallets, password: password));
    if (refusal != null) {
      throw WalletException(refusal!);
    }
  }
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.file);

  final File file;

  @override
  String get name => file.uri.pathSegments.last;

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

class _Api implements BitwindowRPC {
  @override
  final _WalletApi wallet = _WalletApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  _WalletReader(this.availableWallets, {bool? hasNoWallet}) : hasNoWallet = hasNoWallet ?? availableWallets.isEmpty;

  @override
  final List<WalletMetadata> availableWallets;

  @override
  final bool hasNoWallet;

  int reloads = 0;

  @override
  Future<void> init() async => reloads++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletMetadata _wallet(String name) => WalletMetadata(
  id: name,
  name: name,
  gradient: WalletGradient.fromWalletId(name),
  createdAt: DateTime(2026),
  lastUsed: DateTime(2026),
);

File _backupFile() {
  final dir = Directory.systemTemp.createTempSync('restore_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/backup.zip')..writeAsBytesSync([1, 2, 3]);
}

void main() {
  group('restoreBitwindowWalletFromFile', () {
    late _Api api;

    setUp(() async {
      await GetIt.I.reset();
      api = _Api();
      GetIt.I.registerSingleton<BitwindowRPC>(api);
    });

    test('replaces the wallets when the install has no wallet', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader([]));

      expect(await restoreBitwindowWalletFromFile(_backupFile()), isTrue);

      expect(api.wallet.restores, [(keepWallets: false, password: '')]);
    });

    test('keeps the wallets when the install has a wallet', () async {
      final reader = _WalletReader([_wallet('wallet1')]);
      GetIt.I.registerSingleton<WalletReaderProvider>(reader);

      expect(await restoreBitwindowWalletFromFile(_backupFile()), isTrue);

      expect(api.wallet.restores, [(keepWallets: true, password: '')]);
      expect(reader.reloads, 1);
    });

    test('keeps the wallets when the wallet file is locked', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader([], hasNoWallet: false));

      expect(await restoreBitwindowWalletFromFile(_backupFile()), isTrue);

      expect(api.wallet.restores, [(keepWallets: true, password: '')]);
    });

    test('sends the password of an encrypted backup', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader([_wallet('wallet1')]));
      api.wallet.encrypted = true;
      String? asked;

      final done = await restoreBitwindowWalletFromFile(
        _backupFile(),
        askPassword: (filename) async {
          asked = filename;
          return 'backup horse';
        },
      );

      expect(done, isTrue);
      expect(asked, 'backup.zip');
      expect(api.wallet.restores, [(keepWallets: true, password: 'backup horse')]);
    });

    test('restores nothing when the user gives no password', () async {
      GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader([_wallet('wallet1')]));
      api.wallet.encrypted = true;

      final done = await restoreBitwindowWalletFromFile(_backupFile(), askPassword: (_) async => null);

      expect(done, isFalse);
      expect(api.wallet.restores, isEmpty);
    });
  });

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
  });

  tearDown(() async => GetIt.I.reset());

  testWidgets('a finished restore closes setup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => const CreateAnotherWalletPage())),
              child: const Text('Open setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateAnotherWalletPage), findsOneWidget);

    final step = tester.widget<MultisigConfigStep>(find.byType(MultisigConfigStep));
    step.onRestoringChanged!(true);
    await tester.pump();
    final restored = step.onRestored!();
    await tester.pumpAndSettle();
    await restored;

    expect(find.byType(CreateAnotherWalletPage), findsNothing);
    expect(find.text('Open setup'), findsOneWidget);
  });

  testWidgets('an encrypted backup asks for its password and shows a refusal', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api()..wallet.encrypted = true;
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader([_wallet('wallet1')]));
    final file = await tester.runAsync(() async => _backupFile());
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _Picker(file!);
    addTearDown(() => FilePickerPlatform.instance = previous);
    await tester.pumpWidget(
      SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
        child: const MaterialApp(home: CreateAnotherWalletPage()),
      ),
    );

    // The link spins while the restore runs, so the frames never settle.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();

    Future<void> openPasswordDialog() async {
      await tester.tap(find.widgetWithText(SailButton, 'Restore backup').first);
      await settle();
      expect(find.text('Encrypted wallet backup'), findsOneWidget);
      expect(find.text('backup.zip'), findsOneWidget);
    }

    await openPasswordDialog();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle();
    expect(api.wallet.restores, isEmpty);
    expect(find.byType(CreateAnotherWalletPage), findsOneWidget);

    api.wallet.refusal = 'incorrect password';
    await openPasswordDialog();
    await tester.enterText(find.byType(TextField).last, 'wrong horse');
    await tester.tap(find.widgetWithText(SailButton, 'Restore').first);
    await settle();

    expect(api.wallet.restores, [(keepWallets: true, password: 'wrong horse')]);
    expect(find.text('Failed to restore from backup file: incorrect password'), findsOneWidget);
  });
}
