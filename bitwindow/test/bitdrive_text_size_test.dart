import 'package:bitwindow/pages/wallet/bitdrive_page.dart';
import 'package:bitwindow/providers/bitdrive_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _RecordingBitDrive extends MockBitDriveAPI {
  final storedContents = <List<int>>[];

  @override
  Future<StoreFileResponse> storeFile({
    required List<int> content,
    String? filename,
    String? mimeType,
    bool encrypt = false,
    int? feeSatPerVbyte,
  }) async {
    storedContents.add(content);
    return StoreFileResponse();
  }
}

class _Api extends MockAPI {
  _Api() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final recorder = _RecordingBitDrive();

  @override
  BitDriveAPI get bitdrive => recorder;
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? get activeWalletId => 'qa';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder textField() => find.descendant(
  of: find.byWidgetPredicate((w) => w is SailTextField && w.hintText == 'Write anything here...'),
  matching: find.byType(EditableText),
);

Finder storeButton() => find.byWidgetPredicate((w) => w is SailButton && w.label == 'Store on Bitcoin');

void main() {
  late _Api api;
  late BitDriveProvider provider;

  setUp(() async {
    await GetIt.I.reset();
    api = _Api();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    await registerTestDependencies();
    provider = BitDriveProvider();
    GetIt.I.registerSingleton<BitDriveProvider>(provider);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  final oversize = 'small text${'a' * BitDriveProvider.maxContentBytes}';

  test('an oversize text drops the earlier text', () async {
    await provider.setTextContent('small text');
    await provider.setTextContent(oversize);

    expect(provider.textContent, isNull);
    await expectLater(provider.store(), throwsException);
    expect(api.recorder.storedContents, isEmpty);
  });

  testWidgets('an oversize text shows the size error and disables Store', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(const BitDriveTab());
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(textField(), 'small text');
    await tester.pump();
    expect((tester.widget(storeButton()) as SailButton).disabled, isFalse);

    await tester.enterText(textField(), oversize);
    await tester.pump();

    expect(find.text(BitDriveProvider.textSizeError), findsOneWidget);
    expect((tester.widget(storeButton()) as SailButton).disabled, isTrue);

    await tester.enterText(textField(), 'small text');
    await tester.pump();

    expect(find.text(BitDriveProvider.textSizeError), findsNothing);
    expect((tester.widget(storeButton()) as SailButton).disabled, isFalse);
  });
}
