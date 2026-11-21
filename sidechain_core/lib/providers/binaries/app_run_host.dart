import 'dart:async';

import 'package:connectrpc/connect.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/gen/orchestrator/v1/orchestrator.pb.dart';
import 'package:sidechain_core/rpcs/orchestrator_rpc.dart';
import 'package:sidechain_core/rpcs/stream_supervisor.dart';

/// The state that [AppRunner.status] reports.
class AppRunnerStatus {
  final bool running;

  /// The error that ended the last run, or null.
  final String? error;

  const AppRunnerStatus({required this.running, this.error});
}

/// Runs one binary in the app process.
abstract interface class AppRunner {
  /// Starts the binary with the command line flags [args]. The binary writes its log lines to [logPath].
  Future<void> start(List<String> args, String logPath);

  /// Asks the binary to stop. [status] reports when it is gone.
  void stop();

  AppRunnerStatus status();
}

class _Live {
  final AppRunner runner;
  bool stopping = false;

  _Live(this.runner);
}

/// Runs the binaries that the orchestrator gives to the app, and reports each exit.
/// A phone cannot start a child process, so the orchestrator cannot start them.
class AppRunHost {
  final Map<String, AppRunner> _runners;
  final Future<void> Function(String id, String error) _reportExit;
  final Logger _log;

  /// How often a live run gets checked for its exit.
  final Duration pollEvery;

  final Map<String, _Live> _live = {};
  List<AppRun> _runs = const [];

  /// Exits that the orchestrator did not get yet, by run id.
  final Map<String, String> _unreported = {};

  /// The runs that ended. A frame can still list one before the orchestrator gets its exit.
  final Set<String> _ended = {};
  Future<void> _applying = Future.value();
  Timer? _poll;
  StreamSupervisor<WatchAppRunsResponse>? _supervisor;

  AppRunHost(
    this._runners, {
    required this._reportExit,
    required this._log,
    this.pollEvery = const Duration(seconds: 1),
  });

  /// True when the app runs the binary [name] of the orchestrator in its own process.
  bool hosts(String name) => _runners.containsKey(name);

  /// Watches the runs of [orchestrator] until [dispose].
  void watch(OrchestratorRPC orchestrator) {
    _supervisor = StreamSupervisor<WatchAppRunsResponse>(
      subscribe: orchestrator.watchAppRuns,
      onEvent: (frame) {
        if (!frame.heartbeat) {
          unawaited(apply(frame.runs));
        }
      },
      onTransportDeath: orchestrator.recreateConnection,
      logger: _log,
      tag: 'AppRunHost',
    )..start();
    _poll ??= Timer.periodic(pollEvery, (_) => unawaited(check()));
  }

  /// Makes the live runs match [runs]: the full list of runs that the orchestrator holds.
  Future<void> apply(List<AppRun> runs) {
    _runs = runs;
    return _reconcile();
  }

  // Each step reads the newest list when it runs, so a step queued behind a slow start never applies an old list.
  Future<void> _reconcile() {
    _applying = _applying.then((_) => _apply(_runs));
    return _applying;
  }

  Future<void> _apply(List<AppRun> runs) async {
    final ids = {for (final run in runs) run.id};
    for (final id in _live.keys.toList()) {
      if (ids.contains(id)) {
        continue;
      }
      // An orchestrator that started again does not know the run, so nobody else stops it.
      final live = _live[id]!;
      if (!live.stopping) {
        _log.w('AppRunHost: the orchestrator does not know run $id, stopping it');
        live.stopping = true;
        live.runner.stop();
      }
    }
    for (final run in runs) {
      final live = _live[run.id];
      if (live != null) {
        if (run.stop && !live.stopping) {
          _log.i('AppRunHost: stopping ${run.name} (run ${run.id})');
          live.stopping = true;
          live.runner.stop();
        }
        continue;
      }
      if (_ended.contains(run.id)) {
        continue;
      }
      if (run.stop) {
        await _report(run.id, '');
        continue;
      }
      final runner = _runners[run.name];
      if (runner == null) {
        await _report(run.id, 'the app has no runner for ${run.name}');
        continue;
      }
      if (_live.values.any((live) => identical(live.runner, runner))) {
        // The run that the orchestrator forgot holds the runner. A check starts this one after it ends.
        continue;
      }
      _log.i('AppRunHost: starting ${run.name} (run ${run.id})');
      try {
        await runner.start(List.of(run.args), run.logPath);
      } catch (error) {
        await _report(run.id, 'could not start ${run.name}: $error');
        continue;
      }
      _live[run.id] = _Live(runner);
    }
  }

  /// Reports the runs that ended, and sends again each exit that the orchestrator did not get.
  Future<void> check() async {
    for (final entry in _live.entries.toList()) {
      final status = entry.value.runner.status();
      if (status.running) {
        continue;
      }
      _live.remove(entry.key);
      _ended.add(entry.key);
      _unreported[entry.key] = status.error ?? '';
    }
    for (final entry in _unreported.entries.toList()) {
      await _report(entry.key, entry.value);
    }
    await _reconcile();
  }

  Future<void> _report(String id, String error) async {
    _ended.add(id);
    _unreported[id] = error;
    try {
      await _reportExit(id, error);
    } on ConnectException catch (err) {
      if (err.code != Code.notFound) {
        _log.e('AppRunHost: could not report the exit of run $id: $err');
        return;
      }
      // An orchestrator that started again does not know the run.
    } catch (err) {
      // The next check sends it again: the orchestrator holds the binary as live until it gets the exit.
      _log.e('AppRunHost: could not report the exit of run $id: $err');
      return;
    }
    _unreported.remove(id);
  }

  Future<void> dispose() async {
    _poll?.cancel();
    _poll = null;
    await _supervisor?.dispose();
    _supervisor = null;
  }
}
