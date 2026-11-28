import 'package:auto_route/auto_route.dart';
import 'package:bitassets/providers/asset_analytics_provider.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:bitassets/providers/favorites_provider.dart';
import 'package:bitassets/providers/price_alert_provider.dart';
import 'package:bitassets/routing/router.dart';
import 'package:bitassets/settings/price_alerts_settings.dart';
import 'package:bitassets/widgets/auction_parts.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class AuctionBrowserTabPage extends StatelessWidget {
  const AuctionBrowserTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<AuctionBrowserViewModel>.reactive(
        viewModelBuilder: () => AuctionBrowserViewModel(),
        builder: (context, model, child) {
          final selected = model.selectedAuction;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _AuctionsCard(model: model)),
              if (selected != null && !SailStyleValues.phoneLayout(context)) ...[
                const SizedBox(width: SailStyleValues.padding12),
                AuctionPanel(model: model, auction: selected),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AuctionsCard extends StatelessWidget {
  final AuctionBrowserViewModel model;

  const _AuctionsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    final filters = [AuctionFilter.all, AuctionFilter.active, AuctionFilter.upcoming, AuctionFilter.ended];
    final search = SailTextField(
      hintText: 'Search by auction ID or asset...',
      controller: model.searchController,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: SailSVG.icon(SailSVGAsset.iconSearch, width: 16),
      ),
    );
    final sort = SizedBox(
      width: 150,
      child: SailDropdownButton<AuctionSort>(
        value: model.currentSort,
        items: [
          SailDropdownItem(value: AuctionSort.startBlockDesc, label: 'Newest First'),
          SailDropdownItem(value: AuctionSort.startBlockAsc, label: 'Oldest First'),
          SailDropdownItem(value: AuctionSort.priceDesc, label: 'Highest Price'),
          SailDropdownItem(value: AuctionSort.priceAsc, label: 'Lowest Price'),
          SailDropdownItem(value: AuctionSort.amountDesc, label: 'Largest Amount'),
          SailDropdownItem(value: AuctionSort.amountAsc, label: 'Smallest Amount'),
        ],
        onChanged: (value) {
          if (value != null) model.setSort(value);
        },
      ),
    );
    final refresh = SailIconBoxButton(
      icon: SailSVGAsset.refreshCw,
      tooltip: 'Refresh',
      size: sailV2FieldHeight,
      onPressed: () async => model.refresh(),
    );

    return SailCard(
      title: 'Dutch Auctions',
      subtitle: 'Browse and bid on asset auctions',
      widgetHeaderEnd: phone
          ? null
          : SailRow(
              spacing: SailStyleValues.padding08,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 260, child: search),
                sort,
                refresh,
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phone) ...[
            SailRow(
              spacing: SailStyleValues.padding08,
              children: [
                Expanded(child: search),
                refresh,
              ],
            ),
            const SizedBox(height: SailStyleValues.padding08),
            Align(alignment: Alignment.centerLeft, child: sort),
            const SizedBox(height: SailStyleValues.padding08),
          ],
          Row(
            children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SailSegments(
                    labels: [for (final filter in filters) '${_filterLabel(filter)} ${model.countFor(filter)}'],
                    activeIndex: filters.indexOf(model.currentFilter),
                    onSelect: (index) => model.setFilter(filters[index]),
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(width: SailStyleValues.padding12),
              SailText.secondary12('Current Block: ${model.currentBlock}'),
            ],
          ),
          const SizedBox(height: SailStyleValues.padding08),
          Expanded(child: _AuctionsTable(model: model)),
        ],
      ),
    );
  }
}

class _AuctionsTable extends StatelessWidget {
  final AuctionBrowserViewModel model;

