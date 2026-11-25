import 'package:bitwindow/pages/wallet/denability_page.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

void main() {
  final time = Timestamp.fromDateTime(DateTime.utc(2030));

  group('denialStatus', () {
    test('a paused denial is paused in the Deniability tab and in the UTXO tab', () {
      final utxo = UnspentOutput(
        denialInfo: DenialInfo(id: Int64(1), numHops: 3, pausedAt: time),
      );

      expect(denialStatus(utxo), DenialStatus.paused);
      expect(denialStatusWithHops(utxo), 'Paused (0/3)');
      expect(denialCanControl(utxo), isTrue);
    });

    test('reads each state of a denial', () {
      final ongoing = UnspentOutput(denialInfo: DenialInfo(numHops: 3, hopsCompleted: 1, nextExecutionTime: time));
      final completed = UnspentOutput(denialInfo: DenialInfo(numHops: 3, hopsCompleted: 3));
      final cancelled = UnspentOutput(denialInfo: DenialInfo(numHops: 3, hopsCompleted: 1, cancelTime: time));

      expect(denialStatus(UnspentOutput()), DenialStatus.none);
      expect(denialStatusWithHops(UnspentOutput()), '-');
      expect(denialStatusWithHops(ongoing), 'Active (1/3)');
      expect(denialStatusWithHops(completed), 'Done (3)');
      expect(denialStatusWithHops(cancelled), 'Cancelled (1)');
      expect(denialCanControl(ongoing), isTrue);
      expect(denialCanControl(completed), isFalse);
      expect(denialCanControl(cancelled), isFalse);
    });

    test('the change of a hop gives no control of the denial', () {
      final change = UnspentOutput(
        denialInfo: DenialInfo(numHops: 1, hopsCompleted: 1, pausedAt: time, isChange: true),
      );

      expect(denialCanControl(change), isFalse);
    });

    test('the change of a hop stays done after a pause or a cancel of the denial', () {
      final paused = UnspentOutput(
        denialInfo: DenialInfo(numHops: 1, hopsCompleted: 1, pausedAt: time, isChange: true),
      );
      final cancelled = UnspentOutput(
        denialInfo: DenialInfo(numHops: 1, hopsCompleted: 1, cancelTime: time, isChange: true),
      );

      expect(denialStatusWithHops(paused), 'Done (1)');
      expect(denialStatusWithHops(cancelled), 'Done (1)');
    });
  });
}
