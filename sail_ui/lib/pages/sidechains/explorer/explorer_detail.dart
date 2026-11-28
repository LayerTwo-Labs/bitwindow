import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/explorer/transaction_broadcast.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/explorer/v1/explorer.pb.dart' as pb;
import 'package:sidechain_core/utils/explorer_url.dart';

/// What the explorer is looking at.
/// _paidOut is what a transaction pays out. A withdrawal takes the mainchain
/// fee as well as the payout.
int _paidOut(pb.Transaction transaction) => transaction.outputs.fold<int>(
  0,
  (sum, o) => sum + o.valueSats.toInt() + (o.contentType == 'withdrawal' ? o.mainFeeSats.toInt() : 0),
);

enum ExplorerTargetKind { block, transaction, address, search }

/// ExplorerTarget names one thing to read. A search resolves to whichever of
/// the three the chain knows.
class ExplorerTarget {
  final ExplorerTargetKind kind;
  final String id;
  final int? height;

  const ExplorerTarget._(this.kind, this.id, this.height);

  factory ExplorerTarget.block({String? hash, int? height}) =>
      ExplorerTarget._(ExplorerTargetKind.block, hash ?? '', height);
  factory ExplorerTarget.transaction(String txid) => ExplorerTarget._(ExplorerTargetKind.transaction, txid, null);
  factory ExplorerTarget.address(String address) => ExplorerTarget._(ExplorerTargetKind.address, address, null);
  factory ExplorerTarget.search(String query) => ExplorerTarget._(ExplorerTargetKind.search, query, null);
}

/// ExplorerDetail reads one block, transaction or address.
class ExplorerDetail extends StatefulWidget {
  final ExplorerModel model;
  final ExplorerTarget target;
  final VoidCallback onClose;
  final void Function(ExplorerTarget) onOpen;

  const ExplorerDetail({
    super.key,
    required this.model,
    required this.target,
    required this.onClose,
    required this.onOpen,
  });

  @override
  State<ExplorerDetail> createState() => _ExplorerDetailState();
}

class _ExplorerDetailState extends State<ExplorerDetail> {
  Object? _result;
  String? _error;

  /// _generation counts the loads. A reader who opens a second thing before
  /// the first arrives must not see the first land on top of it.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExplorerDetail old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final result = await _read();
      if (mounted && generation == _generation) {
        setState(() => _result = result);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    }
  }

  /// A search tries each kind in turn, because a chain gives no way to tell a
  /// block hash from a txid by its shape alone.
  Future<Object> _read() async {
    final target = widget.target;
    switch (target.kind) {
      case ExplorerTargetKind.block:
        return await widget.model.block(
          hash: target.id.isEmpty ? null : target.id,
          height: target.height,
        );
      case ExplorerTargetKind.transaction:
        return await widget.model.transaction(target.id);
      case ExplorerTargetKind.address:
        return await widget.model.address(target.id);
      case ExplorerTargetKind.search:
        try {
          return await widget.model.transaction(target.id);
        } catch (_) {}
        try {
          return await widget.model.block(hash: target.id);
        } catch (_) {}
        return await widget.model.address(target.id);
    }
  }

  Future<void> _close() async => widget.onClose();

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final colors = SailTheme.of(context).colors;
    if (_error != null) {
      return SailSidePanel(
        title: 'Not found',
        onClose: _close,
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SailStatusPill(label: 'Not found', tone: SailStatusTone.error),
            SailText.primary13(_error!, color: colors.error, overflow: TextOverflow.visible),
          ],
        ),
      );
    }
    if (result == null) {
      return SailSidePanel(
        title: 'Reading',
        onClose: _close,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: SailStyleValues.padding16),
          child: Center(child: LoadingIndicator()),
        ),
      );
    }
    if (result is pb.GetBlockResponse) {
      return _BlockPanel(response: result, onOpen: widget.onOpen, onClose: _close);
    }
    if (result is pb.Transaction) {
      return _TransactionPanel(model: widget.model, transaction: result, onOpen: widget.onOpen, onClose: _close);
    }
    return _AddressPanel(response: result as pb.GetAddressResponse, onOpen: widget.onOpen, onClose: _close);
  }
}

