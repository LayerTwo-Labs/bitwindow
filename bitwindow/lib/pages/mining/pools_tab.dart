import 'dart:async';

import 'package:bitwindow/pages/mining/mining_page.dart';
import 'package:bitwindow/pages/mining/mining_parts.dart';
import 'package:bitwindow/providers/mining_pools_provider.dart';
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/stratum/v1/stratum.pb.dart';

const _windows = [
  MiningPoolWindow.MINING_POOL_WINDOW_24H,
  MiningPoolWindow.MINING_POOL_WINDOW_3D,
  MiningPoolWindow.MINING_POOL_WINDOW_1W,
];

/// The pools on the network and the share of recent blocks each one mined.
class PoolsTab extends StatelessWidget {
  const PoolsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<PoolsViewModel>.reactive(
      viewModelBuilder: () => PoolsViewModel(),
      builder: (context, model, child) => _PoolsCard(model: model),
    );
  }
}

class _PoolsCard extends StatefulWidget {
  final PoolsViewModel model;

  const _PoolsCard({required this.model});

  @override
  State<_PoolsCard> createState() => _PoolsCardState();
}

class _PoolsCardState extends State<_PoolsCard> {
  String? _selectedSlug;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.model.listen(TickerMode.valuesOf(context).enabled);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final provider = model.provider;
    final selected = provider.pools.firstWhereOrNull((share) => share.pool.slug == _selectedSlug);
    return SailColumn(
      spacing: SailStyleValues.padding12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailStrip(
          lead: MiningStripLead(
            title: 'Pools on the network',
            subtitle: model.isLight ? null : model.subtitle,
            error: model.actionError ?? provider.error,
          ),
          stats: [
            if (!model.isLight && provider.blockCount > 0)
              MiningStat(
                label: 'Network hashrate',
                value: formatHashrate(provider.networkHashrate),
                subtitle: '${_blocks(provider.blockCount)} · ${provider.fromHeight} to ${provider.toHeight}',
              ),
          ],
          actions: [
            if (!model.isLight)
              SailToggleGroup<MiningPoolWindow>(
                items: [
                  for (final window in _windows)
                    SailToggleGroupItem(value: window, label: miningPoolWindowLabel(window)),
                ],
                values: [provider.window],
                singleChoice: true,
                onChanged: (values) => provider.setWindow(values.first),
              ),
          ],
        ),
        Expanded(
          child: model.isLight
              ? SailCard(child: Center(child: SailText.secondary13('Pools needs a full node.')))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SailColumn(
                        spacing: SailStyleValues.padding12,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (provider.blockCount > 0) SailCard(child: _ShareChart(provider: provider)),
                          Expanded(
                            child: SailCard(
                              title: 'Pools',
                              bottomPadding: false,
                              child: SailColumn(
                                spacing: SailStyleValues.padding12,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!provider.registryAvailable)
                                    SailText.secondary13(
                                      'This network publishes no pool registry, so every block shows as Unknown.',
                                    ),
                                  Expanded(
                                    child: _PoolsTable(
                                      model: model,
                                      selectedSlug: selected?.pool.slug,
                                      onSelected: (slug) => setState(() => _selectedSlug = slug),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(width: SailStyleValues.padding12),
                      PoolPanel(
                        model: model,
                        share: selected,
                        onClose: () async => setState(() => _selectedSlug = null),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// The colors of the share chart, keyed by pool slug. Pools with no block get none.
Map<String, Color> _shareColors(MiningPoolsProvider provider, List<Color> palette) {
  final mined = provider.pools.where((share) => share.blockCount > 0).toList();
  return {for (var i = 0; i < mined.length; i++) mined[i].pool.slug: palette[i % palette.length]};
}

class _ShareChart extends StatelessWidget {
  final MiningPoolsProvider provider;

  const _ShareChart({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors.chartPalette;
    final mined = provider.pools.where((share) => share.blockCount > 0).toList();

    return SizedBox(
      height: 110,
      child: SailRow(
        spacing: SailStyleValues.padding32,
        children: [
          SizedBox(
            width: 110,
            child: PieChart(
              PieChartData(
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 26,
                sections: [
                  for (var i = 0; i < mined.length; i++)
                    PieChartSectionData(
                      color: colors[i % colors.length],
                      value: mined[i].blockCount.toDouble(),
                      title: '',
                      radius: 28,
                    ),
                ],
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: SailColumn(
                spacing: SailStyleValues.padding04,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < mined.length; i++)
                    SailRow(
                      spacing: SailStyleValues.padding10,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle),
                        ),
                        SizedBox(width: 140, child: SailText.primary13(mined[i].pool.name)),
                        SizedBox(
                          width: 56,
                          child: SailText.primary13(formatShare(mined[i].share), textAlign: TextAlign.right),
                        ),
                        SizedBox(
                          width: 90,
                          child: SailText.secondary13(_blocks(mined[i].blockCount), textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _blocks(int count) => '$count ${count == 1 ? 'block' : 'blocks'}';

const _columnNames = ['Pool', 'Share', 'Blocks', 'Empty blocks', 'Est. hashrate', 'Fee', 'Mode', 'Stratum'];

class _PoolsTable extends StatelessWidget {
  final PoolsViewModel model;
  final String? selectedSlug;
  final ValueChanged<String?> onSelected;

  const _PoolsTable({required this.model, required this.selectedSlug, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final pools = model.provider.pools;
    final mines = model.mines;
    final colors = _shareColors(model.provider, theme.colors.chartPalette);
    return SailTable(
      getRowId: (index) => pools[index].pool.slug,
      selectedRowId: selectedSlug,
      onSelectedRow: onSelected,
      headerBuilder: (context) => [
        for (final name in _columnNames) SailTableHeaderCell(name: name),
        if (mines) const SailTableHeaderCell(name: ''),
      ],
      contextMenuItems: mines
          ? (slug) {
              final pool = pools.firstWhereOrNull((share) => share.pool.slug == slug)?.pool;
              if (pool == null || pool.stratumUrl.isEmpty || model.isTarget(pool)) {
                return const [];
              }
              return [
                SailMenuItem(
                  onSelected: () => unawaited(model.mineHere(pool)),
                  child: SailText.primary12('Mine here'),
                ),
              ];
            }
          : null,
      cellHeight: 40.0,
      rowBuilder: (context, row, selected) {
        final share = pools[row];
        final pool = share.pool;
        final color = colors[pool.slug] ?? theme.colors.textHint;
        return [
          SailTableCell(
            value: pool.name,
            child: SailRow(
              spacing: SailStyleValues.padding08,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                Flexible(child: SailText.primary13(pool.name)),
              ],
            ),
          ),
          SailTableCell(value: formatShare(share.share), monospace: true),
          SailTableCell(value: share.blockCount.toString(), monospace: true),
          SailTableCell(value: share.emptyBlocks.toString(), monospace: true),
          SailTableCell(value: formatHashrate(share.estimatedHashrate), monospace: true),
          SailTableCell(value: pool.mode.isEmpty ? '—' : formatPoolFee(pool.feeBps), monospace: true),
          SailTableCell(value: pool.mode.isEmpty ? '—' : pool.mode),
          SailTableCell(
            value: pool.stratumUrl.isEmpty ? '—' : pool.stratumUrl,
            copyValue: pool.stratumUrl.isEmpty ? null : pool.stratumUrl,
            monospace: true,
          ),
          if (mines) _statusCell(context, pool),
        ];
      },
      rowCount: pools.length,
      emptyPlaceholder: 'No blocks recorded in this window',
    );
  }

  SailTableCell _statusCell(BuildContext context, MiningPool pool) {
    if (pool.stratumUrl.isEmpty || !model.isTarget(pool)) {
      return const SailTableCell(value: '');
    }
    final running = model.stratum.running;
    return SailTableCell(
      value: running ? 'Mining here' : 'Selected',
      textColor: running ? SailTheme.of(context).colors.success : null,
    );
  }
}

/// The side panel of one pool: its share, the one "Mine here" action and its details.
class PoolPanel extends StatelessWidget {
  final PoolsViewModel model;
  final MiningPoolShare share;
  final Future<void> Function() onClose;

  const PoolPanel({super.key, required this.model, required this.share, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final pool = share.pool;
    final canMine = model.mines && pool.stratumUrl.isNotEmpty;
    final target = canMine && model.isTarget(pool);
    final running = model.stratum.running;
    return SailSidePanel(
      title: pool.name,
      onClose: onClose,
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailColumn(
            spacing: 2,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailText.primary24(formatShare(share.share), bold: true),
              SailText.secondary15(_blocks(share.blockCount)),
            ],
          ),
          if (target)
            Align(
              alignment: Alignment.centerLeft,
              child: SailStatusPill(
                label: running ? 'Mining here' : 'Selected',
                tone: running ? SailStatusTone.success : SailStatusTone.neutral,
              ),
            )
          else if (canMine)
            SailButton(label: 'Mine here', onPressed: () async => model.mineHere(pool)),
          SailText.primary13('Details', bold: true),
          SailDetailGroup(
            children: [
              SailDetailLine(label: 'Share', value: formatShare(share.share)),
              SailDetailLine(label: 'Blocks', value: share.blockCount.toString()),
              SailDetailLine(label: 'Empty blocks', value: share.emptyBlocks.toString()),
              SailDetailLine(label: 'Est. hashrate', value: formatHashrate(share.estimatedHashrate)),
              SailDetailLine(label: 'Fee', value: pool.mode.isEmpty ? '—' : formatPoolFee(pool.feeBps)),
              SailDetailLine(label: 'Mode', value: pool.mode.isEmpty ? '—' : pool.mode),
              SailDetailLine(label: 'Stratum', value: pool.stratumUrl.isEmpty ? '—' : pool.stratumUrl),
            ],
          ),
        ],
      ),
    );
  }
}

String formatShare(double share) => '${(share * 100).toStringAsFixed(1)}%';

String formatPoolFee(int feeBps) => '${(feeBps / 100).toStringAsFixed(feeBps % 100 == 0 ? 0 : 1)}%';

class PoolsViewModel extends BaseViewModel {
  final MiningPoolsProvider provider = GetIt.I.get<MiningPoolsProvider>();
  final StratumProvider stratum = GetIt.I.get<StratumProvider>();

  /// Only an eCash node runs the stratum server that "Mine here" points.
  final bool mines = minesHere();

  String? actionError;

  bool _listening = false;

  /// A hidden tab drops its listeners, so the providers stop their full polls.
  void listen(bool shown) {
    if (shown == _listening) {
      return;
    }
    _listening = shown;
    if (shown) {
      provider.addListener(notifyListeners);
      stratum.addListener(notifyListeners);
      return;
    }
    provider.removeListener(notifyListeners);
    stratum.removeListener(notifyListeners);
  }

  bool get isLight => GetIt.I.isRegistered<NodeModeProvider>() && GetIt.I<NodeModeProvider>().isLight;

  String get subtitle {
    final source = provider.registrySource.isEmpty ? '' : ' Pool list from ${provider.registrySource}.';
    if (provider.blockCount == 0) {
      return 'No blocks recorded in this window yet.$source';
    }
    return 'Who mined the last ${_blocks(provider.blockCount)}, read from each coinbase.$source';
  }

  /// The stratum URL the server sends its work to, or null for solo.
  String? get targetUrl {
    final target = stratum.status.target;
    return switch (target.kind) {
      TargetKind.TARGET_KIND_POOL => stratum.pools.firstWhereOrNull((pool) => pool.id == target.poolId)?.url,
      TargetKind.TARGET_KIND_CUSTOM => target.url,
      _ => null,
    };
  }

  bool isTarget(MiningPool pool) => samePoolUrl(pool.stratumUrl, targetUrl ?? '');

  /// A pool the catalog knows becomes the target. Any other pool opens the
  /// custom pool form, because the worker name is the miner's choice.
  Future<void> mineHere(MiningPool pool) async {
    final known = stratum.pools.firstWhereOrNull((catalog) => samePoolUrl(catalog.url, pool.stratumUrl));
    if (known == null) {
      MiningPage.mineAt(pool.stratumUrl);
      return;
    }
    actionError = null;
    notifyListeners();
    try {
      await stratum.setTarget(Target(kind: TargetKind.TARGET_KIND_POOL, poolId: known.id));
    } catch (e) {
      actionError = 'Could not change where the work goes: ${extractConnectException(e)}';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    listen(false);
    super.dispose();
  }
}
