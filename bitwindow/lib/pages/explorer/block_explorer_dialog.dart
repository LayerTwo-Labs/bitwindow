import 'package:bitwindow/dialogs/merkle_tree_dialog.dart';
import 'package:bitwindow/pages/explorer/load_transaction_dialog.dart';
import 'package:bitwindow/pages/explorer/widgets/output_owner.dart';
import 'package:bitwindow/pages/explorer/widgets/transaction_flow_diagram.dart';
import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/widgets/v2_details.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/gen/bitcoin/bitcoind/v1alpha/bitcoin.pb.dart' show GetBlockRequest, GetBlockResponse;
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sail_ui/sail_ui.dart';

/// Thrown when a transaction details lookup runs with no wallet selected.
/// Lets [humanizeTransactionLoadError] distinguish "no wallet" from RPC
/// errors without sniffing exception strings.
class NoActiveWalletException implements Exception {
  const NoActiveWalletException();
}

/// Maps a raw exception from the transaction-details RPC to copy a normal
/// user can act on. Technical detail still goes to the log; this is what we
/// surface in the dialog.
String humanizeTransactionLoadError(Object e) {
  if (e is NoActiveWalletException) {
    return 'Open a wallet first — there is no active wallet to look this transaction up in.';
  }
  final raw = e.toString().toLowerCase();
  if (raw.contains('not found') || raw.contains('no such') || raw.contains('does not exist')) {
    return 'This transaction was not found in the active wallet. It may belong to another wallet, or the wallet may not be fully synced yet.';
  }
  if (raw.contains('connection') || raw.contains('unavailable') || raw.contains('refused')) {
    return 'Could not read transaction details. Check Daemon Status, then try again.';
  }
  return 'Could not load this transaction. Try again, or check the daemon logs if the problem persists.';
}

/// Keeps [keep] characters at each end of a long value, with an ellipsis between.
String middleEllipsis(String value, {int keep = 20}) =>
    value.length <= keep * 2 + 1 ? value : '${value.substring(0, keep)}…${value.substring(value.length - keep)}';

/// The next block hash, or "None" for the chain tip.
String nextBlockHashText(Block block) => block.nextBlockHash.isEmpty ? 'None' : block.nextBlockHash;

/// Maps a failed block search to text for the user.
String blockSearchError(String query, Object e) {
  final raw = e.toString().toLowerCase();
  final isHeight = int.tryParse(query) != null;
  if (isHeight && (raw.contains('out of range') || raw.contains('not found'))) {
    return 'No block at height $query.';
  }
  if (!isHeight && (raw.contains('not found') || raw.contains('hex') || raw.contains('length'))) {
    return 'No block with this hash.';
  }
  return 'Could not load the block. Make sure the node runs, and try again.';
}

class BlockExplorerDialog extends StatelessWidget {
  const BlockExplorerDialog({
    super.key,
  });

