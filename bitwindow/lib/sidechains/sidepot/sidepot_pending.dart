import 'dart:convert';

import 'package:sail_ui/sail_ui.dart';

/// What a move this wallet sent is: a buy or a cash-out travels as data in an
/// eCash transaction, a move into the game is a Sidepot transaction.
enum PendingKind { buy, cashout, fund }

/// How far a sent move has got.
enum PendingStage {
  /// Sent, and not in a block yet.
  waiting,

  /// In an eCash block the node has not shown the outcome of yet.
  mined,

  /// Counted as of the newest eCash block. The next Sidepot block makes it final.
  counted,

  /// A later move of this account counted, so this one can no longer change anything.
  passed,

  /// In an eCash block the node has read, and the game did not take it.
  rejected,

  /// Its time ran out before it counted.
  expired,

  /// Final: nothing more to wait for.
  done,
}

/// One move this install sent, kept until its outcome is known.
class PendingMove {
  final PendingKind kind;

  /// The game account that made it.
  final String account;

  /// The eCash transaction that carries a buy or cash-out, or the Sidepot transaction of a move into the game.
  final String txid;

  /// A buy's or cash-out's place in the account's order of moves. The game takes each account's moves in
  /// this order and never one at or below the last it took.
  final int nonce;

  /// The last tick of the game clock at which a buy or cash-out counts.
  final int expires;
  final int keys;
  final int maxPriceSats;

  /// A cash-out's or a move's amount. A cash-out of 0 takes everything.
  final int amountSats;

  /// The node's eCash height when the move's transaction was first seen in a block, or 0.
  final int minedSeenAt;

  const PendingMove({
    required this.kind,
    required this.account,
    required this.txid,
    this.nonce = 0,
    this.expires = 0,
    this.keys = 0,
    this.maxPriceSats = 0,
    this.amountSats = 0,
    this.minedSeenAt = 0,
  });

  PendingMove seenMinedAt(int height) => PendingMove(
    kind: kind,
    account: account,
    txid: txid,
    nonce: nonce,
    expires: expires,
    keys: keys,
    maxPriceSats: maxPriceSats,
    amountSats: amountSats,
    minedSeenAt: height,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'account': account,
    'txid': txid,
    'nonce': nonce,
    'expires': expires,
    'keys': keys,
    'max_price_sats': maxPriceSats,
    'amount_sats': amountSats,
    'mined_seen_at': minedSeenAt,
  };

  static PendingMove? fromJson(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final kind = PendingKind.values.where((k) => k.name == json['kind']).firstOrNull;
    final account = json['account'];
    final txid = json['txid'];
    if (kind == null || account is! String || txid is! String || txid.isEmpty) {
      return null;
    }
    int n(String name) => (json[name] as num?)?.toInt() ?? 0;
    return PendingMove(
      kind: kind,
      account: account,
      txid: txid,
      nonce: n('nonce'),
      expires: n('expires'),
      keys: n('keys'),
      maxPriceSats: n('max_price_sats'),
      amountSats: n('amount_sats'),
      minedSeenAt: n('mined_seen_at'),
    );
  }
}

/// What the node and the wallet report, as far as the pending moves need it.
class PendingFacts {
  /// The account's last counted move after the last Sidepot block, and as of the newest eCash block.
  final int confirmedNonce;
  final int previewNonce;

  /// The game clock and the eCash height as of the newest eCash block the node has read.
  final int clock;
  final int height;

  /// The eCash transactions of this wallet that are in a block.
  final Set<String> minedTxids;

  /// The Sidepot transactions waiting for a Sidepot block, or null when the node could not list them.
  final Set<String>? sidepotMempool;

  const PendingFacts({
    required this.confirmedNonce,
    required this.previewNonce,
    required this.clock,
    required this.height,
    this.minedTxids = const {},
    this.sidepotMempool,
  });
}

