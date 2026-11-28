import 'package:auto_route/auto_route.dart';
import 'package:coinshift/providers/analytics_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class SwapAnalyticsPage extends StatelessWidget {
  const SwapAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<SwapAnalyticsViewModel>.reactive(
      viewModelBuilder: () => SwapAnalyticsViewModel(),
      builder: (context, model, child) {
        return QtPage(
          child: SailColumn(
            spacing: SailStyleValues.padding12,
            children: [
              _AnalyticsHeader(model: model),
              if (SailStyleValues.phoneLayout(context)) _StatsCardsRow(model: model),

              // Main content
              Expanded(
                child: SailRow(
                  spacing: SailStyleValues.padding12,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side: Chain breakdown
                    Expanded(
                      flex: 1,
                      child: _ChainBreakdownCard(model: model),
                    ),

                    // Right side: Swaps needing attention
                    Expanded(
                      flex: 1,
                      child: _SwapsNeedingAttentionCard(model: model),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  final SwapAnalyticsViewModel model;

  const _AnalyticsHeader({required this.model});

  @override
  Widget build(BuildContext context) {
    final rangePicker = SailDropdownButton<AnalyticsTimeRange>(
      value: model.selectedTimeRange,
      items: AnalyticsTimeRange.values
          .map(
            (range) => SailDropdownItem<AnalyticsTimeRange>(
              value: range,
              label: range.displayName,
            ),
          )
          .toList(),
      onChanged: (range) {
        if (range != null) {
          model.setTimeRange(range);
        }
      },
    );
    final refresh = SailButton(
      label: 'Refresh',
      small: true,
      variant: ButtonVariant.secondary,
      loading: model.isLoading,
      onPressed: () async => await model.refresh(),
    );

    if (SailStyleValues.phoneLayout(context)) {
      return SailCard(
        child: Wrap(
          spacing: SailStyleValues.padding08,
          runSpacing: SailStyleValues.padding08,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: SailStyleValues.padding08),
              child: SailText.primary16('Swap Analytics', bold: true),
            ),
            SailText.secondary13('Time Range:'),
            rangePicker,
            refresh,
          ],
        ),
      );
    }

    final formatter = GetIt.I<FormatterProvider>();
    final stats = model.statistics;
    return ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailStrip(
        lead: SailText.primary15('Swap Analytics', bold: true),
        stats: [
          SailStat(label: 'Total Swaps', value: stats.totalSwaps.toString()),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailStat(label: 'Completed', value: stats.completedSwaps.toString()),
              SailText.secondary12('${(stats.successRate * 100).toStringAsFixed(1)}% success'),
            ],
          ),
          SailStat(label: 'Pending', value: stats.pendingSwaps.toString()),
          SailStat(label: 'Volume (L2)', value: formatter.formatSats(stats.l2AmountTotal)),
          SailStat(label: 'Volume (L1)', value: formatter.formatSats(stats.l1AmountTotal)),
        ],
        actions: [
          SailText.secondary13('Time Range:'),
          rangePicker,
          SailIconBoxButton(
            icon: SailSVGAsset.refreshCw,
            tooltip: 'Refresh',
            size: 32,
            onPressed: model.isLoading ? null : () async => await model.refresh(),
          ),
        ],
      ),
    );
  }
}

class _StatsCardsRow extends StatelessWidget {
  final SwapAnalyticsViewModel model;

  const _StatsCardsRow({required this.model});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final stats = model.statistics;

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailStatList(
        children: [
          SailStatRow(title: 'Total Swaps', subtitle: '', value: stats.totalSwaps.toString()),
          SailStatRow(
            title: 'Completed',
            subtitle: '${(stats.successRate * 100).toStringAsFixed(1)}% success',
            value: stats.completedSwaps.toString(),
          ),
          SailStatRow(title: 'Pending', subtitle: '', value: stats.pendingSwaps.toString()),
          SailStatRow(title: 'Volume (L2)', subtitle: '', value: formatter.formatSats(stats.l2AmountTotal)),
          SailStatRow(title: 'Volume (L1)', subtitle: '', value: formatter.formatSats(stats.l1AmountTotal)),
        ],
      ),
    );
  }
}

class _ChainBreakdownCard extends StatelessWidget {
  final SwapAnalyticsViewModel model;

  const _ChainBreakdownCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final chains = model.chainHealth.entries
        .where((e) => e.value.activeSwaps > 0 || model.statistics.swapsByChain[e.key] != null)
        .toList();