  /// Narrower panes show the block details in a dialog, not in the side panel.
  static const double panelMinWidth = 900;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<BlockExplorerViewModel>.reactive(
      viewModelBuilder: () => BlockExplorerViewModel(
        blockViewBuilder: (block) async {
          await _showBlockDetails(context, block);
        },
      ),
      onViewModelReady: (model) => model.init(),
      builder: (context, model, child) {
        final phone = SailStyleValues.phoneLayout(context);
        if (!phone) {
          return LayoutBuilder(
            builder: (context, constraints) {
              model.usePanel = constraints.maxWidth >= panelMinWidth;
              return _DesktopExplorer(model: model, onShowDialog: (block) => _showBlockDetails(context, block));
            },
          );
        }
        model.usePanel = false;
        return SailCard(
          title: '# Blocks: ${model.blockchainProvider.syncProvider.mainchainSyncInfo?.progressCurrent.toInt()}',
          subtitle:
              'Last block time: ${model.blockchainProvider.syncProvider.mainchainSyncInfo?.lastBlockAt?.toDateTime().toLocal().format()}',
          bottomPadding: false,
          child: Column(
            children: [
              SailTextField(
                controller: model.searchController,
                hintText: 'Enter a block height or hash',
                onSubmitted: model.searchBlock,
              ),
              const SailSpacing(SailStyleValues.padding08),
              SailRow(
                spacing: SailStyleValues.padding08,
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SailButton(
                    onPressed: () => model.searchBlock(model.searchController.text),
                    label: 'Search',
                    variant: ButtonVariant.primary,
                  ),
                  SailButton(
                    onPressed: () => showLoadTransactionDialog(context),
                    label: 'Load transaction',
                  ),
                ],
              ),
              if (model.searchError != null) ...[
                SailSpacing(SailStyleValues.padding08),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SailText.primary13(model.searchError!, color: context.sailTheme.colors.error),
                ),
              ],
              if (model.blockchainProvider.blocksError case final error?) ...[
                SailSpacing(SailStyleValues.padding08),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SailText.primary13('Could not read the blocks: $error', color: context.sailTheme.colors.error),
                ),
              ],
              SailSpacing(SailStyleValues.padding16),
              Expanded(
                child: ListView.builder(
                  controller: model.scrollController,
                  key: PageStorageKey('block_list'),
                  itemCount: model.blocks.length + (model.isLoadingMoreBlocks ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == model.blocks.length) {
                      return const Padding(padding: EdgeInsets.all(16), child: LoadingIndicator());
                    }
                    final block = model.blocks[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (index > 0) const _BlockConnector(),
                        _BlockColumn(block: block, onDoubleTap: () => _showBlockDetails(context, block)),
                      ],
                    );
                  },
                ),
              ),
              SailSpacing(SailStyleValues.padding16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showBlockDetails(BuildContext context, Block block) async {
    await showThemedDialog(
      context: context,
      builder: (context) => SailModal(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SailCard(
          title: 'Block Details',
          subtitle: '',
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow(label: 'Height', value: block.height.toString()),
                DetailRow(label: 'Hash', value: block.hash),
                DetailRow(label: 'Confirmations', value: block.confirmations.toString()),
                DetailRow(label: 'Block Version', value: block.version.toString()),
                SailSpacing(SailStyleValues.padding16),
                Container(
                  padding: const EdgeInsets.only(
                    left: SailStyleValues.padding16,
                    right: SailStyleValues.padding16,
                    top: SailStyleValues.padding04,
                    bottom: SailStyleValues.padding08,
                  ),
                  decoration: BoxDecoration(
                    color: context.sailTheme.colors.backgroundSecondary,
                    borderRadius: context.sailTheme.chrome.radius,
                    border: Border.all(
                      color: context.sailTheme.colors.divider,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SailText.primary13('Block Header'),
                      SailSpacing(SailStyleValues.padding08),
                      DetailRow(label: 'Version', value: block.version.toString()),
                      DetailRow(label: 'Previous Block Hash', value: block.previousBlockHash),
                      DetailRow(label: 'Merkle Root', value: block.merkleRoot),
                      DetailRow(label: 'Time', value: block.blockTime.seconds.toString()),
                      DetailRow(label: 'Bits', value: '0x${block.bits}'),
                      DetailRow(label: 'Nonce', value: block.nonce.toString()),
                    ],
                  ),
                ),
                const SailSpacing(SailStyleValues.padding16),
                DetailRow(label: 'Next Block Hash', value: nextBlockHashText(block)),
                DetailRow(label: 'Difficulty', value: '${block.difficulty}'),
                const SailSpacing(SailStyleValues.padding16),
                SizedBox(
                  height: 300,
                  child: TXIDTransactionTable(
                    transactions: block.txids,
                    onTransactionSelected: (txid) =>
                        showLoadTransactionDialog(context, txid: txid, blockHash: block.hash),
                  ),
                ),
                const SailSpacing(SailStyleValues.padding16),
                // Merkle Tree Viewer Button
                SailButton(
                  label: 'View Merkle Tree',
                  onPressed: () async {
                    await showThemedDialog(
                      context: context,
                      builder: (context) => MerkleTreeDialog(
                        initialTxids: block.txids,
                        expectedRoot: block.merkleRoot,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const DetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: SailText.primary13(
              label,
              monospace: true,
              color: context.sailTheme.colors.textTertiary,
            ),
          ),
          Expanded(
            child: SailText.secondary13(
              value,
              monospace: true,
            ),
          ),
        ],
      ),
    );
  }
}

class BlockExplorerViewModel extends BaseViewModel {
  final BlockchainProvider blockchainProvider = GetIt.I.get<BlockchainProvider>();
  final searchController = TextEditingController();
  late final ScrollController scrollController;
  final OrchestratorRPC orchestrator = GetIt.I.get<OrchestratorRPC>();
  Logger get log => GetIt.I.get<Logger>();

  final Future<void> Function(Block) blockViewBuilder;

  String? searchError;

  /// True when the page shows the block details in the side panel.
  bool usePanel = false;

  /// The block in the side panel.
  Block? selectedBlock;

  void selectBlock(Block? block) {
    selectedBlock = block;
    notifyListeners();
  }

  /// Shows [block] in the side panel, or in a dialog when the page has no panel.
  Future<void> openBlock(Block block) async {
    if (usePanel) {
      selectBlock(block);
      return;
    }
    await blockViewBuilder(block);
  }

  BlockExplorerViewModel({required this.blockViewBuilder}) {
    blockchainProvider.addListener(notifyListeners);
    scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.8) {
        loadMoreBlocks();
      }
    });
  }

  Future<void> searchBlock(String input) async {
    final query = input.trim();
    if (query.isEmpty) {
      return;
    }

    final req = GetBlockRequest();
    final asHeight = int.tryParse(query);
    if (asHeight != null) {
      req.height = asHeight;
    } else {
      req.hash = query;
    }

    final GetBlockResponse block;
    try {
      block = await orchestrator.bitcoind.getBlock(req);
    } catch (e) {
      log.e('block search for $query failed: $e');
      searchError = blockSearchError(query, e);
      notifyListeners();
      return;
    }

    searchError = null;
    notifyListeners();
    // the bitcoind rpc `getblock` returns a slightly
    // different data model than the bitwindowd rpc `listblocks`
    await openBlock(
      Block(
        hash: block.hash,
        height: block.height,
        blockTime: block.time,
        merkleRoot: block.merkleRoot,
        version: block.version,
        previousBlockHash: block.previousBlockHash,
        nonce: block.nonce,
        bits: block.bits,
        difficulty: block.difficulty,
        txids: block.txids,
        confirmations: block.confirmations,
        size: block.size,
        weight: block.weight,
        versionHex: block.versionHex,
        nextBlockHash: block.nextBlockHash,
        strippedSize: block.strippedSize,
      ),
    );
  }

  List<Block> get blocks {
    return blockchainProvider.blocks;
  }

  Future<void> init() async {
    await blockchainProvider.fetch();
    notifyListeners();
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    blockchainProvider.removeListener(notifyListeners);
    super.dispose();
  }

  void loadMoreBlocks() {
    blockchainProvider.loadMoreBlocks();
  }

  bool get isLoadingMoreBlocks => blockchainProvider.isLoadingMoreBlocks;
}

class BlockTransaction {
  final int index;
  final String txid;

