import 'package:bitwindow/widgets/hash_calculator_modal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _sha256d = '4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358';

void main() {
  tearDown(() {
    SailStyleValues.phoneLayoutOverride = null;
    return GetIt.I.reset();
  });

  Future<void> pumpCalculator(WidgetTester tester) async {
    await tester.pumpSailPage(const HashCalculator());
    await tester.enterText(find.byType(EditableText).first, 'abc');
    await tester.pumpAndSettle();
  }

  Future<void> pumpPhone(WidgetTester tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await loadBundledFonts();
    await tester.pumpSailPage(const HashCalculator());
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.enterText(find.byType(EditableText).first, 'abc');
    await tester.pumpAndSettle();
  }

  Finder menu() => find.byType(SailRowMenuButton);

  testWidgets('the Input card head holds Hex, HMAC, "…" and the ? help', (tester) async {
    await pumpCalculator(tester);

    final title = tester.getRect(find.text('Input'));
    for (final part in [find.text('Hex'), find.text('HMAC'), menu(), find.byType(SailIconBoxButton).last]) {
      final rect = tester.getRect(part);
      expect(rect.center.dy, closeTo(title.center.dy, 8));
      expect(rect.left, greaterThan(title.right));
    }
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Paste'), findsNothing);
  });

  testWidgets('the "…" holds Clear and Paste, and Flip Bytes only in hex mode', (tester) async {
    await pumpCalculator(tester);

    await tester.tap(menu());
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Flip Bytes'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text(_sha256d), findsNothing);

    await tester.tap(find.text('Hex'));
    await tester.pumpAndSettle();
    await tester.tap(menu());
    await tester.pumpAndSettle();
    expect(find.text('Flip Bytes'), findsOneWidget);
  });

  testWidgets('a result is a grey label over its value with a copy icon at the right', (tester) async {
    await pumpCalculator(tester);

    final label = tester.getRect(find.text('SHA256D:'));
    final value = tester.getRect(find.text(_sha256d));
    expect(value.top, greaterThanOrEqualTo(label.bottom));
    expect(value.left, closeTo(label.left, 1));

    final copy = find.byWidgetPredicate((w) => w is CopyButton && w.text == _sha256d);
    expect(copy, findsOneWidget);
    expect(tester.getRect(copy).left, greaterThanOrEqualTo(value.right));
    expect(find.byType(CopyButton), findsNWidgets(8));
  });

  testWidgets('bad hex shows its error under the input', (tester) async {
    await pumpCalculator(tester);
    await tester.tap(find.text('Hex'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '68656c6c6');
    await tester.pumpAndSettle();

    final error = tester.getRect(find.text('Input: Invalid length'));
    expect(error.top, greaterThan(tester.getRect(find.byType(SailTextField).first).bottom));
    expect(find.byType(CopyButton), findsNothing);
  });

  testWidgets('the help is a dialog with a ×', (tester) async {
    await pumpCalculator(tester);

    await tester.tap(find.byType(SailIconBoxButton).last);
    await tester.pumpAndSettle();

    expect(find.text('Hash Calculator Help'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x), findsOneWidget);
  });

  testWidgets('on a phone the input controls fit at 390 px in hex and HMAC mode', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.text('Hex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HMAC'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final part in [find.text('Input'), find.text('Hex'), find.text('HMAC'), menu()]) {
      expect(tester.getRect(part).right, lessThanOrEqualTo(390));
    }
    expect(tester.getRect(find.byType(SailIconBoxButton).last).right, lessThanOrEqualTo(390));
    final hmac = tester.getRect(find.text('HMAC'));
    expect(tester.getRect(find.byType(SailTextField).first).top, greaterThan(hmac.bottom));
    expect(find.byType(SailTextField), findsNWidgets(2));
  });
}
