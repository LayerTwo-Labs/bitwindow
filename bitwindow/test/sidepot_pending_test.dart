import 'package:bitwindow/sidechains/sidepot/sidepot_pending.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = 'spot:aa';

PendingMove _buy(int nonce, {int keys = 1, int minedSeenAt = 0, int expires = 103}) => PendingMove(
  kind: PendingKind.buy,
  account: _account,
  txid: 'buy$nonce',
  nonce: nonce,
  expires: expires,
  keys: keys,
  maxPriceSats: 1100000,
  minedSeenAt: minedSeenAt,
);

PendingMove _cashout(int nonce, {int amount = 0}) => PendingMove(
  kind: PendingKind.cashout,
  account: _account,
  txid: 'out$nonce',
  nonce: nonce,
  expires: 244,
  amountSats: amount,
);

PendingFacts _facts({
  int confirmed = 4,
  int preview = 4,
  int clock = 100,
  int height = 500,
  Set<String> mined = const {},
  Set<String>? mempool,
}) => PendingFacts(
  confirmedNonce: confirmed,
  previewNonce: preview,
  clock: clock,
  height: height,
  minedTxids: mined,
  sidepotMempool: mempool,
);

void main() {
  test('a buy waits, is mined, counts, and is final', () {
    final buy = _buy(5);
    expect(stageOf(buy, _facts()), PendingStage.waiting);
    expect(stageOf(buy, _facts(mined: {'buy5'})), PendingStage.mined);
    expect(stageOf(buy, _facts(preview: 5, mined: {'buy5'})), PendingStage.counted);
    expect(stageOf(buy, _facts(confirmed: 5, preview: 5)), PendingStage.done);
  });

  test('a mined buy is refused only once the node has read past the block it was seen in', () {
    final seen = settled([_buy(5)], _facts(mined: {'buy5'})).single;
    expect(seen.minedSeenAt, 500);
    expect(stageOf(seen, _facts(mined: {'buy5'})), PendingStage.mined);
    expect(stageOf(seen, _facts(height: 501, clock: 101, mined: {'buy5'})), PendingStage.rejected);
    // The node was only behind: it counts the move after all.
    expect(stageOf(seen, _facts(height: 501, clock: 101, preview: 5, mined: {'buy5'})), PendingStage.counted);
  });

  test('a buy that is never mined expires, and one a later move passed is settled', () {
    expect(stageOf(_buy(5), _facts(clock: 104)), PendingStage.expired);
    expect(stageOf(_buy(5), _facts(preview: 6)), PendingStage.passed);
  });

  test('final moves are dropped and the others kept', () {
    final kept = settled([_buy(4), _buy(5), _buy(6, expires: 90)], _facts());
    expect(kept.map((m) => m.txid), ['buy5', 'buy6']);
  });

  test('a move into the game waits while the node holds its transaction', () {
    const fund = PendingMove(kind: PendingKind.fund, account: _account, txid: 'f1', amountSats: 300000);
    expect(stageOf(fund, _facts()), PendingStage.waiting, reason: 'the node could not list its transactions');
    expect(stageOf(fund, _facts(mempool: {'f1'})), PendingStage.waiting);
    expect(stageOf(fund, _facts(mempool: {})), PendingStage.done);
  });

  test('the balance after the open moves: buys in order, then a cash-out of everything', () {
    final facts = _facts();
    expect(balanceAfter(3500000, 1000000, [_buy(5), _buy(6)], facts), 1500000);
    expect(balanceAfter(3500000, 1000000, [_buy(5), _cashout(6)], facts), 0);
    expect(balanceAfter(3500000, 1000000, [_cashout(5, amount: 500000)], facts), 3000000);
  });

  test('a move the balance does not cover is left out, as the game refuses it', () {
    final facts = _facts();
    expect(balanceAfter(1500000, 1000000, [_buy(5), _buy(6)], facts), 500000);
    expect(balanceAfter(1500000, 1000000, [_buy(5), _cashout(6, amount: 900000)], facts), 500000);
  });

  test('a pending move into the game is counted before the buys it pays for', () {
    const fund = PendingMove(kind: PendingKind.fund, account: _account, txid: 'f1', amountSats: 1000000);
    expect(balanceAfter(500000, 1000000, [_buy(5), fund], _facts(mempool: {'f1'})), 500000);
  });

  test('moves that have counted or failed no longer change the figure', () {
    expect(balanceAfter(2000000, 1000000, [_buy(5)], _facts(preview: 5)), 2000000);
    expect(balanceAfter(2000000, 1000000, [_buy(5)], _facts(clock: 104)), 2000000);
  });

  test('the saved list reads back, and a damaged one reads as empty', () {
    final moves = [_buy(5, keys: 3), _cashout(6, amount: 42)];
    final back = SidepotPendingSetting.decode(SidepotPendingSetting.encode(moves));
    expect(back.map((m) => m.toJson()), moves.map((m) => m.toJson()));
    expect(SidepotPendingSetting.decode('{not json'), isEmpty);
    expect(SidepotPendingSetting.decode('[{"kind":"buy"}]'), isEmpty);
  });
}
