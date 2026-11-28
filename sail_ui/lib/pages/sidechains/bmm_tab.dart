import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/bmm/v1/bmm.pb.dart' as bmmpb;
import 'package:sidechain_core/utils/explorer_url.dart';

/// What light mode reads for a bid, which the bid controls say out loud.
const String bidSourceInLightMode =
    'Light mode reads the rival bids from the enforcer, and raises up to the ceiling. '
    'It reads no mainchain mempool, so a bid the enforcer never saw stays hidden.';

/// Reason bidding is unavailable, or null when it is allowed.
///
/// A bid commits to the tip the enforcer has validated, so one built while it
/// trails Bitcoin Core names a block miners have already built past and can
/// never be included. The orchestrator rejects those bids too — this only keeps
/// the controls from offering an action that cannot succeed.
String? bidBlockedReasonFor(SyncProvider sync, {bool lightMode = false}) {
  // Without Core the enforcer's goal falls back to its own height, which reads
  // as synced however far behind it is. A light install runs no Core at all,
  // and the remote validator it reads stands at the tip.
  if (!lightMode && (sync.mainchainSyncInfo == null || (sync.mainchainError?.isNotEmpty ?? false))) {
    return 'Waiting for Bitcoin Core';
  }
  final enforcer = sync.enforcerSyncInfo;
  if (enforcer == null || (sync.enforcerError?.isNotEmpty ?? false)) {
    return 'Waiting for the enforcer to start';
  }
  if (lightMode) {
    return lightEnforcerBlockedReason(sync, enforcer);
  }
  if (enforcer.isSynced) {
    return null;
  }
  return 'Enforcer is syncing — '
      '${enforcer.progressCurrent.toInt()} of ${enforcer.progressGoal.toInt()} blocks';
}

/// Reason the remote enforcer blocks a light-mode bid, null when it allows one.
///
/// Without Core the enforcer reports its own height as the goal, so it reads as
/// synced however far it trails. The wallet chain source carries the only other
/// mainchain tip a light install reads.
String? lightEnforcerBlockedReason(SyncProvider sync, SyncInfo enforcer) {
  final source = sync.chainSourceSyncInfo;
  if (source == null || (sync.chainSourceError?.isNotEmpty ?? false) || source.progressCurrent <= 0) {
    return 'Waiting for the wallet chain source';
  }
  if (enforcer.progressCurrent >= source.progressCurrent) {
    return null;
  }
  return 'Enforcer is syncing — '
      '${enforcer.progressCurrent.toInt()} of ${source.progressCurrent.toInt()} blocks';
}

final NumberFormat _thousands = NumberFormat('#,##0', 'en_US');

/// Digits in groups of three, split by a thin space that never breaks a line.
String groupDigits(int value) => _thousands.format(value).replaceAll(',', '\u2009');

/// A hash cut to its first characters, so a table cell holds it on one line.
String shortenHash(String hash) {
  if (hash.isEmpty) {
    return '—';
  }
  return hash.length > 16 ? '${hash.substring(0, 16)}..' : hash;
}

/// A sidechain block hash in the h* form the enforcer and the miners use.
String shortenCriticalHash(String hash) {
  if (hash.isEmpty) {
    return '—';
  }
  return hash.length > 8 ? 'h*${hash.substring(0, 8)}..' : 'h*$hash';
}

const String bidStateWaiting = 'Waiting for a miner';
const String bidStateConnected = 'Connected';
const String bidStateNotIncluded = 'Not included';
const String bidStateSkipped = 'Skipped';

/// One row of the historic bids table: our bid for a round, and its outcome.
class HistoricBid {
  final String prevMainHash;
  final String state;
  final int bidSats;
  final int blockFeesSats;
  final int? profitSats;
  final String txid;
  final String mainchainBlock;

  const HistoricBid({
    required this.prevMainHash,
    required this.state,
    required this.bidSats,
    required this.blockFeesSats,
    required this.profitSats,
    required this.txid,
    required this.mainchainBlock,
  });
}

String historicBidState(String result) => switch (result) {
  'won' => bidStateConnected,
  'lost' => bidStateNotIncluded,
  'skipped' => bidStateSkipped,
  _ => bidStateWaiting,
};

SailStatusTone historicBidStateTone(String state) => switch (state) {
  bidStateConnected => SailStatusTone.success,
  bidStateNotIncluded => SailStatusTone.error,
  bidStateWaiting => SailStatusTone.warning,
  _ => SailStatusTone.neutral,
};

Color? historicBidStateColor(String state, SailColor colors) => switch (state) {
  bidStateConnected => colors.success,
  bidStateWaiting => colors.orange,
  _ => colors.textSecondary,
};

