import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

WalletTransaction _tx(String address, {String label = '', int confirmations = 2, int height = 102}) =>
    WalletTransaction(
      txid: 'a' * 64,
      address: address,
      addressLabel: label,
      receivedSatoshi: Int64(40000000),
      confirmations: confirmations,
      confirmationTime: Confirmation(
        height: confirmations == 0 ? 0 : height,
        timestamp: Timestamp(seconds: Int64(1)),
      ),
    );

void main() {
  test('the CSV gives the block height, not the confirmations', () {
    final csv = transactionsCsv([_tx('bcrt1qown'), _tx('bcrt1qown', confirmations: 0)]).split('\r\n');

    expect(csv.first.split(',').last, 'Block Height');
    expect(csv[1].split(',').last, '102');
    expect(csv[2].split(',').last, '');
  });

  test('the status reads the confirmations, not the block height', () {
    final maturing = _tx('bcrt1qown', confirmations: 7, height: 300)..immature = true;

    expect(transactionStatus(maturing), 'Maturing (7/100)');
    expect(transactionStatus(_tx('bcrt1qown', confirmations: 0)), 'Unconfirmed');
    expect(canBumpFee(_tx('bcrt1qown', confirmations: 0)), isTrue);
    expect(canBumpFee(_tx('bcrt1qown')), isFalse);
  });
}
