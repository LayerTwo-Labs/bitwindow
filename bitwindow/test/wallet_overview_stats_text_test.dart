import 'package:fixnum/fixnum.dart';
import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

void main() {
  final seen = Timestamp(seconds: Int64(1795699190));

  test('the last activity of an unconfirmed transaction says Unconfirmed', () {
    expect(lastActivitySubtitle(GetStatsResponse(lastTxAt: seen)), 'Unconfirmed');
  });

  test('the last activity of a confirmed transaction names its block', () {
    expect(lastActivitySubtitle(GetStatsResponse(lastTxAt: seen, lastTxBlockHeight: 948112)), 'at block 948 112');
  });

  test('a wallet with no transaction has no last activity subtitle', () {
    expect(lastActivitySubtitle(GetStatsResponse()), '');
    expect(lastActivitySubtitle(null), '');
  });

  test('the fees subtitle counts one transaction in the singular', () {
    expect(feesSubtitle(null), 'across 0 transactions');
    expect(feesSubtitle(GetStatsResponse(feeTransactionCount: Int64(1))), 'across 1 transaction');
    expect(feesSubtitle(GetStatsResponse(feeTransactionCount: Int64(14))), 'across 14 transactions');
  });

  test('the fees subtitle counts only the transactions with a paid fee', () {
    final stats = GetStatsResponse(transactionCountTotal: Int64(102), feeTransactionCount: Int64(0));
    expect(feesSubtitle(stats), 'across 0 transactions');
  });
}