  const _AuctionsTable({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    if (model.isLoading) {
      return const Center(child: SailCircularProgressIndicator());
    }
    final auctions = model.filteredAuctions;
    if (auctions.isEmpty) {
      final searching = model.searchController.text.isNotEmpty;
      final all = model.currentFilter == AuctionFilter.all;
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding08,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radiusSmall),
              child: SailSVG.icon(SailSVGAsset.iconCalendar, width: 16),
            ),
            SailText.primary13(
              searching
                  ? 'No auctions match your search'
                  : all
                  ? 'No auctions yet'
                  : 'No ${model.currentFilter.name} auctions',
              bold: true,
            ),
            if (all && !searching) ...[
              SailText.secondary12('Create a Dutch auction to sell your assets'),
              SailButton(
                label: 'Create Auction',
                onPressed: () async {
                  await AutoRouter.of(context).navigate(const DutchAuctionTabRoute());
                },
              ),
            ],
          ],
        ),
      );
    }

    return SailTable(
      getRowId: (index) => auctions[index].id,
      selectedRowId: model.selectedId,
      onSelectedRow: (rowId) {
        final auction = auctions.firstWhereOrNull((a) => a.id == rowId);
        if (auction == null) {
          return;
        }
        if (SailStyleValues.phoneLayout(context)) {
          if (model.getAuctionStatus(auction) == 'Active') {
            model.showBidDialog(context, auction);
          }
          return;
        }
        model.select(auction.id);
      },
      headerBuilder: (context) => const [
        SailTableHeaderCell(name: '', sortable: false),
        SailTableHeaderCell(name: 'Status'),
        SailTableHeaderCell(name: 'Auction ID'),
        SailTableHeaderCell(name: 'Base Asset'),
        SailTableHeaderCell(name: 'Quote Asset'),
        SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight),
        SailTableHeaderCell(name: 'Price Range', alignment: Alignment.centerRight),
        SailTableHeaderCell(name: 'Current', alignment: Alignment.centerRight),
        SailTableHeaderCell(name: 'Duration'),
      ],
      rowBuilder: (context, row, selected) {
        final auction = auctions[row];
        final status = model.getAuctionStatus(auction);
        final favorite = model.isFavorite(auction.baseAsset);
        return [
          SailTableCell(
            value: '',
            width: 40,
            child: SailSVG.fromAsset(
              SailSVGAsset.star,
              color: favorite ? theme.colors.orange : theme.colors.textSecondary,
              width: 14,
            ),
          ),
          SailTableCell(
            value: auctionStatusCellValue(status),
            child: AuctionStatusLabel(status: status),
          ),
          SailTableCell(value: '${auction.id.substring(0, 16)}...', monospace: true),
          SailTableCell(value: model.getAssetName(auction.baseAsset)),
          SailTableCell(value: model.getAssetName(auction.quoteAsset)),
          SailTableCell(value: formatAuctionAmount(auction.baseAmount), alignment: Alignment.centerRight),
          SailTableCell(
            value: '${formatAuctionAmount(auction.finalPrice)} - ${formatAuctionAmount(auction.initialPrice)}',
            alignment: Alignment.centerRight,
          ),
          SailTableCell(
            value: status == 'Upcoming' ? '—' : formatAuctionAmount(model.getCurrentPrice(auction)),
            alignment: Alignment.centerRight,
          ),
          SailTableCell(
            value: '${auction.duration} blocks',
            secondaryValue: switch (status) {
              'Upcoming' => 'Not started',
              'Ended' => 'Ended',
              _ => null,
            },
          ),
        ];
      },
      contextMenuItems: (rowId) {
        final auction = auctions.firstWhereOrNull((a) => a.id == rowId);
        if (auction == null) return [];
        return model.menuItems(context, auction);
      },
      rowCount: auctions.length,
      drawGrid: true,
    );
  }
}

String _filterLabel(AuctionFilter filter) => switch (filter) {
  AuctionFilter.all => 'All',
  AuctionFilter.active => 'Active',
  AuctionFilter.upcoming => 'Upcoming',
  AuctionFilter.ended => 'Ended',
};

/// An amount as 50.0k, 1.20M, or in whole coins from one coin up.
String formatAuctionAmount(int amount) {
  if (amount >= 100000000) {
    return '${(amount / 100000000).toStringAsFixed(4)} ${activeTicker.symbol}';
  } else if (amount >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(2)}M';
  } else if (amount >= 1000) {
    return '${(amount / 1000).toStringAsFixed(1)}k';
  }
  return amount.toString();
}

/// The 380 px panel of one auction: its price now, status, progress, Bid and its fields.
class AuctionPanel extends StatelessWidget {
  final AuctionBrowserViewModel model;
  final DutchAuctionEntry auction;

