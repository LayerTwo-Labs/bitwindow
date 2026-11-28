import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/explorer/explorer_parts.dart';
import 'package:sail_ui/pages/sidechains/explorer/transaction_broadcast.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/explorer/v1/explorer.pb.dart' as pb;
import 'package:sidechain_core/utils/explorer_url.dart';

/// Below this width the side column goes above the page body.
const double _wideExplorer = 860;

/// ChainExplorerTab is the explorer: the search bar, the chain or the withdrawals, and a side column
/// with the treasury and the pending withdrawals, or the block, transaction or address a reader opened.
class ChainExplorerTab extends StatefulWidget {
  const ChainExplorerTab({super.key});

  @override
  State<ChainExplorerTab> createState() => _ChainExplorerTabState();
}

class _ChainExplorerTabState extends State<ChainExplorerTab> {
  final TextEditingController _search = TextEditingController();
  final ExplorerModel _model = ExplorerModel();
  ExplorerTarget? _target;
  int _tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model.setShown(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(ExplorerTarget target) => setState(() => _target = target);

  void _submit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final height = int.tryParse(trimmed);
    if (height != null) {
      _open(ExplorerTarget.block(height: height));
      return;
    }
    _open(ExplorerTarget.search(trimmed));
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ExplorerModel>.reactive(
      viewModelBuilder: () => _model,
      builder: (context, model, child) {
        final colors = SailTheme.of(context).colors;
        final bar = Row(
          children: [
            ExplorerSegments(
              labels: const ['Chain', 'Withdrawals'],
              activeIndex: _tab,
              onSelect: (index) => setState(() => _tab = index),
            ),
            const SizedBox(width: SailStyleValues.padding12),
            Expanded(
              child: SailTextField(
                controller: _search,
                hintText: 'Search a block height, a block hash, a transaction or an address',
                onSubmitted: _submit,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: SailSVG.fromAsset(SailSVGAsset.search, width: 20, height: 20, color: colors.textTertiary),
                ),
                prefixIconConstraints: const BoxConstraints(maxHeight: 20, maxWidth: 40),
              ),
            ),
            if (explorerSupportsBroadcast(model.chain)) ...[
              const SizedBox(width: SailStyleValues.padding12),
              ExplorerBroadcastButton(model: model, onOpen: _open),
            ],
          ],
        );

        final target = _target;
        final overview = model.overview;
        final Widget? side = target != null
            ? ExplorerDetail(
                model: model,
                target: target,
                onClose: () => setState(() => _target = null),
                onOpen: _open,
              )
            : overview != null
            ? _EscrowColumn(overview: overview)
            : null;

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideExplorer;
            final selected = target?.kind == ExplorerTargetKind.transaction ? target!.id : null;
            final body = _tab == 0
                ? _ChainBody(model: model, onOpen: _open, selectedId: selected, fill: wide)
                : WithdrawalsTab(fill: wide);
            if (!wide) {
              return SingleChildScrollView(
                child: SailColumn(
                  spacing: SailStyleValues.padding12,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [bar, ?side, body],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      bar,
                      const SizedBox(height: SailStyleValues.padding12),
                      Expanded(child: body),
                    ],
                  ),
                ),
                if (side != null) ...[
                  const SizedBox(width: SailStyleValues.padding12),
                  SizedBox(width: SailSidePanel.width, child: side),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _ChainBody extends StatelessWidget {
  final ExplorerModel model;
  final void Function(ExplorerTarget) onOpen;
  final String? selectedId;
  final bool fill;

  const _ChainBody({required this.model, required this.onOpen, required this.selectedId, required this.fill});

  @override
  Widget build(BuildContext context) {
    final overview = model.overview;
    if (overview == null) {
      return Align(
        alignment: Alignment.topCenter,
        child: SailCard(
          title: 'Explorer',
          subtitle: model.readError ?? 'Reading the chain',
          child: const SizedBox(height: 40),
        ),
      );
    }
    final activity = _RecentActivity(overview: overview, onOpen: onOpen, selectedId: selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockStrip(model: model, onOpen: onOpen),
        const SizedBox(height: SailStyleValues.padding12),
        if (fill) Expanded(child: activity) else SizedBox(height: 360, child: activity),
      ],
    );
  }
}

/// _EscrowColumn holds what the mainchain keeps for the chain: the treasury and the pending withdrawals.
class _EscrowColumn extends StatelessWidget {
  final pb.GetOverviewResponse overview;

  const _EscrowColumn({required this.overview});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overview.hasTreasury())
            _TreasuryCard(treasury: overview.treasury)
          else
            const _EscrowCard(title: 'Treasury', subtitle: 'This install reads no mainchain escrow'),
          _PendingWithdrawalsCard(bundle: overview.pendingBundle),
        ],
      ),
    );
  }
}

/// _BlockStrip shows the block the chain would mine next, then the blocks it
/// mined, newest first. It reads another page whenever a reader scrolls to
/// the end, down to the genesis block.
class _BlockStrip extends StatefulWidget {
  final ExplorerModel model;
  final void Function(ExplorerTarget) onOpen;

