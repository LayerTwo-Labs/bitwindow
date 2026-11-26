import 'package:sidechain_core/bitcoin.dart';

final _bip21AmountPattern = RegExp(r'^\d+(\.\d{0,8})?$|^\.\d{1,8}$');
final _addressPattern = RegExp(r'^[A-Za-z0-9]+$');

String _decode(String text) {
  try {
    return Uri.decodeComponent(text);
  } on ArgumentError {
    throw const FormatException('Invalid percent encoding');
  }
}

/// [sats] as a BIP-0021 amount: whole coins, with no trailing zeros.
String bip21Amount(int sats) {
  final whole = sats ~/ 100000000;
  final fraction = (sats % 100000000).toString().padLeft(8, '0').replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

class BitcoinURI {
  final String address;
  final double? amount;
  final String? label;
  final String? message;
  final Map<String, String> extraParams;
  final int? amountSats;

  BitcoinURI({
    required this.address,
    this.amount,
    this.amountSats,
    this.label,
    this.message,
    Map<String, String>? extraParams,
  }) : extraParams = extraParams ?? {};

  /// Parses a Bitcoin URI string according to BIP-0021
  /// Throws FormatException if URI is invalid
  static BitcoinURI parse(String text) {
    var uri = text.trim();
    if (!uri.toLowerCase().startsWith('bitcoin:')) {
      throw const FormatException('Not a bitcoin URI');
    }
    // Some wallets write the scheme as a web link.
    if (uri.startsWith('//', 8)) {
      uri = uri.replaceRange(8, 10, '');
    }

    final queryStart = uri.indexOf('?', 8);
    final address = uri.substring(8, queryStart == -1 ? null : queryStart);
    if (address.isEmpty) {
      throw const FormatException('No address specified');
    }
    if (!_addressPattern.hasMatch(address)) {
      throw const FormatException('Invalid address');
    }

    final params = <String, String>{};
    if (queryStart != -1) {
      for (final param in uri.substring(queryStart + 1).split('&')) {
        final separator = param.indexOf('=');
        if (separator == -1) {
          continue;
        }

        final key = param.substring(0, separator);
        if (key.startsWith('req-')) {
          throw FormatException('Required parameter not understood: $key');
        }

        params[_decode(key)] = _decode(param.substring(separator + 1));
      }
    }

    // Parse amount if present
    double? amount;
    int? amountSats;
    if (params.containsKey('amount')) {
      final amountText = params['amount']!;
      if (!_bip21AmountPattern.hasMatch(amountText)) {
        throw const FormatException('Invalid amount format');
      }
      amountSats = parseAmountToSatoshis(amountText, BitcoinUnit.btc);
      amount = satoshiToBTC(amountSats);
    }

    return BitcoinURI(
      address: address,
      amount: amount,
      amountSats: amountSats,
      label: params['label'],
      message: params['message'],
      extraParams: params
        ..removeWhere(
          (key, _) => ['amount', 'label', 'message'].contains(key),
        ),
    );
  }

  /// The BIP-0021 URI for this request. A request with no amount, label or message is the plain address.
  String format() {
    final params = [
      if (amountSats != null) 'amount=${bip21Amount(amountSats!)}',
      if (label?.isNotEmpty ?? false) 'label=${Uri.encodeComponent(label!)}',
      if (message?.isNotEmpty ?? false) 'message=${Uri.encodeComponent(message!)}',
    ];
    return params.isEmpty ? address : 'bitcoin:$address?${params.join('&')}';
  }

  /// Validates if a string could be a valid Bitcoin URI
  static bool isValidURI(String uri) {
    try {
      parse(uri);
      return true;
    } catch (_) {
      return false;
    }
  }
}
