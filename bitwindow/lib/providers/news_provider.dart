import 'dart:async';

import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/misc/v1/misc.pb.dart';
import 'package:sidechain_core/providers/sync_provider.dart';
import 'package:sidechain_core/rpcs/bitwindow_api.dart';

class NewsProvider extends ChangeNotifier {
  BitwindowRPC get api => GetIt.I.get<BitwindowRPC>();
  BlockchainProvider get blockchainProvider => GetIt.I.get<BlockchainProvider>();
  SyncProvider get _syncProvider => GetIt.I.get<SyncProvider>();

  /// Each story of the last read, with the outdated stories.
  List<CoinNews> news = [];

  /// The stories inside the retention of their topic.
  List<CoinNews> get currentNews => news.where((story) => !story.outdated).toList();

  /// The topics that the user subscribes to.
  List<Topic> topics = [
    Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly'),
    Topic(id: Int64(2), topic: 'a2a2a2a2', name: 'Japan Weekly'),
  ];

  /// Each topic in a block or in the mempool, subscribed or not.
  List<Topic> chainTopics = [];
  bool initialized = false;
  String? error;
  String? _topicsError;

  Future<void>? _fetching;
  bool _fetchAgain = false;
  SyncInfo? _bitwindowSync;

  NewsProvider() {
    blockchainProvider.addListener(fetch);
    blockchainProvider.recentChanged.addListener(fetch);
    _bitwindowSync = _syncProvider.bitwindowdSyncInfo;
    _syncProvider.addListener(_onSyncChanged);
    fetch();
  }

  void _onSyncChanged() {
    final sync = _syncProvider.bitwindowdSyncInfo;
    if (_bitwindowSync == sync) {
      return;
    }
    _bitwindowSync = sync;
    unawaited(fetch());
  }

  String? topicName(String id) => topics.firstWhereOrNull((t) => t.topic == id)?.name;

  bool _onChain(String topic) => topics.any((t) => t.topic == topic);

  /// [saved] when this chain has that topic, else the topic at [fallback], else the first topic.
  /// With no topic list, [saved].
  String? topicOnChain(String? saved, {int fallback = 0}) {
    if (topics.isEmpty || (saved != null && _onChain(saved))) {
      return saved;
    }
    return topics.elementAtOrNull(fallback)?.topic ?? topics.firstOrNull?.topic;
  }

  /// The topics of [saved] that this chain has. Null, or a list with no topic
  /// of this chain, gives each topic of this chain. With no topic list, [saved].
  List<String> topicsOnChain(List<String>? saved) {
    if (topics.isEmpty) {
      return saved ?? [];
    }
    final known = saved?.where(_onChain).toList();
    if (known == null || (known.isEmpty && saved!.isNotEmpty)) {
      return topics.map((t) => t.topic).toList();
    }
    return known;
  }

  /// True until the first read of news and topics, when no read failed.
  bool get loading => !initialized && error == null;

  /// Why the last read failed, or null when it worked.
  String? get readError => error == null ? null : 'Could not read the news. $error';

  String? get topicReadError => _topicsError == null ? null : 'Could not read the topics. $_topicsError';

  /// Reads news and topics. A call during a read gets one more read after it,
  /// and completes when that read is done.
  Future<void> fetch() {
    if (_fetching != null) {
      _fetchAgain = true;
      return _fetching!;
    }
    return _fetching = _readUntilCurrent().whenComplete(() => _fetching = null);
  }

  Future<void> _readUntilCurrent() async {
    do {
      _fetchAgain = false;
      await _read();
    } while (_fetchAgain);
  }

  Future<void> _read() async {
    final hadError = error != null;

    List<String> errors = [];
    bool dataChanged = false;

    // Fetch news independently
    try {
      final newNews = await api.misc.listCoinNews();
      if (!listEquals(news, newNews)) {
        news = newNews;
        dataChanged = true;
      }
    } catch (e) {
      errors.add('News: ${e.toString()}');
    }

    // Fetch topics independently
    try {
      final newTopics = await api.misc.listTopics();
      final newChainTopics = await api.misc.listChainTopics();
      _topicsError = null;
      if (!listEquals(topics, newTopics) || !listEquals(chainTopics, newChainTopics)) {
        topics = newTopics;
        chainTopics = newChainTopics;
        dataChanged = true;
      }
    } catch (e) {
      _topicsError = e.toString();
      errors.add('Topics: $_topicsError');
    }

    if (dataChanged || errors.isNotEmpty) {
      if (dataChanged) {
        initialized = true;
      }

      if (errors.isNotEmpty) {
        final newError = errors.join('; ');
        if (newError != error) {
          error = newError;
        }
      } else {
        error = null;
      }

      notifyListeners();
    } else if (hadError) {
      error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    blockchainProvider.removeListener(fetch);
    blockchainProvider.recentChanged.removeListener(fetch);
    _syncProvider.removeListener(_onSyncChanged);
    super.dispose();
  }
}