  const BlockTransaction({
    required this.index,
    required this.txid,
  });
}

class TXIDTransactionTable extends StatefulWidget {
  final List<String> transactions;
  final void Function(String txid)? onTransactionSelected;

  const TXIDTransactionTable({
    super.key,
    required this.transactions,
    this.onTransactionSelected,
  });

  @override
  State<TXIDTransactionTable> createState() => _TXIDTransactionTableState();
}

class _TXIDTransactionTableState extends State<TXIDTransactionTable> {
  String? sortColumn;
  bool sortAscending = true;
  late List<int> sortedIndexes;

  @override
  void initState() {
    super.initState();
    sortTransactions();
  }

  @override
  void didUpdateWidget(TXIDTransactionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.transactions, widget.transactions)) {
      sortTransactions();
    }
  }

  static const columns = ['n', 'txid'];

  void sortTransactions() {
    final txids = widget.transactions;
    sortedIndexes = List.generate(txids.length, (i) => i);
    sortedIndexes.sort((a, b) {
      final cmp = sortColumn == 'txid' ? txids[a].compareTo(txids[b]) : a.compareTo(b);
      return sortAscending ? cmp : -cmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: context.sailTheme.colors.info,
          width: 1,
        ),
        borderRadius: context.sailTheme.chrome.radius,
      ),
      child: SailTable(
        backgroundColor: context.sailTheme.colors.background,
        altBackgroundColor: context.sailTheme.colors.backgroundSecondary,
        getRowId: (index) => widget.transactions[sortedIndexes[index]],
        onDoubleTap: widget.onTransactionSelected != null ? (rowId) => widget.onTransactionSelected!(rowId) : null,
        headerBuilder: (context) => [
          for (final column in columns) SailTableHeaderCell(name: column),
        ],
        rowBuilder: (context, index, selected) => [
          SailTableCell(value: sortedIndexes[index].toString()),
          SailTableCell(value: widget.transactions[sortedIndexes[index]]),
        ],
        rowCount: widget.transactions.length,
        emptyPlaceholder: 'No transactions in block',
        sortColumnIndex: sortColumn == null ? null : columns.indexOf(sortColumn!),
        sortAscending: sortAscending,
        onSort: (columnIndex, ascending) => setState(() {
          sortColumn = columns[columnIndex];
          sortAscending = ascending;
          sortTransactions();
        }),
      ),
    );
  }
}

