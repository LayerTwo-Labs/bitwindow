import 'package:bitwindow/env.dart';
import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

const _headlineChars = 64;

String _truncateHeadline(String headline) {
  var end = headline.length;
  var truncated = false;

  final newline = headline.indexOf(RegExp(r'[\r\n]'));
  if (newline != -1 && newline < end) {
    end = newline;
    truncated = true;
  }
  if (end > _headlineChars) {
    end = _headlineChars;
    truncated = true;
  }

  final str = headline.substring(0, end);
  return truncated ? '$str...' : str;
}

class FeeCoinNewsView extends ViewModelWidget<FeeCoinNewsViewModel> {
  const FeeCoinNewsView({super.key});

  @override
  Widget build(BuildContext context, FeeCoinNewsViewModel viewModel) {
    return SailCard(
      title: 'Coin News',
      titleTooltip: "On-chain news ranked by fee, within each topic's retention window",
      error: viewModel.readError,
      widgetHeaderEnd: SailRowMenuButton(items: () => coinNewsMenuItems(context)),
      child: SailColumn(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 0,
        mainAxisSize: MainAxisSize.min,
        children: [
          SailRow(
            spacing: SailStyleValues.padding16,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              SailDropdownButton<String>(
                items: viewModel.topicItems,
                onChanged: (value) {
                  if (value != null) {
                    viewModel.setTopic(value);
                  }
                },
                value: viewModel.selectedTopic,
                hint: 'Select topic',
              ),
              SailButton(
                label: 'Broadcast',
                onPressed: switch (viewModel.selectedTopic) {
                  final topic? => () => displayBroadcastNewsDialog(context, topic: topic),
                  null => null,
                },
              ),
            ],
          ),
          const SailSpacing(16),
          FeeCoinNewsTable(
            entries: viewModel.entries,
            loading: viewModel.loading,
            onArticleSelected: (news) => showCoinNewsArticle(context, news),
          ),
        ],
      ),
    );
  }
}

class FeeCoinNewsViewModel extends BaseViewModel {
  final NewsProvider _newsProvider = GetIt.I.get<NewsProvider>();
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();

  String? _savedTopic;

  String? get selectedTopic => _newsProvider.topicOnChain(_savedTopic);

  FeeCoinNewsViewModel() {
    _newsProvider.addListener(notifyListeners);
    _loadTopic();
  }

  bool get loading => _newsProvider.loading;
  String? get readError => _newsProvider.readError;
  List<Topic> get topics => _newsProvider.topics;

  List<SailDropdownItem<String>> get topicItems => topicDropdownItems(topics);

  List<CoinNews> get entries {
    if (loading) {
      return [...dummyData];
    }

    return _newsProvider.currentNews.where((news) => news.topic == selectedTopic).toList();
  }

  Future<void> _loadTopic() async {
    if (Environment.isInTest) {
      return;
    }

    final loaded = (await _settings.getValue(FeeTopicSetting(_topicKey))).value;
    _savedTopic = loaded.isEmpty ? null : loaded;
    notifyListeners();
  }

  Future<void> setTopic(String topic) async {
    _savedTopic = topic;
    await _settings.setValue(FeeTopicSetting(_topicKey, newValue: topic));
    notifyListeners();
  }

  @override
  void dispose() {
    _newsProvider.removeListener(notifyListeners);
    super.dispose();
  }
}

class FeeCoinNewsLargeView extends ViewModelWidget<FeeCoinNewsLargeViewModel> {
  const FeeCoinNewsLargeView({super.key});

