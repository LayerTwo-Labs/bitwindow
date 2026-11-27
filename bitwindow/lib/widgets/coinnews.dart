import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bitwindow/env.dart';
import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/utils/explorer_url.dart';
import 'package:bitwindow/utils/web_link.dart';
import 'package:bitwindow/widgets/news_cost.dart';
import 'package:bitwindow/widgets/pagination.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

/// The kinds of a story, by the number that the chain holds.
const storyKinds = {0: 'Link', 1: 'Text', 2: 'Ask', 3: 'Show', 4: 'Poll', 5: 'Job'};

/// The topic, the kind, the NSFW mark and the date of a story, in one line.
/// A link is the kind of a story with no choice, so it has no name here.
String storyMeta(CoinNews news, {required String? topicName, required String date, String separator = ' · '}) {
  final kind = news.subtype == 0 ? null : storyKinds[news.subtype];
  return [
    ?topicName,
    ?kind,
    if (news.nsfw) 'NSFW',
    date,
  ].join(separator);
}

/// The time of a story by [format], or "Pending" for a story in the mempool.
String storyTime(CoinNews news, String Function(DateTime time) format) =>
    news.pending ? 'Pending' : format(news.createTime.toDateTime());

List<SailDropdownItem<String>> topicDropdownItems(List<Topic> topics) {
  final names = <String>{};
  final repeatedNames = <String>{};
  for (final topic in topics) {
    if (!names.add(topic.name)) {
      repeatedNames.add(topic.name);
    }
  }
  return [
    for (final topic in topics)
      SailDropdownItem<String>(
        value: topic.topic,
        label: [
          if (repeatedNames.contains(topic.name)) '${topic.topic} · ',
          topic.name,
          if (!topic.confirmed) ' (pending)',
        ].join(),
      ),
  ];
}

class CoinNewsView extends ViewModelWidget<CoinNewsViewModel> {
  const CoinNewsView({super.key});

