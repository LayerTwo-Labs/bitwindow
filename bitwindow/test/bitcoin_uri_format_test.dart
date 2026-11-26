import 'package:bitwindow/utils/bitcoin_uri.dart';
import 'package:flutter_test/flutter_test.dart';

const _address = 'bcrt1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

void main() {
  test('a BIP21 amount has whole coins and no trailing zeros', () {
    expect(bip21Amount(1), '0.00000001');
    expect(bip21Amount(25000000), '0.25');
    expect(bip21Amount(100000000), '1');
    expect(bip21Amount(2100000000000000), '21000000');
    expect(bip21Amount(123456789), '1.23456789');
  });

  test('a request with no amount, label or message is the plain address', () {
    expect(BitcoinURI(address: _address, label: '', message: '').format(), _address);
  });

  test('a request holds the amount, the label and the message', () {
    expect(
      BitcoinURI(address: _address, amountSats: 25000000, label: 'Invoice 42', message: 'Thanks').format(),
      'bitcoin:$_address?amount=0.25&label=Invoice%2042&message=Thanks',
    );
  });

  test('a formatted request parses back to the same values', () {
    const label = 'Rent & fees = ₿ 🏠';
    const message = 'Line one\nline two?';
    final parsed = BitcoinURI.parse(
      BitcoinURI(address: _address, amountSats: 1, label: label, message: message).format(),
    );

    expect(parsed.address, _address);
    expect(parsed.amountSats, 1);
    expect(parsed.label, label);
    expect(parsed.message, message);
    expect(parsed.extraParams, isEmpty);
  });
}