  const AuctionPanel({super.key, required this.model, required this.auction});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final status = model.getAuctionStatus(auction);
    final current = status == 'Upcoming' ? '—' : formatAuctionAmount(model.getCurrentPrice(auction));
    final range = '${formatAuctionAmount(auction.finalPrice)} - ${formatAuctionAmount(auction.initialPrice)}';

    return SailSidePanel(
      key: ValueKey('auction_panel_${auction.id}'),
      title: '${auction.id.substring(0, 16)}...',
      menuItems: () => model.menuItems(context, auction),
      onClose: () async => model.select(null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelKeyValue(value: current, caption: 'Current'),
          const SizedBox(height: SailStyleValues.padding12),
          Align(
            alignment: Alignment.centerLeft,
            child: SailStatusPill(label: status, tone: auctionStatusTone(status)),
          ),
          const SizedBox(height: SailStyleValues.padding12),
          Row(
            children: [
              Expanded(child: SailText.primary15('Duration')),
              SailText.primary15('${auction.duration} blocks', color: theme.colors.textSecondary),
            ],
          ),
          const SizedBox(height: SailStyleValues.padding08),
          ProgressBar(
            current: model.progressOf(auction),
            goal: 1,
            small: true,
            hideProgressInside: true,
            color: theme.colors.primary,
          ),
          const SizedBox(height: SailStyleValues.padding16),
          SailButton(
            label: 'Bid',
            disabled: status != 'Active',
            onPressed: () async => model.showBidDialog(context, auction),
          ),
          const SizedBox(height: SailStyleValues.padding20),
          SailText.primary13('Details', bold: true),
          const SizedBox(height: SailStyleValues.padding08),
          SailDetailGroup(
            children: [
              SailDetailLine(label: 'Auction ID', value: '${auction.id.substring(0, 16)}...'),
              SailDetailLine(label: 'Base Asset', value: model.getAssetName(auction.baseAsset)),
              SailDetailLine(label: 'Quote Asset', value: model.getAssetName(auction.quoteAsset)),
              SailDetailLine(label: 'Amount', value: formatAuctionAmount(auction.baseAmount)),
              SailDetailLine(label: 'Price Range', value: range),
              SailDetailLine(label: 'Current', value: current),
              SailDetailLine(label: 'Duration', value: '${auction.duration} blocks'),
            ],
          ),
        ],
      ),
    );
  }
}

class AuctionBrowserViewModel extends BaseViewModel {
  final BitAssetsProvider bitAssetsProvider = GetIt.I.get<BitAssetsProvider>();
  final AssetAnalyticsProvider analyticsProvider = GetIt.I.get<AssetAnalyticsProvider>();
  final BitAssetsRPC rpc = GetIt.I.get<BitAssetsRPC>();
  final NotificationProvider notificationProvider = GetIt.I.get<NotificationProvider>();
  final FavoritesProvider favoritesProvider = GetIt.I.get<FavoritesProvider>();
  final PriceAlertProvider priceAlertProvider = GetIt.I.get<PriceAlertProvider>();

  final TextEditingController searchController = TextEditingController();

  int currentBlock = 0;

  AuctionBrowserViewModel() {
    bitAssetsProvider.addListener(_fetchCurrentBlock);
    analyticsProvider.addListener(notifyListeners);
    favoritesProvider.addListener(notifyListeners);
    priceAlertProvider.addListener(notifyListeners);
    searchController.addListener(_onSearchChanged);
    _fetchCurrentBlock();
  }

  bool isFavorite(String assetHash) => favoritesProvider.isFavorite(assetHash);

  bool hasAlertForAuction(String auctionId) => priceAlertProvider.hasAlertForAuction(auctionId);

  Future<void> toggleFavorite(String assetHash) async {
    await favoritesProvider.toggleFavorite(assetHash);
  }

  Future<void> _fetchCurrentBlock() async {
    try {
      currentBlock = await rpc.getBlockCount();
      notifyListeners();
    } catch (_) {}
  }

  bool get isLoading => bitAssetsProvider.isLoadingAuctions;

  List<DutchAuctionEntry> get allAuctions => bitAssetsProvider.auctions;