  const _BlockStrip({required this.model, required this.onOpen});

  @override
  State<_BlockStrip> createState() => _BlockStripState();
}

class _BlockStripState extends State<_BlockStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) {
      return;
    }
    final remaining = _controller.position.maxScrollExtent - _controller.offset;
    if (remaining < 400) {
      unawaited(widget.model.loadOlderBlocks());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = widget.model.overview!;
    final onOpen = widget.onOpen;
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: SailRow(
          spacing: SailStyleValues.padding12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BlockCard(
              label: 'Next',
              mainchain: null,
              amount: blockAmount(context, overview.mempool.feesSats.toInt()),
              transactions: transactionCount(overview.mempool.txCount),
              footer: const SailStatusPill(label: 'Waits for a bid', tone: SailStatusTone.warning),
            ),
            for (final block in widget.model.blocks)
              _BlockCard(
                label: '${block.height}',
                mainchain: block.mainchainHeight != 0 ? '${block.mainchainHeight}' : _shorten(block.mainchainHash),
                mainchainHash: block.mainchainHash,
                onTap: () => onOpen(ExplorerTarget.block(hash: block.hash)),
                amount: blockFigure(context, block),
                transactions: transactionCount(block.txCount),
                deposited: block.depositCount != 0
                    ? '+${blockAmount(context, block.depositValueSats.toInt())} deposited'
                    : null,
                footer: SailText.secondary12(explorerAge(block.blockTime.toInt())),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  static const double width = 196;
  static const double minHeight = 124;

  final String label;
  final String? mainchain;
  final String mainchainHash;
  final String amount;
  final String transactions;
  final String? deposited;
  final Widget footer;
  final VoidCallback? onTap;

  const _BlockCard({
    required this.label,
    required this.mainchain,
    this.mainchainHash = '',
    required this.amount,
    required this.transactions,
    this.deposited,
    required this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailTappable(
      onTap: onTap == null ? null : () async => onTap!(),
      borderRadius: theme.chrome.radiusLarge,
      child: Container(
        width: width,
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.all(SailStyleValues.padding12),
        decoration: theme.chrome.panel(theme.colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SailText.primary12(label, bold: true),
                const SizedBox(width: 6),
                Flexible(
                  child: _MainchainLink(label: mainchain, hash: mainchainHash),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SailText.primary20(amount, bold: true),
            SailText.secondary12(transactions),
            if (deposited != null) SailText.primary12(deposited!, color: theme.colors.success),
            const Spacer(),
            footer,
          ],
        ),
      ),
    );
  }
}

/// _MainchainLink names the mainchain block a header points at, and opens it
/// in the mainchain explorer.
class _MainchainLink extends StatelessWidget {
  final String? label;
  final String hash;

  const _MainchainLink({required this.label, required this.hash});

  @override
  Widget build(BuildContext context) {
    final text = SailText.secondary12(label ?? '—');
    if (hash.isEmpty) {
      return text;
    }
    return SailTappable(
      onTap: () async => openUrl(Uri.parse(mempoolBlockUrl(hash, GetIt.I.get<BitcoinConfProvider>().network))),
      child: text,
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final pb.GetOverviewResponse overview;
  final void Function(ExplorerTarget) onOpen;
  final String? selectedId;

  const _RecentActivity({required this.overview, required this.onOpen, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    final rows = overview.recent;
    final unconfirmed = rows.where((r) => !r.confirmed).length;
    pb.Activity byId(String id) => rows.firstWhere((r) => r.id == id);
    return SailCard(
      title: 'Recent transactions',
      widgetHeaderEnd: SailText.secondary13('Latest ${rows.length} · $unconfirmed unconfirmed'),
      bottomPadding: false,
      child: SailTable(
        getRowId: (index) => rows[index].id,
        selectedRowId: selectedId,
        headerBuilder: (context) => const [
          SailTableHeaderCell(name: 'Transaction'),
          SailTableHeaderCell(name: 'Kind'),
          SailTableHeaderCell(name: 'Value', alignment: Alignment.centerRight),
          SailTableHeaderCell(name: 'Fee', alignment: Alignment.centerRight),
          SailTableHeaderCell(name: 'Status'),
        ],
        rowBuilder: (context, index, selected) {
          final row = rows[index];
          return [
            SailTableCell(value: _shorten(row.id), copyValue: row.id),
            SailTableCell(value: kindLabel(row.kind)),
            SailTableCell(value: explorerAmount(context, row.valueSats.toInt()), alignment: Alignment.centerRight),
            SailTableCell(value: explorerAmount(context, row.feeSats.toInt()), alignment: Alignment.centerRight),
            SailTableCell(
              value: _statusOf(row),
              child: ExplorerStatus(
                label: _statusOf(row),
                tone: row.confirmed ? SailStatusTone.success : SailStatusTone.warning,
              ),
            ),
          ];
        },
        rowCount: rows.length,
        onRowTap: (rowId) {
          if (byId(rowId).kind == pb.Kind.KIND_DEPOSIT) {
            return;
          }
          onOpen(ExplorerTarget.transaction(rowId));
        },
        contextMenuItems: (rowId) => [
          if (byId(rowId).kind == pb.Kind.KIND_DEPOSIT)
            SailMenuItem(
              onSelected: () async => openUrl(
                Uri.parse(mempoolTxUrl(rowId, GetIt.I.get<BitcoinConfProvider>().network)),
              ),
              child: SailText.primary12('View on mempool.space'),
            )
          else
            SailMenuItem(
              onSelected: () => onOpen(ExplorerTarget.transaction(rowId)),
              child: SailText.primary12('Show Details'),
            ),
        ],
        emptyPlaceholder: 'No transactions yet',
      ),
    );
  }
}

class _TreasuryCard extends StatelessWidget {
  final pb.Treasury treasury;

  const _TreasuryCard({required this.treasury});

  @override
  Widget build(BuildContext context) {
    return _EscrowCard(
      title: 'Treasury',
      value: blockAmount(context, treasury.balanceSats.toInt()),
      subtitle: 'Slot ${treasury.slot} · activated at mainchain ${treasury.activationHeight}',
      rows: [SailDetailLine(label: 'CTIP', value: '${_shorten(treasury.ctipTxid)} : ${treasury.ctipVout}')],
    );
  }
}

/// A card with its title and amount on one line, a grey line under them, and a grey group of rows.
class _EscrowCard extends StatelessWidget {
  final String title;
  final String? value;
  final String subtitle;
  final List<Widget> rows;

  const _EscrowCard({required this.title, this.value, required this.subtitle, this.rows = const []});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      child: SailColumn(
        spacing: SailStyleValues.padding04,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: SailText.primary15(title, bold: true)),
              if (value != null) SailText.primary15(value!, bold: true),
            ],
          ),
          SailText.primary13(
            subtitle,
            color: SailTheme.of(context).colors.textSecondary,
            overflow: TextOverflow.visible,
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: SailStyleValues.padding08),
            SailDetailGroup(fill: SailDetailFill.canvas, children: rows),
          ],
        ],
      ),
    );
  }
}

