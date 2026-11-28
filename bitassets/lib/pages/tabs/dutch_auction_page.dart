import 'package:auto_route/auto_route.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:bitassets/widgets/auction_parts.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class DutchAuctionTabPage extends StatelessWidget {
  const DutchAuctionTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<DutchAuctionViewModel>.reactive(
        viewModelBuilder: () => DutchAuctionViewModel(),
        builder: (context, model, child) {
          if (SailStyleValues.phoneLayout(context)) {
            return SingleChildScrollView(
              child: SailColumn(
                spacing: SailStyleValues.padding12,
                children: [
                  SizedBox(height: 420, child: _AuctionsCard(model: model)),
                  SailCard(
                    title: 'Create Dutch Auction',
                    subtitle: 'Create a new dutch auction',
                    child: _CreateAuctionForm(model: model),
                  ),
                ],
              ),
            );
          }
          final details = model.detailsAuction;
          final panel = switch (model.panel) {
            DutchAuctionPanel.create => SailSidePanel(
              title: 'Create Dutch Auction',
              onClose: () async => model.closePanel(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SailText.secondary12('Create a new dutch auction'),
                  const SizedBox(height: SailStyleValues.padding12),
                  _CreateAuctionForm(model: model),
                ],
              ),
            ),
            DutchAuctionPanel.details when details != null => DutchAuctionDetailsPanel(
              auction: details,
              onBid: () => showBidDialog(context, details, model),
              onClose: () async => model.closePanel(),
            ),
            _ => null,
          };
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _AuctionsCard(model: model)),
              if (panel != null) ...[const SizedBox(width: SailStyleValues.padding12), panel],
            ],
          );
        },
      ),
    );
  }
}

class _AuctionsCard extends StatelessWidget {
  final DutchAuctionViewModel model;

  const _AuctionsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final auctions = model.filteredAuctions;
    return SailCard(
      title: 'Active Dutch Auctions',
      subtitle: 'View all ongoing dutch auctions',
      widgetHeaderEnd: SailRow(
        spacing: SailStyleValues.padding08,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            child: SailTextField(hintText: 'Search auctions...', controller: model.searchController),
          ),
          if (!SailStyleValues.phoneLayout(context))
            SailButton(
              label: 'Create New Auction',
              variant: ButtonVariant.outline,
              onPressed: () async => model.openCreate(),
            ),
        ],
      ),
      child: SailSkeletonizer(
        description: 'Loading auctions...',
        enabled: model.isLoading,
        child: SailTable(
          getRowId: (index) => auctions[index].id,
          selectedRowId: model.panel == DutchAuctionPanel.details ? model.detailsAuction?.id : null,
          onSelectedRow: (rowId) {
            final auction = auctions.firstWhereOrNull((a) => a.id == rowId);
            if (auction != null) {
              model.showDetails(context, auction);
            }
          },
          headerBuilder: (context) => [
            SailTableHeaderCell(name: 'ID'),
            SailTableHeaderCell(name: 'Base Asset'),
            SailTableHeaderCell(name: 'Quote Asset'),
            SailTableHeaderCell(name: 'Base Amount', alignment: Alignment.centerRight),
            SailTableHeaderCell(name: 'Current Price', alignment: Alignment.centerRight),
            SailTableHeaderCell(name: 'Status'),
          ],
          rowBuilder: (context, row, selected) {
            final auction = auctions[row];
            return [
              SailTableCell(value: '${auction.id.substring(0, 10)}..', copyValue: auction.id),
              _assetCell(auction.baseAsset),
              _assetCell(auction.quoteAsset),
              SailTableCell(value: auction.baseAmount.toString(), alignment: Alignment.centerRight),
              SailTableCell(value: auction.currentPrice?.toString() ?? 'N/A', alignment: Alignment.centerRight),
              SailTableCell(
                value: auctionStatusCellValue(auction.status),
                child: AuctionStatusLabel(status: auction.status),
              ),
            ];
          },
          contextMenuItems: (rowId) {
            final auction = auctions.firstWhereOrNull((a) => a.id == rowId);
            if (auction == null) return [];
            return [
              SailMenuItem(
                onSelected: () async => model.showDetails(context, auction),
                child: SailText.primary12('Show Details'),
              ),
              SailMenuItem(
                onSelected: () async => showBidDialog(context, auction, model),
                child: SailText.primary12('Place Bid'),
              ),
            ];
          },
          rowCount: auctions.length,
          drawGrid: true,
        ),
      ),
    );
  }
}

/// An asset id cut to its first 34 characters; a copy takes the full id.
SailTableCell _assetCell(String asset) => SailTableCell(
  value: asset.length <= 34 ? asset : '${asset.substring(0, 34)}...',
  copyValue: asset,
);

class _CreateAuctionForm extends StatelessWidget {
  final DutchAuctionViewModel model;

  const _CreateAuctionForm({required this.model});