/// How far `move` has got, from what the node and the wallet report.
///
/// The game says which move of an account counted last, not what became of each one. So a move is known to
/// have counted when it is that last one, and known to have been refused when its transaction is in an eCash
/// block the node has read past while the account's last counted move is still an earlier one. A move with a
/// later one counted after it is only known to be settled.
PendingStage stageOf(PendingMove move, PendingFacts facts) {
  if (move.kind == PendingKind.fund) {
    final mempool = facts.sidepotMempool;
    return mempool == null || mempool.contains(move.txid) ? PendingStage.waiting : PendingStage.done;
  }
  if (facts.confirmedNonce >= move.nonce) {
    return PendingStage.done;
  }
  if (facts.previewNonce == move.nonce) {
    return PendingStage.counted;
  }
  if (facts.previewNonce > move.nonce) {
    return PendingStage.passed;
  }
  // The node reads a block after the wallet may have: only a block it has read past settles a refusal.
  if (move.minedSeenAt > 0 && facts.height > move.minedSeenAt) {
    return PendingStage.rejected;
  }
  if (facts.clock > move.expires) {
    return PendingStage.expired;
  }
  return facts.minedTxids.contains(move.txid) ? PendingStage.mined : PendingStage.waiting;
}

/// The moves still worth keeping, each with the height its transaction was first seen mined at.
///
/// A final move is dropped. A refused or expired one stays, to be shown until it is dismissed.
List<PendingMove> settled(List<PendingMove> moves, PendingFacts facts) {
  final kept = <PendingMove>[];
  for (final move in moves) {
    if (stageOf(move, facts) == PendingStage.done) {
      continue;
    }
    final mined = move.kind != PendingKind.fund && move.minedSeenAt == 0 && facts.minedTxids.contains(move.txid);
    kept.add(mined && facts.height > 0 ? move.seenMinedAt(facts.height) : move);
  }
  return kept;
}

/// Whether a move can still change the balance, or already has as of the newest eCash block.
bool isOpen(PendingStage stage) => stage == PendingStage.waiting || stage == PendingStage.mined;

/// The game balance once the moves still open have counted, as near as it can be told: a buy at the present
/// price, which it pays if it counts in the next block with a buy, and never more than its own limit.
int balanceAfter(int balanceSats, int priceSats, List<PendingMove> moves, PendingFacts facts) {
  var balance = balanceSats;
  final open = moves.where((m) => isOpen(stageOf(m, facts))).toList()..sort((a, b) => a.nonce.compareTo(b.nonce));
  // A move into the game is credited by a Sidepot block, a buy or cash-out counts in an eCash block: which
  // comes first is not known, so the credit is taken first, as the larger balance is what the moves meet.
  for (final move in open.where((m) => m.kind == PendingKind.fund)) {
    balance += move.amountSats;
  }
  for (final move in open.where((m) => m.kind != PendingKind.fund)) {
    final debit = switch (move.kind) {
      PendingKind.buy => move.keys * priceSats,
      _ => move.amountSats == 0 ? balance : move.amountSats,
    };
    // The game takes a move only if the balance covers it.
    if (debit > 0 && debit <= balance) {
      balance -= debit;
    }
  }
  return balance;
}

/// The moves this install has sent and not yet seen settled, kept across restarts.
class SidepotPendingSetting extends SettingValue<String> {
  SidepotPendingSetting({super.newValue});

  @override
  String get key => 'sidepot_pending_moves';

  @override
  String defaultValue() => '';

  @override
  String toJson() => value;

  @override
  String? fromJson(String jsonString) => jsonString.isEmpty ? null : jsonString;

  @override
  SettingValue<String> withValue([String? value]) => SidepotPendingSetting(newValue: value);

  static String encode(List<PendingMove> moves) => jsonEncode(moves.map((m) => m.toJson()).toList());

  static List<PendingMove> decode(String text) {
    if (text.isEmpty) {
      return [];
    }
    try {
      final list = jsonDecode(text);
      return list is List ? list.map(PendingMove.fromJson).whereType<PendingMove>().toList() : [];
    } catch (_) {
      return [];
    }
  }
}
