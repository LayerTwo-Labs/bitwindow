import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/orchestrator/v1/orchestrator.pb.dart' as orch_pb;

class _FakeOrchestratorRPC extends OrchestratorRPC {
  _FakeOrchestratorRPC() : super(host: '127.0.0.1', port: 1);

  @override
  Future<orch_pb.GatherFilesToDeleteResponse> gatherFilesToDelete(List<orch_pb.SingleDeletion> items) async {
    return orch_pb.GatherFilesToDeleteResponse(
      files: [
        for (var i = 0; i < 30; i++) orch_pb.ResetFileInfo(path: '/data/node/dir$i/file$i.log'),
      ],
    );
  }
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestratorRPC());
  });

  tearDown(() async => GetIt.I.reset());

  testWidgets('a long path list keeps Cancel and Delete under the list at 1200x600', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter),
          child: ResetConfirmationPage(
            request: const [],
            appDir: Directory.systemTemp,
            binaryProvider: BinaryProvider.test(appDir: Directory.systemTemp, binaries: [BitcoinCore()]),
            log: Logger(level: Level.off),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.getRect(
      find.ancestor(of: find.byType(PathTreeView), matching: find.byType(SingleChildScrollView)).first,
    );
    final cancel = tester.getRect(find.byType(SailButton).first);
    final delete = tester.getRect(find.byType(SailButton).last);

    expect(cancel.top, greaterThanOrEqualTo(list.bottom));
    expect(delete.top, greaterThanOrEqualTo(list.bottom));
    expect(delete.bottom, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });
}
