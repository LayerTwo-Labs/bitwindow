import 'dart:async';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:bitwindow/env.dart';
import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:bitwindow/utils/explorer_url.dart';
import 'package:bitwindow/utils/web_link.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/headline_highlight_text_field.dart';
import 'package:bitwindow/widgets/news_cost.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/rpcs/stream_supervisor.dart';
import 'package:sidechain_core/providers/price_provider.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  @override
  Widget build(BuildContext context) {
    // A kept-alive tab that is not shown stops the tickers and polls below it.
    final tabs = TabsRouterScope.of(context, watch: true)?.controller;
    return TickerMode(
      enabled: tabs == null || tabs.current.name == OverviewRoute.name,
      child: QtPage(child: HomepageView(provider: GetIt.I.get<HomepageProvider>())),
    );
  }
}

class FireplaceViewModel extends BaseViewModel {
  final PriceProvider priceProvider = GetIt.I.get<PriceProvider>();
  final BitwindowRPC api = GetIt.I.get<BitwindowRPC>();
  final EnforcerRPC _enforcerRPC = GetIt.I<EnforcerRPC>();
  late final StreamSupervisor<WatchFireplaceStatsResponse> _statsWatch;
  late final StreamSubscription<bool> _statsHealth;

  bool get loading => _enforcerRPC.initializingBinary;

  String get priceLastUpdated => priceProvider.priceAge;
  String get price => priceProvider.formattedPrice;
  String get priceTitle => activeTicker == Ticker.bitcoin ? 'Bitcoin Price' : '${activeTicker.symbol} Price';

  FireplaceViewModel() {
    priceProvider.addListener(notifyListeners);
    _enforcerRPC.addListener(notifyListeners);
    _statsWatch = StreamSupervisor<WatchFireplaceStatsResponse>(
      // A recreated connection replaces api.bitwindowd, so resolve it per call.
      subscribe: () => api.bitwindowd.watchFireplaceStats().transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stackTrace, sink) {
            _onStatsError(error);
            sink.addError(error, stackTrace);
          },
        ),
      ),
      onEvent: applyStatsFrame,
      onTransportDeath: () {},
      logger: GetIt.I.get<Logger>(),
      tag: 'FireplaceViewModel',
    );
    _statsHealth = _statsWatch.healthStream.listen(_onStatsHealth);
    _statsWatch.start();
  }

  /// The stats of the last frame, or null before it.
  GetFireplaceStatsResponse? stats;

  /// The stream failed, so the stats are missing or not current.
  bool statsFailed = false;

  @visibleForTesting
  void applyStatsFrame(WatchFireplaceStatsResponse frame) {
    if (frame.heartbeat) {
      return;
    }
    if (frame.stats == stats && !statsFailed) {
      return;
    }
    stats = frame.stats;
    statsFailed = false;
    notifyListeners();
  }

  void _onStatsError(Object error) {
    if (!isExpectedBootError(error)) {
      _markStatsFailed();
    }
  }

  void _onStatsHealth(bool healthy) {
    if (!healthy) {
      _markStatsFailed();
    }
  }

  void _markStatsFailed() {
    if (statsFailed) {
      return;
    }
    statsFailed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    priceProvider.removeListener(notifyListeners);
    _enforcerRPC.removeListener(notifyListeners);
    unawaited(_statsHealth.cancel());
    unawaited(_statsWatch.dispose());
    super.dispose();
  }
}

class FireplaceStats extends StatelessWidget {
  const FireplaceStats({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<FireplaceViewModel>.reactive(
      viewModelBuilder: () => FireplaceViewModel(),
      builder: (context, model, child) => FireplaceStatsView(
        priceLastUpdated: () => model.priceLastUpdated,
        price: model.price,
        priceTitle: model.priceTitle,
        stats: model.statsFailed ? null : model.stats,
        failed: model.statsFailed,
        loading: model.loading,
      ),
    );
  }
}

class FireplaceStat extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final SailSVGAsset icon;
  final bool bitcoinAmount;
  final bool loading;

  const FireplaceStat({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    this.bitcoinAmount = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final details = LoadingDetails(
      enabled: loading,
      description: 'Waiting for enforcer to boot and wallet to sync..',
    );
    if (SailStyleValues.phoneLayout(context)) {
      return SailStatRow(title: title, subtitle: subtitle, value: value, loading: details);
    }
    return SailCardStats(
      title: title,
      subtitle: subtitle,
      value: value,
      icon: icon,
      loading: details,
    );
  }
}

class TransactionsViewModel extends BaseViewModel {
  final BlockchainProvider blockchainProvider = GetIt.I.get<BlockchainProvider>();
  TransactionsViewModel() {
    blockchainProvider.addListener(notifyListeners);
  }

  @override
  void dispose() {
    blockchainProvider.removeListener(notifyListeners);
    super.dispose();
  }

  List<Block> get recentBlocks => blockchainProvider.blocks;
  List<RecentTransaction> get recentTransactions => blockchainProvider.recentTransactions;

  String? get recentError => _readError('the latest transactions', blockchainProvider.recentError);
  String? get blocksError => _readError('the latest blocks', blockchainProvider.blocksError);

  static String? _readError(String what, String? error) => error == null ? null : 'Could not read $what: $error';
}

class QtSeparator extends StatelessWidget {
  final double width;

  const QtSeparator({
    super.key,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
      ),
      child: Container(
        height: 1.5,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.35, 0.36, 1.0],
            colors: [
              theme.colors.divider,
              theme.colors.divider.withValues(alpha: 0.3),
              theme.colors.background,
              theme.colors.background,
            ],
          ),
        ),
      ),
    );
  }
}

class LatestTransactionTable extends StatefulWidget {
  final List<RecentTransaction> entries;

  const LatestTransactionTable({
    super.key,
    required this.entries,
  });

  @override
  State<LatestTransactionTable> createState() => _LatestTransactionTableState();
}

class _LatestTransactionTableState extends State<LatestTransactionTable> {
  String sortColumn = 'time';
  bool sortAscending = false;

  void onSort(String column) {
    setState(() {
      sortAscending = sortColumn == column ? !sortAscending : true;
      sortColumn = column;
    });
  }

  int compare(RecentTransaction a, RecentTransaction b) {
    final result = switch (sortColumn) {
      'fee' => a.feeSats.compareTo(b.feeSats),
      'txid' => a.txid.compareTo(b.txid),
      'size' => a.virtualSize.compareTo(b.virtualSize),
      'height' => a.confirmedInBlock.compareTo(b.confirmedInBlock),
      _ => a.time.toDateTime().compareTo(b.time.toDateTime()),
    };
    return sortAscending ? result : -result;
  }