  @override
  Widget build(BuildContext context, FeeCoinNewsLargeViewModel viewModel) {
    final phone = SailStyleValues.phoneLayout(context);
    final cards = [
      _TopicCard(
        head: [
          SailText.primary15('Coin News', bold: true),
          const Spacer(),
          _TopicDropdown(topic: viewModel.leftTopic, items: viewModel.topicItems, onChanged: viewModel.setLeftTopic),
        ],
        readError: viewModel.readError,
        entries: viewModel.leftEntries,
        loading: viewModel.loading,
      ),
      _TopicCard(
        head: [
          _TopicDropdown(
            topic: viewModel.rightTopic,
            items: viewModel.topicItems,
            onChanged: viewModel.setRightTopic,
          ),
          const Spacer(),
          SailButton(
            label: 'Broadcast News',
            variant: ButtonVariant.primary,
            onPressed: () => displayBroadcastNewsDialog(context, topic: viewModel.rightTopic),
            skipLoading: true,
          ),
          const SizedBox(width: SailStyleValues.padding08),
          SailRowMenuButton(items: () => coinNewsMenuItems(context)),
        ],
        readError: viewModel.readError,
        entries: viewModel.rightEntries,
        loading: viewModel.loading,
      ),
    ];
    if (phone) {
      return SailColumn(spacing: SailStyleValues.padding16, mainAxisSize: MainAxisSize.min, children: cards);
    }
    return SizedBox(
      height: _largeCardHeight,
      child: SailRow(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SailStyleValues.padding12,
        children: [for (final card in cards) Expanded(child: card)],
      ),
    );
  }
}

/// Both cards share one height, so their tables line up.
const double _largeCardHeight = 300;

/// One topic of the large Coin News widget: a card with its head over its stories.
class _TopicCard extends StatelessWidget {
  final List<Widget> head;
  final String? readError;
  final List<CoinNews> entries;
  final bool loading;

  const _TopicCard({required this.head, required this.readError, required this.entries, required this.loading});

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    final table = FeeCoinNewsTable(
      entries: entries,
      loading: loading,
      shrinkWrap: phone,
      onArticleSelected: (news) => showCoinNewsArticle(context, news),
    );
    return SailCard(
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: phone ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SizedBox(height: 36, child: Row(children: head)),
          if (readError != null) NewsReadError(readError!),
          if (phone) table else Expanded(child: table),
        ],
      ),
    );
  }
}

class _TopicDropdown extends StatelessWidget {
  final String topic;
  final List<SailDropdownItem<String>> items;
  final Future<void> Function(String topic) onChanged;

  const _TopicDropdown({required this.topic, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SailDropdownButton<String>(
      items: items,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
      value: topic,
    );
  }
}

class FeeCoinNewsLargeViewModel extends BaseViewModel {
  final NewsProvider _newsProvider = GetIt.I.get<NewsProvider>();
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();

  String? _savedLeftTopic;
  String? _savedRightTopic;

  String get leftTopic => _newsProvider.topicOnChain(_savedLeftTopic) ?? '';
  String get rightTopic => _newsProvider.topicOnChain(_savedRightTopic, fallback: 1) ?? '';

  FeeCoinNewsLargeViewModel() {
    _newsProvider.addListener(notifyListeners);
    _loadTopics();
  }

  bool get loading => _newsProvider.loading;
  String? get readError => _newsProvider.readError;
  List<Topic> get topics => _newsProvider.topics;

  List<SailDropdownItem<String>> get topicItems => topicDropdownItems(topics);

  List<CoinNews> get leftEntries => _entriesFor(leftTopic);
  List<CoinNews> get rightEntries => _entriesFor(rightTopic);

  List<CoinNews> _entriesFor(String topic) {
    if (loading) {
      return [...dummyData];
    }

    return _newsProvider.currentNews.where((news) => news.topic == topic).toList();
  }

  Future<void> _loadTopics() async {
    if (Environment.isInTest) {
      return;
    }

    final left = (await _settings.getValue(FeeTopicSetting(_leftKey))).value;
    final right = (await _settings.getValue(FeeTopicSetting(_rightKey))).value;

    _savedLeftTopic = left.isEmpty ? null : left;
    _savedRightTopic = right.isEmpty ? null : right;
    notifyListeners();
  }

  Future<void> setLeftTopic(String topic) async {
    _savedLeftTopic = topic;
    await _settings.setValue(FeeTopicSetting(_leftKey, newValue: topic));
    notifyListeners();
  }

  Future<void> setRightTopic(String topic) async {
    _savedRightTopic = topic;
    await _settings.setValue(FeeTopicSetting(_rightKey, newValue: topic));
    notifyListeners();
  }

  @override
  void dispose() {
    _newsProvider.removeListener(notifyListeners);
    super.dispose();
  }
}

class FeeCoinNewsTable extends StatelessWidget {
  final List<CoinNews> entries;
  final bool loading;
  final bool shrinkWrap;
  final void Function(CoinNews news)? onArticleSelected;

