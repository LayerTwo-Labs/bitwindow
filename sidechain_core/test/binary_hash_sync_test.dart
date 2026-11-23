import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/sidechain_core.dart';

class _Orchestrator implements OrchestratorRPC {
  List<BinaryStatusMsg> statuses = [];

  @override
  Future<ListBinariesResponse> listBinaries({bool forceBackend = false}) async =>
      ListBinariesResponse(binaries: statuses);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Binaries extends ChangeNotifier implements BinaryProvider {
  @override
  List<Binary> binaries = [BitcoinCore()];

  @override
  void updateBinary(BinaryType type, Binary Function(Binary) updater) {
    binaries = [for (final b in binaries) b.type == type ? updater(b) : b];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Binaries binaries;

  setUp(() {
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    binaries = _Binaries();
    GetIt.I.registerSingleton<BinaryProvider>(binaries);
  });
  tearDown(() => GetIt.I.reset());

  test('a poll copies the binary hash, and clears it when the binary is gone', () async {
    final orchestrator = _Orchestrator();
    final backend = BackendStateProvider(orchestrator);
    const hash = '9a3a45d01531a20e89ac6ae10b0b0beb0492acd7216a368aa062d1a5fecaf9cd';

    orchestrator.statuses = [BinaryStatusMsg(name: 'bitcoind', binaryPath: '/bin/bitcoind', sha256: hash)];
    await backend.poll();
    expect(binaries.binaries.single.downloadInfo.hash, hash);

    orchestrator.statuses = [BinaryStatusMsg(name: 'bitcoind')];
    await backend.poll();
    expect(binaries.binaries.single.downloadInfo.hash, isNull);
  });
}
