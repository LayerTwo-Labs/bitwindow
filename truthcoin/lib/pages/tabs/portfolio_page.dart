import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/shell.dart';
import 'package:truthcoin/routing/open_market.dart';
import 'package:truthcoin/models/address_position.dart';
import 'package:truthcoin/models/voting.dart';
import 'package:truthcoin/providers/market_provider.dart';
import 'package:truthcoin/providers/voting_provider.dart';
import 'package:truthcoin/truthcoin_module.dart';
import 'package:truthcoin/routing/router.dart';
import 'package:truthcoin/widgets/market_card.dart';
import 'package:truthcoin/widgets/market_stat_tile.dart';
import 'package:truthcoin/widgets/v2_parts.dart';

const double _sideWidth = 380;
const int _votecoinNetworkFeeSats = 1000;

@RoutePage()
class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<PortfolioViewModel>.reactive(
      viewModelBuilder: () => PortfolioViewModel(),
      onViewModelReady: (model) => model.init(),
      builder: (context, model, child) {
        final phone = SailStyleValues.phoneLayout(context);
        return QtPage(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (phone || constraints.maxWidth < 900) {
                return SingleChildScrollView(
                  child: SailColumn(
                    spacing: SailStyleValues.padding12,
                    children: [
                      if (phone) ...[_PhoneHeader(model: model), _StatTiles(model: model)] else _Header(model: model),
                      SizedBox(height: 360, child: _PositionsCard(model: model)),
                      SizedBox(height: 300, child: _YourMarketsCard(model: model)),
                      _SendVotecoinCard(model: model),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(model: model),
                  const SizedBox(height: SailStyleValues.padding12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _PositionsCard(model: model)),
                              const SizedBox(height: SailStyleValues.padding12),
                              Expanded(child: _YourMarketsCard(model: model)),
                            ],
                          ),
                        ),
                        const SizedBox(width: SailStyleValues.padding12),
                        SizedBox(
                          width: _sideWidth,
                          child: _SendVotecoinCard(model: model),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The head card: title, the wallet line, the four key numbers, and a "…" with Refresh and Markets.
class _Header extends StatelessWidget {
  final PortfolioViewModel model;

  const _Header({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I.get<FormatterProvider>();

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, _) => PageHeadCard(
        title: 'Portfolio',
        subtitle: model.addresses.isEmpty
            ? 'No wallet address yet'
            : '${model.headlineAddress} · ${model.addresses.length} addresses',
        stats: [
          HeadStat(
            label: 'Portfolio value',
            value: formatter.formatSats(model.totalValueSats),
            caption: 'value of every open share',
          ),
          HeadStat(
            label: 'Profit and loss',
            value: '${model.totalProfitSats >= 0 ? '+' : ''}${model.profitPercent.toStringAsFixed(1)}%',
            caption: 'cost ${formatter.formatSats(model.totalCostBasisSats)}',
            valueColor: model.hasProfit ? theme.colors.success : theme.colors.error,
          ),
          HeadStat(
            label: 'Open positions',
            value: '${model.positions.length}',
            caption: 'across ${model.activeMarkets} markets',
          ),
          HeadStat(label: 'Votecoin', value: '${model.votecoinBalance}', caption: 'weight of your oracle vote'),
        ],
        menuItems: () => [
          menuItem('Refresh', () => unawaited(model.load())),
          menuItem('Markets', () => model.openMarkets(context)),
        ],
      ),
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  final PortfolioViewModel model;

  const _PhoneHeader({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailColumn(
          spacing: SailStyleValues.padding04,
          children: [
            SailText.primary20('Portfolio', bold: true),
            SailText.secondary13(
              model.addresses.isEmpty
                  ? 'No wallet address yet'
                  : '${model.headlineAddress} · ${model.addresses.length} addresses',
            ),
          ],
        ),
        SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            SailButton(
              plainLabel: true,
              label: 'Refresh',
              variant: ButtonVariant.secondary,
              small: true,
              loading: model.isLoading,
              onPressed: () async => model.load(),
            ),
            SailButton(
              plainLabel: true,
              label: 'Markets',
              small: true,
              onPressed: () async => model.openMarkets(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTiles extends StatelessWidget {
  final PortfolioViewModel model;

  const _StatTiles({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I.get<FormatterProvider>();

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, _) => MarketStatTileRow(
        tiles: [
          MarketStatTile(
            label: 'Portfolio value',
            value: formatter.formatSats(model.totalValueSats),
            caption: 'value of every open share',
          ),
          MarketStatTile(
            label: 'Profit and loss',
            value: '${model.totalProfitSats >= 0 ? '+' : ''}${model.profitPercent.toStringAsFixed(1)}%',
            caption: 'cost ${formatter.formatSats(model.totalCostBasisSats)}',
            valueColor: model.hasProfit ? theme.colors.success : theme.colors.error,
          ),
          MarketStatTile(
            label: 'Open positions',
            value: '${model.positions.length}',
            caption: 'across ${model.activeMarkets} markets',
          ),
          MarketStatTile(label: 'Votecoin', value: '${model.votecoinBalance}', caption: 'weight of your oracle vote'),
        ],
      ),
    );
  }
}

class _PositionsCard extends StatelessWidget {
  final PortfolioViewModel model;

  const _PositionsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I.get<FormatterProvider>();

    if (model.isLoading && model.positions.isEmpty) {
      return Center(
        child: SailSkeletonizer(
          enabled: true,
          description: 'Positions load',
          child: SailText.primary15('Positions load'),
        ),
      );
    }

    if (model.loadError != null) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SailText.primary15(model.loadError!),
            SailButton(plainLabel: true, label: 'Try again', small: true, onPressed: () async => model.load()),
          ],
        ),
      );
    }

    if (model.positions.isEmpty) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SailText.secondary15('You hold no share yet'),
            SailButton(
              plainLabel: true,
              label: 'Open the markets',
              small: true,
              onPressed: () async => model.openMarkets(context),
            ),
          ],
        ),
      );
    }

    return SailCard(
      title: 'Open positions',
      bottomPadding: false,
      child: ListenableBuilder(
        listenable: formatter,
        builder: (context, _) => SailTable(
          getRowId: (index) =>
              '${model.positions[index].address}-${model.positions[index].position.marketId}-'
              '${model.positions[index].position.outcomeIndex}',
          headerBuilder: (context) => const [
            SailTableHeaderCell(name: 'Market'),
            SailTableHeaderCell(name: 'Outcome'),
            SailTableHeaderCell(name: 'Address'),
            SailTableHeaderCell(name: 'Shares'),
            SailTableHeaderCell(name: 'Average price'),
            SailTableHeaderCell(name: 'Price'),
            SailTableHeaderCell(name: 'Value'),
            SailTableHeaderCell(name: 'Profit'),
          ],
          contextMenuItems: (rowId) {
            final holder = model.positions.firstWhere(
              (h) => '${h.address}-${h.position.marketId}-${h.position.outcomeIndex}' == rowId,
            );
            return [
              menuItem(
                'Trade',
                () => unawaited(model.openMarket(holder.position.marketId, holder.position.outcomeIndex)),
              ),
            ];
          },
          rowBuilder: (context, row, selected) {
            final holder = model.positions[row];
            final position = holder.position;
            return [
              SailTableCell(value: model.marketTitle(position.marketId)),
              SailTableCell(value: position.outcomeName),
              SailTableCell(value: model.shortAddress(holder.address), monospace: true),
              SailTableCell(value: '${position.shares}', monospace: true),
              SailTableCell(value: formatChance(position.avgPurchasePrice), monospace: true),
              SailTableCell(value: formatChance(position.currentPrice), monospace: true),
              SailTableCell(value: formatter.formatSats(position.currentValueSats), monospace: true),
              SailTableCell(
                value: position.pnlDisplay,
                monospace: true,
                textColor: position.isProfit ? theme.colors.success : theme.colors.error,
              ),
            ];
          },
          rowCount: model.positions.length,
          emptyPlaceholder: 'You hold no share yet',
        ),
      ),
    );
  }
}

class _YourMarketsCard extends StatelessWidget {
  final PortfolioViewModel model;

  const _YourMarketsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I.get<FormatterProvider>();
    final markets = model.yourMarkets;

    return SailCard(
      title: 'Your markets',
      subtitle: 'Markets that you created.',
      error: model.marketsError,
      bottomPadding: false,
      child: SizedBox(
        child: ListenableBuilder(
          listenable: formatter,
          builder: (context, _) => SailTable(
            getRowId: (index) => markets[index].marketId,
            headerBuilder: (context) => const [
              SailTableHeaderCell(name: 'Market'),
              SailTableHeaderCell(name: 'State'),
              SailTableHeaderCell(name: 'Volume'),
              SailTableHeaderCell(name: 'Liquidity'),
            ],
            contextMenuItems: (id) => [menuItem('Open', () => unawaited(model.openMarket(id, null)))],
            rowBuilder: (context, row, selected) {
              final market = markets[row];
              return [
                SailTableCell(value: market.title),
                SailTableCell(
                  value: market.marketState.displayName,
                  child: StatusDotCell(
                    label: market.marketState.displayName,
                    tone: market.isTrading ? SailStatusTone.success : SailStatusTone.neutral,
                  ),
                ),
                SailTableCell(value: formatter.formatSats(market.totalVolumeSats), monospace: true),
                SailTableCell(value: formatter.formatBTC(market.liquidity), monospace: true),
              ];
            },
            rowCount: markets.length,
            emptyPlaceholder: 'You created no market yet',
          ),
        ),
      ),
    );
  }
}

