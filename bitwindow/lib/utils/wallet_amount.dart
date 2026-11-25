import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

/// The change in the wallet balance from [tx], in sats. A fee counts only
/// when this wallet paid it.
int walletNetSats(WalletTransaction tx) => (tx.receivedSatoshi - tx.sentSatoshi - tx.feeSats).toInt();

/// Every address of a history row, the shown one first.
List<String> transactionAddresses(WalletTransaction tx) => {
  if (tx.address.isNotEmpty) tx.address,
  for (final payment in tx.payments) payment.address,
}.toList();
