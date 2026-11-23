import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// The block bonus rules. The eCash block that takes a bid pays the block's
/// producer [bonusBidMultiple] times the bid out of the bonus pool, at most
/// [bonusPoolBps] of the pool, and nothing for a bid under [bonusMinBidSats].
const int bonusPoolBps = 500;
const int bonusBidMultiple = 2;
const int bonusMinBidSats = 10000;

/// The most one block can earn from a bonus pool.
int bonusCapSats(int poolSats) => poolSats <= 0 ? 0 : poolSats * bonusPoolBps ~/ 10000;

/// The smallest bid that earns the whole [capSats].
int bonusOpeningBidSats(int capSats) {
  final half = (capSats + bonusBidMultiple - 1) ~/ bonusBidMultiple;
  return half > bonusMinBidSats ? half : bonusMinBidSats;
}

/// What a won block pays for a bid of [bidSats].
int bonusForBidSats(int capSats, int bidSats) {
  if (bidSats < bonusMinBidSats) {
    return 0;
  }
  final byBid = bidSats * bonusBidMultiple;
  return byBid < capSats ? byBid : capSats;
}

String _grouped(int sats) {
  final digits = sats.abs().toString();
  final out = StringBuffer(sats < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(' ');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// What the BMM tab says about bidding for Sidepot blocks: the bonus on offer,
/// the bid that earns it, and where the bonus goes.
class SidepotBmmNote extends StatefulWidget {
  const SidepotBmmNote({super.key});

  @override
  State<SidepotBmmNote> createState() => _SidepotBmmNoteState();
}

class _SidepotBmmNoteState extends State<SidepotBmmNote> {
  SidepotRPC get _rpc => GetIt.I.get<SidepotRPC>();

  Timer? _timer;
  bool _reading = false;
  int? _poolSats;
  int _feesSats = 0;
  String? _account;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_read()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      final game = await _rpc.callRAW('game_state');
      final account = await _rpc.callRAW('game_my_account');
      // What the transactions waiting on the sidechain pay the block's producer.
      final template = await _rpc.callRAW('get_block_template');
      if (!mounted) {
        return;
      }
      // The pool as of the newest eCash block the node has read, when it gives one.
      final now = game is Map && game['preview'] is Map ? game['preview'] : game;
      setState(() {
        _poolSats = now is Map ? (now['bonus_pool_sats'] as num?)?.toInt() : null;
        _account = account is Map ? account['key'] as String? : null;
        _feesSats = template is Map ? (template['fees_sats'] as num?)?.toInt() ?? 0 : 0;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _poolSats = null);
      }
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final pool = _poolSats;
    final cap = bonusCapSats(pool ?? 0);
    final opening = bonusOpeningBidSats(cap);
    final worth = cap + _feesSats;
    final profit = worth - opening;
    final account = _account;

    String sats(int value) => pool == null ? '—' : '${_grouped(value)} sats';

    final String advice;
    if (pool == null) {
      advice = 'Waiting for the Sidepot node to report the game.';
    } else if (profit > 0) {
      advice =
          'Auto-bidding opens at ${_grouped(opening)} sats, the smallest bid that earns the whole bonus, and raises '
          'against other bidders up to your max bid. Above ${_grouped(worth)} sats a won block costs more than it '
          'pays.';
    } else {
      advice =
          'Auto-bidding is waiting and places no bid: the next block is worth ${_grouped(worth)} sats, under the '
          '${_grouped(opening)} sat bid it takes. Current slot stays empty until that changes. The bonus pool grows '
          'as keys are bought.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SailStyleValues.padding16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailText.primary13('Block bonus', bold: true),
          SailRow(
            spacing: SailStyleValues.padding64,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Figure('Bonus pool', sats(pool ?? 0)),
              _Figure('Bonus for the next block', sats(cap)),
              _Figure('Fees in the next block', sats(_feesSats)),
              _Figure('Bid that earns it', sats(opening)),
              _Figure('Profit if won', pool == null || profit <= 0 ? '—' : sats(profit)),
            ],
          ),
          SailText.secondary13(
            'The eCash block that takes your bid pays the producer of the Sidepot block twice the bid, up to 5% of '
            'the bonus pool. A bid under ${_grouped(bonusMinBidSats)} sats earns nothing.',
          ),
          SailText.secondary13(advice),
          SailText.secondary13(
            account == null
                ? 'The bonus goes to the game account of this wallet.'
                : 'The bonus goes to your game account, spot:${account.substring(0, 8)}…, a few blocks after the '
                      'one you win. Cash it out from the Game tab.',
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;

  const _Figure(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding04,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.secondary13(label),
        SailText.primary20(value, bold: true),
      ],
    );
  }
}
