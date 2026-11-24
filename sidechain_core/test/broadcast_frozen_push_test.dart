import 'dart:typed_data';

import 'package:connectrpc/connect.dart';
import 'package:connectrpc/protobuf.dart';
import 'package:connectrpc/protocol/connect.dart' as connect;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;
import 'package:sidechain_core/sidechain_core.dart';

void main() {
  test('a broadcast hands over the frozen coins first', () async {
    final calls = <(String, List<int>)>[];
    Future<HttpResponse> httpClient(HttpRequest req) async {
      final body = <int>[];
      await for (final chunk in req.body ?? const Stream<Uint8List>.empty()) {
        body.addAll(chunk);
      }
      final method = req.url.split('/').last;
      calls.add((method, body));
      final GeneratedMessage answer = method == 'BroadcastTransaction'
          ? (wmpb.BroadcastTransactionResponse()..txid = 'txid')
          : Empty();
      return HttpResponse(
        200,
        Headers()..add('content-type', 'application/proto'),
        Stream.value(answer.writeToBuffer()),
        Headers(),
      );
    }

    final transport = connect.Transport(baseUrl: 'http://wallet', codec: const ProtoCodec(), httpClient: httpClient);
    final wallet = OrchestratorWalletRPC.fromTransports(unary: transport, stream: transport)
      ..frozenCoins = () async => ['aa:1'];

    final txid = await wallet.broadcastTransaction(walletId: 'w1', txHex: 'beef');

    expect(txid, 'txid');
    expect(calls.map((c) => c.$1), ['SetFrozenCoins', 'BroadcastTransaction']);
    final frozen = wmpb.SetFrozenCoinsRequest.fromBuffer(calls.first.$2);
    expect(frozen.outpoints.single.txid, 'aa');
    expect(frozen.outpoints.single.vout, 1);
    final broadcast = wmpb.BroadcastTransactionRequest.fromBuffer(calls.last.$2);
    expect(broadcast.walletId, 'w1');
    expect(broadcast.txHex, 'beef');
  });
}
