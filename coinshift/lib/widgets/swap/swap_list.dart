import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:coinshift/providers/swap_provider.dart';
import 'package:coinshift/widgets/swap/swap_status_badge.dart';

/// Status filter for swaps
enum SwapStatusFilter {
  all('All'),
  pending('Pending'),
  waitingConfirmations('Waiting Confirmations'),
  readyToClaim('Ready To Claim'),
  completed('Completed'),
  cancelled('Cancelled');

  final String label;
  const SwapStatusFilter(this.label);
}

/// The swaps table with search and filter; a row opens the swap's side panel.
class SwapList extends StatelessWidget {
  final bool showOnlyActive;

  const SwapList({super.key, this.showOnlyActive = false});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<SwapListViewModel>.reactive(
      viewModelBuilder: () => SwapListViewModel(),
      builder: (context, model, child) {
        final phone = SailStyleValues.phoneLayout(context);
        final selected = model.selectedSwap;
        final table = SailCard(
          title: showOnlyActive ? 'Active Swaps' : 'My Swaps',
          bottomPadding: phone,
          widgetHeaderEnd: phone ? null : _SwapListControls(model: model),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (phone)
                Padding(
                  padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
                  child: _SwapListControls(
                    model: model,
                    onFound: (swapId) => unawaited(showSwapSheet(context, model, swapId)),
                  ),
                ),
              if (model.successMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
                  child: SidechainNotice(
                    message: model.successMessage!,
                    tone: SidechainNoticeTone.success,
                    trailing: SailIconBoxButton(
                      icon: SailSVGAsset.x,
                      tooltip: 'Dismiss',
                      size: 22,
                      onPressed: () async => model.clearSuccessMessage(),
                    ),
                  ),
                ),
              if (model.searchError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
                  child: SidechainNotice(message: model.searchError!, tone: SidechainNoticeTone.error),
                ),
              Expanded(
                child: SailSkeletonizer(
                  description: 'Loading swaps...',
                  enabled: model.isLoading && model.filteredSwaps.isEmpty,
                  child: _SwapTable(
                    swaps: model.filteredSwaps,
                    selectedSwapId: phone ? null : model.expandedSwapId,
                    onClaim: (swap) => model.claimSwap(context, swap),
                    onSelect: (swapId) {
                      if (phone) {
                        unawaited(showSwapSheet(context, model, swapId));
                        return;
                      }
                      model.toggleSwapExpanded(swapId);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
        if (phone || selected == null) {
          return table;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: table),
            const SizedBox(width: SailStyleValues.padding12),
            SwapSidePanel(
              swap: selected,
              onClose: () async => model.toggleSwapExpanded(selected.idHex),
              onClaim: () => model.claimSwap(context, selected),
            ),
          ],
        );
      },
    );
  }
}

/// Opens the phone sheet of a swap. The sheet follows the provider, so a new state or a claim shows at once.
Future<void> showSwapSheet(BuildContext context, SwapListViewModel model, String swapId) {
  return showSailSidePanel(
    context,
    (context, close) => ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final swap = model.swaps.where((swap) => swap.idHex == swapId).firstOrNull;
        if (swap == null) {
          return const SizedBox.shrink();
        }
        return SwapSidePanel(swap: swap, onClose: close, onClaim: () => model.claimSwap(context, swap));
      },
    ),
  );
}

/// Search by swap ID, the status filter and Refresh.
class _SwapListControls extends StatelessWidget {
  final SwapListViewModel model;

  /// Runs with the swap ID after a search finds exactly one swap.
  final void Function(String swapId)? onFound;

  const _SwapListControls({required this.model, this.onFound});

