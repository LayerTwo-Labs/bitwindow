import 'package:auto_route/auto_route.dart';
import 'package:bitassets/providers/asset_analytics_provider.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:bitassets/providers/favorites_provider.dart';
import 'package:bitassets/routing/router.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class AssetExplorerTabPage extends StatelessWidget {
  const AssetExplorerTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<AssetExplorerViewModel>.reactive(
        viewModelBuilder: () => AssetExplorerViewModel(),
        builder: (context, model, child) {
          final selected = model.selectedAsset;
          final phone = SailStyleValues.phoneLayout(context);
          return SailColumn(
            spacing: SailStyleValues.padding12,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SailRow(
                spacing: SailStyleValues.padding08,
                children: [
                  Expanded(
                    child: SailTextField(
                      hintText: 'Search by name or hash...',
                      controller: model.searchController,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: SailSVG.icon(SailSVGAsset.iconSearch, width: 16),
                      ),
                    ),
                  ),
                  SailIconBoxButton(
                    icon: SailSVGAsset.refreshCw,
                    tooltip: 'Refresh',
                    size: sailV2FieldHeight,
                    onPressed: () async => model.refresh(),
                  ),
                ],
              ),
              AssetExplorerStats(
                total: model.filteredAssets.length,
                favorites: model.favoritesCount,
                withEncryption: model.assetsWithEncryption,
                withSigning: model.assetsWithSigning,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SailSegments(
                  labels: const ['All', 'Favorites'],
                  activeIndex: model.showFavoritesOnly ? 1 : 0,
                  onSelect: (index) => model.setShowFavoritesOnly(index == 1),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _AssetsCard(model: model)),
                    if (selected != null && !phone) ...[
                      const SizedBox(width: SailStyleValues.padding12),
                      AssetDetailsPanel(asset: selected, onClose: () async => model.select(null)),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AssetsCard extends StatelessWidget {
  final AssetExplorerViewModel model;

  const _AssetsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final assets = model.filteredAssets;
    final searching = model.searchController.text.isNotEmpty;

    return SailCard(
      title: 'Registered BitAssets',
      subtitle: 'Browse all assets on the network',
      child: model.isLoading
          ? const Center(child: SailCircularProgressIndicator())
          : assets.isEmpty
          ? _EmptyState(
              title: searching
                  ? 'No assets match your search'
                  : model.showFavoritesOnly
                  ? 'No favorite assets yet'
                  : 'No BitAssets registered yet',
              subtitle: searching
                  ? null
                  : model.showFavoritesOnly
                  ? 'Star assets to add them to your favorites'
                  : 'Register a new BitAsset to get started',
              action: searching || model.showFavoritesOnly
                  ? null
                  : SailButton(
                      label: 'Register Asset',
                      onPressed: () async {
                        await AutoRouter.of(context).navigate(const BitAssetsTabRoute());
                      },
                    ),
            )
          : SailTable(
              getRowId: (index) => assets[index].hash,
              selectedRowId: model.selectedHash,
              onSelectedRow: (rowId) {
                final asset = assets.firstWhereOrNull((a) => a.hash == rowId);
                if (asset == null) {
                  return;
                }
                if (SailStyleValues.phoneLayout(context)) {
                  showAssetDetailsDialog(context, asset);
                  return;
                }
                model.select(asset.hash);
              },
              headerBuilder: (context) => [
                const SailTableHeaderCell(name: '', sortable: false),
                const SailTableHeaderCell(name: 'Seq #'),
                const SailTableHeaderCell(name: 'Name'),
                const SailTableHeaderCell(name: 'Hash'),
                const SailTableHeaderCell(name: 'Encryption'),
                const SailTableHeaderCell(name: 'Signing'),
                const SailTableHeaderCell(name: 'Network'),
              ],
              rowBuilder: (context, row, selected) {
                final asset = assets[row];
                final favorite = model.isFavorite(asset.hash);
                final hasNetwork = asset.details.socketAddrV4 != null || asset.details.socketAddrV6 != null;
                return [
                  SailTableCell(
                    value: '',
                    width: 40,
                    child: SailTooltip(
                      message: favorite ? 'Remove from favorites' : 'Add to favorites',
                      child: SailTappable(
                        onTap: () async => model.toggleFavorite(asset.hash),
                        borderRadius: theme.chrome.radiusSmall,
                        child: SailSVG.fromAsset(
                          SailSVGAsset.star,
                          color: favorite ? theme.colors.orange : theme.colors.textSecondary,
                          width: 14,
                        ),
                      ),
                    ),
                  ),
                  SailTableCell(value: asset.sequenceID.toString()),
                  SailTableCell(value: asset.plaintextName ?? '-'),
                  SailTableCell(value: '${asset.hash.substring(0, 16)}...', copyValue: asset.hash, monospace: true),
                  SailTableCell(value: asset.details.encryptionPubkey != null ? 'Yes' : 'No'),
                  SailTableCell(value: asset.details.signingPubkey != null ? 'Yes' : 'No'),
                  SailTableCell(value: hasNetwork ? 'Available' : 'None'),
                ];
              },
              contextMenuItems: (rowId) {
                final asset = assets.firstWhereOrNull((a) => a.hash == rowId);
                if (asset == null) return [];
                final favorite = model.isFavorite(asset.hash);
                return [
                  SailMenuItem(
                    onSelected: () async {
                      if (SailStyleValues.phoneLayout(context)) {
                        await showAssetDetailsDialog(context, asset);
                        return;
                      }
                      model.select(asset.hash);
                    },
                    child: SailText.primary12('Show Details'),
                  ),
                  SailMenuItem(
                    onSelected: () async => model.toggleFavorite(asset.hash),
                    child: SailText.primary12(favorite ? 'Remove from favorites' : 'Add to favorites'),
                  ),
                  SailMenuItem(
                    onSelected: () async => model.copyToClipboard(asset.hash, context),
                    child: SailText.primary12('Copy hash'),
                  ),
                ];
              },
              rowCount: assets.length,
              drawGrid: true,
            ),
    );
  }
}

/// An icon, a title, an optional line and an optional button, at the center of an empty table card.
class _EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _EmptyState({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Center(
      child: SailColumn(
        spacing: SailStyleValues.padding08,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radiusSmall),
            child: SailSVG.icon(SailSVGAsset.iconCoins, width: 16),
          ),
          SailText.primary13(title, bold: true),
          if (subtitle != null) SailText.secondary12(subtitle!),
          ?action,
        ],
      ),
    );
  }
}

