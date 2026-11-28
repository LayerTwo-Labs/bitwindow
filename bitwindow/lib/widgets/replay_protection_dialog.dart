import 'package:bitwindow/widgets/send_panel_parts.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

/// What the user chose when a send would spend coins that exist on both chains.
enum ReplayChoice { cancel, sendPlain, sendProtected }

/// Asks before a send spends coins that exist on both chains, and offers
/// replay protection for that one transaction.
Future<ReplayChoice> askReplayProtection(
  BuildContext context, {
  required List<UnspentOutput> coins,
  bool coinsKnown = true,
}) async {
  final choice = await showThemedDialog<ReplayChoice>(
    context: context,
    builder: (context) => SignDialog(
      title: coinsKnown && coins.length == 1 ? 'This coin exists on both chains' : 'These coins exist on both chains',
      subtitle: coinsKnown
          ? 'Spending them makes the same transaction on the other chain.'
          : 'The wallet did not report its coins yet, so this send can spend one that exists on both chains.',
      onClose: () async => Navigator.of(context).pop(ReplayChoice.cancel),
      menuItems: () => [
        sendMenuItem(context, 'Send without protection', () => Navigator.of(context).pop(ReplayChoice.sendPlain)),
      ],
      button: SailButton(
        label: 'Enable replay protection',
        onPressed: () async => Navigator.of(context).pop(ReplayChoice.sendProtected),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coinsKnown) ...[
            _CoinList(coins: coins),
            const SizedBox(height: SailStyleValues.padding16),
          ],
          SailText.primary13(
            'Replay protection keeps this transaction on this chain only. The other chain rejects it.',
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    ),
  );
  return choice ?? ReplayChoice.cancel;
}

/// The coins of the send, with their count and total on top. Scrolls once the
/// list passes five rows, so a big send keeps the dialog short.
class _CoinList extends StatelessWidget {
  final List<UnspentOutput> coins;

  const _CoinList({required this.coins});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I.get<FormatterProvider>();
    final total = coins.fold<int>(0, (sum, c) => sum + c.valueSats.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Row(
          left: coins.length == 1 ? '1 coin' : '${coins.length} coins',
          right: formatter.formatSats(total),
          muted: true,
        ),
        const SizedBox(height: SailStyleValues.padding08),
        SailDetailGroup(
          fill: SailDetailFill.canvas,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 110),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: coins
                      .map(
                        (c) => _Row(
                          left: formatter.formatSats(c.valueSats.toInt()),
                          right: _shortAddress(c.address),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String left;
  final String right;
  final bool muted;

  const _Row({required this.left, required this.right, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SailStyleValues.padding04),
      child: Row(
        children: [
          if (muted) SailText.secondary12(left, bold: true) else SailText.primary13(left, monospace: true),
          const Spacer(),
          if (muted)
            SailText.secondary12(right, bold: true, monospace: true)
          else
            SailText.secondary13(right, monospace: true),
        ],
      ),
    );
  }
}

String _shortAddress(String address) {
  if (address.length <= 14) {
    return address;
  }
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}
