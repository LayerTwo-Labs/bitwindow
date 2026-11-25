import 'package:bitwindow/pages/wallet/denability_page.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _FakeTransactionProvider extends ChangeNotifier implements TransactionProvider {
  int fetches = 0;

  @override
  Future<void> fetch() async => fetches++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FailingBitwindowd extends MockBitwindowdAPI {
  bool fail = true;

  @override
  Future<void> resumeDenial(Int64 id) async {
    if (fail) {
      throw StateError('denial not found, or not paused');
    }
  }
}

class _FailingAPI extends MockAPI {
  _FailingAPI() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final failing = _FailingBitwindowd();

  @override
  BitwindowAPI get bitwindowd => failing;
}

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

  group('DeniabilityViewModel', () {
    late _FailingAPI api;
    late _FakeTransactionProvider provider;

    setUp(() async {
      await GetIt.I.reset();
      api = _FailingAPI();
      provider = _FakeTransactionProvider();
      GetIt.I.registerSingleton<BitwindowRPC>(api);
      GetIt.I.registerSingleton<TransactionProvider>(provider);
      await registerTestDependencies();
    });

    tearDown(() => GetIt.I.reset());

    test('a failed resume keeps its error and reads the list again', () async {
      final model = DeniabilityViewModel();
      addTearDown(model.dispose);
      var notified = 0;
      model.addListener(() => notified++);

      await model.resumeDenial(Int64(3));

      expect(model.actionError, contains('denial not found, or not paused'));
      expect(provider.fetches, 1);
      expect(notified, greaterThan(0));
    });

    test('the next good action clears the error', () async {
      final model = DeniabilityViewModel();
      addTearDown(model.dispose);
      await model.resumeDenial(Int64(3));

      api.failing.fail = false;
      await model.resumeDenial(Int64(3));

      expect(model.actionError, isNull);
    });
  });
}