/// The asset counts: a strip on the desktop, one list panel on a phone.
@visibleForTesting
class AssetExplorerStats extends StatelessWidget {
  final int total;
  final int favorites;
  final int withEncryption;
  final int withSigning;

  const AssetExplorerStats({
    super.key,
    required this.total,
    required this.favorites,
    required this.withEncryption,
    required this.withSigning,
  });

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return SailStatList(
        children: [
          SailStatRow(title: 'Total Assets', subtitle: '', value: total.toString()),
          SailStatRow(title: 'Favorites', subtitle: '', value: favorites.toString()),
          SailStatRow(title: 'With Encryption', subtitle: '', value: withEncryption.toString()),
          SailStatRow(title: 'With Signing Key', subtitle: '', value: withSigning.toString()),
        ],
      );
    }
    return SailStrip(
      stats: [
        SailStat(label: 'Total Assets', value: total.toString()),
        SailStat(label: 'Favorites', value: favorites.toString()),
        SailStat(label: 'With Encryption', value: withEncryption.toString()),
        SailStat(label: 'With Signing Key', value: withSigning.toString()),
      ],
    );
  }
}

/// The 380 px panel with every field of one asset, each with a copy button.
class AssetDetailsPanel extends StatelessWidget {
  final BitAssetEntry asset;
  final Future<void> Function() onClose;

  const AssetDetailsPanel({super.key, required this.asset, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SailSidePanel(
      key: ValueKey('asset_details_${asset.hash}'),
      title: 'Asset Details',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.primary24(asset.plaintextName ?? '-', bold: true),
          const SizedBox(height: SailStyleValues.padding12),
          SailDetailGroup(children: _assetLines(asset)),
        ],
      ),
    );
  }
}

