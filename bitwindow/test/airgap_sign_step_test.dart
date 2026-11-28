import 'package:bitwindow/widgets/airgap_sign_step.dart';
import 'package:bitwindow/widgets/ur_qr_scanner.dart' show urCameraScanSupported;
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _unsignedPsbt =
    'cHNidP8BAHECAAAAAfrxs4O1d0Fw5EbFFqHZ9aOjCXx5s2pPYl5wL9QcF2u6AAAAAAD9////AoCWmAAAAAAAFgAUdBPeN7LqUbDX2iYcJ+JkHLvS4bbYxdQXAAAAABYAFM8A+FQwFOsNOo+uKP0jlUk25DxZAAAAAAAAAAA=';

void main() {
  testWidgets('the export step has one button, its file actions in "…" and a ×', (tester) async {
    var cancels = 0;
    await tester.pumpSailPage(
      Center(
        child: SizedBox(
          width: 560,
          height: 400,
          child: AirgapSignStep(
            unsignedPsbtBase64: _unsignedPsbt,
            onSigned: (_) {},
            onCancel: () => cancels++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(SailButton), findsOneWidget);
    expect(find.text('Next: import signed').hitTestable(), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Copy base64'), findsOneWidget);
    expect(find.text('Save .psbt'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Next: import signed').hitTestable());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Or paste signed PSBT (base64)'), findsOneWidget);
    expect(find.text('Confirm signed'), findsOneWidget);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Load from file'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.arrowLeft));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Next: import signed'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x));
    await tester.pump();
    expect(cancels, 1);
  });

  testWidgets('typing a signed PSBT while the scanner runs turns Confirm signed back on', (tester) async {
    String? signed;
    await tester.pumpSailPage(
      Center(
        child: SizedBox(
          width: 560,
          height: 600,
          child: AirgapSignStep(
            unsignedPsbtBase64: _unsignedPsbt,
            onSigned: (psbt) => signed = psbt,
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Next: import signed').hitTestable());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Scan signed QR'));
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    expect(tester.widget<SailButton>(find.byType(SailButton)).disabled, isTrue);

    await tester.enterText(find.byType(TextField), _unsignedPsbt);
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    expect(tester.widget<SailButton>(find.byType(SailButton)).disabled, isFalse);

    await tester.tap(find.text('Confirm signed').hitTestable());
    await tester.pump();
    expect(signed, _unsignedPsbt);
  }, skip: !urCameraScanSupported);
}