class _SendVotecoinCard extends StatelessWidget {
  final PortfolioViewModel model;

  const _SendVotecoinCard({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'Send Votecoin',
      subtitle: 'Votecoin is your vote weight. You hold ${model.votecoinBalance} Votecoin.',
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        children: [
          SailTextField(
            controller: model.votecoinDestController,
            label: 'To address',
            hintText: 'Truthcoin address',
            onChanged: (_) => model.onSendFormChanged(),
          ),
          SailTextField(
            controller: model.votecoinAmountController,
            label: 'Amount (Votecoin)',
            hintText: '0.005',
            textFieldType: TextFieldType.bitcoin,
            onChanged: (_) => model.onSendFormChanged(),
          ),
          SailTextField(
            controller: model.votecoinFeeController,
            label: 'Network fee (${activeTicker.subunit})',
            hintText: '$_votecoinNetworkFeeSats',
            textFieldType: TextFieldType.number,
            onChanged: (_) => model.onSendFormChanged(),
          ),
          if (model.sendError != null) SailInlineError(model.sendError!),
          SizedBox(
            width: double.infinity,
            child: SailButton(
              plainLabel: true,
              label: 'Send Votecoin',
              loading: model.isSendingVotecoin,
              disabled: !model.canSendVotecoin,
              onPressed: () async => model.sendVotecoin(context),
            ),
          ),
        ],
      ),
    );
  }
}