  void _search() {
    model.searchSwap();
    final found = model.searchedSwap;
    if (found != null) {
      onFound?.call(found.idHex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = SailTextField(
      controller: model.searchController,
      hintText: 'Search by Swap ID...',
      onSubmitted: (_) => _search(),
      suffixWidget: SailRow(
        spacing: SailStyleValues.padding04,
        mainAxisSize: MainAxisSize.min,
        children: [
          SailButton(
            label: 'Search',
            small: true,
            variant: ButtonVariant.ghost,
            onPressed: () async => _search(),
          ),
          if (model.searchController.text.isNotEmpty)
            SailButton(
              label: 'Clear',
              small: true,
              variant: ButtonVariant.ghost,
              onPressed: () async => model.clearSearch(),
            ),
        ],
      ),
    );
    final filter = SailDropdownButton<SwapStatusFilter>(
      value: model.statusFilter,
      items: SwapStatusFilter.values
          .map((filter) => SailDropdownItem<SwapStatusFilter>(value: filter, label: filter.label))
          .toList(),
      onChanged: (filter) {
        if (filter != null) {
          model.setStatusFilter(filter);
        }
      },
    );
    final refresh = SailIconBoxButton(
      icon: SailSVGAsset.refreshCw,
      tooltip: 'Refresh',
      size: 32,
      onPressed: model.isLoading ? null : () async => await model.refresh(),
    );
    return SailRow(
      spacing: SailStyleValues.padding08,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (model.isCheckingConfirmations) SailText.secondary12('Checking confirmations...'),
        if (SailStyleValues.phoneLayout(context)) Expanded(child: search) else SizedBox(width: 280, child: search),
        filter,
        refresh,
      ],
    );
  }
}

class _SwapTable extends StatefulWidget {
  final List<CoinShiftSwap> swaps;
  final Function(CoinShiftSwap) onClaim;
  final void Function(String swapId) onSelect;
  final String? selectedSwapId;

  const _SwapTable({required this.swaps, required this.onClaim, required this.onSelect, this.selectedSwapId});

  @override
  State<_SwapTable> createState() => _SwapTableState();
}

class _SwapTableState extends State<_SwapTable> {
  String sortColumn = 'created';
  bool sortAscending = false;

  static const _columns = ['id', 'direction', 'chain', 'amount', 'status'];

  void onSort(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
    });
  }

  List<CoinShiftSwap> get sortedSwaps {
    final sorted = List<CoinShiftSwap>.from(widget.swaps);
    sorted.sort((a, b) {
      dynamic aValue, bValue;
      switch (sortColumn) {
        case 'id':
          aValue = a.idHex;
          bValue = b.idHex;
        case 'direction':
          aValue = a.direction.name;
          bValue = b.direction.name;
        case 'chain':
          aValue = a.parentChain.label;
          bValue = b.parentChain.label;
        case 'amount':
          aValue = a.l2Amount;
          bValue = b.l2Amount;
        case 'status':
          aValue = a.state.state;
          bValue = b.state.state;
        case 'created':
        default:
          aValue = a.createdAtHeight;
          bValue = b.createdAtHeight;
      }
      return sortAscending ? Comparable.compare(aValue, bValue) : Comparable.compare(bValue, aValue);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final swaps = sortedSwaps;
    final phone = SailStyleValues.phoneLayout(context);

    final table = ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailTable(
        getRowId: (index) => swaps[index].idHex,
        selectedRowId: widget.selectedSwapId,
        headerBuilder: (context) => [
          SailTableHeaderCell(name: 'Swap ID', onSort: () => onSort('id')),
          SailTableHeaderCell(name: 'Direction', onSort: () => onSort('direction')),
          SailTableHeaderCell(name: 'Chain', onSort: () => onSort('chain')),
          SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight, onSort: () => onSort('amount')),
          SailTableHeaderCell(name: 'Status', onSort: () => onSort('status')),
        ],
        rowBuilder: (context, row, selected) {
          final swap = swaps[row];
          final waiting = swap.state.isWaitingConfirmations;
          return [
            SailTableCell(value: '${swap.idHex.substring(0, 8)}...', copyValue: swap.idHex, monospace: true),
            SailTableCell(value: swap.direction == SwapDirection.l2ToL1 ? 'L2 → L1' : 'L1 → L2'),
            SailTableCell(value: swap.parentChain.label),
            SailTableCell(
              value: formatter.formatSats(swap.l2Amount),
              monospace: true,
              alignment: Alignment.centerRight,
            ),
            SailTableCell(
              value: swapStatusLabel(swap.state),
              child: waiting
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwapStatusBadge(state: swap.state),
                        SailText.secondary12(
                          '${swap.state.currentConfirmations ?? 0} / ${swap.state.requiredConfirmations ?? 1}',
                        ),
                      ],
                    )
                  : SwapStatusBadge(state: swap.state),
            ),
          ];
        },
        rowCount: swaps.length,
        drawGrid: true,
        phoneColumns: const [0, 3, 4],
        sortColumnIndex: _columns.indexOf(sortColumn),
        sortAscending: sortAscending,
        onSort: (columnIndex, ascending) => onSort(_columns[columnIndex]),
        onRowTap: widget.onSelect,
        contextMenuItems: (rowId) {
          final swap = swaps.firstWhere((swap) => swap.idHex == rowId);
          return [
            if (swap.state.isReadyToClaim)
              SailMenuItem(onSelected: () => widget.onClaim(swap), child: SailText.primary12('Claim')),
            SailMenuItem(
              onSelected: () => Clipboard.setData(ClipboardData(text: swap.idHex)),
              child: SailText.primary12('Copy swap ID'),
            ),
          ];
        },
      ),
    );

    if (swaps.isNotEmpty) {
      return table;
    }
    return Stack(
      children: [
        table,
        Center(
          child: SailColumn(
            spacing: SailStyleValues.padding04,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phone) SailText.primary13('No swaps found', bold: true) else SailText.primary15('No swaps found'),
              SailText.secondary12('Swaps will appear here once created'),
            ],
          ),
        ),
      ],
    );
  }
}