List<Widget> _assetLines(BitAssetEntry asset) {
  final details = asset.details;
  return [
    SailStackedDetail(label: 'Full Hash', value: asset.hash, copyValue: asset.hash),
    if (details.commitment != null)
      SailStackedDetail(label: 'Commitment', value: details.commitment!, copyValue: details.commitment),
    if (details.encryptionPubkey != null)
      SailStackedDetail(
        label: 'Encryption Pubkey',
        value: details.encryptionPubkey!,
        copyValue: details.encryptionPubkey,
      ),
    if (details.signingPubkey != null)
      SailStackedDetail(label: 'Signing Pubkey', value: details.signingPubkey!, copyValue: details.signingPubkey),
    if (details.socketAddrV4 != null)
      SailStackedDetail(label: 'IPv4 Address', value: details.socketAddrV4!, copyValue: details.socketAddrV4),
    if (details.socketAddrV6 != null)
      SailStackedDetail(label: 'IPv6 Address', value: details.socketAddrV6!, copyValue: details.socketAddrV6),
    if (details.commitment == null &&
        details.encryptionPubkey == null &&
        details.signingPubkey == null &&
        details.socketAddrV4 == null &&
        details.socketAddrV6 == null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SailText.secondary12('No additional metadata configured'),
      ),
  ];
}

Future<void> showAssetDetailsDialog(BuildContext context, BitAssetEntry asset) {
  return widgetDialog<void>(
    context: context,
    title: 'Asset Details',
    subtitle: asset.plaintextName,
    child: SailDetailGroup(children: _assetLines(asset)),
  );
}

class AssetExplorerViewModel extends BaseViewModel {
  final BitAssetsProvider bitAssetsProvider = GetIt.I.get<BitAssetsProvider>();
  final AssetAnalyticsProvider analyticsProvider = GetIt.I.get<AssetAnalyticsProvider>();
  final NotificationProvider notificationProvider = GetIt.I.get<NotificationProvider>();
  final FavoritesProvider favoritesProvider = GetIt.I.get<FavoritesProvider>();

  final TextEditingController searchController = TextEditingController();

  /// The asset the side panel shows. Null hides the panel.
  String? selectedHash;
  bool showFavoritesOnly = false;

  AssetExplorerViewModel() {
    bitAssetsProvider.addListener(notifyListeners);
    analyticsProvider.addListener(notifyListeners);
    favoritesProvider.addListener(notifyListeners);
    searchController.addListener(_onSearchChanged);
  }

  bool get isLoading => !bitAssetsProvider.initialized;

  List<BitAssetEntry> get filteredAssets {
    var assets = analyticsProvider.getFilteredAssets(bitAssetsProvider.entries);
    if (showFavoritesOnly) {
      assets = assets.where((a) => favoritesProvider.isFavorite(a.hash)).toList();
    }
    return assets;
  }

  int get assetsWithEncryption {
    return bitAssetsProvider.entries.where((a) => a.details.encryptionPubkey != null).length;
  }

  int get assetsWithSigning {
    return bitAssetsProvider.entries.where((a) => a.details.signingPubkey != null).length;
  }

  int get favoritesCount => favoritesProvider.favorites.length;

  bool isFavorite(String hash) => favoritesProvider.isFavorite(hash);

  void setShowFavoritesOnly(bool value) {
    showFavoritesOnly = value;
    notifyListeners();
  }

  Future<void> toggleFavorite(String hash) async {
    await favoritesProvider.toggleFavorite(hash);
  }

  void _onSearchChanged() {
    analyticsProvider.setAssetSearchQuery(searchController.text);
  }

  BitAssetEntry? get selectedAsset => bitAssetsProvider.entries.firstWhereOrNull((a) => a.hash == selectedHash);

  void select(String? hash) {
    selectedHash = hash;
    notifyListeners();
  }

  Future<void> refresh() async {
    await bitAssetsProvider.fetch();
    await analyticsProvider.fetch();
  }

  void copyToClipboard(String text, BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    notificationProvider.add(
      title: 'Copied',
      content: 'Value copied to clipboard',
      dialogType: DialogType.success,
    );
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    bitAssetsProvider.removeListener(notifyListeners);
    analyticsProvider.removeListener(notifyListeners);
    favoritesProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