    return SailCard(
      title: 'Chain Breakdown',
      bottomPadding: false,
      child: chains.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(SailStyleValues.padding16),
              child: Center(child: SailText.secondary13('No swap data available')),
            )
          : SailTable(
              getRowId: (index) => chains[index].key.name,
              headerBuilder: (context) => [
                SailTableHeaderCell(name: 'Chain'),
                SailTableHeaderCell(name: 'Total', alignment: Alignment.centerRight),
                SailTableHeaderCell(name: 'Active', alignment: Alignment.centerRight),
                SailTableHeaderCell(name: 'Success', alignment: Alignment.centerRight),
              ],
              rowBuilder: (context, row, selected) {
                final chain = chains[row].key;
                final health = chains[row].value;
                return [
                  SailTableCell(
                    value: chain.label,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SidechainStatusText(
                          tone: health.isHealthy ? SailStatusTone.success : SailStatusTone.warning,
                          text: chain.label,
                        ),
                        SailText.secondary12(health.isHealthy ? 'Healthy' : 'Attention'),
                      ],
                    ),
                  ),
                  SailTableCell(
                    value: (model.statistics.swapsByChain[chain] ?? 0).toString(),
                    alignment: Alignment.centerRight,
                  ),
                  SailTableCell(value: health.activeSwaps.toString(), alignment: Alignment.centerRight),
                  SailTableCell(
                    value: '${(health.successRate * 100).toStringAsFixed(0)}%',
                    alignment: Alignment.centerRight,
                  ),
                ];
              },
              rowCount: chains.length,
              drawGrid: true,
            ),
    );
  }
}

class _SwapsNeedingAttentionCard extends StatelessWidget {
  final SwapAnalyticsViewModel model;

  const _SwapsNeedingAttentionCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final swaps = model.swapsNeedingAttention;
    final formatter = GetIt.I<FormatterProvider>();

    return SailCard(
      title: 'Swaps Needing Attention',
      subtitle: swaps.isEmpty ? null : '${swaps.length} swap(s) may need your attention',
      bottomPadding: false,
      child: swaps.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(SailStyleValues.padding16),
              child: Center(
                child: SailColumn(
                  spacing: SailStyleValues.padding04,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SailText.primary13('All swaps are healthy'),
                    SailText.secondary12('No swaps require attention at this time'),
                  ],
                ),
              ),
            )
          : ListenableBuilder(
              listenable: formatter,
              builder: (context, child) => SailTable(
                getRowId: (index) => swaps[index].idHex,
                headerBuilder: (context) => [
                  SailTableHeaderCell(name: 'Swap'),
                  SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight),
                ],
                rowBuilder: (context, row, selected) {
                  final swap = swaps[row];
                  final (issue, tone) = _issue(swap);
                  return [
                    SailTableCell(
                      value: 'Swap ${swap.idHex.substring(0, 12)}...',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SidechainStatusText(tone: tone, text: 'Swap ${swap.idHex.substring(0, 12)}...'),
                          SailText.secondary12(issue),
                        ],
                      ),
                    ),
                    SailTableCell(
                      value: formatter.formatSats(swap.l2Amount),
                      secondaryValue: swap.parentChain.label,
                      monospace: true,
                      alignment: Alignment.centerRight,
                    ),
                  ];
                },
                rowCount: swaps.length,
                drawGrid: true,
                contextMenuItems: (rowId) => [
                  SailMenuItem(
                    onSelected: () => Clipboard.setData(ClipboardData(text: rowId)),
                    child: SailText.primary12('Copy swap ID'),
                  ),
                ],
              ),
            ),
    );
  }

  (String, SailStatusTone) _issue(CoinShiftSwap swap) {
    if (swap.state.isPending) {
      return ('Pending - waiting for L1 payment', SailStatusTone.warning);
    }
    if (swap.state.isWaitingConfirmations) {
      final current = swap.state.currentConfirmations ?? 0;
      final required = swap.state.requiredConfirmations ?? 1;
      return ('Waiting: $current/$required confirmations', SailStatusTone.info);
    }
    return (swap.state.state, SailStatusTone.neutral);
  }
}

class SwapAnalyticsViewModel extends BaseViewModel {
  AnalyticsProvider get _analyticsProvider => GetIt.I.get<AnalyticsProvider>();

  AnalyticsTimeRange get selectedTimeRange => _analyticsProvider.selectedTimeRange;
  SwapStatistics get statistics => _analyticsProvider.statistics;
  Map<ParentChainType, ChainHealth> get chainHealth => _analyticsProvider.chainHealth;
  List<CoinShiftSwap> get swapsNeedingAttention => _analyticsProvider.swapsNeedingAttention;
  bool get isLoading => _analyticsProvider.isLoading;

  SwapAnalyticsViewModel() {
    _analyticsProvider.addListener(notifyListeners);
  }

  void setTimeRange(AnalyticsTimeRange range) {
    _analyticsProvider.setTimeRange(range);
  }

  Future<void> refresh() async {
    await _analyticsProvider.refresh();
  }

  @override
  void dispose() {
    _analyticsProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
