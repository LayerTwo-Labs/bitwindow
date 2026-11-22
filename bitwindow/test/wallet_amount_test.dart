import 'package:bitwindow/utils/wallet_amount.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

WalletTransaction _tx({int received = 0, int sent = 0, int fee = 0}) => WalletTransaction(
  txid: 'aa',
  receivedSatoshi: Int64(received),
  sentSatoshi: Int64(sent),
  feeSats: Int64(fee),
);

void main() {
  group('walletNetSats', () {
    test('a receive is the received amount', () {
      expect(walletNetSats(_tx(received: 150000000)), 150000000);
    });

    test('a send includes the fee', () {
      expect(walletNetSats(_tx(sent: 25000000, fee: 282)), -25000282);
    });

    test('a self send is minus the fee', () {
      expect(walletNetSats(_tx(received: 10000000, sent: 10000000, fee: 423)), -423);
    });
  });
}