  @override
  Widget build(BuildContext context) {
    final entries = [...widget.entries]..sort(compare);
    final phone = SailStyleValues.phoneLayout(context);
    return SailTable(
      getRowId: (index) => entries[index].txid,
      phoneColumns: const [0, 1, 4],
      headerBuilder: (context) => [
        SailTableHeaderCell(
          name: 'Time',
          onSort: () => onSort('time'),
        ),
        SailTableHeaderCell(
          name: 'Fee',
          onSort: () => onSort('fee'),
        ),
        SailTableHeaderCell(
          name: 'TxID',
          onSort: () => onSort('txid'),
        ),
        SailTableHeaderCell(
          name: 'Size',
          onSort: () => onSort('size'),
        ),
        SailTableHeaderCell(
          name: 'Height',
          onSort: () => onSort('height'),
        ),
      ],
      rowBuilder: (context, row, selected) {
        final entry = entries[row];
        return [
          SailTableCell(value: entry.time.toDateTime().toLocal().toString()),
          SailTableCell(value: entry.feeSats.toString(), hugContent: phone),
          SailTableCell(value: entry.txid),
          SailTableCell(value: entry.virtualSize.toString()),
          SailTableCell(
            value: entry.confirmedInBlock == 0 ? '-' : entry.confirmedInBlock.toString(),
            hugContent: phone,
          ),
        ];
      },
      rowCount: entries.length,
      emptyPlaceholder: 'No transactions yet',
      drawGrid: true,
      sortColumnIndex: _transactionColumns.indexOf(sortColumn),
      sortAscending: sortAscending,
      onSort: (columnIndex, ascending) {
        onSort(_transactionColumns[columnIndex]);
      },
    );
  }
}

const _transactionColumns = ['time', 'fee', 'txid', 'size', 'height'];

const _blockColumns = ['time', 'height', 'hash', 'pool'];

class LatestBlocksTable extends StatefulWidget {
  final List<Block> blocks;

  const LatestBlocksTable({
    super.key,
    required this.blocks,
  });

  @override
  State<LatestBlocksTable> createState() => _LatestBlocksTableState();
}

class _LatestBlocksTableState extends State<LatestBlocksTable> {
  String sortColumn = 'time';
  bool sortAscending = false;

  void onSort(String column) {
    setState(() {
      sortAscending = sortColumn == column ? !sortAscending : true;
      sortColumn = column;
    });
  }

  int compare(Block a, Block b) {
    final result = switch (sortColumn) {
      'height' => a.height.compareTo(b.height),
      'hash' => a.hash.compareTo(b.hash),
      'pool' => a.pool.name.compareTo(b.pool.name),
      _ => a.blockTime.toDateTime().compareTo(b.blockTime.toDateTime()),
    };
    return sortAscending ? result : -result;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = [...widget.blocks]..sort(compare);
    return SailTable(
      getRowId: (index) => blocks[index].hash,
      phoneColumns: const [0, 1, 3],
      headerBuilder: (context) => [
        const SailTableHeaderCell(name: 'Time'),
        const SailTableHeaderCell(name: 'Height'),
        const SailTableHeaderCell(name: 'Block Hash'),
        const SailTableHeaderCell(name: 'Pool'),
      ],
      rowBuilder: (context, row, selected) {
        final entry = blocks[row];
        return [
          SailTableCell(value: entry.blockTime.toDateTime().toLocal().format()),
          SailTableCell(value: entry.height.toString()),
          SailTableCell(value: entry.hash),
          SailTableCell(value: entry.hasPool() ? entry.pool.name : ''),
        ];
      },
      rowCount: blocks.length,
      emptyPlaceholder: 'No blocks yet',
      drawGrid: true,
      sortColumnIndex: _blockColumns.indexOf(sortColumn),
      sortAscending: sortAscending,
      onSort: (columnIndex, ascending) {
        onSort(_blockColumns[columnIndex]);
      },
    );
  }
}

Future<void> displayBroadcastNewsDialog(BuildContext context) async {
  await widgetDialog(
    context: context,
    title: 'Broadcast News',
    subtitle: 'Broadcast News to the whole world',
    child: BroadcastNewsView(),
  );
}

Future<void> displayNewsOverviewDialog(BuildContext context, {required CoinNews news}) async {
  await widgetDialog(
    context: context,
    title: news.headline,
    subtitle: '',
    child: NewsOverviewView(news: news),
  );
}

Future<void> displayCreateTopicDialog(BuildContext context) async {
  await widgetDialog(
    context: context,
    title: 'Manage News Subscriptions',
    subtitle: 'View, subscribe to, and create news topics',
    maxWidth: 700,
    child: const ManageNewsSubscriptionsView(),
  );
}

Future<void> displayGraffitiExplorerDialog(BuildContext context) async {
  await showThemedDialog(
    context: context,
    builder: (context) => const SailModal(
      child: SizedBox(
        width: 900,
        height: 700,
        child: GraffitiExplorerView(),
      ),
    ),
  );
}

void _showNewsHelp(BuildContext context) {
  showThemedDialog(
    context: context,
    builder: (context) => SailDialog(
      title: 'News Help',
      actions: [
        SailButton(
          label: 'OK',
          variant: ButtonVariant.ghost,
          onPressed: () async => Navigator.of(context).pop(),
        ),
      ],
      child: SailText.secondary13(
        'With this page you can pay a fee to broadcast news on any topic. '
        'Clicking "Broadcast" will create a transaction with an OP_RETURN '
        'output that encodes the text you have entered.\n\n'
        'The highlighted green portion is your headline (up to 64 bytes). '
        'Press Enter to end the headline early - everything after becomes content.\n\n'
        'Anyone subscribed to the topic will see posts filtered by time and '
        'sorted by fee amount.',
      ),
    ),
  );
}