List<SailMenuEntity> _copyItem(String label, String text) => [
  SailMenuItem(
    onSelected: () async => Clipboard.setData(ClipboardData(text: text)),
    child: SailText.primary12(label),
  ),
];

/// The long id under the panel title, in grey, wrapped onto more lines.
class _PanelId extends StatelessWidget {
  final String id;

  const _PanelId(this.id);

  @override
  Widget build(BuildContext context) => SailText.secondary12(id, overflow: TextOverflow.visible);
}

/// The big value at the top of a panel, with its grey caption.
class _PanelAmount extends StatelessWidget {
  final String value;
  final String caption;

  const _PanelAmount({required this.value, required this.caption});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailText.primary24(value, bold: true),
        SailText.primary15(caption, color: colors.textSecondary),
      ],
    );
  }
}

class _BlockPanel extends StatelessWidget {
  final pb.GetBlockResponse response;
  final void Function(ExplorerTarget) onOpen;
  final Future<void> Function() onClose;

  const _BlockPanel({required this.response, required this.onOpen, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final block = response.block;
    final network = GetIt.I.get<BitcoinConfProvider>().network;
    final bid = block.hasBid() ? block.bid : null;
    final age = explorerAge(block.blockTime.toInt());
    final deposits = response.activity.where((r) => r.kind == pb.Kind.KIND_DEPOSIT).toList();
    final transactions = response.activity.where((r) => r.kind != pb.Kind.KIND_DEPOSIT).toList();
    return SailSidePanel(
      title: 'Block ${block.height}',
      onClose: onClose,
      menuItems: () => _copyItem('Copy hash', block.hash),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelId(block.hash),
          if (age.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: SailStatusPill(label: age),
            ),
          const SailDetailHeading('Details'),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(label: 'Transactions', value: '${block.txCount}'),
              SailDetailLine(label: 'Deposits', value: '${block.depositCount}'),
              SailDetailLine(label: 'Value', value: explorerAmount(context, block.valueSats.toInt())),
              if (block.depositCount != 0)
                SailDetailLine(label: 'Deposited', value: explorerAmount(context, block.depositValueSats.toInt())),
              SailDetailLine(label: 'Transaction bytes', value: block.sizeBytes == 0 ? '—' : '${block.sizeBytes}'),
              if (block.feesKnown)
                SailDetailLine(label: 'Fees', value: explorerAmount(context, block.feesSats.toInt())),
              SailDetailLine(label: 'Merkle root', value: shortenId(block.merkleRoot)),
            ],
          ),
          SailDetailHeading('Blind merge mine', note: bid == null ? 'This install reads no bid for the block' : null),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              if (bid != null) ...[
                SailDetailLine(label: 'Winning bid', value: explorerAmount(context, bid.sats.toInt())),
                SailDetailLine(
                  label: 'Bid block',
                  value: '${bid.blockHeight}',
                  onTap: () async => openUrl(Uri.parse(mempoolBlockUrl(bid.blockHash, network))),
                ),
                SailDetailLine(
                  label: 'Bid outpoint',
                  value: '${shortenId(bid.txid)} : ${bid.vout}',
                  onTap: () async => openUrl(Uri.parse(mempoolTxUrl(bid.txid, network))),
                ),
              ],
              if (block.mainchainHash.isEmpty)
                const SailDetailLine(label: 'Parent block', value: 'Unknown')
              else
                SailDetailLine(
                  label: 'Parent block',
                  value: block.mainchainHeight != 0 ? '${block.mainchainHeight}' : shortenId(block.mainchainHash),
                  onTap: () async => openUrl(Uri.parse(mempoolBlockUrl(block.mainchainHash, network))),
                ),
              if (block.prevHash.isNotEmpty)
                SailDetailLine(
                  label: 'Previous block',
                  value: shortenId(block.prevHash),
                  onTap: () async => onOpen(ExplorerTarget.block(hash: block.prevHash)),
                ),
            ],
          ),
          SailDetailHeading('Transactions', note: '${block.txCount} in this block'),
          _MiniTable(
            headers: const ['Transaction', 'Kind', 'Value'],
            empty: 'Nothing in this block',
            rows: [
              for (final row in transactions)
                _MiniRow(
                  cells: [shortenId(row.id), kindLabel(row.kind), explorerAmount(context, row.valueSats.toInt())],
                  onTap: () async => onOpen(ExplorerTarget.transaction(row.id)),
                ),
            ],
          ),
          SailDetailHeading('Deposits', note: '${block.depositCount} in this block'),
          _MiniTable(
            headers: const ['Mainchain transaction', 'Amount'],
            empty: 'No deposits yet',
            rows: [
              for (final row in deposits)
                _MiniRow(
                  cells: [shortenId(row.id), explorerAmount(context, row.valueSats.toInt())],
                  secondary: row.address.isEmpty ? null : shortenId(row.address),
                  onTap: () async => openUrl(Uri.parse(mempoolTxUrl(row.id, network))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniRow {
  final List<String> cells;
  final String? secondary;
  final Future<void> Function() onTap;

  const _MiniRow({required this.cells, required this.onTap, this.secondary});
}

class _MiniLine extends StatelessWidget {
  final List<Widget> cells;

  const _MiniLine(this.cells);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cells.length; i++)
          if (i == cells.length - 1)
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: cells[i]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: SailStyleValues.padding16),
              child: i == 0 ? SizedBox(width: 136, child: cells[i]) : cells[i],
            ),
      ],
    );
  }
}

