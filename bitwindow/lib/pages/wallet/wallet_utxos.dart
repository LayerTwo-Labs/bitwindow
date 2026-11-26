import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/pages/wallet/denability_page.dart';
import 'package:bitwindow/pages/wallet/wallet_page.dart';
import 'package:bitwindow/pages/wallet/widgets/utxo_distribution_chart.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/providers/coin_selection_provider.dart';
import 'package:bitwindow/providers/consolidation_provider.dart';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sail_ui/sail_ui.dart';

class UTXOsTab extends StatefulWidget {
  const UTXOsTab({super.key});

  @override
  State<UTXOsTab> createState() => _UTXOsTabState();
}

class _UTXOsTabState extends State<UTXOsTab> {
  // Row height in SailTable (approx - includes padding)
  static const double _rowHeight = 36.0;
  static const double _headerHeight = 40.0;
  static const double _cardPadding = 80.0; // title + padding

  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();

  void _showBucketContextMenu(BuildContext context, UtxoBucket bucket, Offset position) {
    final isSingleUtxo = bucket.count == 1;
    final outpoint = isSingleUtxo ? bucket.outpoints.first : null;

    showSailMenu(
      context: context,
      preferredAnchorPoint: position,
      menu: SailMenu(
        items: [
          if (isSingleUtxo && outpoint != null) ...[
            SailMenuItem(
              onSelected: () async => toggleCoinFreeze(context, outpoint),
              child: SailText.primary12(coinFreezeMenuLabel(outpoint)),
            ),
            SailMenuItem(
              onSelected: () async {
                final txid = outpoint.split(':').first;
                await showTransactionDetails(context, txid);
              },
              child: SailText.primary12('Show Transaction'),
            ),
          ],
          SailMenuItem(
            onSelected: () {
              final selected = WalletPage.selectSendCoins(bucket.outpoints);
              showSailToast(context, 'Selected $selected UTXO(s) for sending - go to Send tab');
            },
            child: SailText.primary12(
              isSingleUtxo ? 'Send This UTXO' : 'Send These ${bucket.count} UTXOs',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return ViewModelBuilder<LatestUTXOsViewModel>.reactive(
          viewModelBuilder: () => LatestUTXOsViewModel(),
          builder: (context, model, child) {
            final walletId = _walletReader.activeWalletId;
            final showChart = walletId != null && !model.loading;

            final entries = model.entries;
            final rowCount = entries.length;
            final tableContentHeight = _headerHeight + (rowCount * _rowHeight) + _cardPadding;
            // Minimum height to fill available space, or larger if more rows
            final tableHeight = tableContentHeight.clamp(
              constraints.maxHeight - (showChart ? 280 : 0),
              double.infinity,
            );

            return CustomScrollView(
              slivers: [
                if (showChart)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: SailStyleValues.padding16),
                      child: SailCard(
                        title: 'UTXO Distribution',
                        widgetHeaderEnd: SailButton(
                          variant: ButtonVariant.icon,
                          icon: SailSVGAsset.iconQuestion,
                          onPressed: () async {
                            await widgetDialog(
                              context: context,
                              title: 'About UTXO Distribution',
                              child: const UTXODistributionHelp(),
                            );
                          },
                        ),
                        child: UTXOBars(
                          utxos: model.entries,
                          onBucketContextMenu: (bucket, position) {
                            _showBucketContextMenu(context, bucket, position);
                          },
                          onConsolidate: SailStyleValues.phoneLayout(context)
                              ? null
                              : () => WalletPage.openSubtab(WalletPage.consolidateSubtabLabel),
                        ),
                      ),
                    ),
                  ),
                SliverSailTable(
                  minHeight: tableHeight,
                  child: UTXOTable(
                    entries: entries,
                    model: model,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The label of a coin: its own label, else the label of its address.
String coinLabel(UnspentOutput utxo) {
  final own = GetIt.I<CoinSelectionProvider>().getLabel(utxo.output);
  return own.isNotEmpty ? own : utxo.label;
}

/// The text of the freeze item in a coin menu.
String coinFreezeMenuLabel(String outpoint) {
  if (GetIt.I<ConsolidationProvider>().reservedOutpoints.contains(outpoint)) {
    return 'Held by a consolidation';
  }
  return GetIt.I<CoinSelectionProvider>().isFrozen(outpoint) ? 'Unfreeze UTXO' : 'Freeze UTXO';
}

/// Freezes or unfreezes a coin from a coin menu, and shows a failure in a toast.
Future<void> toggleCoinFreeze(BuildContext context, String outpoint) async {
  // A consolidation broadcasts its queued transactions without a new freeze,
  // so a release here would break that send.
  if (GetIt.I<ConsolidationProvider>().reservedOutpoints.contains(outpoint)) {
    showSailToast(context, 'A consolidation holds this coin. Stop it from the Consolidate tab first.');
    return;
  }
  final coins = GetIt.I<CoinSelectionProvider>();
  final freeze = !coins.isFrozen(outpoint);
  try {
    await coins.setFrozen(outpoint, freeze);
  } catch (e) {
    if (context.mounted) {
      showSailToast(
        context,
        'BitWindow could not ${freeze ? 'freeze' : 'unfreeze'} the coin: $e',
        variant: SailToastVariant.destructive,
      );
    }
  }
}

/// The label cell of a coin table. Its first [columnChars] characters size the column, and a longer label ends
/// with an ellipsis, so it does not push the other columns out.
SailTableCell coinLabelCell(String label, {bool monospace = false, int columnChars = 24}) => SailTableCell(
  value: label.characters.take(columnChars).toString(),
  copyValue: label,
  monospace: monospace,
  child: SailText.primary13(label, monospace: monospace, overflow: TextOverflow.ellipsis),
);

class UTXOTable extends StatefulWidget {
  final List<UnspentOutput> entries;
  final LatestUTXOsViewModel model;

  const UTXOTable({
    super.key,
    required this.entries,
    required this.model,
  });

  @override
  State<UTXOTable> createState() => _UTXOTableState();
}

class _UTXOTableState extends State<UTXOTable> {
  // One list, so a new column can't be added to the header and forgotten in
  // the sort lookups.
  static const _columns = [
    'frozen',
    'date',
    'value',
    'label',
    'deniability',
    'splittable',
    'output',
    'address',
    'path',
  ];

  String sortColumn = 'date';
  bool sortAscending = true;
  List<UnspentOutput> sortedEntries = [];
  int frozenCount = 0;
  bool hideFrozen = false;

  CoinSelectionProvider get _coinSelection => GetIt.I<CoinSelectionProvider>();

  @override
  void initState() {
    super.initState();
    sortEntries();
    _coinSelection.addListener(_onMetadataChange);
  }

  @override
  void dispose() {
    _coinSelection.removeListener(_onMetadataChange);
    super.dispose();
  }

  void _onMetadataChange() {
    setState(() {
      sortEntries();
    });
  }

  @override
  void didUpdateWidget(UTXOTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entries, oldWidget.entries)) {
      sortEntries();
    }
  }

  void onSort(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
      sortEntries();
    });
  }

  void sortEntries() {
    frozenCount = widget.entries.where((u) => _coinSelection.isFrozen(u.output)).length;
    final entries = hideFrozen
        ? widget.entries.where((u) => !_coinSelection.isFrozen(u.output)).toList()
        : List<UnspentOutput>.of(widget.entries);

    entries.sort((a, b) {
      dynamic aValue, bValue;
      switch (sortColumn) {
        case 'frozen':
          aValue = _coinSelection.isFrozen(a.output) ? 1 : 0;
          bValue = _coinSelection.isFrozen(b.output) ? 1 : 0;
          break;
        case 'date':
          aValue = _receivedAtMicros(a);
          bValue = _receivedAtMicros(b);
          if (aValue == bValue) {
            return a.output.compareTo(b.output);
          }
          break;
        case 'output':
          aValue = a.output;
          bValue = b.output;
          break;
        case 'address':
          aValue = a.address;
          bValue = b.address;
          break;
        case 'path':
          aValue = a.derivationPath;
          bValue = b.derivationPath;
          break;
        case 'label':
          aValue = coinLabel(a);
          bValue = coinLabel(b);
          break;
        case 'value':
          aValue = a.valueSats;
          bValue = b.valueSats;
          break;
        case 'deniability':
          aValue = getDenialHops(a);
          bValue = getDenialHops(b);
          break;
        case 'splittable':
          aValue = splittableRank(a);
          bValue = splittableRank(b);
          break;
      }
      return sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });

    sortedEntries = entries;
  }

  // The precision of Timestamp.toDateTime, with no DateTime per compare.
  static int _receivedAtMicros(UnspentOutput utxo) =>
      utxo.receivedAt.seconds.toInt() * Duration.microsecondsPerSecond + utxo.receivedAt.nanos ~/ 1000;

  // Unknown sorts below no, no below yes.
  int splittableRank(UnspentOutput utxo) {
    if (!utxo.hasSplittable()) {
      return 0;
    }
    return utxo.splittable ? 2 : 1;
  }

  int getDenialHops(UnspentOutput utxo) {
    if (!utxo.hasDenialInfo()) {
      return 0;
    }
    return utxo.denialInfo.hopsCompleted;
  }

  Color? getDenialColor(BuildContext context, UnspentOutput utxo) {
    final theme = SailTheme.of(context);
    final hops = getDenialHops(utxo);

    if (hops == 0) {
      return theme.colors.error;
    } else if (hops <= 2) {
      return theme.colors.orange;
    } else {
      return theme.colors.success;
    }
  }

  bool isDenied(UnspentOutput utxo) {
    return utxo.hasDenialInfo() && getDenialHops(utxo) > 0;
  }

  Future<void> _showLabelDialog(BuildContext context, UnspentOutput utxo) async {
    final controller = TextEditingController(text: coinLabel(utxo));
    final result = await showThemedDialog<String>(
      context: context,
      builder: (context) => SailDialog(
        title: 'Edit UTXO Label',
        subtitle: 'Add a label to help identify this UTXO',
        maxWidth: 400,
        maxHeight: 200,
        actions: [
          SailButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            onPressed: () async => Navigator.pop(context),
          ),
          SailButton(
            label: 'Save',
            onPressed: () async => Navigator.pop(context, controller.text),
          ),
        ],
        child: SailTextField(
          controller: controller,
          hintText: 'e.g., Cold storage, Exchange deposit',
          autofocus: true,
        ),
      ),
    );

    if (result == null) {
      return;
    }
    try {
      await _coinSelection.setLabel(utxo.output, result);
    } catch (e) {
      if (context.mounted) {
        showSailToast(context, 'BitWindow could not save the label: $e', variant: SailToastVariant.destructive);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final theme = SailTheme.of(context);

    return SailCard(
      title: 'Your UTXOs',
      error: widget.model.readError,
      bottomPadding: false,
      widgetHeaderEnd: SailCheckbox(
        value: hideFrozen,
        onChanged: (value) {
          setState(() {
            hideFrozen = value;
            sortEntries();
          });
        },
        label: 'Hide frozen ($frozenCount)',
      ),
      child: SailSkeletonizer(
        description: 'Waiting for enforcer to start and wallet to sync..',
        enabled: widget.model.loading,
        child: ListenableBuilder(
          listenable: Listenable.merge([formatter, _coinSelection]),
          builder: (context, child) => SailTable(
            rowBackgroundColor: (index) {
              final utxo = sortedEntries[index];
              if (_coinSelection.isFrozen(utxo.output)) {
                return theme.colors.divider.withValues(alpha: 0.3);
              }
              return isDenied(utxo) ? theme.colors.success.withValues(alpha: 0.1) : null;
            },
            getRowId: (index) => sortedEntries[index].output,
            phoneColumns: const [2, 3, 6],
            headerBuilder: (context) => [
              SailTableHeaderCell(name: '', onSort: () => onSort('frozen')),
              SailTableHeaderCell(
                name: 'Date',
                onSort: () => onSort('date'),
                filterWidget: DateFilter(range: widget.model.dateRange, onChanged: widget.model.setDateRange),
              ),
              SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight, onSort: () => onSort('value')),
              SailTableHeaderCell(name: 'Label', onSort: () => onSort('label')),
              SailTableHeaderCell(name: 'Deniability', onSort: () => onSort('deniability')),
              SailTableHeaderCell(name: 'Split', onSort: () => onSort('splittable')),
              SailTableHeaderCell(name: 'Output', onSort: () => onSort('output')),
              SailTableHeaderCell(name: 'Address', onSort: () => onSort('address')),
              SailTableHeaderCell(name: 'Path', onSort: () => onSort('path')),
            ],
            rowBuilder: (context, row, selected) {
              final utxo = sortedEntries[row];
              final formattedAmount = formatter.formatSats(utxo.valueSats.toInt());
              final isFrozen = _coinSelection.isFrozen(utxo.output);

              return [
                SailTableCell(
                  width: 14,
                  value: '',
                  child: isFrozen
                      ? SailSVG.fromAsset(SailSVGAsset.snowflake, width: 14, color: theme.colors.info)
                      : const SizedBox(width: 14),
                ),
                SailTableCell(
                  value: utxo.confirmations == 0
                      ? 'Pending'
                      : (utxo.hasReceivedAt() ? formatDate(utxo.receivedAt.toDateTime().toLocal()) : '—'),
                  textColor: utxo.confirmations == 0 ? theme.colors.orange : null,
                ),
                SailTableCell(
                  value: formattedAmount,
                  alignment: Alignment.centerRight,
                  monospace: true,
                ),
                coinLabelCell(coinLabel(utxo), monospace: true),
                SailTableCell(
                  value: denialStatusWithHops(utxo),
                  textColor: getDenialColor(context, utxo),
                  monospace: true,
                ),
                SailTableCell(
                  value: !utxo.hasSplittable() ? '—' : (utxo.splittable ? 'Yes' : 'No'),
                  child: !utxo.hasSplittable()
                      ? SailText.secondary12('—')
                      : SailSVG.fromAsset(
                          SailSVGAsset.split,
                          width: 14,
                          color: utxo.splittable ? theme.colors.success : theme.colors.textSecondary,
                        ),
                ),
                SailTableCell(
                  value: '',
                  copyValue: utxo.output,
                  child: _OutputCell(utxo.output),
                ),
                SailTableCell(
                  value: shortenId(utxo.address),
                  copyValue: utxo.address,
                  monospace: true,
                ),
                SailTableCell(
                  value: utxo.derivationPath.isEmpty ? '—' : utxo.derivationPath,
                  copyValue: utxo.derivationPath,
                  monospace: true,
                ),
              ];
            },
            rowCount: sortedEntries.length,
            emptyPlaceholder: hideFrozen ? 'No unfrozen UTXOs' : 'No UTXOs in wallet',
            drawGrid: true,
            sortColumnIndex: _columns.indexOf(sortColumn),
            sortAscending: sortAscending,
            onSort: (columnIndex, ascending) => onSort(_columns[columnIndex]),
            onDoubleTap: (rowId) => showTransactionDetails(context, rowId.split(':').first),
            contextMenuItems: (rowId) {
              final utxo = sortedEntries.firstWhere((u) => u.output == rowId);

              return [
                SailMenuItem(
                  onSelected: () async => toggleCoinFreeze(context, rowId),
                  child: SailText.primary12(coinFreezeMenuLabel(rowId)),
                ),
                SailMenuItem(
                  onSelected: () async {
                    await _showLabelDialog(context, utxo);
                  },
                  child: SailText.primary12('Edit Label'),
                ),
                SailMenuItem(
                  onSelected: () async {
                    await showTransactionDetails(context, rowId.split(':').first);
                  },
                  child: SailText.primary12('Show Details'),
                ),
                MempoolMenuItem(txid: rowId.split(':').first),
              ];
            },
          ),
        ),
      ),
    );
  }
}

/// Orchestrator migration status:
/// - UTXOs list: routed via TransactionProvider (already on orchestrator)
/// - setUTXOMetadata (freeze/label): STAYS on bitwindowd — BW-only coin control
/// - getUTXODistribution: STAYS on bitwindowd — BW-only chart aggregation
/// - Consolidation getNewAddress: MOVED to orchestrator
/// - Consolidation sendTransaction: MOVED to orchestrator shared wallet RPC
class LatestUTXOsViewModel extends BaseViewModel with ChangeTrackingMixin {
  final TransactionProvider _txProvider = GetIt.I<TransactionProvider>();
  final CoinSelectionProvider _coinSelection = GetIt.I<CoinSelectionProvider>();
  final EnforcerRPC _enforcerRPC = GetIt.I<EnforcerRPC>();

  static final _loadingEntries = List<UnspentOutput>.unmodifiable([
    UnspentOutput(
      output: 'dummy_output:0',
      address: 'dummy_address',
      label: 'dummy_label',
    ),
    UnspentOutput(
      output: 'dummy_output:1',
      address: 'dummy_address',
      label: 'dummy_label',
    ),
    UnspentOutput(
      output: 'dummy_output:2',
      address: 'dummy_address',
      label: 'dummy_label',
    ),
  ]);

  List<UnspentOutput>? _entries;
  List<UnspentOutput>? _entriesSource;
  ({DateTime start, DateTime end})? _entriesRange;

  /// The same list until the UTXOs, the loading state or the date range change.
  List<UnspentOutput> get entries {
    if (loading) {
      return _loadingEntries;
    }

    final utxos = _txProvider.utxos;
    final range = dateRange;
    if (_entries != null && identical(utxos, _entriesSource) && range == _entriesRange) {
      return _entries!;
    }
    _entriesSource = utxos;
    _entriesRange = range;
    return _entries = range == null
        ? List.unmodifiable(utxos)
        : List.unmodifiable(
            utxos.where((utxo) => utxo.hasReceivedAt() && isInDateRange(utxo.receivedAt.toDateTime(), range)),
          );
  }

  String sortColumn = 'date';
  bool sortAscending = true;
  ({DateTime start, DateTime end})? dateRange;

  LatestUTXOsViewModel() {
    initChangeTracker();
    _txProvider.addListener(_onChange);
    _coinSelection.addListener(_onChange);
  }

  void _onChange() {
    track('entriesss', entries);
    track('loading', loading);
    track('readError', readError);
    notifyIfChanged();
  }

  bool get loading => _enforcerRPC.initializingBinary;

  /// Why the coins or their freeze marks did not read. The rows then show the last good read.
  String? get readError => _txProvider.error ?? _coinSelection.error;

  @override
  void dispose() {
    _txProvider.removeListener(_onChange);
    _coinSelection.removeListener(_onChange);
    super.dispose();
  }

  void setDateRange(({DateTime start, DateTime end})? range) {
    dateRange = range;
    notifyListeners();
  }
}

class _OutputCell extends StatelessWidget {
  final String output;

  const _OutputCell(this.output);

  @override
  Widget build(BuildContext context) {
    final separator = output.lastIndexOf(':');
    return Row(
      children: [
        Flexible(child: SailText.primary13(output.substring(0, separator), overflow: TextOverflow.ellipsis)),
        SailText.primary13(output.substring(separator)),
      ],
    );
  }
}

class UTXODistributionHelp extends StatelessWidget {
  const UTXODistributionHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding12,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary13(
          'UTXOs (Unspent Transaction Outputs) are the individual "coins" in your wallet. '
          'This chart shows how your balance is distributed across different UTXO sizes.',
        ),
        SailText.primary13(
          'Why it matters: Many small UTXOs can lead to higher transaction fees. '
          'Consider consolidating small UTXOs when fees are low.',
        ),
        SailText.primary13(
          '${SailStyleValues.phoneLayout(context) ? 'Long-press any bar' : 'Right-click on any bar'} '
          'to see options for the UTXOs in that bucket.',
        ),
      ],
    );
  }
}

/// Dialog for consolidating small UTXOs
