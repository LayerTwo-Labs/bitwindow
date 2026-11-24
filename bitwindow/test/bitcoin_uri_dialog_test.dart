import 'package:bitwindow/pages/wallet/bitcoin_uri_dialog.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _address = 'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297';

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('a long address wraps, and no part of it is cut off', (tester) async {
    await tester.pumpSailPage(const Center(child: BitcoinURIDialog()));
    await tester.enterText(find.byType(EditableText), 'bitcoin:$_address?amount=1.23&label=Rent');
    await tester.pump();

    final line = find.text('Address: $_address');
    expect(line, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: line, matching: find.byType(RichText), matchRoot: true),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getSize(line).height, greaterThan(tester.getSize(find.text('Amount: 1.2300,0000 BTC')).height));
  });
  testWidgets('A malformed URI amount disables Use', (tester) async {
    await tester.pumpSailPage(const Center(child: BitcoinURIDialog()));

    final input = find.byType(EditableText);
    final use = find.widgetWithText(SailButton, 'Use');
    await tester.enterText(input, 'bitcoin:$_address?amount=0.00000001');
    await tester.pump();
    expect(tester.widget<SailButton>(use).disabled, isFalse);

    await tester.enterText(input, 'bitcoin:$_address?amount=1=2');
    await tester.pump();
    expect(tester.widget<SailButton>(use).disabled, isTrue);
    expect(find.textContaining('Invalid amount format'), findsOneWidget);
  });
}