/// The 380 px panel of one swap: amount, status, Claim when ready, and its details.
class SwapSidePanel extends StatelessWidget {
  final CoinShiftSwap swap;
  final Future<void> Function() onClose;
  final Future<void> Function() onClaim;

  const SwapSidePanel({super.key, required this.swap, required this.onClose, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final state = swap.state;
    final current = state.currentConfirmations ?? 0;
    final required = state.requiredConfirmations ?? 1;
    return SailSidePanel(
      title: '${swap.idHex.substring(0, 8)}...',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.primary24(formatter.formatSats(swap.l2Amount), bold: true),
          SailText.secondary13(swap.direction == SwapDirection.l2ToL1 ? 'L2 → L1' : 'L1 → L2'),
          const SizedBox(height: SailStyleValues.padding12),
          Align(
            alignment: Alignment.centerLeft,
            child: SailStatusPill(label: swapStatusLabel(state), tone: swapStatusTone(state)),
          ),
          if (state.isReadyToClaim) ...[
            const SizedBox(height: SailStyleValues.padding12),
            SailButton(label: 'Claim', onPressed: onClaim),
          ],
          if (state.isWaitingConfirmations) ...[
            const SizedBox(height: SailStyleValues.padding16),
            Row(
              children: [
                Expanded(child: SailText.primary15('Confirmations')),
                SailText.secondary15('$current / $required'),
              ],
            ),
            const SizedBox(height: SailStyleValues.padding08),
            ProgressBar(
              current: required > 0 ? (current / required).clamp(0.0, 1.0) : 0.0,
              goal: 1,
              small: true,
              hideProgressInside: true,
            ),
          ],
          if (swap.createdAtHeight == 0) ...[
            const SizedBox(height: SailStyleValues.padding12),
            const SidechainNotice(
              message: 'PENDING (in mempool, not yet in block). Mine a block or wait for one to be mined to confirm your swap.',
              tone: SidechainNoticeTone.error,
            ),
          ],
          const SizedBox(height: SailStyleValues.padding16),
          SailText.primary13('Details', bold: true),
          const SizedBox(height: SailStyleValues.padding08),
          SailDetailGroup(
            children: [
              SailDetailLine(label: 'Chain', value: swap.parentChain.label),
              SailDetailLine(label: 'State', value: state.toString()),
              SailDetailLine(label: 'L2 Amount', value: formatter.formatSats(swap.l2Amount)),
              if (swap.l1Amount != null)
                SailDetailLine(label: 'L1 Amount', value: formatter.formatSats(swap.l1Amount!)),
              SailDetailLine(label: 'L2 Recipient', value: swap.l2Recipient ?? 'Open Swap'),
              SailDetailLine(
                label: 'Created',
                value: swap.createdAtHeight == 0 ? 'Pending' : 'Block ${swap.createdAtHeight}',
              ),
              SailDetailLine(label: 'Required Confirmations', value: swap.requiredConfirmations.toString()),
            ],
          ),
          const SizedBox(height: SailStyleValues.padding12),
          SailDetailGroup(
            children: [
              SailStackedDetail(label: 'Swap ID', value: swap.idHex, largeLabel: true, selectable: true),
              if (swap.l1RecipientAddress != null)
                SailStackedDetail(
                  label: 'L1 Recipient',
                  value: swap.l1RecipientAddress!,
                  largeLabel: true,
                  selectable: true,
                ),
              if (swap.l1Txid != null)
                SailStackedDetail(label: 'L1 TxID', value: swap.l1Txid!, largeLabel: true, selectable: true),
            ],
          ),
          if (state.isWaitingConfirmations) ...[
            const SizedBox(height: SailStyleValues.padding12),
            const SidechainNotice(
              title: 'Waiting for Confirmations',
              message: 'Confirmations are checked automatically every 10 seconds.',
            ),
          ],
          if (state.isPending) ...[
            const SizedBox(height: SailStyleValues.padding12),
            SidechainNotice(
              title: 'For users filling this swap',
              message:
                  'Only send the L1 transaction to fill this swap after the swap has '
                  '${swap.requiredConfirmations} confirmations from the L2 sidechain.',
              tone: SidechainNoticeTone.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class SwapListViewModel extends BaseViewModel {
  SwapProvider get _swapProvider => GetIt.I.get<SwapProvider>();

  final TextEditingController searchController = TextEditingController();

  SwapStatusFilter statusFilter = SwapStatusFilter.all;
  String? expandedSwapId;
  CoinShiftSwap? searchedSwap;
  String? searchError;
  String? successMessage;
  bool isCheckingConfirmations = false;

  List<CoinShiftSwap> get swaps => _swapProvider.swaps;
  List<CoinShiftSwap> get activeSwaps => _swapProvider.activeSwaps;
  bool get isLoading => _swapProvider.isLoading;

  /// The swap the side panel shows.
  CoinShiftSwap? get selectedSwap => swaps.where((swap) => swap.idHex == expandedSwapId).firstOrNull;

  /// Filter swaps by status
  List<CoinShiftSwap> get filteredSwaps {
    return swaps.where((swap) {
      switch (statusFilter) {
        case SwapStatusFilter.all:
          return true;
        case SwapStatusFilter.pending:
          return swap.state.isPending;
        case SwapStatusFilter.waitingConfirmations:
          return swap.state.isWaitingConfirmations;
        case SwapStatusFilter.readyToClaim:
          return swap.state.isReadyToClaim;
        case SwapStatusFilter.completed:
          return swap.state.isCompleted;
        case SwapStatusFilter.cancelled:
          return swap.state.isCancelled;
      }
    }).toList();
  }

  SwapListViewModel() {
    _swapProvider.addListener(notifyListeners);
  }

  void setStatusFilter(SwapStatusFilter filter) {
    statusFilter = filter;
    notifyListeners();
  }

  void toggleSwapExpanded(String swapId) {
    if (expandedSwapId == swapId) {
      expandedSwapId = null;
    } else {
      expandedSwapId = swapId;
    }
    notifyListeners();
  }

  void searchSwap() {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      searchedSwap = null;
      searchError = null;
      notifyListeners();
      return;
    }

    // Search in loaded swaps first
    final matches = swaps.where((swap) => swap.idHex.toLowerCase().startsWith(query.toLowerCase())).toList();

    if (matches.isEmpty) {
      searchError = 'No swap found starting with "$query"';
      searchedSwap = null;
    } else if (matches.length > 1) {
      searchError = 'Multiple swaps found. Please enter more characters.';
      searchedSwap = null;
    } else {
      searchedSwap = matches.first;
      expandedSwapId = matches.first.idHex;
      searchError = null;
    }
    notifyListeners();
  }

  void clearSearch() {
    searchController.clear();
    searchedSwap = null;
    searchError = null;
    notifyListeners();
  }

  void clearSuccessMessage() {
    successMessage = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _swapProvider.refresh();
  }

  Future<void> claimSwap(BuildContext context, CoinShiftSwap swap) async {
    final txid = await _swapProvider.claimSwap(swap);
    if (txid != null) {
      successMessage = 'Swap claimed successfully! Transaction ID: $txid';
      notifyListeners();
    } else if (_swapProvider.error != null && context.mounted) {
      showSailToast(
        context,
        'Failed to claim: ${_swapProvider.error}',
        variant: SailToastVariant.destructive,
      );
    }
  }

  @override
  void dispose() {
    _swapProvider.removeListener(notifyListeners);
    searchController.dispose();
    super.dispose();
  }
}