/// _statusOf names the block a row sits in, and how long ago that was.
String _statusOf(pb.Activity row) {
  if (!row.confirmed) {
    return 'Unconfirmed';
  }
  final age = explorerAge(row.blockTime.toInt());
  if (age.isEmpty) {
    return 'Block ${row.blockHeight}';
  }
  return 'Block ${row.blockHeight} · $age';
}

class _PendingWithdrawalsCard extends StatelessWidget {
  final pb.WithdrawalBundle bundle;

  const _PendingWithdrawalsCard({required this.bundle});

  @override
  Widget build(BuildContext context) {
    if (!bundle.present) {
      return const _EscrowCard(title: 'Pending withdrawals', subtitle: 'No bundle');
    }
    return _EscrowCard(
      title: 'Pending withdrawals',
      value: blockAmount(context, bundle.totalValueSats.toInt()),
      subtitle: '${bundle.withdrawals.length} withdrawals · bundle ${bundle.totalWeight} / ${bundle.maxWeight}',
      rows: [
        SailDetailLine(label: 'Total mainchain fees', value: explorerAmount(context, bundle.totalMainFeesSats.toInt())),
        SailDetailLine(label: 'Height created', value: '${bundle.heightCreated}'),
      ],
    );
  }
}

/// explorerAmount reads an amount in the unit the user picked, and in the
/// active network's own name for it.
String explorerAmount(BuildContext context, int sats) {
  if (sats == 0) {
    return '—';
  }
  return BitcoinFormatting.formatSatsWithUnit(context, sats);
}

/// blockAmount reads an amount on a block card, where a zero is a figure of
/// its own rather than a missing value.
String blockAmount(BuildContext context, int sats) {
  return BitcoinFormatting.formatSatsWithUnit(context, sats);
}

/// blockFigure is what a block card states in large type: what the block
/// moved, or what it collected. A source states one or the other, never both.
String blockFigure(BuildContext context, pb.Block block) {
  if (block.valueKnown) {
    return blockAmount(context, block.valueSats.toInt());
  }
  if (block.feesKnown) {
    return blockAmount(context, block.feesSats.toInt());
  }
  return '';
}

/// transactionCount names how many transactions a block carried.
String transactionCount(int count) {
  return switch (count) {
    0 => 'No transactions',
    1 => '1 transaction',
    _ => '$count transactions',
  };
}

/// explorerAge reads how long ago a block arrived. A sidechain header carries
/// no clock, so the time comes from the mainchain block it names.
String explorerAge(int unixSeconds) {
  if (unixSeconds <= 0) {
    return '';
  }
  final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));
  if (age.inMinutes < 1) {
    return 'just now';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes} ${age.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (age.inHours < 24) {
    return '${age.inHours} ${age.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  return '${age.inDays} ${age.inDays == 1 ? 'day' : 'days'} ago';
}

String _shorten(String id) {
  if (id.length <= 20) {
    return id;
  }
  return '${id.substring(0, 8)}…${id.substring(id.length - 8)}';
}
