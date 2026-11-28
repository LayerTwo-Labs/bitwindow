import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/pages/explorer/load_transaction_dialog.dart';
import 'package:bitwindow/providers/mempool_watch_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class TransactionCensorshipPage extends StatelessWidget {
  const TransactionCensorshipPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailScaffold(
      backgroundColor: theme.colors.background,
      appBar: SailAppBar.build(context, title: SailText.primary20('Transaction Censorship')),
      body: Padding(
        padding: const EdgeInsets.all(SailStyleValues.padding12),
        child: ViewModelBuilder<TransactionCensorshipViewModel>.reactive(
          viewModelBuilder: () => TransactionCensorshipViewModel(),
          builder: (context, model, child) {
            final provider = model.provider;
            if (SailStyleValues.phoneLayout(context)) {
              return SailCard(
                title: 'Transaction Censorship',
                subtitle: 'Every transaction in the mempool and how long it has waited to be mined.',
                error: provider.error,
                bottomPadding: false,
                child: model.isLight
                    ? SailText.secondary13('Transaction Censorship needs a full node.')
                    : SailColumn(
                        spacing: SailStyleValues.padding16,
                        children: [
                          _Header(model: model),
                          if (provider.alarm) _AlarmBanner(count: provider.alarmCount),
                          if (provider.truncated)
                            SailText.secondary13('Showing the first $maxPendingRows of ${provider.total} candidates'),
                          Expanded(child: _Table(model: model)),
                        ],
                      ),
              );
            }
            return _DesktopBody(model: model);
          },
        ),
      ),
    );
  }
}

class _DesktopBody extends StatelessWidget {
  final TransactionCensorshipViewModel model;