  @override
  Widget build(BuildContext context) {
    Widget pair(Widget first, Widget second) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: SailStyleValues.padding08),
        Expanded(child: second),
      ],
    );

    return SailColumn(
      spacing: SailStyleValues.padding12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(
          SailTextField(label: 'Base Asset ID', hintText: 'Asset to auction', controller: model.baseAssetController),
          SailTextField(label: 'Quote Asset ID', hintText: 'Quote asset', controller: model.quoteAssetController),
        ),
        SailTextField(label: 'Base Amount', hintText: 'Amount to auction', controller: model.baseAmountController),
        pair(
          SailTextField(
            label: 'Start Block',
            hintText: 'Block to start auction',
            controller: model.startBlockController,
          ),
          SailTextField(label: 'Duration (blocks)', hintText: 'Auction duration', controller: model.durationController),
        ),
        pair(
          SailTextField(label: 'Initial Price', hintText: 'Starting price', controller: model.initialPriceController),
          SailTextField(label: 'Final Price', hintText: 'Ending price', controller: model.finalPriceController),
        ),
        SailText.secondary12('Estimated creation fee: ~1,000 sats (network fee)'),
        if (model.createError != null)
          SailText.primary13(model.createError!, color: SailTheme.of(context).colors.error),
        SailButton(
          label: 'Create Auction',
          onPressed: model.createLoading ? null : () => model.createDutchAuction(context),
          loading: model.createLoading,
        ),
      ],
    );
  }
}

/// The 380 px panel of one dutch auction: its price now, its status, Place Bid and every field.
class DutchAuctionDetailsPanel extends StatelessWidget {
  final DutchAuctionEntry auction;
  final Future<void> Function() onBid;
  final Future<void> Function() onClose;

  const DutchAuctionDetailsPanel({super.key, required this.auction, required this.onBid, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SailSidePanel(
      key: ValueKey('dutch_auction_${auction.id}'),
      title: 'Dutch Auction Details',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelKeyValue(value: auction.currentPrice?.toString() ?? 'N/A', caption: 'Current Price'),
          const SizedBox(height: SailStyleValues.padding12),
          Align(
            alignment: Alignment.centerLeft,
            child: SailStatusPill(label: auction.status, tone: auctionStatusTone(auction.status)),
          ),
          const SizedBox(height: SailStyleValues.padding16),
          SailButton(label: 'Place Bid', onPressed: onBid),
          const SizedBox(height: SailStyleValues.padding12),
          SailDetailGroup(children: _auctionLines(auction)),
        ],
      ),
    );
  }
}

List<Widget> _auctionLines(DutchAuctionEntry auction) => [
  SailStackedDetail(label: 'ID', value: auction.id),
  SailStackedDetail(label: 'Base Asset', value: auction.baseAsset),
  SailStackedDetail(label: 'Quote Asset', value: auction.quoteAsset),
  SailStackedDetail(label: 'Base Amount', value: auction.baseAmount.toString()),
  SailStackedDetail(label: 'Initial Price', value: auction.initialPrice.toString()),
  SailStackedDetail(label: 'Final Price', value: auction.finalPrice.toString()),
  SailStackedDetail(label: 'Start Block', value: auction.startBlock.toString()),
  SailStackedDetail(label: 'Duration', value: auction.duration.toString()),
  SailStackedDetail(label: 'Status', value: auction.status),
  if (auction.currentPrice != null) SailStackedDetail(label: 'Current Price', value: auction.currentPrice.toString()),
];

Future<void> showAuctionDetails(BuildContext context, DutchAuctionEntry auction) async {
  await Future.microtask(() async {
    if (!context.mounted) return;
    return showThemedDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: true,
          child: SailModal(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SailCard(
              title: 'Dutch Auction Details',
              subtitle: auction.id,
              withCloseButton: true,
              child: SingleChildScrollView(child: SailDetailGroup(children: _auctionLines(auction))),
            ),
          ),
        );
      },
    );
  });
}

Future<void> showBidDialog(BuildContext context, DutchAuctionEntry auction, DutchAuctionViewModel model) async {
  final bidController = TextEditingController();

  await widgetDialog<void>(
    context: context,
    title: 'Place Bid',
    subtitle: 'Auction: ${auction.id.substring(0, 10)}...',
    maxWidth: 400,
    action: SailDialogAction(
      label: 'Place Bid',
      onPressed: () async {
        final bidSize = int.tryParse(bidController.text);
        if (bidSize == null) {
          return;
        }
        Navigator.of(context, rootNavigator: true).pop();
        await model.placeBid(context, auction.id, bidSize);
      },
    ),
    child: SailTextField(label: 'Bid Size', hintText: 'Amount to bid', controller: bidController),
  );
}

/// What the side panel of the Dutch Auction tab shows.
enum DutchAuctionPanel { create, details, closed }

class DutchAuctionViewModel extends BaseViewModel {
  final SidechainBalanceProvider balanceProvider = GetIt.I.get<SidechainBalanceProvider>();
  final NotificationProvider notificationProvider = GetIt.I.get<NotificationProvider>();
  final BitAssetsRPC bitassetsRPC = GetIt.I.get<BitAssetsRPC>();
  final BitAssetsProvider bitAssetsProvider = GetIt.I.get<BitAssetsProvider>();