class PortfolioViewModel extends BaseViewModel {
  final MarketProvider _marketProvider = GetIt.I.get<MarketProvider>();
  final VotingProvider _votingProvider = GetIt.I.get<VotingProvider>();
  final TruthcoinRPC _rpc = GetIt.I.get<TruthcoinRPC>();

  List<String> addresses = [];
  List<AddressPosition> positions = [];
  double votecoinBalance = 0;
  int totalValueSats = 0;
  int totalCostBasisSats = 0;
  int totalProfitSats = 0;
  int activeMarkets = 0;
  bool isLoading = false;
  String? loadError;
  String? marketsError;

  final TextEditingController votecoinDestController = TextEditingController();
  final TextEditingController votecoinAmountController = TextEditingController();
  final TextEditingController votecoinFeeController = TextEditingController(text: '$_votecoinNetworkFeeSats');
  bool isSendingVotecoin = false;
  String? sendError;

  /// Markets whose creator is one of the wallet addresses.
  List<MarketData> get yourMarkets => [
    for (final summary in _marketProvider.markets)
      if (_marketProvider.marketDetails[summary.marketId] case final market?)
        if (addresses.contains(market.marketMaker)) market,
  ];

  double get votecoinAmount => double.tryParse(votecoinAmountController.text) ?? 0;
  int get votecoinFeeSats => int.tryParse(votecoinFeeController.text) ?? 0;

  bool get canSendVotecoin =>
      votecoinDestController.text.trim().isNotEmpty && votecoinAmount > 0 && votecoinFeeSats > 0;