class TransactionDetailsDialog extends StatefulWidget {
  final String txid;

  const TransactionDetailsDialog({
    super.key,
    required this.txid,
  });

  @override
  State<TransactionDetailsDialog> createState() => _TransactionDetailsDialogState();
}

class _TransactionDetailsDialogState extends State<TransactionDetailsDialog> {
  OrchestratorWalletRPC get orchestratorWallet => GetIt.I.get<OrchestratorRPC>().wallet;
  WalletReaderProvider get walletReader => GetIt.I.get<WalletReaderProvider>();
  TransactionProvider get _transactions => GetIt.I.get<TransactionProvider>();
  Logger get log => GetIt.I.get<Logger>();

  GetTransactionDetailsResponse? _details;
  String? error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTransaction();
  }

  Future<void> _loadTransaction() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      error = null;
    });

    try {
      final walletId = walletReader.activeWalletId;
      if (walletId == null) {
        throw const NoActiveWalletException();
      }

      final details = await orchestratorWallet.getTransactionDetails(
        walletId: walletId,
        txid: widget.txid,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
        error = null;
        _isLoading = false;
      });
    } catch (e) {
      log.e('failed to load transaction details for txid=${widget.txid}: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _details = null;
        error = humanizeTransactionLoadError(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v2 = SailTheme.of(context).isBitwindowV2;
    return SailModal(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
      child: SailCard(
        title: 'Transaction Details',
        subtitle: widget.txid,
        error: error,
        withCloseButton: v2,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(SailStyleValues.padding16),
                  child: LoadingIndicator(),
                ),
              )
            : _details == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(SailStyleValues.padding16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SailText.primary13('Failed to load transaction details'),
                      if (error != null) SailText.secondary13(error!),
                      const SailSpacing(SailStyleValues.padding08),
                      SailButton(
                        onPressed: _loadTransaction,
                        label: 'Retry',
                        variant: ButtonVariant.primary,
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_details!.warningMessage.trim().isNotEmpty) ...[
                    SailAlert(variant: SailAlertVariant.warning, description: _details!.warningMessage),
                    const SailSpacing(SailStyleValues.padding08),
                  ],
                  Expanded(
                    child: InlineTabBar(
                      tabs: [
                        TabItem(
                          label: 'Overview',
                          child: ListenableBuilder(
                            listenable: _transactions,
                            builder: (context, _) {
                              final walletTx = _transactions.walletTransactions.firstWhereOrNull(
                                (tx) => tx.txid == widget.txid,
                              );
                              return v2
                                  ? TxOverviewGroups(details: _details!, walletTx: walletTx)
                                  : _OverviewTab(details: _details!, walletTx: walletTx);
                            },
                          ),
                        ),
                        TabItem(
                          label: 'Inputs (${_details!.inputs.length})',
                          child: TxInputsTable(inputs: _details!.inputs),
                        ),
                        TabItem(
                          label: 'Outputs (${_details!.outputs.length})',
                          child: TxOutputsTable(outputs: _details!.outputs),
                        ),
                        TabItem(
                          label: 'Diagram',
                          child: SingleChildScrollView(
                            padding: v2 ? EdgeInsets.zero : const EdgeInsets.all(SailStyleValues.padding16),
                            child: v2
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      TransactionDiagram(details: _details!),
                                      const SailSpacing(SailStyleValues.padding16),
                                      TransactionFlowDiagram(details: _details!),
                                    ],
                                  )
                                : TransactionDiagram(details: _details!),
                          ),
                        ),
                        TabItem(
                          label: 'Bytes',
                          child: TransactionByteView(rawHex: _details!.hex),
                        ),
                      ],
                      initialIndex: 0,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final GetTransactionDetailsResponse details;

  /// The history row of this transaction in the active wallet, or null.
  final WalletTransaction? walletTx;

  const _OverviewTab({required this.details, required this.walletTx});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SailStyleValues.padding16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (walletTx case final tx?) ...[
            SailText.primary13('In this wallet'),
            const SailSpacing(SailStyleValues.padding08),
            for (final (label, value) in walletTransactionRows(tx, formatter)) DetailRow(label: label, value: value),
            const SailSpacing(SailStyleValues.padding16),
          ],
          // Transaction Flow Diagram
          TransactionFlowDiagram(details: details),

          const SailSpacing(SailStyleValues.padding16),

          // Header Info
          SailText.primary13('Transaction Info'),
          const SailSpacing(SailStyleValues.padding08),
          DetailRow(label: 'TXID', value: details.txid),
          DetailRow(label: 'Block Hash', value: details.blockhash.isEmpty ? 'Unconfirmed' : details.blockhash),
          DetailRow(label: 'Confirmations', value: '${details.confirmations}'),
          DetailRow(label: 'Version', value: '${details.version}'),
          DetailRow(label: 'Lock Time', value: '${details.locktime}'),

          const SailSpacing(SailStyleValues.padding16),

          // Size Info
          SailText.primary13('Size'),
          const SailSpacing(SailStyleValues.padding08),
          DetailRow(label: 'Size', value: '${details.sizeBytes} bytes'),
          DetailRow(label: 'Virtual Size', value: '${details.vsizeVbytes} vbytes'),
          DetailRow(label: 'Weight', value: '${details.weightWu} WU'),

          const SailSpacing(SailStyleValues.padding16),

          // Fee Info
          SailText.primary13('Fee'),
          const SailSpacing(SailStyleValues.padding08),
          DetailRow(label: 'Fee', value: formatter.formatSats(details.feeSats.toInt())),
          DetailRow(label: 'Fee Rate', value: '${details.feeRateSatVb.toStringAsFixed(2)} ${activeTicker.feeRate}'),

          const SailSpacing(SailStyleValues.padding16),

          // Totals
          SailText.primary13('Totals'),
          const SailSpacing(SailStyleValues.padding08),
          DetailRow(label: 'Total Input', value: formatter.formatSats(details.totalInputSats.toInt())),
          DetailRow(label: 'Total Output', value: formatter.formatSats(details.totalOutputSats.toInt())),
        ],
      ),
    );
  }
}

