import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/mocks/mocks.dart';
import 'package:sidechain_core/sidechain_core.dart';

class _CapturingOutput extends LogOutput {
  final List<String> lines = [];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

/// A wallet the network serves no chain source for fails the same way on every
/// poll.
class _UnservedRPC extends MockBitwindowRPC {
  _UnservedRPC() {
    setConnected(true);
  }

  int calls = 0;
  bool served = false;

  @override
  Future<(double, double, double)> balances() async {
    if (served) {
      return (2.0, 0.0, 0.0);
    }
    final (confirmed, pending) = await balance();
    return (confirmed, pending, 0.0);
  }

  @override
  Future<(double, double)> balance() {
    calls++;
    return Future.error(Exception('electrum wallet ABC has no chain source on this network'));
  }
}

void main() {
  late _CapturingOutput output;
  late _UnservedRPC rpc;
  late BalanceProvider provider;

  setUp(() async {
    await GetIt.I.reset();
    output = _CapturingOutput();
    GetIt.I.registerSingleton<Logger>(Logger(output: output, level: Level.all, printer: SimplePrinter()));
    GetIt.I.registerSingleton<BinaryProvider>(MockBinaryProvider());
    rpc = _UnservedRPC();
    provider = BalanceProvider(connections: [rpc]);
  });

  tearDown(() async {
    provider.dispose();
    await GetIt.I.reset();
  });

  test('a failure that stands prints one time', () async {
    await provider.fetch();
    await provider.fetch();
    await provider.fetch();

    expect(rpc.calls, greaterThanOrEqualTo(3));

    final reports = output.lines.where((l) => l.contains('balance failed')).length;
    expect(reports, 1);
    expect(provider.error, contains('no chain source'));
  });

  test('a failed poll tells the listeners, and a good read clears the error', () async {
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.fetch();
    expect(provider.error, contains('no chain source'));
    expect(notified, 1);

    await provider.fetch();
    expect(notified, 1);

    rpc.served = true;
    await provider.fetch();
    expect(provider.error, isNull);
    expect(provider.balance, 2.0);
    expect(notified, 2);
  });
}