  double get profitPercent => totalCostBasisSats > 0 ? totalProfitSats / totalCostBasisSats * 100 : 0;
  bool get hasProfit => totalProfitSats > 0;

  /// The first address stands for the wallet in the page header.
  String? get headlineAddress => addresses.isEmpty ? null : addresses.first;

  void init() {
    _marketProvider.addListener(_onProviderChange);
    load();
  }

  void _onProviderChange() {
    notifyListeners();
  }

  String marketTitle(String marketId) {
    final match = _marketProvider.markets.where((m) => m.marketId == marketId);
    if (match.isNotEmpty) return match.first.title;
    return _marketProvider.marketDetails[marketId]?.title ?? marketId;
  }

  String shortAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
  }

  /// Reads every wallet address, because a position sits on one address only.
  Future<void> load() async {
    isLoading = true;
    loadError = null;
    marketsError = null;
    addresses = [];
    positions = [];
    totalValueSats = 0;
    totalCostBasisSats = 0;
    totalProfitSats = 0;
    activeMarkets = 0;
    votecoinBalance = 0;
    notifyListeners();

    try {
      addresses = await _rpc.getWalletAddresses();
    } catch (e) {
      loadError = 'Failed to read the wallet addresses: $e';
      isLoading = false;
      notifyListeners();
      return;
    }

    await _marketProvider.loadMarkets();
    // market_list carries no creator, so the market details name it.
    await _marketProvider.loadMarketPrices(refresh: true);
    marketsError = _marketProvider.error ?? _marketProvider.priceError;

    final collected = <AddressPosition>[];
    final marketIds = <String>{};
    var value = 0;
    var costBasis = 0;
    var profit = 0;
    var votecoin = 0.0;

    for (final address in addresses) {
      try {
        final response = await _rpc.marketPositions(address: address);
        final holdings = UserHoldings.fromJson(response);
        for (final position in holdings.positions) {
          collected.add(AddressPosition(address, position));
          marketIds.add(position.marketId);
        }
        value += holdings.totalValueSats;
        costBasis += holdings.totalCostBasisSats;
        profit += holdings.totalUnrealizedPnlSats;
      } catch (e) {
        loadError = 'Failed to load the positions of $address: $e';
        isLoading = false;
        notifyListeners();
        return;
      }

      try {
        votecoin += await _votingProvider.getVotecoinBalance(address);
      } catch (e) {
        loadError = 'Failed to read the Votecoin of $address: $e';
        isLoading = false;
        notifyListeners();
        return;
      }
    }

    positions = collected;
    activeMarkets = marketIds.length;
    totalValueSats = value;
    totalCostBasisSats = costBasis;
    totalProfitSats = profit;
    votecoinBalance = votecoin;

    isLoading = false;
    notifyListeners();
  }

  void onSendFormChanged() {
    notifyListeners();
  }

  Future<void> sendVotecoin(BuildContext context) async {
    if (!canSendVotecoin) return;

    isSendingVotecoin = true;
    sendError = null;
    notifyListeners();

    final String txid;
    try {
      txid = await _rpc.transferVotecoin(
        dest: votecoinDestController.text.trim(),
        amount: votecoinAmount,
        feeSats: votecoinFeeSats,
      );
    } catch (e) {
      sendError = 'Failed to send Votecoin: $e';
      isSendingVotecoin = false;
      notifyListeners();
      return;
    }

    isSendingVotecoin = false;
    votecoinDestController.clear();
    votecoinAmountController.clear();
    if (context.mounted) {
      showSailToast(
        context,
        'Votecoin sent: ${txid.length > 16 ? txid.substring(0, 16) : txid}',
        variant: SailToastVariant.success,
      );
    }
    await load();
  }

  void openMarkets(BuildContext context) {
    AutoRouterX(context).tabsRouter.setActiveIndex(ShellTabIndex.of(TruthcoinModule()).chainTab(0));
  }

  Future<void> openMarket(String marketId, int? outcomeIndex) async {
    await openMarketsRoute(
      MarketDetailRoute(marketId: marketId, initialOutcomeIndex: outcomeIndex),
    );
  }

  @override
  void dispose() {
    _marketProvider.removeListener(_onProviderChange);
    votecoinDestController.dispose();
    votecoinAmountController.dispose();
    votecoinFeeController.dispose();
    super.dispose();
  }
}