/// The overview of a transaction as four grey detail groups in two columns.
class TxOverviewGroups extends StatelessWidget {
  final GetTransactionDetailsResponse details;

  /// The history row of this transaction in the active wallet, or null.
  final WalletTransaction? walletTx;

  const TxOverviewGroups({super.key, required this.details, this.walletTx});

  static const double _twoColumnWidth = 600;

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    List<Widget> group(String title, List<SailDetailLine> rows) => [
      SailDetailHeading(title),
      const SizedBox(height: 8),
      SailDetailGroup(fill: SailDetailFill.canvas, children: rows),
    ];

    final info = group('Transaction Info', [
      SailDetailLine(wrap: true, label: 'TXID', value: details.txid),
      SailDetailLine(
        wrap: true,
        label: 'Block Hash',
        value: details.blockhash.isEmpty ? 'Unconfirmed' : details.blockhash,
      ),
      SailDetailLine(wrap: true, label: 'Confirmations', value: '${details.confirmations}'),
      SailDetailLine(wrap: true, label: 'Version', value: '${details.version}'),
      SailDetailLine(wrap: true, label: 'Lock Time', value: '${details.locktime}'),
    ]);
    final fee = group('Fee', [
      SailDetailLine(wrap: true, label: 'Fee', value: formatter.formatSats(details.feeSats.toInt())),
      SailDetailLine(
        wrap: true,
        label: 'Fee Rate',
        value: '${details.feeRateSatVb.toStringAsFixed(2)} ${activeTicker.feeRate}',
      ),
    ]);
    final size = group('Size', [
      SailDetailLine(wrap: true, label: 'Size', value: '${details.sizeBytes} bytes'),
      SailDetailLine(wrap: true, label: 'Virtual Size', value: '${details.vsizeVbytes} vbytes'),
      SailDetailLine(wrap: true, label: 'Weight', value: '${details.weightWu} WU'),
    ]);
    final totals = group('Totals', [
      SailDetailLine(wrap: true, label: 'Total Input', value: formatter.formatSats(details.totalInputSats.toInt())),
      SailDetailLine(wrap: true, label: 'Total Output', value: formatter.formatSats(details.totalOutputSats.toInt())),
    ]);

