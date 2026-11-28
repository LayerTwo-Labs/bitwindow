import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/shell.dart';

final _theme = SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2);

Widget _app() => MaterialApp(
  home: SailTheme(
    data: _theme,
    child: Scaffold(
      body: MessagingView(
        noun: 'BitName',
        resolveEncryptionKey: (input) => input == 'bo' ? 'enc1bo' : null,
        encrypt: ({required msg, required encryptionPubkey}) async => 'cipher:$encryptionPubkey:$msg',
        decrypt: ({required ciphertext, required encryptionPubkey}) async => 'plain',
      ),
    ),
  ),
);

void main() {
  testWidgets('Encrypt and Decrypt sit side by side with a 12 px gap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    final encrypt = find.widgetWithText(SailCard, 'Encrypt').first;
    final decrypt = find.widgetWithText(SailCard, 'Decrypt').first;
    expect(tester.getTopLeft(decrypt).dx - tester.getTopRight(encrypt).dx, SailStyleValues.padding12);
    expect(tester.getTopLeft(decrypt).dy, tester.getTopLeft(encrypt).dy);
  });

  testWidgets('the ciphertext shows in full under the Encrypt button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    await tester.enterText(find.byType(EditableText).at(0), 'bo');
    await tester.enterText(find.byType(EditableText).at(1), 'Meet me at block 980,000.');
    await tester.tap(find.widgetWithText(SailButton, 'Encrypt'));
    await tester.pumpAndSettle();

    expect(find.text('cipher:enc1bo:Meet me at block 980,000.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('cipher:enc1bo:Meet me at block 980,000.')).dy,
      greaterThan(tester.getBottomLeft(find.widgetWithText(SailButton, 'Encrypt')).dy),
    );
  });

  testWidgets('a phone stacks Decrypt under Encrypt', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    await tester.pumpWidget(_app());

    expect(
      tester.getTopLeft(find.text('Decrypt a message using your pubkey')).dy,
      greaterThan(tester.getBottomLeft(find.widgetWithText(SailButton, 'Encrypt')).dy),
    );
  });
}
