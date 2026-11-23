import 'package:bitwindow/sidechains/sidepot/sidepot_bmm_note.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  const figures = [
    ('Bonus pool', '1 250 000 sats'),
    ('Bonus for the next block', '62 500 sats'),
    ('Fees in the next block', '1 200 sats'),
    ('Bid that earns it', '31 250 sats'),
    ('Profit if won', '32 450 sats'),
  ];

  testWidgets('the figures stay inside the note of a 1024 px window', (tester) async {
    const width = 694.0;
    await tester.pumpSailPage(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: SidepotBonusFigures(figures)),
      ),
    );

    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byType(SidepotBonusFigures));
    for (final (label, value) in figures) {
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(box.right), reason: label);
      expect(tester.getRect(find.text(value)).right, lessThanOrEqualTo(box.right), reason: value);
    }
    expect(tester.getRect(find.text('Profit if won')).top, greaterThan(tester.getRect(find.text('Bonus pool')).top));
  });
}
