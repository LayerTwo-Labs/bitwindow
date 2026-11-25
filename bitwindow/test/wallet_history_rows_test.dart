import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sidechain_core/gen/bitwindowd/v1/bitwindowd.pb.dart';
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

AddressBookEntry _book(String label, String address, Direction direction) =>
    AddressBookEntry(id: Int64(1), label: label, address: address, direction: direction);

void main() {
  test('a history row shows the address book label of its address', () {
    final labels = labelsByAddress([
      _book('salary', 'bcrt1qown', Direction.DIRECTION_RECEIVE),
      _book('exchange', 'bcrt1qext', Direction.DIRECTION_SEND),
    ]);

    final rows = withBookLabels([_tx('bcrt1qown'), _tx('bcrt1qext'), _tx('bcrt1qnone', label: 'core')], labels);

    expect(rows.map((tx) => tx.addressLabel), ['salary', 'exchange', 'core']);
  });

  test('the first label of an address wins, and an empty label is no label', () {
    final labels = labelsByAddress([
      _book('', 'bcrt1qown', Direction.DIRECTION_RECEIVE),
      _book('salary', 'bcrt1qown', Direction.DIRECTION_RECEIVE),
      _book('other', 'bcrt1qown', Direction.DIRECTION_SEND),
    ]);

    expect(labels, {'bcrt1qown': 'salary'});
  });

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

  test('an abandoned transaction says so, and has no fee bump', () {
    final sent = _tx('bcrt1qext', confirmations: 0)
      ..receivedSatoshi = Int64.ZERO
      ..sentSatoshi = Int64(300000000)
      ..abandoned = true;
    final received = _tx('bcrt1qown', confirmations: 0)..abandoned = true;
    final lostBid = _tx('bcrt1qown', confirmations: 0)
      ..bmmBid = BmmBid(slot: 9, lost: true)
      ..abandoned = true;

    for (final tx in [sent, received, lostBid]) {
      expect(transactionStatus(tx), 'Abandoned');
      expect(canBumpFee(tx), isFalse);
      expect(canCancelBid(tx), isFalse);
      expect(canAccelerate(tx), isFalse);
    }
    expect(canAccelerate(_tx('bcrt1qown', confirmations: 0)), isTrue);
    expect(canAccelerate(_tx('bcrt1qown')), isFalse);
  });

  test('the CSV names an abandoned transaction', () {
    final csv = transactionsCsv([
      _tx('bcrt1qown', confirmations: 0)..abandoned = true,
      _tx('bcrt1qown', confirmations: 0),
    ]).split('\r\n');

    expect(csv[1].split(',')[2], 'Abandoned');
    expect(csv[2].split(',')[2], 'Received');
  });

  test('the address cell keeps 10 characters at each end, and the label', () {
    const address = 'bcrt1qhd4cfqjafyun28mpktu3te85pf9njwpu4v5jr5';

    expect(historyAddressText(_tx(address)), 'bcrt1qhd4c…jwpu4v5jr5');
    expect(historyAddressText(_tx(address, label: 'salary')), 'bcrt1qhd4c…jwpu4v5jr5 (salary)');
    expect(historyAddressText(_tx('short')), 'short');
  });
}
