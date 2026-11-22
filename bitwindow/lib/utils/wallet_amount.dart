import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

/// The change in the wallet balance from [tx], in sats. A fee counts only
/// when this wallet paid it.
int walletNetSats(WalletTransaction tx) => (tx.receivedSatoshi - tx.sentSatoshi - tx.feeSats).toInt();