/// Our bids on the rounds the chain already decided, newest first. A round we
/// never bid on has no row, and the round in play stays in the current slot.
List<HistoricBid> historicBids(
  bmmpb.Round? current,
  List<bmmpb.Round> history,
) {
  final rows = <HistoricBid>[];
  final seen = <String>{};
  if (current != null) {
    seen.add(current.prevMainHash);
  }
  for (final round in history) {
    final bid = round.ourBids.lastOrNull;
    if (bid == null || !seen.add(round.prevMainHash)) {
      continue;
    }
    rows.add(
      HistoricBid(
        prevMainHash: round.prevMainHash,
        state: historicBidState(round.result),
        bidSats: bid.bidSats.toInt(),
        blockFeesSats: round.blockWorthSats.toInt(),
        profitSats: round.hasProfit ? round.profitSats.toInt() : null,
        txid: bid.txid,
        // Only a bid a miner took rides in a block. A lost round names the
        // winner's block, which was never ours.
        mainchainBlock: round.result == 'won' ? round.includedInBlock : '',
      ),
    );
  }
  return rows;
}

String profitLabel(int? sats) {
  if (sats == null) {
    return '—';
  }
  return sats < 0 ? '-${groupDigits(-sats)}' : '+${groupDigits(sats)}';
}

/// A round the chain left behind pays no fees back, so it returns the bid as a
/// loss.
Color? profitColor(int? profitSats, SailColor colors) {
  if (profitSats == null) {
    return null;
  }
  return profitSats < 0 ? colors.error : colors.success;
}

class BMMTab extends StatelessWidget {
  /// The engine the tab drives. The engine of the open sidechain when null.
  final BMMProvider? provider;

  /// What the open chain says about bidding on it, shown above the controls.
  final Widget? note;

  const BMMTab({super.key, this.provider, this.note});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder.reactive(
      viewModelBuilder: () => BMMViewModel(provider: provider),
      builder: (context, viewModel, child) {
        if (SailStyleValues.phoneLayout(context)) {
          return SailCard(
            title: 'BMM',
            subtitle: 'Bid on the parent chain to mine a ${viewModel.chainName} block',
            error: viewModel.bmmError,
            // The two tables grow with the rounds they list, so the tab scrolls.
            child: SingleChildScrollView(
              child: SailColumn(
                spacing: SailStyleValues.padding16,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ?note,
                  BmmControls(viewModel: viewModel),
                  BMMCurrentSlot(viewModel: viewModel),
                  _BidsOnNextBlock(viewModel: viewModel),
                  _HistoricBids(viewModel: viewModel),
                ],
              ),
            ),
          );
        }
        return BmmPageBody(viewModel: viewModel, note: note);
      },
    );
  }
}

/// Below this height the two tables get their row height and the page scrolls.
const double bmmFillHeight = 640;

/// The desktop BMM tab: a head card with the bid controls, the current slot, and two table cards.
@visibleForTesting
class BmmPageBody extends StatelessWidget {
  final BMMViewModel viewModel;
  final Widget? note;

  const BmmPageBody({super.key, required this.viewModel, this.note});

  @override
  Widget build(BuildContext context) {
    final head = [
      ?note,
      SailCard(
        child: _BmmHead(viewModel: viewModel),
      ),
      SailCard(child: BMMCurrentSlot(viewModel: viewModel)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight && constraints.maxHeight >= bmmFillHeight) {
          return SailColumn(
            spacing: SailStyleValues.padding12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...head,
              Expanded(
                child: SailCard(child: _BidsOnNextBlock(viewModel: viewModel, fill: true)),
              ),
              Expanded(
                child: SailCard(child: _HistoricBids(viewModel: viewModel, fill: true)),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          key: const ValueKey('bmm-page-scroll'),
          child: SailColumn(
            spacing: SailStyleValues.padding12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...head,
              SailCard(child: _BidsOnNextBlock(viewModel: viewModel)),
              SailCard(child: _HistoricBids(viewModel: viewModel)),
            ],
          ),
        );
      },
    );
  }
}

/// The title of the tab at the left, the bid controls at the right.
class _BmmHead extends StatelessWidget {
  final BMMViewModel viewModel;

  const _BmmHead({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final error = viewModel.bmmError;
    final title = SailColumn(
      spacing: 2,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary15('BMM', bold: true),
        SailText.secondary13('Bid on the parent chain to mine a ${viewModel.chainName} block'),
        if (error != null) SailText.secondary12(error, color: theme.colors.error),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _bmmHeadRowWidth) {
          return SailColumn(
            spacing: SailStyleValues.padding12,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              BmmControls(viewModel: viewModel),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(padding: const EdgeInsets.only(bottom: 2), child: title),
            ),
            const SizedBox(width: SailStyleValues.padding16),
            BmmControls(viewModel: viewModel),
          ],
        );
      },
    );
  }
}