  const FeeCoinNewsTable({
    super.key,
    required this.entries,
    required this.loading,
    this.shrinkWrap = true,
    this.onArticleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    if (SailStyleValues.phoneLayout(context)) {
      return SailSkeletonizer(
        description: 'Waiting for backend to boot and for it to load coin news..',
        enabled: loading,
        duration: const Duration(seconds: 3),
        child: ListenableBuilder(
          listenable: formatter,
          builder: (context, child) =>
              _FeeStoryList(entries: entries, shrinkWrap: shrinkWrap, onArticleSelected: onArticleSelected),
        ),
      );
    }

    return SailSkeletonizer(
      description: 'Waiting for backend to boot and for it to load coin news..',
      enabled: loading,
      duration: const Duration(seconds: 3),
      child: ListenableBuilder(
        listenable: formatter,
        builder: (context, child) => SailTable(
          shrinkWrap: shrinkWrap,
          getRowId: (index) => index.toString(),
          phoneColumns: const [2, 1],
          headerBuilder: (context) => const [
            SailTableHeaderCell(name: 'Fees'),
            SailTableHeaderCell(name: 'Time'),
            SailTableHeaderCell(name: 'Headline'),
          ],
          rowBuilder: (context, row, selected) {
            final entry = entries[row];
            return [
              SailTableCell(value: formatter.formatSats(entry.feeSats.toInt()), hugContent: true),
              SailTableCell(value: storyTime(entry, (time) => formatDate(time, long: false)), hugContent: true),
              _headlineCell(_truncateHeadline(entry.headline)),
            ];
          },
          rowCount: entries.length,
          emptyPlaceholder: 'No news articles yet',
          drawGrid: true,
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
            return [
              SailMenuItem(
                onSelected: () {
                  final index = int.tryParse(rowId);
                  if (index != null && index < entries.length && onArticleSelected != null) {
                    onArticleSelected!(entries[index]);
                  }
                },
                child: SailText.primary12('Show Details'),
              ),
            ];
          },
        ),
      ),
    );
  }
}

/// A headline takes the width the other columns leave, so the row "…" stays in the card.
SailTableCell _headlineCell(String headline) => SailTableCell(
  value: headline,
  fill: true,
  child: SailText.primary13(headline, overflow: TextOverflow.ellipsis),
);

/// The phone form of [FeeCoinNewsTable]: one row per story, with the headline and time at the left and the fee at the right.
class _FeeStoryList extends StatelessWidget {
  final List<CoinNews> entries;
  final bool shrinkWrap;
  final void Function(CoinNews news)? onArticleSelected;

  const _FeeStoryList({required this.entries, required this.shrinkWrap, required this.onArticleSelected});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding16),
        child: Center(child: SailText.secondary13('No news articles yet')),
      );
    }
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, i) => _FeeStoryRow(
        entry: entries[i],
        onTap: onArticleSelected == null ? null : () => onArticleSelected!(entries[i]),
      ),
    );
  }
}

class _FeeStoryRow extends StatelessWidget {
  final CoinNews entry;
  final VoidCallback? onTap;

  const _FeeStoryRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colors.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SailStyleValues.padding08,
            vertical: SailStyleValues.padding10,
          ),
          child: SailRow(
            spacing: SailStyleValues.padding12,
            children: [
              Expanded(
                child: SailColumn(
                  spacing: SailStyleValues.padding04,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SailText.primary13(_truncateHeadline(entry.headline), bold: true),
                    SailText.secondary12(storyTime(entry, (time) => formatDate(time, long: false))),
                  ],
                ),
              ),
              SailText.primary13(GetIt.I<FormatterProvider>().formatSats(entry.feeSats.toInt()), bold: true),
            ],
          ),
        ),
      ),
    );
  }
}

const _topicKey = 'fee_coin_news_topic';
const _leftKey = 'fee_coin_news_left_topic';
const _rightKey = 'fee_coin_news_right_topic';

class FeeTopicSetting extends SettingValue<String> {
  final String _key;

  FeeTopicSetting(this._key, {super.newValue});

  @override
  String get key => _key;

  @override
  String defaultValue() => '';

  @override
  String? fromJson(String jsonString) => jsonString;

  @override
  String toJson() => value;

  @override
  SettingValue<String> withValue([String? value]) => FeeTopicSetting(_key, newValue: value);
}
