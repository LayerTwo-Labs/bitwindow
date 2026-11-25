import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bitwindow/providers/multisig_provider.dart';
import 'package:bitwindow/widgets/import_psbt_modal.dart';
import 'package:connectrpc/connect.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/multisig/v1/multisig.pb.dart' as storagepb;
import 'package:sidechain_core/gen/multisiglounge/v1/multisiglounge.pb.dart' as loungepb;
import 'package:sidechain_core/gen/orchestrator/v1/orchestrator.pb.dart' as orchestrationpb;

import 'mocks/api_mock.dart';

storagepb.MultisigGroup _group({bool initialCosigner = false}) => storagepb.MultisigGroup(
  id: 'group',
  name: 'Signers',
  m: 2,
  n: 2,
  watchWalletName: 'test-watch',
  keys: [
    storagepb.MultisigKey(owner: 'Alice', xpub: 'alice', isWallet: true),
    storagepb.MultisigKey(owner: initialCosigner ? 'Initial' : 'Bob', xpub: 'bob'),
  ],
);

class _StoredMultisig extends MockMultisigAPI {
  _StoredMultisig(this.group);

  final storagepb.MultisigGroup group;
  storagepb.MultisigTransaction? transaction;

  @override
  Future<List<storagepb.MultisigGroup>> listGroups() async => [group];

  @override
  Future<storagepb.MultisigTransaction> getTransaction(String transactionId) async {
    return transaction ?? (throw ConnectException(Code.notFound, 'Missing transaction'));
  }

  @override
  Future<storagepb.MultisigTransaction> saveTransaction(storagepb.MultisigTransaction transaction) async {
    this.transaction = transaction;
    return transaction;
  }
}

class _Bitwindow extends ChangeNotifier implements BitwindowRPC {
  _Bitwindow(storagepb.MultisigGroup group) : multisig = _StoredMultisig(group);

