import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:truthcoin/routing/open_market.dart';
import 'package:truthcoin/models/market.dart';
import 'package:truthcoin/models/voting.dart';
import 'package:truthcoin/providers/market_provider.dart';
import 'package:truthcoin/routing/router.dart';
import 'package:truthcoin/widgets/market_card.dart';
import 'package:truthcoin/widgets/v2_parts.dart';

const double _cardGap = 24;
const int _maxCardsPerRow = 3;

/// A card holds its content at this width.
const double _minCardWidth = 330;

@RoutePage()
class MarketExplorerPage extends StatelessWidget {
  const MarketExplorerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<MarketExplorerViewModel>.reactive(
      viewModelBuilder: () => MarketExplorerViewModel(),
      onViewModelReady: (model) => model.init(),
      builder: (context, model, child) {
        if (SailStyleValues.phoneLayout(context)) {
          return QtPage(
            child: SailColumn(
              spacing: SailStyleValues.padding16,
              children: [
                _HeaderSection(model: model),
                _FilterDropdown(model: model),
                Expanded(child: _MarketGrid(model: model)),
              ],
            ),
          );
        }
        final selected = model.selectedMarket;
        return QtPage(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MarketsCard(model: model)),
              if (selected != null) ...[
                const SizedBox(width: SailStyleValues.padding12),
                MarketSidePanel(
                  market: selected,
                  detail: model.marketDetails[selected.marketId],
                  onClose: () => model.selectMarket(null),
                  onOpen: () => model.openMarket(selected.marketId),
                  onTradeOutcome: (index) => model.openMarket(selected.marketId, outcomeIndex: index),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The table card of all markets: search, sort, filter, Create market and a "…" with Refresh.
class _MarketsCard extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _MarketsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I.get<FormatterProvider>();

    final toolbar = [
      SizedBox(width: 220, child: _SearchField(model: model)),
      SizedBox(width: 130, child: _SortDropdown(model: model)),
      SizedBox(width: 130, child: _FilterDropdown(model: model)),
      SailButton(
        plainLabel: true,
        label: 'Create market',
        icon: SailSVGAsset.plus,
        onPressed: () async => model.openCreateMarket(),
      ),
      SailRowMenuButton(
        items: () => [menuItem('Refresh', () => unawaited(model.loadMarkets(refresh: true)))],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // The toolbar sits in the head only where the title keeps room beside it.
        final wide = constraints.maxWidth >= 1000;
        return ListenableBuilder(
          listenable: formatter,
          builder: (context, _) => SailCard(
            bottomPadding: false,
            title: 'Prediction markets',
            subtitle: [
              '${model.totalMarkets} markets · ${model.activeMarkets} live · '
                  '${formatter.formatBTC(model.totalVolumeBTC)} traded',
              if (model.isLoadingPrices) 'prices load',
              ?model.priceError,
            ].join(' · '),
            widgetHeaderEnd: wide ? SailRow(spacing: SailStyleValues.padding08, children: toolbar) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!wide) ...[
                  const SizedBox(height: SailStyleValues.padding08),
                  Wrap(
                    spacing: SailStyleValues.padding08,
                    runSpacing: SailStyleValues.padding08,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: toolbar,
                  ),
                ],
                const SizedBox(height: SailStyleValues.padding08),
                Expanded(child: _MarketTable(model: model)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _SearchField({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailTextField(
      controller: model.searchController,
      hintText: 'Search markets',
      onChanged: model.onSearchChanged,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: SailStyleValues.padding10),
        child: SailSVG.fromAsset(SailSVGAsset.search, width: 14, height: 14, color: SailTheme.of(context).colors.icon),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 14),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _SortDropdown({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailDropdownButton<MarketSort>(
      value: model.sortBy,
      items: const [
        SailDropdownItem<MarketSort>(value: MarketSort.volume, label: 'By volume'),
        SailDropdownItem<MarketSort>(value: MarketSort.created, label: 'By date'),
        SailDropdownItem<MarketSort>(value: MarketSort.title, label: 'By title'),
      ],
      onChanged: (sort) {
        if (sort != null) model.onSortChanged(sort);
      },
    );
  }
}

/// One filter dropdown: All, each tag, and each market state.
class _FilterDropdown extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _FilterDropdown({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailDropdownButton<MarketFilter>(
      value: model.filter,
      items: [
        const SailDropdownItem<MarketFilter>(value: MarketFilter.all, label: 'All'),
        for (final tag in model.availableTags) SailDropdownItem<MarketFilter>(value: MarketFilter.tag(tag), label: tag),
        for (final state in MarketState.values)
          SailDropdownItem<MarketFilter>(value: MarketFilter.state(state), label: state.displayName),
      ],
      onChanged: (filter) {
        if (filter != null) model.onFilterChanged(filter);
      },
    );
  }
}

/// The All, tag or state filter of the market list.
class MarketFilter {
  final String? tag;
  final MarketState? state;

  const MarketFilter._() : tag = null, state = null;

  static const all = MarketFilter._();
  const MarketFilter.tag(String this.tag) : state = null;
  const MarketFilter.state(MarketState this.state) : tag = null;

  @override
  bool operator ==(Object other) => other is MarketFilter && other.tag == tag && other.state == state;

  @override
  int get hashCode => Object.hash(tag, state);
}

SailStatusTone marketTone(MarketState state) => switch (state) {
  MarketState.trading => SailStatusTone.success,
  MarketState.ossified => SailStatusTone.neutral,
  MarketState.cancelled || MarketState.invalid => SailStatusTone.error,
};

/// The outcomes of [detail] in display order.
List<MarketOutcome> sortedOutcomes(MarketData? detail) =>
    [...?detail?.outcomes]..sort((a, b) => a.displayIndex.compareTo(b.displayIndex));

/// The Yes outcome of a two-outcome market, else the last.
MarketOutcome? yesOutcome(List<MarketOutcome> outcomes) {
  if (outcomes.length != 2) return null;
  return outcomes.firstWhere((o) => o.label.toLowerCase() == 'yes', orElse: () => outcomes.last);
}

/// The two price lines of a market row.
(String, String) priceLines(List<MarketOutcome> outcomes) {
  if (outcomes.isEmpty) return ('price loads', '');
  if (outcomes.length == 2) {
    final yes = yesOutcome(outcomes)!;
    final no = outcomes.firstWhere((o) => o != yes);
    return ('${yes.label} ${formatChance(yes.currentPrice)}', '${no.label} ${formatChance(no.currentPrice)}');
  }
  final byPrice = [...outcomes]..sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
  String label(MarketOutcome o) => '${o.label} ${formatChance(o.currentPrice)}';
  final first = byPrice.take(2).map(label).join(' · ');
  final rest = byPrice.skip(2).take(1).map(label).toList();
  if (byPrice.length > 3) rest.add(moreOutcomesText(byPrice.length - 3));
  return (first, rest.join(' · '));
}

String marketMetaLine(MarketSummary market, MarketData? detail) {
  final parts = <String>['${market.outcomeCount} outcomes'];
  if (detail != null) {
    parts.add('β ${detail.beta.toStringAsFixed(1)}');
    parts.add('fee ${detail.tradingFeePercent}');
  }
  return parts.join(' · ');
}

/// The "…" items of a market: Buy each side of a live two-outcome market, and Trade.
List<SailMenuEntity> marketMenuItems(
  MarketSummary market,
  MarketData? detail, {
  required VoidCallback onTrade,
  required void Function(int outcomeIndex) onTradeOutcome,
}) {
  final outcomes = sortedOutcomes(detail);
  final yes = yesOutcome(outcomes);
  return [
    if (market.isTrading && yes != null) ...[
      menuItem('Buy ${yes.label}', () => onTradeOutcome(yes.index)),
      for (final no in outcomes.where((o) => o != yes)) menuItem('Buy ${no.label}', () => onTradeOutcome(no.index)),
    ],
    menuItem('Trade', onTrade),
  ];
}

class _MarketTable extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _MarketTable({required this.model});

  @override
  Widget build(BuildContext context) {
    if (model.isLoading && model.markets.isEmpty) {
      return Center(
        child: SailSkeletonizer(
          enabled: true,
          description: 'Markets load',
          child: SailText.primary15('Markets load'),
        ),
      );
    }

    if (model.marketError != null) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SailText.primary13(model.marketError!),
            SailButton(
              plainLabel: true,
              label: 'Try again',
              variant: ButtonVariant.secondary,
              onPressed: () async => model.loadMarkets(refresh: true),
            ),
          ],
        ),
      );
    }

    if (model.markets.isEmpty) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SailText.secondary13('No market matches the filter'),
            SailButton(
              plainLabel: true,
              label: 'Create the first market',
              variant: ButtonVariant.secondary,
              onPressed: () async => model.openCreateMarket(),
            ),
          ],
        ),
      );
    }

    final formatter = GetIt.I.get<FormatterProvider>();
    final markets = model.markets;
    return SailTable(
      getRowId: (index) => markets[index].marketId,
      cellHeight: 56,
      selectedRowId: model.selectedMarket?.marketId,
      onRowTap: (id) => model.selectMarket(id),
      onDoubleTap: (id) => model.openMarket(id),
      headerBuilder: (context) => const [
        SailTableHeaderCell(name: 'Market'),
        SailTableHeaderCell(name: 'Prices'),
        SailTableHeaderCell(name: 'Volume', alignment: Alignment.centerRight),
        SailTableHeaderCell(name: 'Status'),
      ],
      contextMenuItems: (id) {
        final market = markets.firstWhere((m) => m.marketId == id);
        return marketMenuItems(
          market,
          model.marketDetails[id],
          onTrade: () => model.openMarket(id),
          onTradeOutcome: (index) => model.openMarket(id, outcomeIndex: index),
        );
      },
      rowBuilder: (context, row, selected) {
        final market = markets[row];
        final detail = model.marketDetails[market.marketId];
        final (first, second) = priceLines(sortedOutcomes(detail));
        return [
          SailTableCell(value: market.title, secondaryValue: marketMetaLine(market, detail)),
          SailTableCell(value: first, secondaryValue: second.isEmpty ? null : second),
          SailTableCell(value: '${formatter.formatSats(market.volumeSats)} volume', alignment: Alignment.centerRight),
          SailTableCell(
            value: market.marketState.displayName,
            child: StatusDotCell(
              label: market.marketState.displayName,
              tone: marketTone(market.marketState),
              secondary: 'block ${market.createdAtHeight}',
            ),
          ),
        ];
      },
      rowCount: markets.length,
    );
  }
}

/// The 380 px panel of the selected market: its leading price, one trade button and its numbers.
class MarketSidePanel extends StatelessWidget {
  final MarketSummary market;
  final MarketData? detail;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final void Function(int outcomeIndex) onTradeOutcome;