/// The width the head needs to hold the title and the controls on one row.
const double _bmmHeadRowWidth = 1000;

/// The bid controls: wallet, bounds, the auto-bid switch, and a "…" with the manual bid.
class BmmControls extends StatelessWidget {
  final BMMViewModel viewModel;
  const BmmControls({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final phone = SailStyleValues.phoneLayout(context);
    // Stopping stays available while the enforcer is behind: an engine started
    // before it fell back has to be stoppable.
    final blocked = !viewModel.canBid;
    final toggle = SailButton(
      label: viewModel.running ? 'Stop auto-bidding' : 'Start auto-bidding',
      disabled: blocked && !viewModel.running,
      onPressed: () async => viewModel.running ? await viewModel.stopBidding() : await viewModel.startBidding(),
    );
    final wallet = _Field(
      label: 'Wallet:',
      width: phone ? 220 : 200,
      child: WalletPicker(
        selectedWalletId: viewModel.fundingWalletId,
        onChanged: viewModel.setFundingWallet,
      ),
    );
    final minBid = _Field(
      label: 'Min bid:',
      width: phone ? 130 : 140,
      child: SailTextField(
        controller: viewModel.minBidController,
        hintText: '0.00005000',
        readOnly: true,
      ),
    );
    final maxBid = _Field(
      label: 'Max bid:',
      width: phone ? 130 : 140,
      child: SailTextField(
        controller: viewModel.maxBidController,
        hintText: '0.00020000',
      ),
    );
    final notes = [
      if (viewModel.isLight) SailText.secondary12(bidSourceInLightMode),
      if (viewModel.fundingWarning)
        SailText.secondary12(
          viewModel.fundingWarningLabel,
          color: colors.orange,
        ),
    ];

    if (phone) {
      return SailColumn(
        spacing: SailStyleValues.padding08,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: double.infinity, child: toggle),
          wallet,
          minBid,
          maxBid,
          SizedBox(
            width: double.infinity,
            child: SailButton(
              label: 'Bid manually',
              variant: ButtonVariant.secondary,
              disabled: blocked,
              onPressed: () async => _showManualBidDialog(context, viewModel),
            ),
          ),
          ...notes,
        ],
      );
    }