  @override
  final _StoredMultisig multisig;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lounge implements OrchestratorMultisigLoungeRPC {
  _Lounge(this.foreignPacket);

  final bool foreignPacket;

  @override
  Future<loungepb.ValidatePsbtResponse> validatePsbt({
    required String psbtBase64,
    required int requiredSigs,
    loungepb.MultisigGroup? group,
  }) async => loungepb.ValidatePsbtResponse(
    error: foreignPacket && group != null ? 'input does not match the selected group' : '',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  _Orchestrator({required this.watchWalletLoaded, required bool foreignPacket})
    : multisigLounge = _Lounge(foreignPacket);

  bool watchWalletLoaded;

  @override
  final OrchestratorMultisigLoungeRPC multisigLounge;

  @override
  Future<orchestrationpb.CoreRawCallResponse> coreRawCall(
    String method, {
    String paramsJson = '',
    String wallet = '',
  }) async {
    final result = switch (method) {
      'decodepsbt' => {
        'fee': 0.00000028,
        'outputs': [
          {},
          {},
          {},
          {
            'bip32_derivs': [
              {'path': 'm/1/1100'},
            ],
          },
        ],
        'tx': {
          'vout': [
            {
              'value': 0.01234567,
              'scriptPubKey': {'address': 'first-recipient'},
            },
            {
              'value': 0.20000000,
              'scriptPubKey': {'address': 'group-change'},
            },
            {
              'value': 0.00000001,
              'scriptPubKey': {'address': 'second-recipient'},
            },
            {
              'value': 0.01000000,
              'scriptPubKey': {'address': 'far-change'},
            },
          ],
        },
      },
      'listwallets' => [if (watchWalletLoaded) 'test-watch'],
      'loadwallet' when jsonDecode(paramsJson).single == 'test-watch' => {'loaded': watchWalletLoaded = true},
      'listdescriptors' when wallet == 'test-watch' && watchWalletLoaded => {
        'descriptors': [
          {'desc': 'receive-descriptor', 'internal': false, 'active': true},
          {'desc': 'change-descriptor', 'internal': true, 'active': true},
        ],
      },
      'getaddressinfo' when wallet == 'test-watch' && watchWalletLoaded => switch (jsonDecode(paramsJson).single) {
        'first-recipient' => {'ischange': true, 'parent_desc': 'receive-descriptor'},
        'group-change' => {'ischange': true, 'parent_desc': 'change-descriptor'},
        _ => {'ischange': false},
      },
      'deriveaddresses' when paramsJson == '["change-descriptor",[1100,1100]]' => ['far-change'],
      _ => throw StateError('Unexpected Core call: $method'),
    };
    return orchestrationpb.CoreRawCallResponse(resultJson: jsonEncode(result));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  Stream<Uint8List> readAsByteStream() => file.openRead().map(Uint8List.fromList);
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

Finder _button(String label) => find.byWidgetPredicate((widget) => widget is SailButton && widget.label == label);

void main() {
  for (final (description, owner, watchWalletLoaded, foreignPacket, initialCosigner, initialExport) in [
    ('keeps payments from the initial file', 'Initial', true, false, false, false),
    ('keeps payments from a cosigner file', 'Bob', true, false, false, false),
    ('loads the watch wallet to find change', 'Bob', false, false, false, false),
    ('refuses an initial file from another group', 'Initial', true, true, false, false),
    ('assigns a legacy file to the cosigner named Initial', 'Initial', true, false, true, false),
    ('keeps an explicit initial export separate from that cosigner', 'Initial', true, false, true, true),
  ]) {
    testWidgets('PSBT import $description', (tester) async {
      final bitwindow = _Bitwindow(_group(initialCosigner: initialCosigner));
      GetIt.I.registerSingleton<BitwindowRPC>(bitwindow);
      GetIt.I.registerSingleton<OrchestratorRPC>(
        _Orchestrator(watchWalletLoaded: watchWalletLoaded, foreignPacket: foreignPacket),
      );
      addTearDown(GetIt.I.reset);
      final directory = Directory.systemTemp.createTempSync('multisig-import-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/unsigned.json');
      await tester.runAsync(
        () => file.writeAsString(
          jsonEncode({
            'transaction_id': 'draft',
            'psbt': 'unsigned-packet',
            'is_signed': false,
            'key_owner': owner,
            if (initialExport) 'is_initial': true,
            'exported_at': '2026-11-25T00:00:00Z',
          }),
        ),
      );
      final previousPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _Picker(file);
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      final groups = await MultisigStorage.loadGroups();
      tester.view.physicalSize = const Size(1024, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var imported = false;
      await tester.pumpWidget(
        SailTheme(
          data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ImportPSBTModal(
                      availableGroups: groups,
                      onImportSuccess: () => imported = true,
                    ),
                  ),
                  child: const Text('Open import'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Select Group'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(_button('Choose File'));
        for (var i = 0; i < 20 && !tester.any(find.text('unsigned.json')); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('unsigned.json'), findsOneWidget);
      await tester.tap(_button('Import'));
      await tester.pumpAndSettle();

      if (foreignPacket) {
        expect(imported, isFalse);
        expect(bitwindow.multisig.transaction, isNull);
        expect(find.textContaining('input does not match the selected group'), findsOneWidget);
        return;
      }

      expect(imported, isTrue);
      final saved = bitwindow.multisig.transaction!;
      final cosignerPacket = saved.keyPsbts.singleWhere((item) => item.keyId == 'bob').psbt;
      expect(cosignerPacket, owner == 'Bob' || (initialCosigner && !initialExport) ? 'unsigned-packet' : '');
      expect(saved.initialPsbt, 'unsigned-packet');
      expect(saved.fee, 0.00000028);
      expect((saved.amount * 100000000).round(), 1234568);
      expect(saved.destination, 'first-recipient, second-recipient');
      expect(saved.keyPsbts.singleWhere((item) => item.keyId == 'alice').psbt, 'unsigned-packet');
      expect(saved.keyPsbts.every((item) => !item.isSigned), isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }
}