  const MarketSidePanel({
    super.key,
    required this.market,
    required this.detail,
    required this.onClose,
    required this.onOpen,
    required this.onTradeOutcome,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I.get<FormatterProvider>();
    final outcomes = sortedOutcomes(detail);
    final lead =
        yesOutcome(outcomes) ??
        (outcomes.isEmpty ? null : ([...outcomes]..sort((a, b) => b.currentPrice.compareTo(a.currentPrice))).first);

    return SailSidePanel(
      title: 'Market',
      menuItems: () => marketMenuItems(market, detail, onTrade: onOpen, onTradeOutcome: onTradeOutcome),
      onClose: () async => onClose(),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.primary15(market.title, bold: true),
          if (lead != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary24(formatChance(lead.currentPrice), bold: true),
                SailText.secondary15(lead.label),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: SailStatusPill(
              label: '${market.marketState.displayName} · block ${market.createdAtHeight}',
              tone: marketTone(market.marketState),
            ),
          ),
          SailButton(
            label: market.isTrading && lead != null ? 'Buy ${lead.label} ${formatChance(lead.currentPrice)}' : 'Trade',
            onPressed: () async => market.isTrading && lead != null ? onTradeOutcome(lead.index) : onOpen(),
          ),
          if (outcomes.isNotEmpty) ...[
            const SailDetailHeading('Outcome prices'),
            SailDetailGroup(
              fill: SailDetailFill.canvas,
              children: [
                for (final outcome in outcomes)
                  SailDetailLine(wrap: true, label: outcome.label, value: formatChance(outcome.currentPrice)),
              ],
            ),
          ],
          const SailDetailHeading('Market'),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(wrap: true, label: 'Outcomes', value: '${market.outcomeCount}'),
              if (detail != null) ...[
                SailDetailLine(wrap: true, label: 'Liquidity β', value: detail!.beta.toStringAsFixed(1)),
                SailDetailLine(wrap: true, label: 'Trading fee', value: detail!.tradingFeePercent),
              ],
              SailDetailLine(wrap: true, label: 'Volume', value: formatter.formatSats(market.volumeSats)),
              SailDetailLine(wrap: true, label: 'Created at block', value: '${market.createdAtHeight}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _HeaderSection({required this.model});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I.get<FormatterProvider>();

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, _) => SailColumn(
        spacing: SailStyleValues.padding12,
        children: [
          SailColumn(
            spacing: SailStyleValues.padding04,
            children: [
              SailText.primary24('Prediction markets', bold: true),
              SailText.secondary12(
                '${model.totalMarkets} markets  ·  ${model.activeMarkets} live  ·  '
                '${formatter.formatBTC(model.totalVolumeBTC)} traded',
              ),
            ],
          ),
          Wrap(
            spacing: SailStyleValues.padding08,
            runSpacing: SailStyleValues.padding08,
            children: [
              SizedBox(width: 180, child: _SearchField(model: model)),
              SizedBox(width: 150, child: _SortDropdown(model: model)),
              SailButton(
                plainLabel: true,
                label: 'Create market',
                icon: SailSVGAsset.plus,
                onPressed: () async => model.openCreateMarket(),
              ),
              SailRowMenuButton(
                items: () => [menuItem('Refresh', () => unawaited(model.loadMarkets(refresh: true)))],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarketGrid extends StatelessWidget {
  final MarketExplorerViewModel model;

  const _MarketGrid({required this.model});

  @override
  Widget build(BuildContext context) {
    if (model.isLoading && model.markets.isEmpty) {
      return Center(
        child: SailSkeletonizer(
          enabled: true,
          description: 'Markets load',
          child: SailText.primary15('Markets load'),
        ),
      );
    }

    if (model.marketError != null) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SailText.primary15(model.marketError!),
            SailButton(
              plainLabel: true,
              label: 'Try again',
              small: true,
              onPressed: () async => model.loadMarkets(refresh: true),
            ),
          ],
        ),
      );
    }

    if (model.markets.isEmpty) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SailText.secondary15('No market matches the filter'),
            SailButton(
              plainLabel: true,
              label: 'Create the first market',
              small: true,
              onPressed: () async => model.openCreateMarket(),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = ((constraints.maxWidth + _cardGap) / (_minCardWidth + _cardGap)).floor();
        final columns = fit.clamp(1, _maxCardsPerRow);
        final cardWidth = (constraints.maxWidth - _cardGap * (columns - 1)) / columns;

        return SingleChildScrollView(
          child: Wrap(
            spacing: _cardGap,
            runSpacing: _cardGap,
            children: [
              for (final market in model.markets)
                SizedBox(
                  width: cardWidth,
                  child: MarketCard(
                    market: market,
                    detail: model.marketDetails[market.marketId],
                    onTap: () => model.openMarket(market.marketId),
                    onTradeOutcome: (outcomeIndex) => model.openMarket(
                      market.marketId,
                      outcomeIndex: outcomeIndex,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MarketExplorerViewModel extends BaseViewModel {
  final MarketProvider _marketProvider = GetIt.I.get<MarketProvider>();
  final TextEditingController searchController = TextEditingController();

  List<MarketSummary> get markets => _marketProvider.filteredMarkets;
  Map<String, MarketData> get marketDetails => _marketProvider.marketDetails;
  bool get isLoading => _marketProvider.isLoading;
  bool get isLoadingPrices => _marketProvider.isLoadingPrices;
  String? get marketError => _marketProvider.error;
  String? get priceError => _marketProvider.priceError;
  MarketState? get stateFilter => _marketProvider.stateFilter;
  String? get tagFilter => _marketProvider.tagFilter;
  List<String> get availableTags => _marketProvider.availableTags;
  MarketSort get sortBy => _marketProvider.sortBy;

  MarketFilter get filter => tagFilter != null
      ? MarketFilter.tag(tagFilter!)
      : stateFilter != null
      ? MarketFilter.state(stateFilter!)
      : MarketFilter.all;

  String? _selectedId;

  /// The market of the side panel, while it is in the list.
  MarketSummary? get selectedMarket => markets.where((m) => m.marketId == _selectedId).firstOrNull;

  void selectMarket(String? marketId) {
    _selectedId = marketId;
    notifyListeners();
  }

  void onFilterChanged(MarketFilter filter) {
    _marketProvider.setTagFilter(filter.tag);
    _marketProvider.setStateFilter(filter.state);
  }

  int get totalMarkets => _marketProvider.markets.length;
  int get activeMarkets => _marketProvider.markets.where((m) => m.isTrading).length;
  double get totalVolumeBTC => _marketProvider.markets.fold(0.0, (sum, m) => sum + satoshiToBTC(m.volumeSats));

  void init() {
    _marketProvider.addListener(_onProviderChange);
    // The load notifies the market page too, and that page still listens
    // while the back button builds this page.
    WidgetsBinding.instance.addPostFrameCallback((_) => loadMarkets());
  }

  void _onProviderChange() {
    notifyListeners();
  }

  Future<void> loadMarkets({bool refresh = false}) async {
    await _marketProvider.loadMarkets();
    await _marketProvider.loadMarketPrices(refresh: refresh);
  }

  void onSearchChanged(String query) {
    _marketProvider.setSearchQuery(query);
  }

  void onStateFilterChanged(MarketState? state) {
    _marketProvider.setStateFilter(state);
  }

  void onTagFilterChanged(String? tag) {
    _marketProvider.setTagFilter(tag);
  }

  void clearFilters() {
    _marketProvider.setStateFilter(null);
    _marketProvider.setTagFilter(null);
  }

  void onSortChanged(MarketSort sort) {
    _marketProvider.setSort(sort);
  }

  Future<void> openMarket(String marketId, {int? outcomeIndex}) async {
    await openMarketsRoute(
      MarketDetailRoute(marketId: marketId, initialOutcomeIndex: outcomeIndex),
    );
  }

  Future<void> openCreateMarket() async {
    await openMarketsRoute(const MarketCreationRoute());
    // A new market carries no price yet, so the grid reads the list again.
    await loadMarkets();
  }

  @override
  void dispose() {
    _marketProvider.removeListener(_onProviderChange);
    searchController.dispose();
    super.dispose();
  }
}