class BroadcastNewsView extends StatelessWidget {
  const BroadcastNewsView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<BroadcastNewsViewModel>.reactive(
      viewModelBuilder: () => BroadcastNewsViewModel(),
      builder: (context, viewModel, child) {
        return SingleChildScrollView(
          child: SailColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SailStyleValues.padding16,
            mainAxisSize: MainAxisSize.min,
            leadingSpacing: true,
            children: [
              SailDropdownButton<String>(
                items: [
                  ...viewModel.topics.map(
                    (topic) => SailDropdownItem(
                      value: topic.topic,
                      label: topic.confirmed ? topic.name : '${topic.name} (pending)',
                    ),
                  ),
                ],
                onChanged: viewModel.setTopic,
                value: viewModel.topic?.topic,
                hint: 'Select a topic',
              ),
              HeadlineHighlightTextField(
                controller: viewModel.messageController,
                label: 'Message (highlighted = headline)',
                hintText: 'First 64 bytes (or until Enter) is the headline',
                minLines: 9,
              ),
              SailTextField(
                controller: viewModel.urlController,
                hintText: 'Link URL (optional)',
              ),
              SailRow(
                spacing: SailStyleValues.padding16,
                children: [
                  SailDropdownButton<int>(
                    items: [
                      for (final kind in storyKinds.entries) SailDropdownItem(value: kind.key, label: kind.value),
                    ],
                    value: viewModel.subtype,
                    onChanged: viewModel.setSubtype,
                  ),
                  SailCheckbox(
                    value: viewModel.nsfw,
                    onChanged: viewModel.setNsfw,
                    label: 'NSFW',
                  ),
                ],
              ),
              SailColumn(
                spacing: SailStyleValues.padding08,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SailTextField(
                    controller: viewModel.feeController,
                    hintText: 'Fee (optional)',
                    suffixWidget: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SailText.secondary12(viewModel.feeUnit.symbol),
                    ),
                  ),
                  if (viewModel.feeEstimatePending)
                    SailText.secondary12('Checking the fee…')
                  else if (viewModel.feeEstimate case final estimate?)
                    SailText.secondary12('Network fee: ${formatFee(estimate)}')
                  else if (viewModel.feeEstimateError case final error?)
                    SailText.secondary12(error, color: context.sailTheme.colors.error),
                ],
              ),
              if (viewModel.broadcastError != null) SailInlineError(viewModel.broadcastError!),
              SailRow(
                spacing: SailStyleValues.padding08,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                children: [
                  SailButton(
                    label: 'Help',
                    variant: ButtonVariant.ghost,
                    icon: SailSVGAsset.iconQuestion,
                    onPressed: () async => _showNewsHelp(context),
                  ),
                  SailButton(
                    label: 'Broadcast',
                    onPressed: () async => viewModel.broadcastNews(context),
                    disabled: viewModel.headline.isEmpty || viewModel.topic == null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class LastUsedTopicSetting extends SettingValue<String> {
  @override
  String get key => 'last_used_broadcast_topic';

  LastUsedTopicSetting({super.newValue});

  @override
  String defaultValue() => '';

  @override
  String? fromJson(String jsonString) {
    return jsonString;
  }

  @override
  String toJson() {
    return value;
  }

  @override
  SettingValue<String> withValue([String? value]) {
    return LastUsedTopicSetting(newValue: value);
  }
}

class BroadcastNewsViewModel extends BaseViewModel {
  final NewsProvider _newsProvider = GetIt.I.get<NewsProvider>();
  final BitwindowRPC _api = GetIt.I.get<BitwindowRPC>();
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();

  // Single unified controller for headline + content
  final HeadlineHighlightController messageController = HeadlineHighlightController();
  final TextEditingController feeController = TextEditingController();
  final TextEditingController urlController = TextEditingController();

  // Story subtype (spec §10): 0=link, 1=text, 2=ask, 3=show, 4=poll, 5=job.
  int subtype = 0;
  bool nsfw = false;

  void setSubtype(int? value) {
    if (value == null) {
      return;
    }
    subtype = value;
    _onInputChanged();
  }

  void setNsfw(bool value) {
    nsfw = value;
    _onInputChanged();
  }

  /// The fee that the wallet pays for the story when the fee field is empty.
  NewsFeeEstimate? feeEstimate;

  /// Why the wallet gave no fee for the story.
  String? feeEstimateError;

  /// True from an input until the wallet gives the fee of the changed story.
  bool feeEstimatePending = false;

  Timer? _estimateTimer;
  int _estimates = 0;

  /// Prices the story a short time after the last input.
  void _estimateFeeLater() {
    _estimateTimer?.cancel();
    final read = ++_estimates;
    feeEstimate = null;
    feeEstimateError = null;
    feeEstimatePending = headline.trim().isNotEmpty && feeController.text.trim().isEmpty;
    if (!feeEstimatePending) {
      return;
    }
    _estimateTimer = Timer(const Duration(milliseconds: 400), () => _estimateFee(read));
  }

  Future<void> _estimateFee(int read) async {
    NewsFeeEstimate? estimate;
    String? error;
    try {
      estimate = await _api.misc.estimateNewsFee(
        NewsAction.NEWS_ACTION_STORY,
        headline: headline,
        body: content,
        url: urlController.text.trim(),
        subtype: subtype,
        nsfw: nsfw,
      );
    } catch (e) {
      final reason = e is BitwindowException ? e.message : e.toString();
      error = reason.isEmpty ? reason : '${reason[0].toUpperCase()}${reason.substring(1)}';
    }
    if (disposed || read != _estimates) {
      return;
    }
    feeEstimate = estimate;
    feeEstimateError = error;
    feeEstimatePending = false;
    notifyListeners();
  }

  BitcoinUnit get feeUnit => GetIt.I.get<SettingsProvider>().bitcoinUnit;

  String? _topicId;

  /// The selected topic, looked up by ID so a new read of the topics keeps it.
  Topic? get topic => topics.firstWhereOrNull((t) => t.topic == _topicId);

  List<Topic> get topics => _newsProvider.topics;

  String get headline => messageController.text.substring(0, headlineEndIndex(messageController.text));

  /// The text after the headline, without the newline that ends the headline.
  String get content {
    final text = messageController.text;
    final end = headlineEndIndex(text);
    return text.startsWith('\n', end) ? text.substring(end + 1) : text.substring(end);
  }

  String? broadcastError;

  BroadcastNewsViewModel() {
    _newsProvider.addListener(notifyListeners);
    _loadLastUsedTopic();
    messageController.addListener(_onInputChanged);
    feeController.addListener(_onInputChanged);
    urlController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    broadcastError = null;
    _estimateFeeLater();
    notifyListeners();
  }

  Future<void> _loadLastUsedTopic() async {
    final setting = LastUsedTopicSetting();
    final lastUsedTopicId = (await _settings.getValue(setting)).value;

    _topicId = topics.any((t) => t.topic == lastUsedTopicId) ? lastUsedTopicId : topics.firstOrNull?.topic;

    // Defer notifyListeners to avoid mouse tracker assertion during dialog initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  void setTopic(String? topicId) async {
    if (topicId == null) {
      return;
    }

    _topicId = topicId;
    broadcastError = null;
    await _settings.setValue(LastUsedTopicSetting(newValue: topicId));

    // Defer notifyListeners to avoid mouse tracker assertion during dropdown interaction
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  Future<void> broadcastNews(BuildContext context) async {
    final topicId = topic?.topic;
    if (headline.isEmpty || topicId == null) {
      return;
    }

    broadcastError = null;
    notifyListeners();
    try {
      // Parse fee in user's preferred unit and convert to sats
      final unit = feeUnit;
      final feeSats = feeController.text.isNotEmpty ? parseAmountToSatoshis(feeController.text, unit) : null;
      if (feeSats != null && feeSats <= 0) {
        broadcastError = unit == BitcoinUnit.btc
            ? 'Enter a fee greater than zero. Use up to 8 decimal places.'
            : 'Enter a fee greater than zero.';
        notifyListeners();
        return;
      }

      final link = urlController.text.trim();
      if (link.isNotEmpty && webLink(link) == null) {
        broadcastError = 'Enter a link that starts with http:// or https://.';
        notifyListeners();
        return;
      }

      await _api.misc.broadcastNews(
        topicId,
        headline,
        content,
        url: link.isEmpty ? null : link,
        subtype: subtype,
        nsfw: nsfw,
        feeSats: feeSats,
      );

      unawaited(_newsProvider.fetch());

      GetIt.I.get<NotificationProvider>().add(
        title: 'News broadcast',
        content: headline,
        dialogType: DialogType.success,
      );
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      broadcastError = 'Could not broadcast news: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _estimateTimer?.cancel();
    _newsProvider.removeListener(notifyListeners);
    messageController.removeListener(_onInputChanged);
    messageController.dispose();
    feeController.removeListener(_onInputChanged);
    feeController.dispose();
    urlController.removeListener(_onInputChanged);
    urlController.dispose();
    super.dispose();
  }
}

class NewsOverviewView extends StatelessWidget {
  final CoinNews news;

  const NewsOverviewView({
    super.key,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    return SailText.primary12(news.content);
  }
}

class ManageNewsSubscriptionsView extends StatelessWidget {
  const ManageNewsSubscriptionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ManageNewsSubscriptionsViewModel>.reactive(
      viewModelBuilder: () => ManageNewsSubscriptionsViewModel(),
      builder: (context, viewModel, child) {
        return SizedBox(
          height: 400,
          child: InlineTabBar(
            secondary: true,
            tabs: [
              SingleTabItem(
                label: 'Your Topics',
                child: _YourTopicsTab(viewModel: viewModel),
              ),
              SingleTabItem(
                label: 'Subscribe',
                child: _SubscribeTab(viewModel: viewModel),
              ),
              SingleTabItem(
                label: 'Create Topic',
                child: _CreateTopicTab(viewModel: viewModel),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _YourTopicsTab extends StatelessWidget {
  final ManageNewsSubscriptionsViewModel viewModel;

  const _YourTopicsTab({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding16,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewModel.topicReadError case final error?) SailInlineError(error),
        Expanded(
          child: SailTable(
            getRowId: (index) => viewModel.topics[index].topic,
            headerBuilder: (context) => [
              const SailTableHeaderCell(name: 'Name'),
              const SailTableHeaderCell(name: 'Identifier'),
              const SailTableHeaderCell(name: 'Status'),
            ],
            rowBuilder: (context, row, selected) {
              final topic = viewModel.topics[row];
              return [
                SailTableCell(value: topic.name),
                SailTableCell(value: topic.topic, monospace: true),
                SailTableCell(
                  value: topic.confirmed ? 'Confirmed' : 'Pending',
                  textColor: topic.confirmed ? context.sailTheme.colors.success : context.sailTheme.colors.orange,
                ),
              ];
            },
            rowCount: viewModel.topics.length,
            emptyPlaceholder: 'No topics subscribed',
            drawGrid: true,
            onDoubleTap: (rowId) {
              final topic = viewModel.topics.firstWhere((t) => t.topic == rowId);
              if (topic.txid.isNotEmpty) {
                showTransactionDetails(context, topic.txid);
              }
            },
          ),
        ),
        SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            SailButton(
              label: 'Export',
              variant: ButtonVariant.outline,
              onPressed: () async => viewModel.exportTopics(context),
            ),
            SailButton(
              label: 'Import',
              variant: ButtonVariant.outline,
              onPressed: () async => viewModel.importTopics(context),
            ),
            const Spacer(),
            SailButton(
              label: 'Restore Defaults',
              variant: ButtonVariant.secondary,
              onPressed: () async => viewModel.restoreDefaults(context),
            ),
          ],
        ),
        if (viewModel.importError != null) SailInlineError(viewModel.importError!),
      ],
    );
  }
}

class _SubscribeTab extends StatelessWidget {
  final ManageNewsSubscriptionsViewModel viewModel;

  const _SubscribeTab({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding16,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SailText.secondary13('Add news topic by URL:'),
        SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            Expanded(
              child: SailTextField(
                controller: viewModel.urlController,
                hintText: SailStyleValues.phoneLayout(context)
                    ? 'e.g. 7{a1a1a1a1}US Weekly'
                    : 'Enter URL e.g. 7{a1a1a1a1}US Weekly',
              ),
            ),
            SailButton(
              label: 'Paste',
              variant: ButtonVariant.secondary,
              onPressed: () async => viewModel.pasteUrl(),
            ),
            SailButton(
              label: 'Add',
              onPressed: viewModel.urlController.text.isNotEmpty ? () async => viewModel.addFromUrl(context) : null,
            ),
          ],
        ),
        if (viewModel.subscribeError != null) SailInlineError(viewModel.subscribeError!),
        const SailSpacing(SailStyleValues.padding16),
        SailText.secondary12(
          'URL format: {days}{identifier}Name\n'
          'Example: 7{a1a1a1a1}US Weekly means a topic named "US Weekly" with identifier a1a1a1a1 and 7 day retention',
          color: context.sailTheme.colors.textTertiary,
        ),
      ],
    );
  }
}

class _CreateTopicTab extends StatelessWidget {
  final ManageNewsSubscriptionsViewModel viewModel;

  const _CreateTopicTab({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final pendingTopics = viewModel.topics.where((t) => !t.confirmed).toList();
    final phone = SailStyleValues.phoneLayout(context);

    return SingleChildScrollView(
      child: SailColumn(
        spacing: SailStyleValues.padding16,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SailTextField(
            label: 'Title',
            controller: viewModel.nameController,
            hintText: 'Enter title (e.g. "US Weekly")',
          ),
          SailTextField(
            label: 'Header Bytes (8 hex chars to identify this news type)',
            controller: viewModel.identifierController,
            hintText: 'Enter header bytes e.g. A1A1A1A1',
          ),
          SailTextField(
            label: 'Retention Days (0 = infinite, max 255)',
            controller: viewModel.retentionDaysController,
            hintText: '7',
          ),
          SailButton(
            label: 'Create Topic',
            onPressed: viewModel.canCreate ? () async => viewModel.createTopic(context) : null,
          ),
          if (viewModel.createTopicError != null) SailInlineError(viewModel.createTopicError!),
          if (pendingTopics.isNotEmpty) ...[
            const SailSpacing(SailStyleValues.padding08),
            SailText.secondary13('Pending Topics (awaiting confirmation)'),
            ...pendingTopics.map(
              (topic) => SailTappable(
                onTap: phone ? () async => showTransactionDetails(context, topic.txid) : null,
                onDoubleTap: phone ? null : () async => showTransactionDetails(context, topic.txid),
                borderRadius: context.sailTheme.chrome.radius,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: context.sailTheme.colors.backgroundSecondary,
                    borderRadius: context.sailTheme.chrome.radius,
                  ),
                  child: SailRow(
                    spacing: SailStyleValues.padding08,
                    children: [
                      SailText.primary13(topic.name),
                      SailText.secondary12('(${topic.topic})'),
                      const Spacer(),
                      if (phone)
                        SailText.secondary12('Tap to view tx', maxLines: 1)
                      else
                        SailText.secondary12(
                          'double-click to view tx',
                          italic: true,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ManageNewsSubscriptionsViewModel extends BaseViewModel {
  final NewsProvider _newsProvider = GetIt.I.get<NewsProvider>();
  final BitwindowRPC _api = GetIt.I.get<BitwindowRPC>();

  List<Topic> get topics => _newsProvider.topics;
  String? get topicReadError => _newsProvider.topicReadError;

  final TextEditingController identifierController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController urlController = TextEditingController();
  final TextEditingController retentionDaysController = TextEditingController(text: '7');

  bool get canCreate =>
      identifierController.text.isNotEmpty && nameController.text.isNotEmpty && identifierController.text.length == 8;

  String? createTopicError;
  String? subscribeError;
  String? importError;

  ManageNewsSubscriptionsViewModel() {
    _newsProvider.addListener(notifyListeners);
    identifierController.addListener(_onTopicInputChanged);
    nameController.addListener(_onTopicInputChanged);
    urlController.addListener(_onUrlChanged);
    retentionDaysController.addListener(_onTopicInputChanged);
  }

  void _onTopicInputChanged() {
    createTopicError = null;
    notifyListeners();
  }

  void _onUrlChanged() {
    subscribeError = null;
    notifyListeners();
  }

  void _setCreateTopicError(String error) {
    createTopicError = error;
    notifyListeners();
  }

  Future<void> createTopic(BuildContext context) async {
    if (identifierController.text.isEmpty || nameController.text.isEmpty) {
      return;
    }
    if (identifierController.text.length != 8) {
      _setCreateTopicError('Identifier must be exactly 8 hex characters');
      return;
    }
    final hexRegex = RegExp(r'^[0-9A-Fa-f]+$');
    if (!hexRegex.hasMatch(identifierController.text)) {
      _setCreateTopicError('Identifier must contain only valid hex characters (0-9, A-F)');
      return;
    }
    if (nameController.text.length > 20) {
      _setCreateTopicError('Name must be 20 characters or less');
      return;
    }
    final retentionText = retentionDaysController.text.trim();
    final retentionDays = retentionText.isEmpty ? 7 : int.tryParse(retentionText);
    if (retentionDays == null || retentionDays < 0 || retentionDays > 255) {
      _setCreateTopicError('Retention days must be between 0 and 255 (0 = infinite)');
      return;
    }

    createTopicError = null;
    notifyListeners();
    try {
      final response = await _api.misc.createTopic(
        identifierController.text,
        nameController.text,
        retentionDays: retentionDays,
      );
      await _newsProvider.fetch();
      if (!context.mounted) {
        return;
      }
      showSailToast(context, 'Topic created! txid: ${response.txid.substring(0, 8)}...');
      identifierController.clear();
      nameController.clear();
      retentionDaysController.text = '7';
    } catch (e) {
      _setCreateTopicError('Could not create topic: $e');
    }
  }

  Future<void> pasteUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      urlController.text = data!.text!;
    }
  }

  Future<void> addFromUrl(BuildContext context) async {
    final url = urlController.text.trim();
    if (url.isEmpty) {
      return;
    }

    // Parse URL format: {days}{identifier}Name
    // Example: 7{a1a1a1a1}US Weekly
    final regex = RegExp(r'^(\d+)\{([a-fA-F0-9]{8})\}(.+)$');
    final match = regex.firstMatch(url);
    final days = int.tryParse(match?.group(1) ?? '');

    if (match == null || days == null) {
      subscribeError = 'Invalid URL format. Expected: {days}{identifier}Name';
      notifyListeners();
      return;
    }

    final identifier = match.group(2)!;
    final name = match.group(3)!;

    try {
      final response = await _api.misc.createTopic(identifier, name, retentionDays: days);
      await _newsProvider.fetch();
      if (!context.mounted) {
        return;
      }
      showSailToast(context, 'Subscribed to "$name"! txid: ${response.txid.substring(0, 8)}...');
      urlController.clear();
    } catch (e) {
      subscribeError = 'Could not subscribe: $e';
      notifyListeners();
    }
  }

  Future<void> exportTopics(BuildContext context) async {
    final urls = topics.map((t) => '${t.retentionDays}{${t.topic}}${t.name}').join('\n');
    await Clipboard.setData(ClipboardData(text: urls));
    if (!context.mounted) {
      return;
    }
    showSailToast(context, 'Topics exported to clipboard');
  }

  Future<void> importTopics(BuildContext context) async {
    importError = null;
    notifyListeners();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      importError = 'Clipboard is empty';
      notifyListeners();
      return;
    }

    final lines = data.text!.split('\n').where((l) => l.trim().isNotEmpty).toList();
    var imported = 0;
    var failed = 0;
    String? firstError;

    for (final line in lines) {
      final regex = RegExp(r'^(\d+)\{([a-fA-F0-9]{8})\}(.+)$');
      final match = regex.firstMatch(line.trim());
      final days = int.tryParse(match?.group(1) ?? '');

      if (match != null && days != null) {
        final identifier = match.group(2)!;
        final name = match.group(3)!;

        // Check if already subscribed
        if (topics.any((t) => t.topic == identifier)) {
          continue;
        }

        try {
          await _api.misc.createTopic(identifier, name, retentionDays: days);
          imported++;
        } catch (e) {
          failed++;
          firstError ??= e.toString();
        }
      } else {
        failed++;
        firstError ??= '"${line.trim()}" is not in the format {days}{identifier}Name';
      }
    }

    await _newsProvider.fetch();
    if (!context.mounted) {
      return;
    }

    if (failed > 0) {
      importError = 'Failed to import $failed topic(s): $firstError';
      notifyListeners();
    }
    if (imported > 0) {
      showSailToast(context, 'Imported $imported topic(s)');
    } else if (failed == 0) {
      showSailToast(context, 'No new topics to import');
    }
  }

  Future<void> restoreDefaults(BuildContext context) async {
    // Default topics from mainchain-deprecated
    // Format: (identifier, name, retentionDays)
    const defaults = [
      ('a1a1a1a1', 'US Weekly', 7),
      ('a2a2a2a2', 'Japan Weekly', 7),
    ];

    var restored = 0;
    for (final (identifier, name, days) in defaults) {
      if (!topics.any((t) => t.topic == identifier)) {
        try {
          await _api.misc.createTopic(identifier, name, retentionDays: days);
          restored++;
        } catch (e) {
          // Ignore errors for defaults
        }
      }
    }

    await _newsProvider.fetch();
    if (!context.mounted) {
      return;
    }

    if (restored > 0) {
      showSailToast(context, 'Restored $restored default topic(s)');
    } else {
      showSailToast(context, 'All default topics already exist');
    }
  }

  @override
  void dispose() {
    _newsProvider.removeListener(notifyListeners);
    identifierController.removeListener(_onTopicInputChanged);
    identifierController.dispose();
    nameController.removeListener(_onTopicInputChanged);
    nameController.dispose();
    retentionDaysController.removeListener(_onTopicInputChanged);
    retentionDaysController.dispose();
    urlController.removeListener(_onUrlChanged);
    urlController.dispose();
    super.dispose();
  }
}

class NewGraffitiView extends StatelessWidget {
  const NewGraffitiView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<NewGraffitiViewModel>.reactive(
      viewModelBuilder: () => NewGraffitiViewModel(),
      builder: (context, viewModel, child) {
        return SailColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          leadingSpacing: true,
          children: [
            SailTextField(
              label: 'Message',
              controller: viewModel.messageController,
              onChanged: viewModel._onMessageEdited,
              hintText: 'Enter a message',
              size: TextFieldSize.small,
              minLines: 1,
              maxLines: 4,
            ),
            SailButton(
              label: 'Broadcast',
              onPressed: () => viewModel.createGraffiti(context),
              disabled: viewModel.messageController.text.isEmpty,
            ),
            if (viewModel.graffitiResult case final link?)
              Semantics(
                liveRegion: true,
                child: Wrap(
                  spacing: SailStyleValues.padding08,
                  runSpacing: SailStyleValues.padding04,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SailRow(
                      spacing: SailStyleValues.padding08,
                      children: [
                        SailSVG.fromAsset(SailSVGAsset.iconInfo, width: 16, color: context.sailTheme.colors.success),
                        SailText.primary13(NewGraffitiViewModel._broadcastTitle),
                      ],
                    ),
                    NotificationLinkText(link: link),
                  ],
                ),
              ),
            if (viewModel.graffitiError != null) SailInlineError(viewModel.graffitiError!),
          ],
        );
      },
    );
  }
}

class NewGraffitiViewModel extends BaseViewModel {
  static const _broadcastTitle = 'Graffiti broadcast';
  final TextEditingController messageController = TextEditingController();
  final OrchestratorWalletRPC _orchestratorWallet = GetIt.I<OrchestratorRPC>().wallet;
  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();

  int _draftRevision = 0;

  String? graffitiError;
  NotificationLink? graffitiResult;

  NewGraffitiViewModel() {
    messageController.addListener(_onMessageChanged);
  }

  void _onMessageChanged() {
    graffitiError = null;
    notifyListeners();
  }

  void _onMessageEdited(String _) {
    _draftRevision++;
  }

  Future<void> createGraffiti(BuildContext context) async {
    final message = messageController.text;
    final draftRevision = _draftRevision;
    if (message.isEmpty) {
      return;
    }

    graffitiError = null;
    graffitiResult = null;
    notifyListeners();
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }

      final address = (await _orchestratorWallet.getNewAddress(walletId)).address;
      final txid = (await _orchestratorWallet.sendTransaction(
        walletId: walletId,
        destinations: {address: 10000}, // 0.0001 BTC
        opReturnMessage: message,
        feeRateSatPerVbyte: 1,
      )).txid;

      final network = GetIt.I.get<BitcoinConfProvider>().network;
      final link = NotificationLink(text: 'View transaction', url: mempoolTxUrl(txid, network));
      graffitiResult = link;
      notifyListeners();
      GetIt.I.get<NotificationProvider>().add(
        title: _broadcastTitle,
        content: txid,
        dialogType: DialogType.success,
        links: [link],
      );

      if (!context.mounted || _draftRevision != draftRevision) {
        return;
      }
      messageController.clear();
    } catch (e) {
      graffitiError = 'Could not broadcast graffiti: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    messageController.removeListener(_onMessageChanged);
    messageController.dispose();
    super.dispose();
  }
}

class GraffitiExplorerView extends StatelessWidget {
  const GraffitiExplorerView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<GraffitiExplorerViewModel>.reactive(
      viewModelBuilder: () => GraffitiExplorerViewModel(),
      builder: (context, viewModel, child) {
        final hasFilters =
            viewModel.fromDate != null || viewModel.toDate != null || viewModel.searchController.text.isNotEmpty;
        final phone = SailStyleValues.phoneLayout(context);

        return SailCard(
          title: 'Graffiti Explorer',
          subtitle: 'Browse blockchain graffiti and OP_RETURN data',
          error: viewModel.readError,
          widgetHeaderEnd: SailButton(
            label: 'New Graffiti',
            onPressed: () => newGraffitiDialog(context),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate available height for the table (total height minus filter row and spacing)
              final filterHeight = SailStyleValues.phoneLayout(context) ? 124 : 60;
              final tableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight - filterHeight : 500.0;

              final search = SailTextField(
                hintText: 'Search by message or txid...',
                controller: viewModel.searchController,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: SailSVG.fromAsset(SailSVGAsset.search, color: context.sailTheme.colors.textTertiary),
                ),
                prefixIconConstraints: const BoxConstraints(maxHeight: 20, maxWidth: 40),
              );
              final fromField = _DatePickerField(
                label: 'From',
                value: viewModel.fromDate,
                onChanged: viewModel.setFromDate,
                lastDate: viewModel.toDate ?? DateTime.now(),
                compact: phone,
              );
              final toField = _DatePickerField(
                label: 'To',
                value: viewModel.toDate,
                onChanged: viewModel.setToDate,
                firstDate: viewModel.fromDate,
                lastDate: DateTime.now(),
                compact: phone,
              );
              final clear = hasFilters
                  ? SailButton(
                      label: 'Clear',
                      variant: ButtonVariant.secondary,
                      onPressed: () async => viewModel.clearFilters(),
                    )
                  : null;

              return SailColumn(
                spacing: SailStyleValues.padding16,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (phone) ...[
                    search,
                    Wrap(
                      spacing: SailStyleValues.padding08,
                      runSpacing: SailStyleValues.padding08,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [fromField, toField, ?clear],
                    ),
                  ] else
                    SailRow(
                      spacing: SailStyleValues.padding16,
                      children: [
                        Expanded(flex: 2, child: search),
                        Expanded(child: fromField),
                        Expanded(child: toField),
                        ?clear,
                      ],
                    ),
                  SizedBox(
                    height: tableHeight,
                    child: GraffitiTable(
                      entries: viewModel.entries,
                      sortColumn: viewModel.sortColumn,
                      sortAscending: viewModel.sortAscending,
                      onSort: viewModel.onSort,
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

  Future<void> newGraffitiDialog(BuildContext context) async {
    await widgetDialog(
      context: context,
      title: 'New Graffiti',
      subtitle: 'Write whatever you want and broadcast it to the blockchain',
      child: const NewGraffitiView(),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// True takes the width of the date, with the icon first.
  final bool compact;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final date = value;
    final text = date == null ? label : cachedDateFormat('yyyy-MM-dd', Intl.getCurrentLocale()).format(date);

    return SailTappable(
      onTap: () async {
        final picked = await showSailDatePicker(
          context: context,
          initialDate: value ?? lastDate ?? DateTime.now(),
          firstDate: firstDate ?? DateTime(2009),
          lastDate: lastDate ?? DateTime.now(),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      borderRadius: context.sailTheme.chrome.radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colors.backgroundSecondary,
          borderRadius: context.sailTheme.chrome.radius,
          border: Border.all(color: theme.colors.border),
        ),
        child: compact
            ? SailRow(
                spacing: SailStyleValues.padding08,
                children: [
                  SailSVG.fromAsset(SailSVGAsset.calendar, color: theme.colors.textTertiary, width: 12),
                  SailText.secondary12(
                    text,
                    color: value != null ? theme.colors.text : theme.colors.textTertiary,
                  ),
                ],
              )
            : SailRow(
                spacing: SailStyleValues.padding08,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SailText.secondary12(
                    text,
                    color: value != null ? theme.colors.text : theme.colors.textTertiary,
                  ),
                  SailSVG.fromAsset(
                    SailSVGAsset.calendar,
                    color: theme.colors.textTertiary,
                  ),
                ],
              ),
      ),
    );
  }
}

class GraffitiExplorerViewModel extends BaseViewModel {
  static const searchDelay = Duration(milliseconds: 300);

  static const _sorts = {
    'time': OPReturnSort.OP_RETURN_SORT_TIME,
    'height': OPReturnSort.OP_RETURN_SORT_HEIGHT,
    'fee': OPReturnSort.OP_RETURN_SORT_FEE,
    'txid': OPReturnSort.OP_RETURN_SORT_TXID,
    'message': OPReturnSort.OP_RETURN_SORT_MESSAGE,
  };

  BitwindowRPC get _api => GetIt.I.get<BitwindowRPC>();
  final BlockchainProvider _blockchain = GetIt.I.get<BlockchainProvider>();
  final SyncProvider _sync = GetIt.I.get<SyncProvider>();
  final SyncedTipWatch _tip = SyncedTipWatch();
  final TextEditingController searchController = TextEditingController();

  String _sortColumn = 'time';
  bool _sortAscending = false;
  DateTime? _fromDate;
  DateTime? _toDate;

  String _search = '';
  Timer? _searchTimer;
  int _reads = 0;
  String? _pendingOpReturnState;

  /// The rows of the last read that worked, in the server order.
  List<OPReturn> entries = [];

  /// The error of the last read, or null when it worked.
  String? readError;

  String get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  DateTime? get fromDate => _fromDate;
  DateTime? get toDate => _toDate;

  GraffitiExplorerViewModel() {
    _blockchain.addListener(read);
    _blockchain.recentChanged.addListener(read);
    _sync.addListener(_onSyncChanged);
    searchController.addListener(_onSearchChanged);
    read();
  }

  void _onSyncChanged() {
    final info = _sync.bitwindowdSyncInfo;
    final previous = _pendingOpReturnState;
    _pendingOpReturnState = info?.pendingOpReturnState;
    if (_tip.moved(_sync, synced: info != null) || _pendingOpReturnState != previous) {
      read();
    }
  }

  ListOPReturnRequest get request => ListOPReturnRequest(
    search: _search,
    from: _fromDate == null ? null : Timestamp.fromDateTime(_dayStart(_fromDate!)),
    to: _toDate == null ? null : Timestamp.fromDateTime(_dayStart(_toDate!, plusDays: 1)),
    sort: _sorts[_sortColumn],
    ascending: _sortAscending,
  );

  static DateTime _dayStart(DateTime date, {int plusDays = 0}) => DateTime(date.year, date.month, date.day + plusDays);

  /// Reads the rows for the current filter. Only the newest read changes the rows.
  Future<void> read() async {
    final id = ++_reads;
    try {
      final rows = await _api.misc.listOPReturns(request);
      if (id != _reads) {
        return;
      }
      entries = rows;
      readError = null;
    } catch (e) {
      if (id != _reads) {
        return;
      }
      readError = e.toString();
    }
    notifyListeners();
  }

  void _onSearchChanged() {
    final search = searchController.text.trim();
    if (search == _search) {
      return;
    }
    _search = search;
    _searchTimer?.cancel();
    _searchTimer = Timer(searchDelay, read);
    notifyListeners();
  }

  void setFromDate(DateTime? date) {
    _fromDate = date;
    read();
    notifyListeners();
  }

  void setToDate(DateTime? date) {
    _toDate = date;
    read();
    notifyListeners();
  }

  void clearFilters() {
    _fromDate = null;
    _toDate = null;
    _search = '';
    _searchTimer?.cancel();
    searchController.clear();
    read();
    notifyListeners();
  }

  void onSort(String column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = column != 'time';
    }
    read();
    notifyListeners();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _blockchain.removeListener(read);
    _blockchain.recentChanged.removeListener(read);
    _sync.removeListener(_onSyncChanged);
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }
}

class GraffitiTable extends StatelessWidget {
  static const columns = ['time', 'height', 'fee', 'txid', 'message'];

  final List<OPReturn> entries;
  final String sortColumn;
  final bool sortAscending;
  final void Function(String column) onSort;

  const GraffitiTable({
    super.key,
    required this.entries,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  static const _phoneTimeWidth = 136.0;
  static const _phoneHeightWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I<FormatterProvider>();
    final phone = SailStyleValues.phoneLayout(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final phoneMessageWidth = max(
          defaultMinColumnWidth,
          constraints.maxWidth - _phoneTimeWidth - _phoneHeightWidth,
        );
        return ListenableBuilder(
          listenable: formatter,
          builder: (context, child) => SailTable(
            backgroundColor: theme.colors.backgroundSecondary,
            getRowId: (index) => entries[index].id.toString(),
            phoneColumns: const [0, 1, 4],
            headerBuilder: (context) => const [
              SailTableHeaderCell(name: 'Time'),
              SailTableHeaderCell(name: 'Height'),
              SailTableHeaderCell(name: 'Fee'),
              SailTableHeaderCell(name: 'TXID'),
              SailTableHeaderCell(name: 'Message'),
            ],
            rowBuilder: (context, row, selected) {
              final entry = entries[row];
              return [
                SailTableCell(
                  value: phone
                      ? cachedDateFormat(
                          'yyyy-MM-dd HH:mm',
                          Intl.getCurrentLocale(),
                        ).format(entry.createTime.toDateTime().toLocal())
                      : entry.createTime.toDateTime().toLocal().format(),
                  width: phone ? _phoneTimeWidth : null,
                ),
                SailTableCell(
                  value: entry.height == 0 ? '-' : entry.height.toString(),
                  width: phone ? _phoneHeightWidth : null,
                ),
                SailTableCell(value: entry.feeSats == 0 ? '-' : formatter.formatSats(entry.feeSats.toInt())),
                SailTableCell(value: shortenId(entry.txid), copyValue: entry.txid, monospace: true),
                SailTableCell(
                  value: entry.message,
                  width: phone ? phoneMessageWidth : null,
                  child: phone ? SailText.primary13(entry.message) : null,
                ),
              ];
            },
            rowCount: entries.length,
            emptyPlaceholder: 'No graffiti found',
            sortColumnIndex: columns.indexOf(sortColumn),
            sortAscending: sortAscending,
            onSort: (columnIndex, ascending) => onSort(columns[columnIndex]),
          ),
        );
      },
    );
  }
}

class FireplaceStatsView extends StatelessWidget {
  /// Read each second, so only the price card rebuilds for the age.
  final String Function() priceLastUpdated;
  final String price;
  final String priceTitle;

  /// Null before the first good read and after a failed read, so the tiles show "-".
  final GetFireplaceStatsResponse? stats;

  /// The last read failed.
  final bool failed;
  final bool loading;

  const FireplaceStatsView({
    super.key,
    required this.priceLastUpdated,
    required this.price,
    required this.priceTitle,
    required this.stats,
    this.failed = false,
    required this.loading,
  });

  String _value(Int64 Function(GetFireplaceStatsResponse s) read) {
    final current = stats;
    return current == null ? '-' : read(current).toString();
  }

  String _subtitle(String period) => failed ? 'Could not read the stats' : period;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = min(4, (constraints.maxWidth / 301).ceil());
        double gridSpacing = SailStyleValues.padding16;
        double totalSpacing = gridSpacing * (crossAxisCount - 1);
        double cardWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;
        double desiredCardHeight = 128; // Set your ideal card height here

        double childAspectRatio = cardWidth / desiredCardHeight;

        List<Widget> cardList = [
          _EachSecond(
            builder: (context) => FireplaceStat(
              title: priceTitle,
              subtitle: 'Last updated ${priceLastUpdated()}',
              value: price,
              bitcoinAmount: true,
              icon: SailSVGAsset.dollarSign,
              loading: loading,
            ),
          ),
          FireplaceStat(
            title: 'New transactions',
            value: _value((s) => s.transactionCount24h),
            subtitle: _subtitle('Last 24 hours'),
            icon: SailSVGAsset.iconTransactions,
            loading: loading,
          ),
          FireplaceStat(
            title: 'New coinnews',
            value: _value((s) => s.coinnewsCount7d),
            subtitle: _subtitle('Last 7 days'),
            icon: SailSVGAsset.newspaper,
            loading: loading,
          ),
          FireplaceStat(
            title: 'Number of blocks',
            value: _value((s) => s.blockCount24h),
            subtitle: _subtitle('Last 24 hours'),
            icon: SailSVGAsset.blocks,
            loading: loading,
          ),
        ];

        if (SailStyleValues.phoneLayout(context)) {
          return SailStatList(children: cardList);
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          childAspectRatio: childAspectRatio,
          children: cardList,
        );
      },
    );
  }
}

class _EachSecond extends StatefulWidget {
  final WidgetBuilder builder;

  const _EachSecond({required this.builder});

  @override
  State<_EachSecond> createState() => _EachSecondState();
}

class _EachSecondState extends State<_EachSecond> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!Environment.isInTest) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