  final TextEditingController searchController = TextEditingController();
  final TextEditingController baseAssetController = TextEditingController();
  final TextEditingController quoteAssetController = TextEditingController();
  final TextEditingController baseAmountController = TextEditingController();
  final TextEditingController startBlockController = TextEditingController();
  final TextEditingController durationController = TextEditingController();
  final TextEditingController initialPriceController = TextEditingController();
  final TextEditingController finalPriceController = TextEditingController();

  bool createLoading = false;
  String? createError;

  DutchAuctionPanel panel = DutchAuctionPanel.create;
  DutchAuctionEntry? detailsAuction;

  DutchAuctionViewModel() {
    searchController.addListener(notifyListeners);
    bitAssetsProvider.addListener(notifyListeners);
    bitAssetsProvider.fetch();
  }

  List<DutchAuctionEntry> get filteredAuctions {
    final searchText = searchController.text.toLowerCase();
    if (searchText.isEmpty) {
      return bitAssetsProvider.auctions;
    }

    return bitAssetsProvider.auctions.where((auction) {
      return auction.id.toLowerCase().contains(searchText) ||
          auction.baseAsset.toLowerCase().contains(searchText) ||
          auction.quoteAsset.toLowerCase().contains(searchText) ||
          auction.status.toLowerCase().contains(searchText);
    }).toList();
  }

  bool get isLoading => bitAssetsProvider.isLoadingAuctions;

  void openCreate() {
    panel = DutchAuctionPanel.create;
    notifyListeners();
  }

  void closePanel() {
    panel = DutchAuctionPanel.closed;
    detailsAuction = null;
    notifyListeners();
  }

  /// Shows [auction] in the side panel, or in a dialog on a phone.
  Future<void> showDetails(BuildContext context, DutchAuctionEntry auction) async {
    if (SailStyleValues.phoneLayout(context)) {
      await showAuctionDetails(context, auction);
      return;
    }
    panel = DutchAuctionPanel.details;
    detailsAuction = auction;
    notifyListeners();
  }

  Future<void> createDutchAuction(BuildContext context) async {
    createError = null;

    // Validate inputs
    final baseAsset = baseAssetController.text.trim();
    final quoteAsset = quoteAssetController.text.trim();
    final baseAmount = int.tryParse(baseAmountController.text.trim());
    final startBlock = int.tryParse(startBlockController.text.trim());
    final duration = int.tryParse(durationController.text.trim());
    final initialPrice = int.tryParse(initialPriceController.text.trim());
    final finalPrice = int.tryParse(finalPriceController.text.trim());

    if (baseAsset.isEmpty ||
        quoteAsset.isEmpty ||
        baseAmount == null ||
        startBlock == null ||
        duration == null ||
        initialPrice == null ||
        finalPrice == null) {
      createError = 'All fields are required and must be valid numbers';
      notifyListeners();
      return;
    }

    createLoading = true;
    notifyListeners();

    try {
      final auctionId = await bitassetsRPC.dutchAuctionCreate(
        DutchAuctionParams(
          baseAsset: baseAsset,
          quoteAsset: quoteAsset,
          baseAmount: baseAmount,
          startBlock: startBlock,
          duration: duration,
          initialPrice: initialPrice,
          finalPrice: finalPrice,
        ),
      );

      if (context.mounted) {
        notificationProvider.add(
          title: 'Success',
          content: 'Dutch auction created successfully: $auctionId',
          dialogType: DialogType.success,
        );
      }

      // Clear form
      baseAssetController.clear();
      quoteAssetController.clear();
      baseAmountController.clear();
      startBlockController.clear();
      durationController.clear();
      initialPriceController.clear();
      finalPriceController.clear();

      // Refresh auctions
      await bitAssetsProvider.fetch();
    } catch (e) {
      createError = e.toString();
    } finally {
      createLoading = false;
      notifyListeners();
    }
  }

  Future<void> placeBid(BuildContext context, String auctionId, int bidSize) async {
    try {
      final result = await bitassetsRPC.dutchAuctionBid(dutchAuctionId: auctionId, bidSize: bidSize);

      if (context.mounted) {
        notificationProvider.add(
          title: 'Success',
          content: 'Bid placed successfully. You will receive $result base asset',
          dialogType: DialogType.success,
        );
      }

      await bitAssetsProvider.fetch();
    } catch (e) {
      if (context.mounted) {
        notificationProvider.add(
          title: 'Error',
          content: 'Failed to place bid: $e',
          dialogType: DialogType.error,
        );
      }
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    baseAssetController.dispose();
    quoteAssetController.dispose();
    baseAmountController.dispose();
    startBlockController.dispose();
    durationController.dispose();
    initialPriceController.dispose();
    finalPriceController.dispose();
    bitAssetsProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
