import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/gen/orchestrator/v1/orchestrator.pb.dart';
import 'package:sidechain_core/providers/binaries/app_run_host.dart';

class _Runner implements AppRunner {
  final List<String> starts = [];
  int stops = 0;
  bool running = false;
  String? error;
  Object? startError;

  Completer<void>? gate;

  @override
  Future<void> start(List<String> args, String logPath) async {
    if (startError != null) {
      throw startError!;
    }
    await gate?.future;
    starts.add('${args.join(' ')} > $logPath');
    running = true;
    error = null;
  }

  @override
  void stop() => stops++;

  @override
  AppRunnerStatus status() => AppRunnerStatus(running: running, error: error);
}

void main() {
  late _Runner thunder;
  late List<(String, String)> reports;
  late bool reportFails;
  late AppRunHost host;

  setUp(() {
    thunder = _Runner();
    reports = [];
    reportFails = false;
    host = AppRunHost(
      {'thunder': thunder},
      reportExit: (id, error) async {
        if (reportFails) {
          throw StateError('the backend is down');
        }
        reports.add((id, error));
      },
      log: Logger(level: Level.off),
    );
  });

  AppRun run(String id, {String name = 'thunder', bool stop = false}) =>
      AppRun(id: id, name: name, args: ['--headless'], logPath: '/logs/thunder.log', stop: stop);

  test('a run starts, stops on request and reports its exit one time', () async {
    await host.apply([run('r1')]);
    expect(thunder.starts, ['--headless > /logs/thunder.log']);

    await host.apply([run('r1', stop: true)]);
    await host.apply([run('r1', stop: true)]);
    expect(thunder.stops, 1);

    thunder.running = false;
    thunder.error = 'the node panicked';
    await host.check();
    expect(reports, [('r1', 'the node panicked')]);

    // A frame from before the orchestrator got the exit must not start the run again.
    await host.apply([run('r1', stop: true)]);
    await host.check();
    expect(thunder.starts, hasLength(1));
    expect(reports, hasLength(1));
  });

  test('the host names the binaries it runs', () {
    expect(host.hosts('thunder'), isTrue);
    expect(host.hosts('bitnames'), isFalse);
  });

  test('a run of an unknown binary or a failed start reports an error', () async {
    await host.apply([run('r1', name: 'bitnames')]);
    expect(reports, [('r1', 'the app has no runner for bitnames')]);

    thunder.startError = StateError('no datadir');
    await host.apply([run('r2')]);
    expect(reports.last.$1, 'r2');
    expect(reports.last.$2, contains('no datadir'));
  });

  test('a run that the orchestrator forgot stops, and the new run starts after it', () async {
    await host.apply([run('old')]);
    await host.apply([run('new')]);
    expect(thunder.stops, 1, reason: 'the old run stops');
    expect(thunder.starts, hasLength(1), reason: 'the runner holds the old run');

    thunder.running = false;
    await host.check();
    expect(thunder.starts, hasLength(2));
    expect(reports, [('old', '')]);
  });

  test('a failed report goes again on the next check', () async {
    await host.apply([run('r1')]);
    thunder.running = false;
    reportFails = true;
    await host.check();
    expect(reports, isEmpty);

    reportFails = false;
    await host.check();
    expect(reports, [('r1', '')]);
    await host.check();
    expect(reports, hasLength(1));
  });

  test('a check queued behind a slow start applies the newest list, not the one it saw', () async {
    thunder.gate = Completer<void>();
    final first = host.apply([run('r1')]);
    await Future<void>.delayed(Duration.zero);

    // The orchestrator starts again and replaces r1 with r2 while r1 still starts.
    final second = host.apply([run('r2')]);
    final check = host.check();
    thunder.gate!.complete();
    thunder.gate = null;
    await Future.wait([first, second, check]);

    // r1 holds the runner, so the newest list stops it. r2 starts after r1 ends.
    expect(thunder.stops, 1);
    thunder.running = false;
    await host.check();
    expect(thunder.starts, hasLength(2));
    await host.check();
    expect(thunder.stops, 1, reason: 'no step stops r2 for a list that names only r1');
    expect(reports.where((r) => r.$1 == 'r2'), isEmpty);
  });
}