/// A small table in a grey group: the first column at the left, the last one at the right.
class _MiniTable extends StatelessWidget {
  final List<String> headers;
  final List<_MiniRow> rows;
  final String empty;

  const _MiniTable({required this.headers, required this.rows, required this.empty});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    return SailDetailGroup(
      fill: SailDetailFill.canvas,
      children: [
        _MiniLine([for (final header in headers) SailText.primary12(header, color: colors.textSecondary)]),
        if (rows.isEmpty) SailText.secondary13(empty),
        for (final row in rows)
          SailTappable(
            onTap: row.onTap,
            child: _MiniLine([
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SailText.primary13(row.cells.first),
                  if (row.secondary != null) SailText.secondary12(row.secondary!),
                ],
              ),
              for (final cell in row.cells.skip(1)) SailText.primary13(cell),
            ]),
          ),
      ],
    );
  }
}

class _TransactionPanel extends StatefulWidget {
  final ExplorerModel model;
  final pb.Transaction transaction;
  final void Function(ExplorerTarget) onOpen;
  final Future<void> Function() onClose;

  const _TransactionPanel({
    required this.model,
    required this.transaction,
    required this.onOpen,
    required this.onClose,
  });

  @override
  State<_TransactionPanel> createState() => _TransactionPanelState();
}

class _TransactionPanelState extends State<_TransactionPanel> {
  var _actions = GlobalKey<ExplorerTransactionActionsState>();

  @override
  void didUpdateWidget(covariant _TransactionPanel old) {
    super.didUpdateWidget(old);
    if (old.transaction.txid != widget.transaction.txid) {
      _actions = GlobalKey<ExplorerTransactionActionsState>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final hasActions = explorerTransactionHasActions(widget.model.chain, transaction);
    final coins = [...transaction.inputs, ...transaction.outputs];
    return SailSidePanel(
      title: 'Transaction',
      onClose: widget.onClose,
      menuItems: () => [
        ..._copyItem('Copy TxID', transaction.txid),
        if (hasActions)
          SailMenuItem(
            onSelected: () async => _actions.currentState?.copy(),
            child: SailText.primary12('Copy Signed Transaction'),
          ),
      ],
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelAmount(value: explorerAmount(context, _paidOut(transaction)), caption: 'Total value'),
          _PanelId(transaction.txid),
          Align(
            alignment: Alignment.centerLeft,
            child: transaction.confirmed
                ? SailStatusPill(label: 'Block ${transaction.blockHeight}')
                : const SailStatusPill(label: 'Unconfirmed', tone: SailStatusTone.warning),
          ),
          if (hasActions)
            ExplorerTransactionActions(
              key: _actions,
              model: widget.model,
              transaction: transaction,
              onOpen: widget.onOpen,
            ),
          const SailDetailHeading('Details'),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(label: 'Kind', value: kindLabel(transaction.kind)),
              SailDetailLine(label: 'Size', value: '${transaction.sizeBytes} bytes'),
              SailDetailLine(label: 'Fee', value: explorerAmount(context, transaction.feeSats.toInt())),
              SailDetailLine(label: 'Total value', value: explorerAmount(context, _paidOut(transaction))),
            ],
          ),
          SailDetailHeading(
            'Inputs and outputs',
            note: '${transaction.inputs.length} in · ${transaction.outputs.length} out',
          ),
          if (coins.isNotEmpty)
            SailDetailGroup(
              fill: SailDetailFill.canvas,
              children: [for (final coin in coins) _CoinRow(coin: coin, onOpen: widget.onOpen)],
            ),
        ],
      ),
    );
  }
}

