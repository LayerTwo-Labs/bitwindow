import 'dart:async';

import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/misc/v1/misc.pb.dart';
import 'package:sidechain_core/rpcs/bitwindow_api.dart';

class NewsProvider extends ChangeNotifier {
  BitwindowRPC get api => GetIt.I.get<BitwindowRPC>();
  BlockchainProvider get blockchainProvider => GetIt.I.get<BlockchainProvider>();

  List<OPReturn> opReturns = [];
  List<CoinNews> news = [];
  List<Topic> topics = [
    Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly'),
    Topic(id: Int64(2), topic: 'a2a2a2a2', name: 'Japan Weekly'),
  ];
  bool initialized = false;
  String? error;

  Future<void>? _fetching;
  bool _fetchAgain = false;

  /// The error of the last OP_RETURN read, or null when it worked.
  String? opReturnsError;


  NewsProvider() {
    blockchainProvider.addListener(fetch);
    blockchainProvider.recentChanged.addListener(fetch);
    fetch();
  }

  String? topicName(String id) => topics.firstWhereOrNull((t) => t.topic == id)?.name;

  /// True until the first read of news and topics, when no read failed.
  bool get loading => !initialized && error == null;

  /// Why the last read failed, or null when it worked.
  String? get readError => error == null ? null : 'Could not read the news. $error';

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
      if (!listEquals(topics, newTopics)) {
        topics = newTopics;
        dataChanged = true;
      }
    } catch (e) {
      errors.add('Topics: ${e.toString()}');
    }

    final previousOPReturnsError = opReturnsError;
    try {
      final newOPReturns = await api.misc.listOPReturns();
      opReturnsError = null;
      if (!listEquals(opReturns, newOPReturns)) {
        opReturns = newOPReturns;
        dataChanged = true;
      }
    } catch (e) {
      opReturnsError = e.toString();
      errors.add('OP_RETURNs: $opReturnsError');
    }

    if (dataChanged || errors.isNotEmpty || opReturnsError != previousOPReturnsError) {
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
    super.dispose();
  }
}