  const _DesktopBody({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final provider = model.provider;
    final status = provider.status;
    return SailColumn(
      spacing: SailStyleValues.padding12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailColumn(
          spacing: 2,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailText.primary20('Transaction Censorship', bold: true),
            SailText.secondary13('Every transaction in the mempool and how long it has waited to be mined.'),
            if (provider.error != null) SailText.primary12(provider.error!, color: theme.colors.error),
          ],
        ),
        if (model.isLight)
          Expanded(child: SailCard(child: SailText.secondary13('Transaction Censorship needs a full node.')))
        else ...[
          SailSkeletonizer(
            enabled: model.loading,
            description: 'Reading the watch status',
            child: SailStrip(
              lead: SailRow(
                spacing: SailStyleValues.padding12,
                children: [
                  SailStatusDot(tone: status.enabled ? SailStatusTone.success : SailStatusTone.neutral),
                  SailText.primary13(model.statusText),
                ],
              ),
              actions: [
                SailButton(
                  label: status.enabled ? 'Stop watching' : 'Start watching',
                  disabled: model.loading,
                  onPressed: model.toggle,
                ),
                SailRowMenuButton(
                  items: () => [
                    if (!model.loading)
                      SailMenuItem(
                        onSelected: () => unawaited(provider.reset()),
                        child: SailText.primary12('Reset tracker'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (provider.alarm) _AlarmBanner(count: provider.alarmCount),
          Expanded(
            child: SailCard(
              bottomPadding: false,
              child: SailColumn(
                spacing: SailStyleValues.padding12,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: SailTextField(
                          controller: model.searchController,
                          hintText: 'Search txid',
                          onChanged: (_) => model.onSearchChanged(),
                        ),
                      ),
                      const Spacer(),
                      if (provider.truncated)
                        SailText.secondary12('Showing the first $maxPendingRows of ${provider.total} candidates'),
                    ],
                  ),
                  Expanded(child: _Table(model: model)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final TransactionCensorshipViewModel model;

  const _Header({required this.model});

  @override
  Widget build(BuildContext context) {
    final provider = model.provider;
    final status = provider.status;

    return SailSkeletonizer(
      enabled: model.loading,
      description: 'Reading the watch status',
      child: SailColumn(
        spacing: SailStyleValues.padding08,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailRow(
            spacing: SailStyleValues.padding08,
            children: [
              SailButton(
                label: status.enabled ? 'Stop watching' : 'Start watching',
                variant: status.enabled ? ButtonVariant.outline : ButtonVariant.primary,
                small: true,
                disabled: model.loading,
                onPressed: model.toggle,
              ),
              SailButton(
                label: 'Reset tracker',
                variant: ButtonVariant.outline,
                small: true,
                disabled: model.loading,
                onPressed: provider.reset,
              ),
            ],
          ),
          SailText.secondary13(model.statusText),
          SailTextField(
            controller: model.searchController,
            hintText: 'Search txid',
            onChanged: (_) => model.onSearchChanged(),
          ),
        ],
      ),
    );
  }
}

class _AlarmBanner extends StatelessWidget {
  final int count;

  const _AlarmBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final textColor = theme.colors.destructiveButtonText;
    return Container(
      key: const Key('censorship-alarm'),
      padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 10),
      decoration: BoxDecoration(color: theme.colors.destructiveButtonBackground, borderRadius: theme.chrome.radius),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: textColor),
          ),
          const SizedBox(width: SailStyleValues.padding08),
          Expanded(
            child: SailText.primary13(
              'Censorship alarm: $count pending ${count == 1 ? 'transaction scores' : 'transactions score'} above ${alarmScore.toInt()}',
              color: textColor,
              bold: true,
            ),
          ),
        ],
      ),
    );
  }
}

const _columns = <MempoolWatchSort?>[
  null,
  MempoolWatchSort.feeRate,
  MempoolWatchSort.fee,
  MempoolWatchSort.vsize,
  MempoolWatchSort.firstSeen,
  MempoolWatchSort.blocksWaited,
  MempoolWatchSort.blocksEligible,
  MempoolWatchSort.score,
  MempoolWatchSort.timeWaited,
];

const _columnNames = [
  'Txid',
  'Fee rate',
  'Fee',
  'vSize',
  'First seen',
  'Blocks waited',
  'Blocks eligible',
  'Score',
  'Time waited',
];

// Fits the header with its sort arrow and info icon, which the table does not measure.
const _scoreColumnWidth = 110.0;

class _Table extends StatelessWidget {
  final TransactionCensorshipViewModel model;

  const _Table({required this.model});

  @override
  Widget build(BuildContext context) {
    final provider = model.provider;
    final formatter = GetIt.I<FormatterProvider>();
    final theme = SailTheme.of(context);
    final rows = provider.rows;

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailTable(
        getRowId: (index) => rows[index].txid,
        headerBuilder: (context) => [
          for (var i = 0; i < _columns.length; i++)
            SailTableHeaderCell(
              name: _columnNames[i],
              sortable: _columns[i] != null,
              onSort: _columns[i] == null ? null : () => model.onSort(i),
              filterWidget: _columns[i] == MempoolWatchSort.score
                  ? Padding(
                      padding: const EdgeInsets.only(left: SailStyleValues.padding04),
                      child: SailInfoIcon(
                        title: 'Score = (fee rate − F*) / F* × blocks waited',
                        message:
                            'F* is the mean fees of the last $referenceBlocks blocks spread over a full block, in sat/vB. '
                            'A well-paying transaction that keeps waiting scores higher; above ${alarmScore.toInt()} counts as censored.',
                      ),
                    )
                  : null,
            ),
        ],
        cellHeight: 36.0,
        minColumnWidths: {
          _columns.indexOf(MempoolWatchSort.score): MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: 2).scale(_scoreColumnWidth),
        },
        rowBackgroundColor: (index) => provider.alarmed(rows[index]) ? theme.colors.error.withValues(alpha: 0.1) : null,
        rowBuilder: (context, row, selected) {
          final tx = rows[row];
          final score = provider.score(tx);
          return [
            SailTableCell(value: '${tx.txid.substring(0, 10)}…', copyValue: tx.txid, monospace: true),
            SailTableCell(value: tx.feeRate.toStringAsFixed(1), monospace: true),
            SailTableCell(value: formatter.formatSats(tx.feeSats.toInt()), monospace: true),
            SailTableCell(value: tx.vsize.toString(), monospace: true),
            SailTableCell(value: formatDate(tx.firstSeen.toDateTime())),
            SailTableCell(value: provider.waited(tx).toString(), monospace: true),
            SailTableCell(value: provider.eligible(tx).toString(), monospace: true),
            SailTableCell(
              value: score?.toStringAsFixed(1) ?? '…',
              monospace: true,
              textColor: provider.alarmed(tx) ? theme.colors.error : null,
            ),
            SailTableCell(value: formatWait(tx), monospace: true),
          ];
        },
        rowCount: rows.length,
        emptyPlaceholder: emptyPlaceholder(provider),
        drawGrid: true,
        sortColumnIndex: _columns.indexOf(provider.sortBy),
        sortAscending: !provider.sortDescending,
        onSort: (columnIndex, _) => model.onSort(columnIndex),
        onDoubleTap: (rowId) => showLoadTransactionDialog(context, txid: rowId),
      ),
    );
  }
}

String emptyPlaceholder(MempoolWatchProvider provider) {
  if (!provider.initialized) {
    return 'Loading the mempool…';
  }
  if (!provider.status.enabled) {
    return 'Start watching to record the mempool';
  }
  return provider.txidSearch.isEmpty ? 'The mempool is empty' : 'No transaction matches';
}

String formatWait(MempoolTransaction tx) {
  final d = waitedFor(tx, DateTime.now());
  if (d.inMinutes < 1) {
    return '${d.inSeconds}s';
  }
  if (d.inHours < 1) {
    return '${d.inMinutes}m';
  }
  if (d.inDays < 1) {
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
  return '${d.inDays}d ${d.inHours % 24}h';
}

class TransactionCensorshipViewModel extends BaseViewModel {
  final MempoolWatchProvider provider = GetIt.I.get<MempoolWatchProvider>();
  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

  TransactionCensorshipViewModel() {
    provider.addListener(notifyListeners);
  }

  bool get isLight => GetIt.I.isRegistered<NodeModeProvider>() && GetIt.I<NodeModeProvider>().isLight;
  bool get loading => !provider.initialized;

  String get statusText {
    if (loading) {
      return 'Loading…';
    }
    final s = provider.status;
    if (!s.enabled) {
      return 'Not watching';
    }
    if (s.error.isNotEmpty) {
      return 'Error: ${s.error}';
    }
    if (!s.running) {
      return 'Starting…';
    }
    return 'Watching at height ${s.tipHeight} · ${s.pendingCount} in the mempool';
  }

  Future<void> toggle() async {
    if (loading) {
      return;
    }
    await provider.setEnabled(!provider.status.enabled);
  }

  void onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (searchController.text.trim() != provider.txidSearch) {
        provider.setTxidSearch(searchController.text);
      }
    });
  }

  void onSort(int columnIndex) {
    final field = _columns[columnIndex];
    if (field == null) {
      return;
    }
    final descending = field == provider.sortBy ? !provider.sortDescending : true;
    provider.setSort(field, descending);
  }

  @override
  void dispose() {
    provider.removeListener(notifyListeners);
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }
}
