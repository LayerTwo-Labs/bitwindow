import 'dart:async';

import 'package:bitwindow/providers/news_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _MiscAPI extends MockMiscAPI {
  List<CoinNews> served = [];
  Completer<void>? gate;

  @override
  Future<List<CoinNews>> listCoinNews() async {
    final answer = List<CoinNews>.of(served);
    await gate?.future;
    return answer;
  }
}

class _API extends MockAPI {
  _API() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _MiscAPI fakeMisc = _MiscAPI();

  @override
  _MiscAPI get misc => fakeMisc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _API rpc;

  setUp(() async {
    await GetIt.I.reset();
    rpc = _API();
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  test('a fetch during a read gets the news that comes after the read starts', () async {
    final provider = NewsProvider();
    addTearDown(provider.dispose);
    await pumpEventQueue();

    rpc.misc.gate = Completer<void>();
    final first = provider.fetch();
    await pumpEventQueue();
    rpc.misc.served = [CoinNews(topic: 'a1a1a1a1', headline: 'Broadcast during a read')];
    final second = provider.fetch();
    rpc.misc.gate!.complete();
    await second;
    await first;

    expect(provider.news.map((n) => n.headline), ['Broadcast during a read']);
  });
}
