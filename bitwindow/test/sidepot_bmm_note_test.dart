import 'package:bitwindow/sidechains/sidepot/sidepot_bmm_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the bonus is 5% of the pool, earned in full by half of it', () {
    final cap = bonusCapSats(1130019);
    expect(cap, 56500);
    expect(bonusOpeningBidSats(cap), 28250);
    expect(bonusForBidSats(cap, 28250), 56500);
    expect(bonusForBidSats(cap, 20000), 40000);
  });

  test('a small pool still takes the minimum bid, and pays less than it', () {
    final cap = bonusCapSats(186915);
    expect(cap, 9345);
    expect(bonusOpeningBidSats(cap), 10000);
    expect(bonusForBidSats(cap, 10000), 9345);
    expect(bonusForBidSats(cap, 9999), 0);
  });

  test('an odd cap rounds the bid up', () {
    expect(bonusOpeningBidSats(25001), 12501);
    expect(bonusForBidSats(25001, 12501), 25001);
  });
}
