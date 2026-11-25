import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

final _deposit = 'd' * 64;
final _payment = 'e' * 64;

wmpb.TransactionEntry _entry(
  String txid,
  int vout,
  int amountSats, {
  double fee = 0,
  String address = '',
  int confirmations = 1,
}) => wmpb.TransactionEntry(
  txid: txid,
  vout: vout,
  address: address,
  category: amountSats < 0 ? 'send' : 'receive',
  amountSats: Int64(amountSats),
  fee: fee,
  confirmations: confirmations,
  blockTime: Int64(1700000000),
);

void main() {
  test('a deposit with two outputs gives one row', () {
    final deposit = wmpb.SidechainDeposit(txid: _deposit, slot: 9, destination: 'QAdeposit1');
    final rows = walletTransactionsFromEntries([
      _entry(_deposit, 0, -150000000, fee: -0.00000374)..sidechainDeposit = deposit,
      _entry(_deposit, 1, 0, fee: -0.00000374)..sidechainDeposit = deposit,
    ], {});

    expect(rows, hasLength(1));
    expect(rows.single.sentSatoshi, Int64(150000000));
    expect(rows.single.receivedSatoshi, Int64.ZERO);
    expect(rows.single.feeSats, Int64(374));
    expect(rows.single.address, 'QAdeposit1');
    expect(rows.single.depositRequest.slot, 9);
  });

  test('a payment to two addresses gives one row with the sum', () {
    final rows = walletTransactionsFromEntries(
      [
        _entry(_payment, 0, -1000, fee: -0.00000200, address: 'first'),
        _entry(_payment, 1, -2000, fee: -0.00000200, address: 'second'),
      ],
      {_payment: 'rent'},
    );

    expect(rows, hasLength(1));
    expect(rows.single.sentSatoshi, Int64(3000));
    expect(rows.single.feeSats, Int64(200));
    expect(rows.single.address, 'second');
    expect(rows.single.payments.map((p) => (p.address, p.amountSats.toInt())), [('second', 2000), ('first', 1000)]);
    expect(rows.single.note, 'rent');
  });

  test('a send names what it pays to others, not its own outputs', () {
    final rows = walletTransactionsFromEntries([
      _entry(_payment, 2, -20000, fee: -0.00000344, address: 'own'),
      _entry(_payment, 2, 20000, address: 'own')..label = 'savings',
      _entry(_payment, 1, -10000, fee: -0.00000344, address: 'shop'),
    ], {});

    expect(rows.single.address, 'shop');
    expect(rows.single.addressLabel, '');
    expect(rows.single.payments.map((p) => p.address), ['shop']);
    expect(rows.single.sentSatoshi - rows.single.receivedSatoshi, Int64(10000));
  });

  test('a transfer inside the wallet names its own output', () {
    final rows = walletTransactionsFromEntries([
      _entry(_payment, 1, -50000000, fee: -0.00000282, address: 'own'),
      _entry(_payment, 1, 50000000, address: 'own')..label = 'savings',
    ], {});

    expect(rows.single.address, 'own');
    expect(rows.single.addressLabel, 'savings');
    expect(rows.single.payments.single.amountSats, Int64(50000000));
  });

  test('a payment to two wallet addresses names both', () {
    final rows = walletTransactionsFromEntries([
      _entry(_payment, 0, 10000000, address: 'first'),
      _entry(_payment, 1, 20000000, address: 'second'),
    ], {});

    expect(rows.single.receivedSatoshi, Int64(30000000));
    expect(rows.single.payments.map((p) => p.address), ['second', 'first']);
  });

  test('an output with no address is no payment', () {
    final rows = walletTransactionsFromEntries([_entry(_payment, 0, 0, fee: -0.00000200)..category = 'send'], {});

    expect(rows.single.address, '');
    expect(rows.single.payments, isEmpty);
    expect(rows.single.feeSats, Int64(200));
  });

  test('a transaction the wallet abandoned gives an abandoned row', () {
    final rows = walletTransactionsFromEntries([
      _entry(_payment, 0, -1000, fee: -0.00000200, confirmations: 0),
      _entry(_payment, 1, -2000, fee: -0.00000200, confirmations: 0)..abandoned = true,
      _entry(_deposit, 0, 5000, confirmations: 0),
    ], {});

    expect({for (final tx in rows) tx.txid: tx.abandoned}, {_payment: true, _deposit: false});
  });

  test('each txid keeps its own row', () {
    final rows = walletTransactionsFromEntries([
      _entry(_deposit, 0, 5000),
      _entry(_payment, 0, -1000),
    ], {});

    expect(rows.map((tx) => tx.txid), unorderedEquals([_deposit, _payment]));
  });

  test('blocks of one second list the newest block first', () {
    final rows = walletTransactionsFromEntries([
      _entry('a' * 64, 0, 5000, confirmations: 3),
      _entry('b' * 64, 0, 5000, confirmations: 1),
      _entry('c' * 64, 0, 5000, confirmations: 2),
    ], {});

    expect(rows.map((tx) => tx.confirmations), [1, 2, 3]);
  });

  test('a row gives the block height and the confirmations apart', () {
    final rows = walletTransactionsFromEntries([_entry(_payment, 0, 5000, confirmations: 3)..blockHeight = 102], {});

    expect(rows.single.confirmationTime.height, 102);
    expect(rows.single.confirmations, 3);
  });

  test('a failed parallel read names the read that failed', () async {
    Object? caught;
    try {
      await (Future<int>.value(1), Future<int>.error(Exception('connection refused'))).wait;
    } catch (e) {
      caught = e;
    }

    expect(readFailure(caught!).toString(), 'Exception: connection refused');
    expect(readFailure(StateError('down')).toString(), 'Bad state: down');
  });
}