    Widget column(List<Widget> first, List<Widget> second) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [...first, const SizedBox(height: 8), ...second],
    );

    final wallet = switch (walletTx) {
      final tx? => [
        ...group('In this wallet', [
          for (final (label, value) in walletTransactionRows(tx, formatter))
            SailDetailLine(wrap: true, label: label, value: value),
        ]),
        const SizedBox(height: 8),
      ],
      null => const <Widget>[],
    };

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _twoColumnWidth) {
            return column(
              [...wallet, ...info, const SizedBox(height: 8), ...fee],
              [...size, const SizedBox(height: 8), ...totals],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...wallet,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: column(info, fee)),
                  const SizedBox(width: 16),
                  Expanded(child: column(size, totals)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class TxInputsTable extends StatelessWidget {
  final List<TransactionInput> inputs;

  const TxInputsTable({super.key, required this.inputs});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    final phone = SailStyleValues.phoneLayout(context);

    return SailTable(
      getRowId: (i) => '${inputs[i].prevTxid}:${inputs[i].prevVout}',
      phoneColumns: const [0, 1],
      headerBuilder: (_) => [
        SailTableHeaderCell(name: '#'),
        SailTableHeaderCell(name: 'Amount'),
        SailTableHeaderCell(name: 'Address'),
        SailTableHeaderCell(name: 'Previous Output'),
        SailTableHeaderCell(name: 'Sequence'),
      ],
      rowBuilder: (_, i, _) {
        final input = inputs[i];
        final prevOutput = input.isCoinbase ? 'Coinbase' : '${input.prevTxid.substring(0, 8)}...:${input.prevVout}';

        return [
          SailTableCell(value: '${input.index}', width: phone ? 32 : null),
          SailTableCell(
            value: input.isCoinbase ? 'N/A' : formatter.formatSats(input.valueSats.toInt()),
            monospace: true,
          ),
          SailTableCell(
            value: input.isCoinbase ? 'Coinbase' : (input.address.isEmpty ? 'Unknown' : input.address),
            monospace: true,
            copyValue: input.address,
          ),
          SailTableCell(
            value: prevOutput,
            monospace: true,
            copyValue: input.isCoinbase ? null : '${input.prevTxid}:${input.prevVout}',
          ),
          SailTableCell(value: '${input.sequence}', monospace: true),
        ];
      },
      rowCount: inputs.length,
      emptyPlaceholder: 'No inputs',
    );
  }
}

class TxOutputsTable extends StatelessWidget {
  final List<TransactionOutput> outputs;

  const TxOutputsTable({super.key, required this.outputs});

  String _decodeOpReturnData(String scriptPubkeyHex) {
    // scriptPubkeyHex for OP_RETURN: "6a" (OP_RETURN) + push opcode + data
    // Skip the OP_RETURN byte (6a) and the push length byte
    if (scriptPubkeyHex.length < 4) {
      return '';
    }
    try {
      // Skip 6a (OP_RETURN), then read push opcode
      var hex = scriptPubkeyHex.substring(2);
      // Skip the push length byte(s)
      final pushByte = int.parse(hex.substring(0, 2), radix: 16);
      if (pushByte <= 0x4b) {
        // Direct push: 1 byte length
        hex = hex.substring(2);
      } else if (pushByte == 0x4c) {
        // OP_PUSHDATA1: next byte is length
        hex = hex.substring(4);
      } else if (pushByte == 0x4d) {
        // OP_PUSHDATA2: next 2 bytes are length
        hex = hex.substring(6);
      }
      // Decode hex to UTF-8 string
      final bytes = <int>[];
      for (var j = 0; j < hex.length - 1; j += 2) {
        bytes.add(int.parse(hex.substring(j, j + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return scriptPubkeyHex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    final phone = SailStyleValues.phoneLayout(context);

    return SailTable(
      getRowId: (i) => '${outputs[i].index}',
      phoneColumns: const [0, 3, 4],
      headerBuilder: (_) => [
        SailTableHeaderCell(name: '#'),
        SailTableHeaderCell(name: 'Amount'),
        SailTableHeaderCell(name: 'Address'),
        SailTableHeaderCell(name: 'Owner'),
        SailTableHeaderCell(name: 'Type'),
      ],
      rowBuilder: (_, i, _) {
        final output = outputs[i];
        final isOpReturn = output.scriptType == 'nulldata';
        final decodedData = isOpReturn ? _decodeOpReturnData(output.scriptPubkeyHex) : '';

        return [
          SailTableCell(value: '${output.index}', width: phone ? 32 : null),
          SailTableCell(
            value: formatter.formatSats(output.valueSats.toInt()),
            monospace: true,
          ),
          SailTableCell(
            value: output.address.isEmpty ? (isOpReturn ? 'OP_RETURN: $decodedData' : 'Unknown') : output.address,
            monospace: true,
            copyValue: isOpReturn ? decodedData : (output.address.isNotEmpty ? output.address : null),
          ),
          SailTableCell(value: outputOwnerLabel(output) ?? '', width: phone ? 112 : null),
          SailTableCell(value: output.scriptType),
        ];
      },
      rowCount: outputs.length,
      emptyPlaceholder: 'No outputs',
    );
  }
}

class BorderedSection extends StatelessWidget {
  final String title;
  final Widget child;

  const BorderedSection({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary13(title),
        const SailSpacing(SailStyleValues.padding08),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: context.sailTheme.colors.divider,
              width: 1,
            ),
            borderRadius: context.sailTheme.chrome.radius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(SailStyleValues.padding16),
            child: child,
          ),
        ),
      ],
    );
  }
}

Future<void> showTransactionDetails(BuildContext context, String txid) async {
  // Ensure we're running on a new frame
  await Future.microtask(() async {
    if (!context.mounted) {
      return;
    }
    return showThemedDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            // You can handle pop result here if needed
          },
          child: TransactionDetailsDialog(
            txid: txid,
          ),
        );
      },
    );
  });
}