  List<DutchAuctionEntry> get filteredAuctions {
    return analyticsProvider.getFilteredAuctions(allAuctions, currentBlock);
  }

  AuctionFilter get currentFilter => analyticsProvider.auctionFilter;
  AuctionSort get currentSort => analyticsProvider.auctionSort;

  int get activeCount => allAuctions.where((a) => getAuctionStatus(a) == 'Active').length;
  int get upcomingCount => allAuctions.where((a) => getAuctionStatus(a) == 'Upcoming').length;
  int get endedCount => allAuctions.where((a) => getAuctionStatus(a) == 'Ended').length;

  int countFor(AuctionFilter filter) => switch (filter) {
    AuctionFilter.all => allAuctions.length,
    AuctionFilter.active => activeCount,
    AuctionFilter.upcoming => upcomingCount,
    AuctionFilter.ended => endedCount,
  };

  /// The auction the side panel shows. Null hides the panel.
  String? selectedId;

  DutchAuctionEntry? get selectedAuction => allAuctions.where((a) => a.id == selectedId).firstOrNull;

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  /// The part of the duration that passed, from 0 to 1. Only an active auction moves.
  double progressOf(DutchAuctionEntry auction) {
    if (getAuctionStatus(auction) != 'Active') return 0;
    final elapsed = currentBlock - auction.startBlock;
    return (elapsed / auction.duration).clamp(0.0, 1.0);
  }

  /// The "…" actions of [auction]: the price alert for an active auction, the favorite and the id copy.
  List<SailMenuEntity> menuItems(BuildContext context, DutchAuctionEntry auction) {
    final favorite = isFavorite(auction.baseAsset);
    return [
      if (getAuctionStatus(auction) == 'Active')
        SailMenuItem(
          onSelected: () async => showAlertDialog(context, auction),
          child: SailText.primary12(hasAlertForAuction(auction.id) ? 'Edit Price Alert' : 'Set Price Alert'),
        ),
      SailMenuItem(
        onSelected: () async => toggleFavorite(auction.baseAsset),
        child: SailText.primary12(favorite ? 'Remove from favorites' : 'Favorite'),
      ),
      SailMenuItem(
        onSelected: () async => copyToClipboard(auction.id, context),
        child: SailText.primary12('Copy auction ID'),
      ),
    ];
  }

  void _onSearchChanged() {
    analyticsProvider.setAuctionSearchQuery(searchController.text);
  }

  void setFilter(AuctionFilter filter) {
    analyticsProvider.setAuctionFilter(filter);
  }

  void setSort(AuctionSort sort) {
    analyticsProvider.setAuctionSort(sort);
  }

  String getAuctionStatus(DutchAuctionEntry auction) {
    return analyticsProvider.getAuctionStatus(auction, currentBlock);
  }

  int getCurrentPrice(DutchAuctionEntry auction) {
    return analyticsProvider.calculateCurrentPrice(auction, currentBlock);
  }

  String getAssetName(String assetId) {
    if (assetId == 'btc' || assetId.isEmpty) return activeTicker.symbol;
    final asset = bitAssetsProvider.entries.where((e) => e.hash == assetId).firstOrNull;
    return asset?.plaintextName ?? '${assetId.substring(0, 8)}...';
  }

  Future<void> refresh() async {
    await Future.wait([
      bitAssetsProvider.fetch(),
      _fetchCurrentBlock(),
    ]);
  }

  void copyToClipboard(String text, BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    notificationProvider.add(
      title: 'Copied',
      content: 'Auction ID copied to clipboard',
      dialogType: DialogType.success,
    );
  }

