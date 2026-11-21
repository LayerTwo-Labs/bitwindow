import 'package:sidechain_core/providers/binaries/app_run_host.dart';
import 'package:thunder_bridge/thunder_bridge.dart' as bridge;

/// The Thunder node in the app process. A phone cannot start it as a child process.
class ThunderInApp implements AppRunner {
  @override
  Future<void> start(List<String> args, String logPath) async {
    await bridge.loadThunderBridge();
    await bridge.startNode(args: args, logPath: logPath);
  }

  @override
  void stop() => bridge.stopNode();

  @override
  AppRunnerStatus status() {
    final status = bridge.nodeStatus();
    return AppRunnerStatus(running: status.running, error: status.error);
  }
}