class _BlockColumn extends StatelessWidget {
  final Block block;
  final VoidCallback onDoubleTap;

  const _BlockColumn({
    required this.block,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Container(
        padding: const EdgeInsets.all(SailStyleValues.padding16),
        decoration: BoxDecoration(
          color: context.sailTheme.colors.backgroundSecondary,
          borderRadius: context.sailTheme.chrome.radius,
          border: Border.all(
            color: context.sailTheme.colors.divider,
            width: 1,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Block height as header
              Container(
                padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
                margin: const EdgeInsets.only(bottom: SailStyleValues.padding08),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: context.sailTheme.colors.divider,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SailText.primary13('${block.height}', monospace: true, color: context.sailTheme.colors.info),
                    SailText.secondary13(block.blockTime.toDateTime().toLocal().format(), monospace: true),
                  ],
                ),
              ),
              _BlockValueLine(label: 'Hash', value: block.hash),
              _BlockValueLine(label: 'Prev Hash', value: block.previousBlockHash),
              _BlockValueLine(label: 'Merkle Root', value: block.merkleRoot),
              _BlockValueLine(label: 'Bits', value: '0x${block.bits}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockValueLine extends StatelessWidget {
  final String label;
  final String value;

  const _BlockValueLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SailStyleValues.padding04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailText.primary13(label, monospace: true, color: context.sailTheme.colors.textTertiary),
          SailText.secondary13(value, monospace: true),
        ],
      ),
    );
  }
}

class _BlockConnector extends StatelessWidget {
  const _BlockConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding08),
      child: Center(
        child: SailSVG.fromAsset(SailSVGAsset.chevronDown, width: 16, color: context.sailTheme.colors.textTertiary),
      ),
    );
  }
}

/// The desktop page: a top strip with the search, the blocks table, and the block details at the right.
class _DesktopExplorer extends StatelessWidget {
  final BlockExplorerViewModel model;
  final Future<void> Function(Block block) onShowDialog;

  const _DesktopExplorer({required this.model, required this.onShowDialog});

