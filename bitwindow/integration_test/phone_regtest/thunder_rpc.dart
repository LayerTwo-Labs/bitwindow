import 'dart:convert';
import 'dart:io';

/// The JSON-RPC of the Thunder node that the app runs. The test reads the chain state through it.
class ThunderRpc {
  final Uri url;

  ThunderRpc(this.url);

  /// The URL from `--dart-define=PHONE_THUNDER_RPC_URL`.
  factory ThunderRpc.fromDefine() {
    const url = String.fromEnvironment('PHONE_THUNDER_RPC_URL');
    if (url.isEmpty) {
      throw StateError('give --dart-define=PHONE_THUNDER_RPC_URL, the RPC of the Thunder node in the app');
    }
    return ThunderRpc(Uri.parse(url));
  }

  Future<dynamic> call(String method, [List<Object?> params = const []]) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}));
      final response = await request.close();
      final body = jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      if (body['error'] != null) {
        throw StateError('$method: ${body['error']}');
      }
      return body['result'];
    } finally {
      client.close();
    }
  }

  /// The spendable sats of the wallet.
  Future<int> availableSats() async => ((await call('balance')) as Map<String, dynamic>)['available_sats'] as int;

  Future<int> blockCount() async => (await call('getblockcount')) as int;

  Future<String> newAddress() async => (await call('get_new_address')) as String;
}
