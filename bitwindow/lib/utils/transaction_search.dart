import 'package:bitwindow/utils/wallet_amount.dart';
import 'package:sidechain_core/bitcoin.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

final RegExp _searchNoise = RegExp(r'[\s,+]');

String normalizeSearchText(String text) => text.toLowerCase().replaceAll(_searchNoise, '');

/// True if the query matches the txid, an address, the net amount or a payment amount of the transaction.
bool transactionMatchesSearch(WalletTransaction tx, String query) {
  final needle = normalizeSearchText(query);
  if (needle.isEmpty) {
    return true;
  }

  final net = walletNetSats(tx);
  final payment = (tx.receivedSatoshi - tx.sentSatoshi).toInt();

  final fields = [
    tx.txid,
    ...transactionAddresses(tx),
    for (final satoshi in {net, payment, ...tx.payments.map((p) => p.amountSats.toInt())}) ...[
      satoshi.toString(),
      satoshiToBTC(satoshi).toStringAsFixed(8),
    ],
  ];

  return fields.any((field) => normalizeSearchText(field).contains(needle));
}