class _CoinRow extends StatelessWidget {
  final pb.Coin coin;
  final void Function(ExplorerTarget) onOpen;

  const _CoinRow({required this.coin, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final note = coin.mainAddress.isNotEmpty
        ? 'Withdrawal to ${shortenId(coin.mainAddress)} · '
              'mainchain fee ${explorerAmount(context, coin.mainFeeSats.toInt())}'
        : coin.outpointKind == 'deposit'
        ? 'Deposit ${shortenId(coin.txid)}'
        : null;
    return SailTappable(
      onTap: coin.address.isEmpty ? null : () async => onOpen(ExplorerTarget.address(coin.address)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: SailText.primary13(shortenId(coin.address), color: colors.textSecondary)),
              const SizedBox(width: SailStyleValues.padding08),
              SailText.primary13(explorerAmount(context, coin.valueSats.toInt())),
            ],
          ),
          if (note != null) SailText.secondary12(note),
        ],
      ),
    );
  }
}

class _AddressPanel extends StatelessWidget {
  final pb.GetAddressResponse response;
  final void Function(ExplorerTarget) onOpen;
  final Future<void> Function() onClose;

  const _AddressPanel({required this.response, required this.onOpen, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SailSidePanel(
      title: 'Address',
      onClose: onClose,
      menuItems: () => _copyItem('Copy address', response.address),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelAmount(
            value: explorerAmount(context, response.totalReceivedSats.toInt()),
            caption: 'Total received',
          ),
          _PanelId(response.address),
          SailDetailHeading(
            'Summary',
            note: '${response.confirmedBalanceSats} sats confirmed, over ${response.confirmedCoinCount} coins',
          ),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(
                label: 'Total received',
                value: explorerAmount(context, response.totalReceivedSats.toInt()),
              ),
              SailDetailLine(
                label: 'Unconfirmed',
                value: explorerAmount(context, response.unconfirmedBalanceSats.toInt()),
              ),
              SailDetailLine(label: 'Unconfirmed coins', value: '${response.unconfirmedCoinCount}'),
              SailDetailLine(label: 'Transactions', value: '${response.txCount}'),
            ],
          ),
          if (response.transactions.isNotEmpty) ...[
            const SailDetailHeading('Transactions'),
            SailDetailGroup(
              fill: SailDetailFill.canvas,
              children: [
                for (final tx in response.transactions) _AddressTransaction(transaction: tx, onOpen: onOpen),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressTransaction extends StatelessWidget {
  final pb.Transaction transaction;
  final void Function(ExplorerTarget) onOpen;

  const _AddressTransaction({required this.transaction, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final deposit = transaction.kind == pb.Kind.KIND_DEPOSIT;
    final where = transaction.confirmed ? 'Block ${transaction.blockHeight}' : 'Unconfirmed';
    return SailTappable(
      onTap: deposit ? null : () async => onOpen(ExplorerTarget.transaction(transaction.txid)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary13(shortenId(transaction.txid), bold: true),
                SailText.secondary12('${kindLabel(transaction.kind)} · $where'),
              ],
            ),
          ),
          const SizedBox(width: SailStyleValues.padding08),
          SailText.secondary12(
            '${explorerAmount(context, transaction.feeSats.toInt())} fee · '
            '${transaction.inputs.length} in · ${transaction.outputs.length} out',
          ),
        ],
      ),
    );
  }
}

String kindLabel(pb.Kind kind) {
  return switch (kind) {
    pb.Kind.KIND_DEPOSIT => 'Deposit',
    pb.Kind.KIND_WITHDRAWAL => 'Withdrawal',
    _ => 'Transfer',
  };
}

String shortenId(String id) {
  if (id.length <= 20) {
    return id;
  }
  return '${id.substring(0, 8)}…${id.substring(id.length - 8)}';
}