  @override
  Widget build(BuildContext context) {
    final sync = model.blockchainProvider.syncProvider.mainchainSyncInfo;
    final blocks = model.blocks;
    final selected = model.usePanel ? model.selectedBlock : null;
    final errors = [
      if (model.searchError != null) model.searchError!,
      if (model.blockchainProvider.blocksError case final error?) 'Could not read the blocks: $error',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailStrip(
          lead: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SailText.primary13('# Blocks: ${sync?.progressCurrent.toInt()}', bold: true),
              SailText.secondary12('Last block time: ${sync?.lastBlockAt?.toDateTime().toLocal().format()}'),
            ],
          ),
          stats: [
            SailTextField(
              controller: model.searchController,
              hintText: 'Enter a block height or hash',
              onSubmitted: model.searchBlock,
            ),
          ],
          actions: [
            SailButton(
              onPressed: () => model.searchBlock(model.searchController.text),
              label: 'Search',
              variant: ButtonVariant.primary,
            ),
            SailRowMenuButton(
              items: () => [
                SailMenuItem(
                  onSelected: () => showLoadTransactionDialog(context),
                  child: SailText.primary12('Load transaction'),
                ),
              ],
            ),
          ],
        ),
        for (final error in errors) ...[
          const SizedBox(height: SailStyleValues.padding08),
          SailText.primary13(error, color: context.sailTheme.colors.error),
        ],
        const SizedBox(height: SailStyleValues.padding12),
        Expanded(
          child: SailPageWithPanel(
            panel: selected == null
                ? null
                : _BlockDetailsPanel(block: selected, onClose: () async => model.selectBlock(null)),
            child: SailCard(
              bottomPadding: false,
              child: SailTable(
                getRowId: (index) => blocks[index].hash,
                selectedRowId: selected?.hash,
                onSelectedRow: (rowId) => model.selectBlock(rowId == null ? null : _byHash(rowId)),
                onDoubleTap: (rowId) => model.openBlock(_byHash(rowId)),
                onScrollApproachingEnd: model.loadMoreBlocks,
                cellHeight: 48,
                headerBuilder: (context) => const [
                  SailTableHeaderCell(name: 'Height'),
                  SailTableHeaderCell(name: 'Hash'),
                  SailTableHeaderCell(name: 'Prev Hash'),
                  SailTableHeaderCell(name: 'Merkle Root'),
                  SailTableHeaderCell(name: 'Bits', alignment: Alignment.centerRight),
                ],
                rowBuilder: (context, row, selected) {
                  final block = blocks[row];
                  return [
                    SailTableCell(
                      value: '${block.height}',
                      secondaryValue: block.blockTime.toDateTime().toLocal().format(),
                    ),
                    SailTableCell(value: middleEllipsis(block.hash, keep: 12), copyValue: block.hash),
                    SailTableCell(
                      value: middleEllipsis(block.previousBlockHash, keep: 12),
                      copyValue: block.previousBlockHash,
                    ),
                    SailTableCell(value: middleEllipsis(block.merkleRoot, keep: 10), copyValue: block.merkleRoot),
                    SailTableCell(value: '0x${block.bits}', alignment: Alignment.centerRight),
                  ];
                },
                contextMenuItems: (rowId) {
                  final block = _byHash(rowId);
                  return [
                    SailMenuItem(onSelected: () => model.openBlock(block), child: SailText.primary12('Show Details')),
                    SailMenuItem(
                      onSelected: () => showMerkleTree(context, block),
                      child: SailText.primary12('View Merkle Tree'),
                    ),
                  ];
                },
                rowCount: blocks.length,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Block _byHash(String hash) => model.blocks.firstWhere((b) => b.hash == hash);
}

Future<void> showMerkleTree(BuildContext context, Block block) => showThemedDialog(
  context: context,
  builder: (context) => MerkleTreeDialog(initialTxids: block.txids, expectedRoot: block.merkleRoot),
);

/// The side panel of one block.
class _BlockDetailsPanel extends StatelessWidget {
  final Block block;
  final Future<void> Function() onClose;

  const _BlockDetailsPanel({required this.block, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SailSidePanel(
      title: 'Block Details',
      onClose: onClose,
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeadline(value: '${block.height}', caption: block.blockTime.toDateTime().toLocal().format()),
          SailButton(label: 'View Merkle Tree', onPressed: () => showMerkleTree(context, block)),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(wrap: true, label: 'Height', value: block.height.toString()),
              SailStackedDetail(monospace: false, label: 'Hash', value: block.hash),
              SailDetailLine(wrap: true, label: 'Confirmations', value: block.confirmations.toString()),
              SailDetailLine(wrap: true, label: 'Block Version', value: block.version.toString()),
            ],
          ),
          const SailDetailHeading('Block Header'),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(wrap: true, label: 'Version', value: block.version.toString()),
              SailStackedDetail(monospace: false, label: 'Previous Block Hash', value: block.previousBlockHash),
              SailStackedDetail(monospace: false, label: 'Merkle Root', value: block.merkleRoot),
              SailDetailLine(wrap: true, label: 'Time', value: block.blockTime.seconds.toString()),
              SailDetailLine(wrap: true, label: 'Bits', value: '0x${block.bits}'),
              SailDetailLine(wrap: true, label: 'Nonce', value: block.nonce.toString()),
            ],
          ),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailStackedDetail(monospace: false, label: 'Next Block Hash', value: nextBlockHashText(block)),
              SailDetailLine(wrap: true, label: 'Difficulty', value: '${block.difficulty}'),
            ],
          ),
          SizedBox(
            height: 300,
            child: TXIDTransactionTable(
              transactions: block.txids,
              onTransactionSelected: (txid) => showLoadTransactionDialog(context, txid: txid, blockHash: block.hash),
            ),
          ),
        ],
      ),
    );
  }
}