    return SailColumn(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailRow(
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SailRow(
              spacing: SailStyleValues.padding16,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [wallet, minBid, maxBid],
            ),
            toggle,
            SailRowMenuButton(
              items: () => [
                SailMenuItem(
                  onSelected: blocked ? null : () => unawaited(_showManualBidDialog(context, viewModel)),
                  child: SailText.primary13('Bid manually', color: blocked ? colors.textTertiary : null),
                ),
              ],
            ),
          ],
        ),
        ...notes,
      ],
    );
  }

  Future<void> _showManualBidDialog(BuildContext context, BMMViewModel viewModel) async {
    final controller = TextEditingController(
      text: viewModel.bmmProvider.suggestedBidSats.toString(),
    );
    final worth = viewModel.blockWorthSats;
    BuildContext? dialogContext;

    await widgetDialog(
      context: context,
      title: 'Manual bid',
      maxWidth: 440,
      action: SailDialogAction(
        label: 'Place bid',
        onPressed: () async {
          final sats = int.tryParse(controller.text.trim());
          Navigator.of(dialogContext!).pop();
          if (sats != null && sats > 0) {
            await viewModel.bmmProvider.bidManually(sats);
          }
        },
      ),
      child: Builder(
        builder: (context) {
          dialogContext = context;
          return SailColumn(
            spacing: SailStyleValues.padding12,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SailText.secondary13(
                'One bid for the next mainchain block. It costs nothing unless a miner takes it.',
              ),
              SailTextField(controller: controller, hintText: 'Bid in sats'),
              if (worth > 0)
                SailText.secondary12(
                  'This block is worth $worth sats. A bid above that loses money.',
                  color: SailTheme.of(context).colors.orange,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A label over its control on the desktop, beside it on a phone.
class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  final double width;

  const _Field({required this.label, required this.child, this.width = 130});

  @override
  Widget build(BuildContext context) {
    if (!SailStyleValues.phoneLayout(context)) {
      return SizedBox(
        width: width,
        child: SailColumn(
          spacing: SailStyleValues.padding04,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SailText.primary12(label, bold: true),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: child,
            ),
          ],
        ),
      );
    }
    return SailRow(
      spacing: SailStyleValues.padding08,
      children: [
        SailText.primary13(label),
        SizedBox(width: width, child: child),
      ],
    );
  }
}

/// The block being bid on: what it is worth, what we bid, what we stand to make.
@visibleForTesting
class BMMCurrentSlot extends StatelessWidget {
  final BMMViewModel viewModel;
  const BMMCurrentSlot({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final live = viewModel.bmmProvider.liveBid;
    final yourBid = live == null ? '—' : viewModel.satsLabel(live.bidSats.toInt());

    if (SailStyleValues.phoneLayout(context)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SailStyleValues.padding16),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SailColumn(
          spacing: SailStyleValues.padding08,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailRow(
              spacing: SailStyleValues.padding12,
              children: [
                SailText.primary13('Current slot', bold: true),
                SailBadge(viewModel.slotStatus, tone: viewModel.slotTone),
              ],
            ),
            if (viewModel.slotHint.isNotEmpty) SailText.secondary12(viewModel.slotHint),
            SailStatList(
              panel: false,
              children: [
                SailStatRow(title: 'Block worth', subtitle: '', value: viewModel.satsLabel(viewModel.blockWorthSats)),
                SailStatRow(title: 'Your bid', subtitle: '', value: yourBid),
                SailStatRow(title: 'Profit if won', subtitle: '', value: viewModel.satsLabel(viewModel.profitIfWon)),
                SailStatRow(title: 'Sidechain block ready', subtitle: '', value: viewModel.currentCriticalHash),
              ],
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SailColumn(
            spacing: SailStyleValues.padding08,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailRow(
                spacing: SailStyleValues.padding12,
                children: [
                  SailText.primary15('Current slot', bold: true),
                  SailStatusPill(label: viewModel.slotStatus, tone: viewModel.slotStatusTone),
                ],
              ),
              if (viewModel.slotHint.isNotEmpty) SailText.secondary13(viewModel.slotHint),
            ],
          ),
        ),
        const SizedBox(width: SailStyleValues.padding16),
        Flexible(
          child: Wrap(
            spacing: SailStyleValues.padding40,
            runSpacing: SailStyleValues.padding08,
            alignment: WrapAlignment.end,
            children: [
              SailStat(label: 'Block worth', value: viewModel.satsLabel(viewModel.blockWorthSats)),
              SailStat(label: 'Your bid', value: yourBid),
              SailStat(label: 'Profit if won', value: viewModel.satsLabel(viewModel.profitIfWon)),
              SailStat(label: 'Sidechain block ready', value: viewModel.currentCriticalHash),
            ],
          ),
        ),
      ],
    );
  }
}

/// A title over its explanation, with room for one action on the right.
class _SectionHead extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;

  const _SectionHead({
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    return SailRow(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SailColumn(
            spacing: phone ? 2 : SailStyleValues.padding08,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              phone ? SailText.primary14(title, bold: true) : SailText.primary15(title, bold: true),
              SailText.secondary13(subtitle),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

/// The border every table on this page sits inside on a phone. The desktop table sits on the card.
class _TableFrame extends StatelessWidget {
  final double height;
  final Widget child;

  const _TableFrame({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    if (!SailStyleValues.phoneLayout(context)) {
      return SizedBox(width: double.infinity, height: height, child: child);
    }
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// A hash that opens the mainchain explorer.
class _HashLink extends StatelessWidget {
  final String label;
  final String url;
  final Color? color;

  const _HashLink({required this.label, required this.url, this.color});

  @override
  Widget build(BuildContext context) {
    final tone = color ?? SailTheme.of(context).colors.info;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => unawaited(openUrl(Uri.parse(url))),
        child: SailRow(
          spacing: SailStyleValues.padding08,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Flexible(child: SailText.primary13(label, color: tone)),
            SailSVG.icon(
              SailSVGAsset.externalLink,
              color: tone,
              width: 12,
              height: 12,
            ),
          ],
        ),
      ),
    );
  }
}

/// A status dot before its label, as a table cell shows a state.
class _DotCell extends StatelessWidget {
  final String label;
  final SailStatusTone tone;

  const _DotCell({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SailStatusDot(tone: tone),
        const SizedBox(width: 6),
        Flexible(child: SailText.primary13(label, maxLines: 1)),
      ],
    );
  }
}

/// Height a bordered table takes: its header, plus one line per row.
double tableFrameHeight(int rows) => rows == 0 ? 100 : (rows * 40) + 42;

SailMenuItem _explorerItem(String label, String url) =>
    SailMenuItem(onSelected: () => unawaited(openUrl(Uri.parse(url))), child: SailText.primary13(label));

/// Every bid we can see for this round, highest first. Ours are marked rather
/// than reordered, so the running order of the auction stays readable.
class _BidsOnNextBlock extends StatelessWidget {
  final BMMViewModel viewModel;

  /// True lets the table take the height the card has, and scroll inside it.
  final bool fill;

  const _BidsOnNextBlock({required this.viewModel, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final phone = SailStyleValues.phoneLayout(context);
    final bids = viewModel.bmmProvider.currentBids;

    final table = SailTable(
      getRowId: (index) => bids[index].txid.isEmpty ? 'bid-$index' : bids[index].txid,
      emptyPlaceholder: 'No bids yet',
      headerBackgroundColor: phone ? colors.backgroundSecondary : null,
      headerBuilder: (context) => [
        SailTableHeaderCell(name: 'Bid (sats)', alignment: phone ? Alignment.centerLeft : Alignment.centerRight),
        SailTableHeaderCell(name: 'Bidder'),
        SailTableHeaderCell(name: 'Sidechain block (h*)'),
        SailTableHeaderCell(name: 'Prev mainchain block'),
        SailTableHeaderCell(name: 'Mainchain txid'),
        SailTableHeaderCell(name: 'Status'),
      ],
      rowBuilder: (context, row, selected) {
        final bid = bids[row];
        return [
          SailTableCell(
            value: groupDigits(bid.bidSats.toInt()),
            alignment: phone ? Alignment.centerLeft : Alignment.centerRight,
          ),
          SailTableCell(
            value: bid.isOurs ? 'You' : '—',
            textColor: bid.isOurs && phone ? colors.info : null,
          ),
          SailTableCell(value: shortenCriticalHash(bid.criticalHash)),
          SailTableCell(value: shortenHash(bid.prevMainHash)),
          SailTableCell(
            value: phone ? bid.txid : shortenHash(bid.txid),
            copyValue: bid.txid,
            child: bid.txid.isEmpty || !phone
                ? null
                : _HashLink(
                    label: shortenHash(bid.txid),
                    url: viewModel.txUrl(bid.txid),
                  ),
          ),
          _statusCell(bid, bids, colors, phone),
        ];
      },
      rowCount: bids.length,
      rowBackgroundColor: (index) => bids[index].isOurs && phone ? colors.info.withValues(alpha: 0.06) : null,
      drawLastRowsBorder: !phone,
      contextMenuItems: phone
          ? null
          : (rowId) {
              final bid = bids.firstWhere((b) => b.txid == rowId, orElse: () => bmmpb.Bid());
              return [
                if (bid.txid.isNotEmpty) _explorerItem('View on explorer', viewModel.txUrl(bid.txid)),
                if (bid.replacedByTxid.isNotEmpty)
                  _explorerItem('View replacement on explorer', viewModel.txUrl(bid.replacedByTxid)),
              ];
            },
      rowHasMenu: phone ? null : (rowId) => !rowId.startsWith('bid-'),
    );

    return SailColumn(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(
          title: 'Bids on next block',
          subtitle:
              'Every bid for slot ${viewModel.slot} in the mainchain mempool, highest first. '
              'Updates as bids arrive.',
        ),
        if (fill) Expanded(child: table) else _TableFrame(height: tableFrameHeight(bids.length), child: table),
      ],
    );
  }

  SailTableCell _statusCell(
    bmmpb.Bid bid,
    List<bmmpb.Bid> bids,
    SailColor colors,
    bool phone,
  ) {
    final replacement = bid.replacedByTxid;
    if (replacement.isNotEmpty && phone) {
      return SailTableCell(
        value: replacement,
        copyValue: replacement,
        child: _HashLink(
          label: 'Replaced by ${shortenHash(replacement)}',
          url: viewModel.txUrl(replacement),
          color: colors.orange,
        ),
      );
    }
    final status = viewModel.bidStatus(bid, bids);
    if (phone) {
      return SailTableCell(
        value: status,
        copyValue: bid.error.isEmpty ? null : bid.error,
        textColor: viewModel.bidStatusColor(bid, bids, colors),
      );
    }
    return SailTableCell(
      value: status,
      copyValue: replacement.isNotEmpty ? replacement : (bid.error.isEmpty ? null : bid.error),
      child: _DotCell(label: status, tone: viewModel.bidStatusTone(bid, bids)),
    );
  }
}

/// One row per bid we placed, newest first, with a drilldown to the round.
class _HistoricBids extends StatelessWidget {
  final BMMViewModel viewModel;

  /// True lets the table take the height the card has, and scroll inside it.
  final bool fill;

  const _HistoricBids({required this.viewModel, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final phone = SailStyleValues.phoneLayout(context);
    final rows = viewModel.historicRows;

    final table = SailTable(
      getRowId: (index) => rows[index].prevMainHash,
      emptyPlaceholder: 'No bids yet',
      headerBackgroundColor: phone ? colors.backgroundSecondary : null,
      headerBuilder: (context) => [
        SailTableHeaderCell(name: 'State'),
        SailTableHeaderCell(name: 'Bid (sats)', alignment: phone ? Alignment.centerLeft : Alignment.centerRight),
        SailTableHeaderCell(name: 'Block fees (sats)', alignment: phone ? Alignment.centerLeft : Alignment.centerRight),
        SailTableHeaderCell(name: 'Profit (sats)', alignment: phone ? Alignment.centerLeft : Alignment.centerRight),
        SailTableHeaderCell(name: 'Mainchain txid'),
        SailTableHeaderCell(name: 'Mainchain block'),
      ],
      rowBuilder: (context, row, selected) {
        final bid = rows[row];
        final numbers = phone ? Alignment.centerLeft : Alignment.centerRight;
        return [
          SailTableCell(
            value: bid.state,
            textColor: phone ? historicBidStateColor(bid.state, colors) : null,
            child: phone ? null : _DotCell(label: bid.state, tone: historicBidStateTone(bid.state)),
          ),
          SailTableCell(value: groupDigits(bid.bidSats), alignment: numbers),
          SailTableCell(value: groupDigits(bid.blockFeesSats), alignment: numbers),
          SailTableCell(
            value: profitLabel(bid.profitSats),
            textColor: profitColor(bid.profitSats, colors),
            alignment: numbers,
          ),
          SailTableCell(
            value: phone ? bid.txid : shortenHash(bid.txid),
            copyValue: bid.txid,
            child: bid.txid.isEmpty
                ? (phone ? null : SailText.primary13('—'))
                : !phone
                ? null
                : _HashLink(
                    label: shortenHash(bid.txid),
                    url: viewModel.txUrl(bid.txid),
                  ),
          ),
          SailTableCell(
            value: phone ? bid.mainchainBlock : shortenHash(bid.mainchainBlock),
            copyValue: bid.mainchainBlock,
            child: bid.mainchainBlock.isEmpty
                ? SailText.primary13('—', color: phone ? colors.textSecondary : null)
                : !phone
                ? null
                : _HashLink(
                    label: shortenHash(bid.mainchainBlock),
                    url: viewModel.blockUrl(bid.mainchainBlock),
                  ),
          ),
        ];
      },
      rowCount: rows.length,
      drawLastRowsBorder: !phone,
      contextMenuItems: (rowId) {
        final bid = rows.firstWhereOrNull((r) => r.prevMainHash == rowId);
        return [
          SailMenuItem(
            onSelected: () => viewModel.showAllBids(context, rowId),
            child: SailText.primary12('See all bids for block'),
          ),
          if (!phone && bid != null && bid.txid.isNotEmpty)
            _explorerItem('View on explorer', viewModel.txUrl(bid.txid)),
          if (!phone && bid != null && bid.mainchainBlock.isNotEmpty)
            _explorerItem('View block on explorer', viewModel.blockUrl(bid.mainchainBlock)),
        ];
      },
      onDoubleTap: (rowId) => viewModel.showAllBids(context, rowId),
    );

    final Widget? clear;
    if (rows.isEmpty) {
      clear = null;
    } else if (phone) {
      clear = SailButton(
        label: 'Clear history',
        variant: ButtonVariant.secondary,
        small: true,
        onPressed: () async => viewModel.bmmProvider.clearHistory(),
      );
    } else {
      clear = SailRowMenuButton(
        items: () => [
          SailMenuItem(
            onSelected: () => unawaited(viewModel.bmmProvider.clearHistory()),
            child: SailText.primary13('Clear history'),
          ),
        ],
      );
    }

    return SailColumn(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(
          title: 'Historic bids',
          subtitle: 'What your bids came to. A bid only costs anything once a miner takes it.',
          action: clear,
        ),
        if (fill)
          Expanded(child: table)
        else
          _TableFrame(
            height: phone ? tableFrameHeight(rows.length).clamp(100, 362) : tableFrameHeight(rows.length),
            child: table,
          ),
      ],
    );
  }
}

class BMMViewModel extends BaseViewModel {
  final BMMProvider bmmProvider;
  final BitcoinConfProvider _conf = GetIt.I.get<BitcoinConfProvider>();
  final SyncProvider _sync = GetIt.I.get<SyncProvider>();
  final NodeModeProvider? _nodeMode = GetIt.I.isRegistered<NodeModeProvider>() ? GetIt.I.get<NodeModeProvider>() : null;

  final TextEditingController maxBidController = TextEditingController();
  final TextEditingController minBidController = TextEditingController();

  BMMViewModel({BMMProvider? provider}) : bmmProvider = provider ?? GetIt.I.get<SidechainBMMProvider>() {
    maxBidController.text = bmmProvider.maxBidAmount.toStringAsFixed(8);
    maxBidController.addListener(_onMaxBound);
    minBidController.text = _minBidText;
    bmmProvider.addListener(_onProviderChanged);
    _sync.addListener(_onSyncChanged);
    _nodeMode?.addListener(_onSyncChanged);
  }

  String get chainName => bmmProvider.sidechainRPC.chain.name;
  int get slot => bmmProvider.sidechainRPC.chain.slot;

  bool get canBid => bidBlockedReason == null;
  bool get isLight => _nodeMode?.isLight ?? false;
  String? get bidBlockedReason => bidBlockedReasonFor(_sync, lightMode: isLight);

  bool get running => bmmProvider.running;
  String? get bmmError => bmmProvider.error ?? bmmProvider.lastBidError;

  String? get fundingWalletId => bmmProvider.fundingWalletId;
  void setFundingWallet(String walletId) => bmmProvider.setFundingWalletId(walletId);

  bool get fundingBalanceTooLow => bmmProvider.fundingBalanceTooLow;

  bool get fundingWarning => fundingWalletId == null || fundingBalanceTooLow;

  String get fundingWarningLabel {
    if (fundingWalletId == null) {
      return BMMProvider.noFundingWallet;
    }
    final sats = bmmProvider.fundingBalanceSats ?? 0;
    return 'The wallet holds ${satoshiToBTC(sats).toStringAsFixed(8)} BTC, '
        'under the max bid of ${bmmProvider.maxBidAmount.toStringAsFixed(8)} BTC';
  }

  /// The bid the engine opens at, from Core's own rate and a plain bid's size.
  String get _minBidText => satoshiToBTC(bmmProvider.suggestedBidSats).toStringAsFixed(8);

  int get blockWorthSats => bmmProvider.current?.blockWorthSats.toInt() ?? 0;

  List<HistoricBid> get historicRows => historicBids(bmmProvider.current, bmmProvider.history);

  /// What the live bid stands to make, not money already earned: profit is only
  /// real once the block connects.
  int get profitIfWon {
    final live = bmmProvider.liveBid;
    if (live == null || blockWorthSats == 0) {
      return 0;
    }
    return blockWorthSats - live.bidSats.toInt();
  }

  String get currentCriticalHash {
    final live = bmmProvider.liveBid;
    return live == null ? '—' : shortenCriticalHash(live.criticalHash);
  }

  String get slotStatus {
    if (bmmProvider.liveBid != null) {
      return 'Bid placed';
    }
    return running ? 'Assembling' : 'Not bidding';
  }

  SailStatusTone get slotStatusTone {
    if (bmmProvider.liveBid != null) {
      return SailStatusTone.warning;
    }
    return running ? SailStatusTone.info : SailStatusTone.neutral;
  }

  SailBadgeTone get slotTone => bmmProvider.liveBid == null ? SailBadgeTone.neutral : SailBadgeTone.success;

  String get slotHint {
    final live = bmmProvider.liveBid;
    if (!running && live == null) {
      return bidBlockedReason ?? 'Press Start auto-bidding to bid for the next block';
    }
    if (live == null) {
      return '';
    }
    return 'Waiting for a miner to commit to ${shortenCriticalHash(live.criticalHash)}';
  }

  void _onMaxBound() {
    final max = double.tryParse(maxBidController.text.trim());
    if (max != null) {
      bmmProvider.setMaxBidAmount(max);
    }
  }

  // Sync progress moves constantly, and mirroring the bounds on every step
  // would overwrite a bound the user is still typing.
  void _onSyncChanged() {
    notifyListeners();
  }

  void _onProviderChanged() {
    // Mirror bounds the backend reports, except while an edit is waiting to be
    // pushed — that value is the user's, mid-typing.
    if (!bmmProvider.boundsPushPending) {
      _mirrorBound(maxBidController, bmmProvider.maxBidAmount);
    }
    if (minBidController.text != _minBidText) {
      minBidController.text = _minBidText;
    }
    notifyListeners();
  }

  void _mirrorBound(TextEditingController controller, double value) {
    if (double.tryParse(controller.text.trim()) == value) {
      return;
    }
    controller.text = value.toStringAsFixed(8);
  }

  Future<void> startBidding() => bmmProvider.startBidding();
  Future<void> stopBidding() => bmmProvider.stopBidding();

  String satsLabel(int sats) => sats == 0 ? '—' : '${groupDigits(sats)} sats';

  String txUrl(String txid) => mempoolTxUrl(txid, _conf.network);
  String blockUrl(String hash) => mempoolBlockUrl(hash, _conf.network);

  /// The block that decided the round, by height when the enforcer gave us one.
  String blockLabel(bmmpb.Round round) {
    if (round.includedInHeight > 0) {
      return round.includedInHeight.toString();
    }
    return shortenHash(round.includedInBlock);
  }

  /// A replaced bid is superseded by our own raise, so it can never be mined.
  String bidStatus(bmmpb.Bid bid, List<bmmpb.Bid> bids) {
    if (bid.replacedByTxid.isNotEmpty) {
      return 'Replaced by ${shortenHash(bid.replacedByTxid)}';
    }
    if (bid.state == 'failed') {
      return 'Failed';
    }
    if (bids.isNotEmpty && bids.first.txid == bid.txid) {
      return 'Leading';
    }
    return 'Outbid';
  }

  SailStatusTone bidStatusTone(bmmpb.Bid bid, List<bmmpb.Bid> bids) {
    if (bid.replacedByTxid.isNotEmpty) {
      return SailStatusTone.warning;
    }
    if (bid.state == 'failed') {
      return SailStatusTone.error;
    }
    if (bids.isNotEmpty && bids.first.txid == bid.txid) {
      return SailStatusTone.success;
    }
    return SailStatusTone.neutral;
  }

  Color? bidStatusColor(bmmpb.Bid bid, List<bmmpb.Bid> bids, SailColor colors) {
    if (bid.replacedByTxid.isNotEmpty) {
      return colors.orange;
    }
    if (bid.state == 'failed') {
      return colors.error;
    }
    if (bids.isNotEmpty && bids.first.txid == bid.txid) {
      return colors.success;
    }
    return colors.textSecondary;
  }

  void openTx(String txid) {
    if (txid.isEmpty || txid.startsWith('bid-')) {
      return;
    }
    unawaited(openUrl(Uri.parse(txUrl(txid))));
  }

  Future<void> showAllBids(BuildContext context, String prevMainHash) async {
    final round = await bmmProvider.roundBids(prevMainHash);
    if (!context.mounted) {
      return;
    }
    final bids = [...round.ourBids, ...round.otherBids]..sort((a, b) => b.bidSats.compareTo(a.bidSats));
    final phone = SailStyleValues.phoneLayout(context);

    await widgetDialog(
      context: context,
      title: 'Bids for mainchain block ${blockLabel(round)}',
      maxWidth: phone ? 740 : 900,
      child: Builder(
        builder: (context) {
          final colors = SailTheme.of(context).colors;
          return SailColumn(
            spacing: SailStyleValues.padding12,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SailText.secondary13(
                isLight
                    ? 'Light mode reads the rival bids from the enforcer, not from a mainchain mempool. '
                          'A bid the enforcer never saw can exist and never appear here.'
                    : 'A losing bid never confirms and leaves the mempool, so this is every bid we saw '
                          'while the block was pending — not proof that it was all of them.',
              ),
              Container(
                width: double.infinity,
                height: tableFrameHeight(bids.length),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: colors.formField, borderRadius: SailTheme.of(context).chrome.radius),
                child: SailTable(
                  getRowId: (index) => bids[index].txid.isEmpty ? 'bid-$index' : bids[index].txid,
                  emptyPlaceholder: 'No bids yet',
                  backgroundColor: colors.formField,
                  headerBuilder: (context) => [
                    SailTableHeaderCell(name: 'Bid (sats)', alignment: Alignment.centerRight),
                    SailTableHeaderCell(name: 'Bidder'),
                    SailTableHeaderCell(name: 'Sidechain block (h*)'),
                    SailTableHeaderCell(name: 'Mainchain txid'),
                    SailTableHeaderCell(name: 'Outcome'),
                  ],
                  rowBuilder: (context, row, selected) {
                    final bid = bids[row];
                    final outcome = outcomeOf(bid, round);
                    return [
                      SailTableCell(value: groupDigits(bid.bidSats.toInt()), alignment: Alignment.centerRight),
                      SailTableCell(value: bid.isOurs ? 'You' : '—'),
                      SailTableCell(value: shortenCriticalHash(bid.criticalHash)),
                      SailTableCell(value: shortenHash(bid.txid), copyValue: bid.txid),
                      SailTableCell(
                        value: outcome,
                        child: _DotCell(label: outcome, tone: outcomeTone(outcome)),
                      ),
                    ];
                  },
                  rowCount: bids.length,
                  drawLastRowsBorder: false,
                  onDoubleTap: openTx,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  SailStatusTone outcomeTone(String outcome) => switch (outcome) {
    'Won' => SailStatusTone.success,
    'Replaced' => SailStatusTone.warning,
    _ => SailStatusTone.neutral,
  };

  String outcomeOf(bmmpb.Bid bid, bmmpb.Round round) {
    if (bid.replacedByTxid.isNotEmpty) {
      return 'Replaced';
    }
    if (bid.txid.isNotEmpty && bid.txid == round.winnerTxid) {
      return 'Won';
    }
    if (bid.criticalHash.isNotEmpty && bid.criticalHash == round.winnerCriticalHash) {
      return 'Won';
    }
    return 'Lost';
  }

  @override
  void dispose() {
    bmmProvider.removeListener(_onProviderChanged);
    _sync.removeListener(_onSyncChanged);
    _nodeMode?.removeListener(_onSyncChanged);
    maxBidController.dispose();
    minBidController.dispose();
    super.dispose();
  }
}