  @override
  Widget build(BuildContext context, CoinNewsViewModel viewModel) {
    final selectedTopicCount = viewModel.selectedTopicIds.length;
    return SailCard(
      title: 'Coin News',
      titleTooltip: 'Stay up-to-date on the latest world developments',
      error: viewModel.readError,
      widgetHeaderEnd: ExtraActionsDropdown(
        title: 'Extra Coin News Actions',
        items: [
          ExtraActionItem(
            label: 'Manage Topics',
            icon: SailSVGAsset.newspaper,
            onSelect: () => displayCreateTopicDialog(context),
          ),
          ExtraActionItem(
            label: 'Graffiti Explorer',
            icon: SailSVGAsset.sprayCan,
            onSelect: () => displayGraffitiExplorerDialog(context),
          ),
        ],
      ),
      child: SailRow(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SailStyleValues.padding16,
        children: [
          Flexible(
            child: SailColumn(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              spacing: 0,
              mainAxisSize: MainAxisSize.min,
              children: [
                SailRow(
                  spacing: SailStyleValues.padding16,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: SailTextField(hintText: 'Search coin news...', controller: viewModel.searchController),
                    ),
                    SailMultiSelectDropdown(
                      selectedCountText: selectedTopicCount == 1 ? '1 topic' : '$selectedTopicCount topics',
                      items: topicDropdownItems(viewModel.topics),
                      selectedValues: viewModel.selectedTopicIds,
                      onSelected: viewModel.toggleTopic,
                      searchPlaceholder: 'Select topics..',
                    ),
                    SailButton(
                      label: 'Broadcast',
                      onPressed: viewModel.selectedTopicIds.isNotEmpty
                          ? () => displayBroadcastNewsDialog(context, topic: viewModel.broadcastTopic)
                          : null,
                    ),
                  ],
                ),
                const SailSpacing(16),
                CoinNewsTable(
                  entries: viewModel.paginatedEntries,
                  onSort: viewModel.sortEntries,
                  loading: viewModel.loading,
                  onArticleSelected: (news) => showCoinNewsArticle(context, news),
                ),
                const SizedBox(height: 16),
                Pagination(
                  currentPage: viewModel.currentPage,
                  totalPages: viewModel.totalPages,
                  onPageChanged: viewModel.setPage,
                  pageSize: viewModel.pageSize,
                  pageSizeOptions: const [3, 5, 10, 20],
                  onPageSizeChanged: (val) => viewModel.setPageSize(val ?? viewModel.pageSize),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The failed read of the news, in red under a card header.
class NewsReadError extends StatelessWidget {
  final String message;

  const NewsReadError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return SailText.primary12(
      message,
      color: context.sailTheme.colors.error,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Height that fits four whole story rows per column.
const double _largeWidgetHeight = 387;

/// Height that fits four whole story rows in a stacked phone card.
const double _stackedStoriesHeight = 232;

class CoinNewsLargeView extends ViewModelWidget<CoinNewsLargeViewModel> {
  const CoinNewsLargeView({super.key});

  @override
  Widget build(BuildContext context, CoinNewsLargeViewModel viewModel) {
    if (SailStyleValues.phoneLayout(context)) {
      return SailColumn(
        spacing: SailStyleValues.padding16,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (topic, onChanged) in [
            (viewModel.leftTopic, viewModel.setLeftTopic),
            (viewModel.rightTopic, viewModel.setRightTopic),
          ])
            _LargeColumn(
              topic: topic,
              onTopicChanged: onChanged,
              entries: viewModel.entriesFor(topic),
              outdatedCount: viewModel.outdatedCountFor(topic),
              viewModel: viewModel,
              stacked: true,
            ),
        ],
      );
    }
    return SizedBox(
      height: _largeWidgetHeight,
      child: SailRow(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SailStyleValues.padding16,
        children: [
          Expanded(
            child: _LargeColumn(
              topic: viewModel.leftTopic,
              onTopicChanged: viewModel.setLeftTopic,
              entries: viewModel.entriesFor(viewModel.leftTopic),
              outdatedCount: viewModel.outdatedCountFor(viewModel.leftTopic),
              viewModel: viewModel,
            ),
          ),
          Expanded(
            child: _LargeColumn(
              topic: viewModel.rightTopic,
              onTopicChanged: viewModel.setRightTopic,
              entries: viewModel.entriesFor(viewModel.rightTopic),
              outdatedCount: viewModel.outdatedCountFor(viewModel.rightTopic),
              viewModel: viewModel,
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeColumn extends StatelessWidget {
  final String topic;
  final void Function(String?) onTopicChanged;
  final List<CoinNews> entries;
  final int outdatedCount;
  final CoinNewsLargeViewModel viewModel;

  /// True sizes the card to its stories, up to four rows, for the phone stack.
  final bool stacked;

  const _LargeColumn({
    required this.topic,
    required this.onTopicChanged,
    required this.entries,
    required this.outdatedCount,
    required this.viewModel,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    return SailCard(
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: stacked ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SailRow(
            children: [
              SailText.primary15('Coin News', bold: true),
              Expanded(child: Container()),
              SailDropdownButton<String>(
                items: topicDropdownItems(viewModel.topics),
                onChanged: onTopicChanged,
                value: topic,
              ),
            ],
          ),
          if (viewModel.readError != null) NewsReadError(viewModel.readError!),
          if (stacked)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _stackedStoriesHeight),
              child: _body(context),
            )
          else
            Expanded(child: _body(context)),
          if (outdatedCount > 0 || viewModel.showOutdated) _outdatedLink(context),
        ],
      ),
    );
  }

  Widget _outdatedLink(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SailButton(
        label: viewModel.showOutdated ? 'Hide Outdated' : 'Show Outdated',
        variant: ButtonVariant.link,
        small: true,
        onPressed: () async => viewModel.toggleOutdated(),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (viewModel.loading) {
      return Center(child: SailText.secondary12('Loading…'));
    }
    if (entries.isEmpty) {
      return Center(
        child: SailColumn(
          spacing: SailStyleValues.padding04,
          mainAxisSize: MainAxisSize.min,
          children: [
            SailText.primary15('Nothing here yet', bold: true),
            SailText.secondary12('Broadcast a story to start the feed.'),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: stacked,
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, i) => _LargeStoryRow(entry: entries[i], outdated: entries[i].outdated),
    );
  }
}

/// One ranked story: headline, then its origin.
class _LargeStoryRow extends StatefulWidget {
  final CoinNews entry;
  final bool outdated;

  const _LargeStoryRow({required this.entry, required this.outdated});

  @override
  State<_LargeStoryRow> createState() => _LargeStoryRowState();
}

class _LargeStoryRowState extends State<_LargeStoryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final date = storyTime(widget.entry, (time) => time.toLocal().toIso8601String().substring(0, 10));
    final topicName = GetIt.I.get<NewsProvider>().topicName(widget.entry.topic);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => showCoinNewsArticle(context, widget.entry),
        child: Opacity(
          opacity: widget.outdated ? 0.5 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _hovered ? theme.colors.backgroundSecondary : SailColorScheme.transparent,
              border: Border(bottom: BorderSide(color: theme.colors.divider)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SailStyleValues.padding08,
                vertical: SailStyleValues.padding10,
              ),
              child: SailColumn(
                spacing: SailStyleValues.padding04,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SailText.primary13(widget.entry.headline, bold: true),
                  SailText.secondary12(storyMeta(widget.entry, topicName: topicName, date: date)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CoinNewsLargeViewModel extends BaseViewModel {
  final NewsProvider _newsProvider = GetIt.I.get<NewsProvider>();
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();
  late final Future<void> _topicsLoaded;

  String? _savedLeftTopic;
  String? _savedRightTopic;

  String get leftTopic => _newsProvider.topicOnChain(_savedLeftTopic) ?? '';
  String get rightTopic => _newsProvider.topicOnChain(_savedRightTopic, fallback: 1) ?? '';

  /// Stories past their topic's retention are hidden until the user asks.
  bool showOutdated = false;

  CoinNewsLargeViewModel() {
    _newsProvider.addListener(notifyListeners);
    _topicsLoaded = _loadTopics();
  }

  bool get loading => _newsProvider.loading;
  String? get readError => _newsProvider.readError;
  List<Topic> get topics => _newsProvider.topics;

  Future<void> _loadTopics() async {
    final config = (await _settings.getValue(SelectedTopicsSetting())).value;
    _savedLeftTopic = config.leftTopic;
    _savedRightTopic = config.rightTopic;
    notifyListeners();
  }

  Future<void> setLeftTopic(String? topic) async {
    if (topic == null) {
      return;
    }
    await _topicsLoaded;
    _savedLeftTopic = topic;
    await _settings.mergeValue(SelectedTopicsSetting(), (config) => config.copyWith(leftTopic: topic));
    notifyListeners();
  }

  Future<void> setRightTopic(String? topic) async {
    if (topic == null) {
      return;
    }
    await _topicsLoaded;
    _savedRightTopic = topic;
    await _settings.mergeValue(SelectedTopicsSetting(), (config) => config.copyWith(rightTopic: topic));
    notifyListeners();
  }

  void toggleOutdated() {
    showOutdated = !showOutdated;
    notifyListeners();
  }

  int outdatedCountFor(String topic) {
    return _allFor(topic).where((news) => news.outdated).length;
  }

  List<CoinNews> entriesFor(String topic) {
    final entries = _allFor(topic).where((news) => showOutdated || !news.outdated).toList();
    entries.sort((a, b) => b.feeSats.compareTo(a.feeSats));
    return entries;
  }

  List<CoinNews> _allFor(String topic) {
    if (loading) {
      return [...dummyData];
    }
    return _newsProvider.news.where((news) => news.topic == topic).toList();
  }

  @override
  void dispose() {
    _newsProvider.removeListener(notifyListeners);
    super.dispose();
  }
}

class CoinNewsViewModel extends BaseViewModel {
  BitwindowRPC get bitwindowd => GetIt.I.get<BitwindowRPC>();

  final NewsProvider _newsProvider = GetIt.I.get<NewsProvider>();
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();
  final TextEditingController searchController = TextEditingController();

  // Pagination state
  int _currentPage = 1;
  int pageSize = 5;

  /// The selected page, kept inside the pages that the filtered entries fill.
  int get currentPage => _currentPage.clamp(1, totalPages);

  // Sorting state
  bool _sortAscending = false;
  String _sortColumn = 'date';

  // Selected article for side panel
  CoinNews? selectedArticle;
  String? selectedRowId;

  void selectArticle(CoinNews news) {
    // Find the index in paginatedEntries for row highlighting
    final index = paginatedEntries.indexOf(news);
    selectedRowId = index >= 0 ? index.toString() : null;
    selectedArticle = news;
    notifyListeners();
  }

  void clearSelection() {
    selectedArticle = null;
    selectedRowId = null;
    notifyListeners();
  }

  bool get loading => _newsProvider.loading;
  String? get readError => _newsProvider.readError;

  double get coinnewsHeight {
    switch (pageSize) {
      case 3:
        return 289;
      case 5:
        return 337;
      case 10:
        return 457;
      case 20:
        return 553;
      default:
        return 400;
    }
  }

  List<CoinNews> get entries {
    if (loading) {
      // if loading, add dummy date for the skeletonizer to render things properly
      return [
        CoinNews(
          topic: 'bitcoin',
          headline: 'Bitcoin price hits new all-time high',
          content: 'Bitcoin price hits new all-time high',
          createTime: Timestamp.fromDateTime(DateTime.now()),
        ),
        CoinNews(
          topic: 'bitcoin',
          headline: 'Bitcoin price hits new all-time high',
          content: 'Bitcoin price hits new all-time high',
          createTime: Timestamp.fromDateTime(DateTime.now()),
        ),
        CoinNews(
          topic: 'drivechain',
          headline: 'Drivechain upgrade successfully completed',
          content:
              'The long-awaited Drivechain upgrade has been successfully implemented, bringing bitcoin to the masses.',
          createTime: Timestamp.fromDateTime(DateTime.now().subtract(const Duration(hours: 2))),
        ),
        CoinNews(
          topic: 'defi',
          headline: 'New DeFi protocol launches with 100M TVL',
          content: 'A revolutionary DeFi protocol has launched, offering innovative yield farming strategies and cross-layer (using drivechain!!) liquidity solutions.',
          createTime: Timestamp.fromDateTime(DateTime.now().subtract(const Duration(hours: 4))),
        ),
        CoinNews(
          topic: 'bitcoin',
          headline: 'Major financial institution announces Bitcoin ETF',
          content: 'A leading financial institution has filed for a spot Bitcoin ETF, potentially opening the door for institutional investors to gain direct exposure to Bitcoin.',
          createTime: Timestamp.fromDateTime(DateTime.now().subtract(const Duration(hours: 6))),
        ),
      ];
    }

    final selectedTopics = selectedTopicIds;
    final filteredEntries = _newsProvider.currentNews
        .where(
          (news) =>
              selectedTopics.contains(news.topic) &&
              (searchController.text.isEmpty ||
                  news.headline.toLowerCase().contains(searchController.text.toLowerCase()) ||
                  news.content.toLowerCase().contains(searchController.text.toLowerCase())),
        )
        .toList();

    // Apply sorting
    filteredEntries.sort((a, b) {
      dynamic aValue = '';
      dynamic bValue = '';

      switch (_sortColumn) {
        case 'date':
          aValue = a.createTime.toDateTime().millisecondsSinceEpoch;
          bValue = b.createTime.toDateTime().millisecondsSinceEpoch;
          break;
        case 'topic':
          aValue = a.topic;
          bValue = b.topic;
          break;
        case 'title':
          aValue = a.headline;
          bValue = b.headline;
          break;
        case 'readtime':
          aValue = expectedReadTime(a.content);
          bValue = expectedReadTime(b.content);
          break;
        case 'fee':
          aValue = a.feeSats.toInt();
          bValue = b.feeSats.toInt();
          break;
      }

      return _sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });

    return filteredEntries;
  }

  List<CoinNews> get paginatedEntries {
    final start = (currentPage - 1) * pageSize;
    final end = (start + pageSize).clamp(0, entries.length);
    return entries.sublist(start, end);
  }

  int get totalPages => (entries.length / pageSize).ceil().clamp(1, 9999);

  void setPage(int page) {
    _currentPage = page;
    notifyListeners();
  }

  void setPageSize(int size) async {
    pageSize = size;
    _currentPage = 1;

    // Persist the page size
    final setting = PageSizeSetting(newValue: size);
    await _settings.setValue(setting);

    notifyListeners();
  }

  List<Topic> get topics => _newsProvider.topics;

  List<String>? _selectedTopicIds = [];
  List<String> get selectedTopicIds => _newsProvider.topicsOnChain(_selectedTopicIds);

  /// The topic for a new story: the one selected topic, or null when more topics are selected.
  String? get broadcastTopic => selectedTopicIds.length == 1 ? selectedTopicIds.single : null;

  CoinNewsViewModel() {
    _newsProvider.addListener(notifyListeners);
    _loadSelectedTopics();
    _loadPageSize();
    searchController.addListener(notifyListeners);
  }

  Future<void> _loadSelectedTopics() async {
    if (Environment.isInTest) {
      return;
    }

    final setting = await _settings.getValue(SelectedTopicsSetting());
    _selectedTopicIds = setting.value.selectedTopics;
    notifyListeners();
  }

  Future<void> _loadPageSize() async {
    if (Environment.isInTest) {
      return;
    }

    final setting = PageSizeSetting();
    final loadedSetting = await _settings.getValue(setting);
    pageSize = loadedSetting.value;
    notifyListeners();
  }

  Future<void> setSelectedTopics(List<String> topicIds) async {
    _selectedTopicIds = topicIds;

    await _settings.mergeValue(SelectedTopicsSetting(), (config) => config.copyWith(selectedTopics: topicIds));

    notifyListeners();
  }

  Future<void> toggleTopic(String topicId) async {
    final newSelection = List<String>.of(selectedTopicIds);
    if (newSelection.contains(topicId)) {
      newSelection.remove(topicId);
    } else {
      newSelection.add(topicId);
    }
    await setSelectedTopics(newSelection);
  }

  void sortEntries(String column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      // Default to descending for date column, ascending for others
      _sortAscending = column != 'date';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _newsProvider.removeListener(notifyListeners);
    searchController.removeListener(notifyListeners);
    searchController.dispose();
    super.dispose();
  }
}

List<CoinNews> get dummyData => [
  // if loading, add dummy date for the skeletonizer to render things properly
  CoinNews(
    topic: 'bitcoin',
    headline: 'Bitcoin price hits new all-time high',
    content: 'Bitcoin price hits new all-time high',
    createTime: Timestamp.fromDateTime(DateTime.now()),
  ),
  CoinNews(
    topic: 'bitcoin',
    headline: 'Bitcoin price hits new all-time high',
    content: 'Bitcoin price hits new all-time high',
    createTime: Timestamp.fromDateTime(DateTime.now()),
  ),
  CoinNews(
    topic: 'drivechain',
    headline: 'Drivechain upgrade successfully completed',
    content: 'The long-awaited Drivechain upgrade has been successfully implemented, bringing bitcoin to the masses.',
    createTime: Timestamp.fromDateTime(DateTime.now().subtract(const Duration(hours: 2))),
  ),
  CoinNews(
    topic: 'defi',
    headline: 'New DeFi protocol launches with 100M TVL',
    content: 'A revolutionary DeFi protocol has launched, offering innovative yield farming strategies and cross-layer (using drivechain!!) liquidity solutions.',
    createTime: Timestamp.fromDateTime(DateTime.now().subtract(const Duration(hours: 4))),
  ),
  CoinNews(
    topic: 'bitcoin',
    headline: 'Major financial institution announces Bitcoin ETF',
    content: 'A leading financial institution has filed for a spot Bitcoin ETF, potentially opening the door for institutional investors to gain direct exposure to Bitcoin.',
    createTime: Timestamp.fromDateTime(DateTime.now().subtract(const Duration(hours: 6))),
  ),
];

class TopicsConfigData {
  final List<String>? selectedTopics;
  final String? leftTopic;
  final String? rightTopic;

  TopicsConfigData({this.selectedTopics, this.leftTopic, this.rightTopic});

  Map<String, dynamic> toMap() {
    return {'selectedTopics': selectedTopics, 'leftTopic': leftTopic, 'rightTopic': rightTopic};
  }

  factory TopicsConfigData.fromMap(Map<String, dynamic> map) {
    return TopicsConfigData(
      selectedTopics: map['selectedTopics'] == null ? null : List<String>.from(map['selectedTopics']),
      leftTopic: map['leftTopic'] as String?,
      rightTopic: map['rightTopic'] as String?,
    );
  }

  TopicsConfigData copyWith({List<String>? selectedTopics, String? leftTopic, String? rightTopic}) {
    return TopicsConfigData(
      selectedTopics: selectedTopics ?? this.selectedTopics,
      leftTopic: leftTopic ?? this.leftTopic,
      rightTopic: rightTopic ?? this.rightTopic,
    );
  }
}

class SelectedTopicsSetting extends SettingValue<TopicsConfigData> {
  @override
  String get key => 'selected_topics_config';

  SelectedTopicsSetting({super.newValue});

  @override
  TopicsConfigData defaultValue() => TopicsConfigData();

  @override
  TopicsConfigData? fromJson(String jsonString) {
    try {
      final Map<String, dynamic> decoded = json.decode(jsonString);
      return TopicsConfigData.fromMap(decoded);
    } catch (e) {
      return null;
    }
  }

  @override
  String toJson() {
    return json.encode(value.toMap());
  }

  @override
  SettingValue<TopicsConfigData> withValue([TopicsConfigData? value]) {
    return SelectedTopicsSetting(newValue: value);
  }
}

class PageSizeSetting extends SettingValue<int> {
  @override
  String get key => 'coin_news_page_size';

  PageSizeSetting({super.newValue});

  @override
  int defaultValue() => 3; // Default to 3 items per page

  @override
  int? fromJson(String jsonString) {
    try {
      return int.parse(jsonString);
    } catch (e) {
      return null;
    }
  }

  @override
  String toJson() {
    return value.toString();
  }

  @override
  SettingValue<int> withValue([int? value]) {
    return PageSizeSetting(newValue: value);
  }
}

class CoinNewsEntry extends StatefulWidget {
  final CoinNews entry;

  const CoinNewsEntry({required this.entry, super.key});

  @override
  State<CoinNewsEntry> createState() => _CoinNewsEntryState();
}

class _CoinNewsEntryState extends State<CoinNewsEntry> {
  bool isHovered = false;

  String _getInitials(String topic) {
    final name = GetIt.I.get<NewsProvider>().topicName(topic);
    if (name == null || name.isEmpty) {
      return '';
    }
    final words = name.split(' ');
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    return words[0].substring(0, min(2, words[0].length)).toUpperCase();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w';
    }

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (date.year != now.year) {
      return "${months[date.month - 1]} '${date.year.toString().substring(2)}";
    }
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: () {
          final article = Article(title: widget.entry.headline, markdown: widget.entry.content, filename: '');
          showArticleDetails(context, article, 'Coin News');
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHovered ? context.sailTheme.colors.backgroundSecondary : SailColorScheme.transparent,
            borderRadius: context.sailTheme.chrome.radius,
          ),
          child: SailRow(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SailStyleValues.padding16,
            children: [
              SailColumn(
                spacing: SailStyleValues.padding04,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.sailTheme.colors.backgroundSecondary,
                    ),
                    child: Center(
                      child: SailText.primary12(
                        _getInitials(widget.entry.topic),
                        color: context.sailTheme.colors.textSecondary,
                      ),
                    ),
                  ),
                  Center(
                    child: SailText.secondary12(
                      storyTime(widget.entry, _formatDate),
                      color: context.sailTheme.colors.textTertiary,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SailColumn(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: SailStyleValues.padding04,
                  children: [
                    SailText.primary15(widget.entry.headline, bold: true),
                    SailText.secondary12(
                      widget.entry.content.replaceAll('\n', ' '),
                      color: context.sailTheme.colors.textSecondary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoinNewsTable extends StatelessWidget {
  final List<CoinNews> entries;
  final Function(String) onSort;
  final bool loading;
  final bool shrinkWrap;
  final bool condensed;
  final void Function(CoinNews news)? onArticleSelected;
  final String? selectedRowId;

  const CoinNewsTable({
    super.key,
    required this.entries,
    required this.onSort,
    required this.loading,
    this.shrinkWrap = true,
    this.condensed = false,
    this.onArticleSelected,
    this.selectedRowId,
  });

  static const _phoneDateWidth = 72.0;
  static const _phoneReadTimeWidth = 88.0;

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final phone = SailStyleValues.phoneLayout(context) && !condensed;

    return SailSkeletonizer(
      description: 'Waiting for backend to boot and for it to load coin news..',
      enabled: loading,
      duration: const Duration(seconds: 3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final phoneTitleWidth = max(
            defaultMinColumnWidth,
            constraints.maxWidth - _phoneDateWidth - _phoneReadTimeWidth,
          );
          return ListenableBuilder(
            listenable: formatter,
            builder: (context, child) => SailTable(
              shrinkWrap: shrinkWrap,
              selectedRowId: selectedRowId,
              getRowId: (index) => index.toString(),
              phoneColumns: condensed ? null : const [0, 2, 3],
              headerBuilder: (context) => [
                if (condensed) ...[
                  const SailTableHeaderCell(name: 'Date'),
                  const SailTableHeaderCell(name: 'Fee'),
                  const SailTableHeaderCell(name: 'Title'),
                ] else ...[
                  const SailTableHeaderCell(name: 'Date'),
                  const SailTableHeaderCell(name: 'Topic'),
                  const SailTableHeaderCell(name: 'Title'),
                  const SailTableHeaderCell(name: 'Read time'),
                ],
              ],
              rowBuilder: (context, row, selected) {
                final entry = entries[row];
                final topicName = GetIt.I.get<NewsProvider>().topicName(entry.topic);

                return [
                  if (condensed) ...[
                    SailTableCell(value: storyTime(entry, formatDate)),
                    SailTableCell(value: formatter.formatSats(entry.feeSats.toInt())),
                    SailTableCell(value: entry.headline),
                  ] else ...[
                    SailTableCell(
                      value: phone
                          ? storyTime(
                              entry,
                              (time) => cachedDateFormat('MMM d', Intl.getCurrentLocale()).format(time.toLocal()),
                            )
                          : storyTime(entry, formatDate),
                      width: phone ? _phoneDateWidth : null,
                    ),
                    SailTableCell(value: topicName ?? ''),
                    SailTableCell(
                      value: entry.headline,
                      width: phone ? phoneTitleWidth : null,
                      child: phone ? SailText.primary13(entry.headline) : null,
                    ),
                    SailTableCell(
                      value: expectedReadTime(entry.content),
                      width: phone ? _phoneReadTimeWidth : null,
                    ),
                  ],
                ];
              },
              rowCount: entries.length,
              emptyPlaceholder: 'No news articles yet',
              drawGrid: true,
              onSort: (columnIndex, ascending) {
                final columns = condensed ? ['date', 'fee', 'title'] : ['date', 'topic', 'title', 'readtime'];
                onSort(columns[columnIndex]);
              },
              onRowTap: (rowId) {
                if (onArticleSelected == null) {
                  return;
                }
                final index = int.tryParse(rowId);
                if (index != null && index < entries.length) {
                  onArticleSelected!(entries[index]);
                }
              },
              contextMenuItems: (rowId) {
                final index = int.tryParse(rowId);
                final news = index != null && index < entries.length ? entries[index] : null;
                return [
                  SailMenuItem(
                    onSelected: () {
                      if (news != null && onArticleSelected != null) {
                        onArticleSelected!(news);
                      }
                    },
                    child: SailText.primary12('Show Details'),
                  ),
                  // The indexer does not always report the on-chain position.
                  if (news != null && news.txid.isNotEmpty)
                    SailMenuItem(
                      onSelected: () async {
                        final network = GetIt.I.get<BitcoinConfProvider>().network;
                        await openUrl(Uri.parse(mempoolTxUrl(news.txid, network)));
                      },
                      child: SailText.primary12('View on chain'),
                    ),
                ];
              },
            ),
          );
        },
      ),
    );
  }
}

void showCoinNewsArticle(BuildContext context, CoinNews news) {
  unawaited(
    showSailSheet(
      context: context,
      side: SailSheetSide.bottom,
      size: MediaQuery.of(context).size.height * 0.95,
      builder: (context) {
        return CoinNewsArticlePanel(news: news, onClose: () => Navigator.of(context).pop());
      },
    ),
  );
}

class CoinNewsArticlePanel extends StatefulWidget {
  final CoinNews news;
  final VoidCallback onClose;

  const CoinNewsArticlePanel({super.key, required this.news, required this.onClose});

  @override
  State<CoinNewsArticlePanel> createState() => _CoinNewsArticlePanelState();
}

class _CoinNewsArticlePanelState extends State<CoinNewsArticlePanel> {
  BitwindowRPC get api => GetIt.I.get<BitwindowRPC>();
  NewsProvider get _newsProvider => GetIt.I.get<NewsProvider>();
  final BlockchainProvider _blockchain = GetIt.I.get<BlockchainProvider>();
  final FormatterProvider _formatter = GetIt.I.get<FormatterProvider>();

  List<Comment> _comments = [];
  bool _loading = true;
  bool _posting = false;
  String? _loadError;
  String? _postError;
  String? _replyTo; // item_id being replied to; null = top-level
  int _reads = 0;
  final TextEditingController _controller = TextEditingController();

  /// The newest read of the story. A story in the mempool gets its block time and item ID from a later read.
  late CoinNews _story = _newest() ?? widget.news;

  String get _itemId => _story.itemId;

  @override
  void initState() {
    super.initState();
    _newsProvider.addListener(_onNews);
    _blockchain.addListener(_load);
    _blockchain.recentChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _newsProvider.removeListener(_onNews);
    _blockchain.removeListener(_load);
    _blockchain.recentChanged.removeListener(_load);
    _controller.dispose();
    super.dispose();
  }

  CoinNews? _newest() {
    final txid = widget.news.txid;
    if (txid.isEmpty) {
      return null;
    }
    return _newsProvider.news.firstWhereOrNull((n) => n.txid == txid && n.vout == widget.news.vout);
  }

  void _onNews() {
    final story = _newest();
    if (story == null || story == _story) {
      return;
    }
    final itemChanged = story.itemId != _itemId;
    setState(() => _story = story);
    if (itemChanged) {
      unawaited(_load());
    }
  }

  /// Reads the thread. Only the newest read changes the panel.
  Future<void> _load() async {
    final read = ++_reads;
    if (_itemId.isEmpty) {
      setState(() {
        _comments = [];
        _replyTo = null;
        _loadError = null;
        _loading = false;
      });
      return;
    }
    List<Comment>? comments;
    String? error;
    try {
      comments = await api.misc.listComments(_itemId);
    } catch (e) {
      error = e.toString();
    }
    if (!mounted || read != _reads) {
      return;
    }
    setState(() {
      _comments = comments ?? _comments;
      _loadError = error;
      _loading = false;
    });
  }

  Future<void> _post() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _posting) {
      return;
    }
    if (!await NewsCost.confirmFirstComment(context, body: body)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _posting = true;
      _postError = null;
    });
    try {
      await api.misc.commentNews(_replyTo ?? _itemId, body);
      if (!mounted) {
        return;
      }
      _controller.clear();
      setState(() => _replyTo = null);
      await _load();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _postError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = SailTheme.of(context);

    // Use the opposite theme for the article panel
    final oppositeThemeData = currentTheme.isLightMode()
        ? SailThemeData.darkTheme(currentTheme.colors.primary, currentTheme.dense, currentTheme.font)
        : SailThemeData.lightTheme(currentTheme.colors.primary, currentTheme.dense, currentTheme.font);

    return SailTheme(
      data: oppositeThemeData,
      child: Builder(
        builder: (context) {
          final theme = SailTheme.of(context);

          return SailCard(
            padding: false,
            color: theme.colors.background,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(SailStyleValues.padding08),
                    child: SailButton(
                      label: 'Close',
                      variant: ButtonVariant.ghost,
                      onPressed: () async => widget.onClose(),
                    ),
                  ),
                ),
                Expanded(
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SailStyleValues.padding40,
                          SailStyleValues.padding08,
                          SailStyleValues.padding40,
                          SailStyleValues.padding40,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SailText.primary24(_story.headline, bold: true),
                              const SailSpacing(SailStyleValues.padding12),
                              ListenableBuilder(
                                listenable: _newsProvider,
                                builder: (context, _) {
                                  final date = storyTime(_story, formatDate);
                                  final topicName = _newsProvider.topicName(_story.topic);
                                  return SailText.secondary13(
                                    storyMeta(_story, topicName: topicName, date: date, separator: '  ·  '),
                                    color: theme.colors.textTertiary,
                                  );
                                },
                              ),
                              const SailSpacing(SailStyleValues.padding16),
                              Container(height: 1, color: theme.colors.divider),
                              const SailSpacing(SailStyleValues.padding20),
                              if (_story.url.isNotEmpty) ...[
                                if (webLink(_story.url) case final link?)
                                  GestureDetector(
                                    onTap: () async => openUrl(link),
                                    child: SailText.primary13(_story.url, color: theme.colors.primary),
                                  )
                                else
                                  SailText.primary13(_story.url, color: theme.colors.textSecondary),
                                const SailSpacing(SailStyleValues.padding16),
                              ],
                              MarkdownBody(
                                data: _story.content,
                                styleSheet: MarkdownStyleSheet(
                                  p: SailStyleValues.fifteen.copyWith(color: theme.colors.text, height: 1.6),
                                  h1: SailStyleValues.twentyTwo.copyWith(color: theme.colors.text),
                                  h2: SailStyleValues.twenty.copyWith(color: theme.colors.text),
                                  h3: SailStyleValues.fifteen.copyWith(
                                    color: theme.colors.text,
                                    fontWeight: SailStyleValues.boldWeight,
                                  ),
                                  listBullet: SailStyleValues.fifteen.copyWith(color: theme.colors.text, height: 1.6),
                                  pPadding: const EdgeInsets.only(bottom: 16),
                                  blockquoteDecoration: BoxDecoration(
                                    color: SailColorScheme.transparent,
                                    borderRadius: context.sailTheme.chrome.radius,
                                  ),
                                  codeblockDecoration: BoxDecoration(
                                    color: theme.colors.backgroundSecondary,
                                    borderRadius: context.sailTheme.chrome.radius,
                                  ),
                                  code: SailStyleValues.thirteen.copyWith(
                                    color: theme.colors.text,
                                    fontFamily: SailFonts.mono,
                                  ),
                                  codeblockPadding: const EdgeInsets.all(12),
                                ),
                                onTapLink: (_, href, _) async {
                                  final link = href == null ? null : webLink(href);
                                  if (link == null) {
                                    return;
                                  }
                                  await openUrl(link);
                                },
                              ),
                              const SailSpacing(SailStyleValues.padding32),
                              ListenableBuilder(
                                listenable: _formatter,
                                builder: (context, _) => _commentsThread(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_itemId.isNotEmpty) _composerFooter(context),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The comment thread (spec §7). Replies nest under their parent;
  /// siblings are ordered by fee, highest first.
  Widget _commentsThread(BuildContext context) {
    final theme = SailTheme.of(context);
    final roots = _comments.where((c) => c.parentId == _itemId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: theme.colors.divider),
        const SailSpacing(SailStyleValues.padding12),
        SailText.primary15('Comments (${_comments.length})', bold: true),
        const SailSpacing(SailStyleValues.padding12),
        if (_loadError != null) ...[
          SailText.secondary12(_loadError!, color: theme.colors.error),
          const SailSpacing(SailStyleValues.padding12),
        ],
        if (_itemId.isEmpty)
          SailText.secondary12('Comments open when the story is in a block.')
        else if (_loading)
          SailText.secondary12('Loading comments…')
        else if (roots.isEmpty && _loadError == null)
          SailText.secondary12('No comments yet. Be the first.')
        else
          ...roots.map((c) => _commentTree(context, c, depth: 0)),
      ],
    );
  }

  Widget _commentTree(BuildContext context, Comment comment, {required int depth}) {
    final children = _comments.where((c) => c.parentId == comment.itemId).toList();
    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : SailStyleValues.padding16, bottom: SailStyleValues.padding08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _commentTile(context, comment),
          ...children.map((c) => _commentTree(context, c, depth: depth + 1)),
        ],
      ),
    );
  }

  Widget _commentTile(BuildContext context, Comment comment) {
    final theme = SailTheme.of(context);
    final author = comment.author.length > 10 ? '${comment.author.substring(0, 10)}…' : comment.author;
    final meta = [
      author,
      comment.pending ? 'Pending' : formatDate(comment.createTime.toDateTime()),
      // The server sends 0 for a fee that it does not know.
      if (comment.feeSats > 0) _formatter.formatSats(comment.feeSats.toInt()),
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding08),
      decoration: BoxDecoration(color: theme.colors.backgroundSecondary, borderRadius: context.sailTheme.chrome.radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailText.secondary12(meta, color: theme.colors.textTertiary),
          const SailSpacing(SailStyleValues.padding04),
          SailText.primary13(comment.body),
          if (comment.url.isNotEmpty) SailText.secondary12(comment.url, color: theme.colors.textSecondary),
          // A reply in a block before its parent is not valid, so it waits for the block of the parent.
          if (!comment.pending) ...[
            const SailSpacing(SailStyleValues.padding04),
            SailButton(
              label: _replyTo == comment.itemId ? 'Cancel reply' : 'Reply',
              variant: ButtonVariant.ghost,
              onPressed: () async {
                setState(() => _replyTo = _replyTo == comment.itemId ? null : comment.itemId);
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Pinned composer at the bottom of the panel so posting the first
  /// comment never requires scrolling past the article. Tapping a
  /// comment's Reply re-targets this same box; otherwise it posts a
  /// top-level comment.
  Widget _composerFooter(BuildContext context) {
    final theme = SailTheme.of(context);
    final replying = _replyTo != null;

    String? replyAuthor;
    if (replying) {
      final idx = _comments.indexWhere((c) => c.itemId == _replyTo);
      if (idx != -1) {
        final a = _comments[idx].author;
        replyAuthor = a.length > 10 ? '${a.substring(0, 10)}…' : a;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding40, vertical: SailStyleValues.padding12),
      decoration: BoxDecoration(
        color: theme.colors.background,
        border: Border(top: BorderSide(color: theme.colors.divider, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyAuthor != null) ...[
            Row(
              children: [
                SailText.secondary12('Replying to $replyAuthor', color: theme.colors.textTertiary),
                const SailSpacing(SailStyleValues.padding08),
                SailButton(
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  onPressed: () async => setState(() => _replyTo = null),
                ),
              ],
            ),
            const SailSpacing(SailStyleValues.padding04),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SailTextField(hintText: replying ? 'Write a reply…' : 'Add a comment…', controller: _controller),
              ),
              const SailSpacing(SailStyleValues.padding08),
              NewsCostTooltip(
                action: NewsAction.NEWS_ACTION_COMMENT,
                body: _controller,
                child: SailButton(label: 'Comment', loading: _posting, onPressed: () async => _post()),
              ),
            ],
          ),
          if (_postError != null) ...[
            const SailSpacing(SailStyleValues.padding04),
            SailText.secondary12(_postError!, color: theme.colors.error),
          ],
        ],
      ),
    );
  }
}