  void showBidDialog(BuildContext context, DutchAuctionEntry auction) {
    final bidController = TextEditingController();
    final quote = getAssetName(auction.quoteAsset);

    widgetDialog<void>(
      context: context,
      title: 'Bid on Auction',
      maxWidth: 440,
      action: SailDialogAction(
        label: 'Place Bid',
        onPressed: () async {
          final bidAmount = int.tryParse(bidController.text);
          if (bidAmount == null || bidAmount <= 0) {
            notificationProvider.add(
              title: 'Invalid Bid',
              content: 'Please enter a valid bid amount',
              dialogType: DialogType.error,
            );
            return;
          }

          try {
            final received = await rpc.dutchAuctionBid(
              dutchAuctionId: auction.id,
              bidSize: bidAmount,
            );

            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }

            notificationProvider.add(
              title: 'Bid Successful',
              content: 'Received $received ${getAssetName(auction.baseAsset)}',
              dialogType: DialogType.success,
            );

            await refresh();
          } catch (e) {
            notificationProvider.add(
              title: 'Bid Failed',
              content: e.toString(),
              dialogType: DialogType.error,
            );
          }
        },
      ),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailDetailGroup(
            children: [
              SailDetailLine(label: 'Auction:', value: '${auction.id.substring(0, 20)}...'),
              SailDetailLine(label: 'Current Price:', value: '${getCurrentPrice(auction)} sats per unit'),
              SailDetailLine(label: 'Available:', value: '${auction.baseAmount} ${getAssetName(auction.baseAsset)}'),
            ],
          ),
          SailTextField(
            label: 'Bid amount in $quote',
            hintText: '',
            controller: bidController,
            suffix: quote,
          ),
        ],
      ),
    );
  }

  void showAlertDialog(BuildContext context, DutchAuctionEntry auction) {
    final priceController = TextEditingController();
    final existingAlert = priceAlertProvider.getAlertsForAuction(auction.id).firstOrNull;
    bool alertWhenBelow = existingAlert?.alertWhenBelow ?? true;

    if (existingAlert != null) {
      priceController.text = existingAlert.targetPrice.toString();
    }

    final save = SailDialogAction(
      label: existingAlert != null ? 'Update Alert' : 'Set Alert',
      onPressed: () async {
        final targetPrice = int.tryParse(priceController.text);
        if (targetPrice == null || targetPrice <= 0) {
          notificationProvider.add(
            title: 'Invalid Price',
            content: 'Please enter a valid target price',
            dialogType: DialogType.error,
          );
          return;
        }

        final alert = PriceAlert(
          auctionId: auction.id,
          assetId: auction.baseAsset,
          targetPrice: targetPrice,
          alertWhenBelow: alertWhenBelow,
          enabled: true,
          createdAt: DateTime.now(),
        );

        if (existingAlert != null) {
          await priceAlertProvider.updateAlert(alert);
        } else {
          await priceAlertProvider.addAlert(alert);
        }

        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        notificationProvider.add(
          title: 'Alert Set',
          content:
              'You will be notified when price ${alertWhenBelow ? "drops below" : "rises above"} $targetPrice ${activeTicker.subunit}',
          dialogType: DialogType.success,
        );
      },
    );

    widgetDialog<void>(
      context: context,
      title: existingAlert != null ? 'Edit Price Alert' : 'Set Price Alert',
      maxWidth: 440,
      child: StatefulBuilder(
        builder: (context, setState) {
          return SailColumn(
            spacing: SailStyleValues.padding12,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SailDetailGroup(
                children: [
                  SailDetailLine(label: 'Auction:', value: '${auction.id.substring(0, 20)}...'),
                  SailDetailLine(label: 'Current Price:', value: '${getCurrentPrice(auction)} ${activeTicker.subunit}'),
                ],
              ),
              SailTextField(
                label: 'Target Price (sats)',
                hintText: 'Alert when price reaches this value',
                controller: priceController,
              ),
              SailText.primary13('Alert when price:', bold: true),
              Align(
                alignment: Alignment.centerLeft,
                child: SailSegments(
                  labels: const ['Drops below', 'Rises above'],
                  activeIndex: alertWhenBelow ? 0 : 1,
                  onSelect: (index) => setState(() => alertWhenBelow = index == 0),
                ),
              ),
              SailDialogActionButton(action: save),
              if (existingAlert != null)
                SailButton(
                  label: 'Remove Alert',
                  variant: ButtonVariant.ghost,
                  onPressed: () async {
                    await priceAlertProvider.removeAlert(auction.id);
                    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
                    notificationProvider.add(
                      title: 'Alert Removed',
                      content: 'Price alert has been removed',
                      dialogType: DialogType.success,
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    bitAssetsProvider.removeListener(_fetchCurrentBlock);
    analyticsProvider.removeListener(notifyListeners);
    favoritesProvider.removeListener(notifyListeners);
    priceAlertProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
