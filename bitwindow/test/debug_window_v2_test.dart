import 'package:bitwindow/pages/debug_window.dart';
import 'package:connectrpc/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/bitcoin/bitcoind/v1alpha/bitcoin.connect.client.dart';
import 'package:sidechain_core/gen/bitcoin/bitcoind/v1alpha/bitcoin.connect.spec.dart';
import 'package:sidechain_core/gen/bitcoin/bitcoind/v1alpha/bitcoin.pb.dart';

import 'test_utils.dart';

class _Orchestrator implements OrchestratorRPC {
  @override
  final BitcoinServiceClient bitcoind = BitcoinServiceClient(
    FakeTransportBuilder()
        .unary(BitcoinService.getNetworkInfo, (_, _) => GetNetworkInfoResponse(networkActive: true))
        .unary(
          BitcoinService.getPeerInfo,
          (_, _) => GetPeerInfoResponse(
            peers: [
              Peer(id: 0, addr: '95.217.41.12:8333', version: 70016),
              Peer(id: 1, addr: '185.25.48.184:8333', version: 70016),
            ],
          ),
        )
        .build(),
  );

  @override
  Future<GetMainchainBlockchainInfoResponse> getMainchainBlockchainInfo() async =>
      GetMainchainBlockchainInfoResponse(chain: 'regtest');

  @override
  Future<GetCoreMempoolInfoResponse> getCoreMempoolInfo() async => GetCoreMempoolInfoResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String ecashNetworkId = '';

  @override
  String? get detectedDataDir => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the information tab shows each section as a grey group', (tester) async {
    await tester.pumpSailPage(const InformationTab());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SailDetailGroup), findsNWidgets(4));
    for (final title in ['General Info', 'Network Info', 'Blockchain Info', 'Mempool Info']) {
      expect(find.widgetWithText(SailDetailHeading, title), findsOneWidget);
    }
    final label = tester.getRect(find.text('Chain'));
    final value = tester.getRect(find.text('regtest'));
    expect(value.center.dy, closeTo(label.center.dy, 1));
    expect(value.left, greaterThan(label.right));
  });

  testWidgets('a click on a peer opens Peer Details as a side panel with a ×', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpSailPage(const PeersTab());
    await tester.pumpAndSettle();

    expect(find.byType(SailSidePanel), findsNothing);
    await tester.tap(find.text('185.25.48.184:8333'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final panel = find.byType(SailSidePanel);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, SailSidePanel.width);
    expect(find.descendant(of: panel, matching: find.text('Peer Details')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailDetailHeading, 'Traffic')), findsOneWidget);

    await tester.tap(find.descendant(of: panel, matching: find.byType(SailIconBoxButton)));
    await tester.pumpAndSettle();
    expect(find.byType(SailSidePanel), findsNothing);
  });
}
