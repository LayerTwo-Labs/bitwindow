import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:bitwindow/widgets/import_txid_modal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

const _txid = 'AB12000000000000000000000000000000000000000000000000000000000000';

class _Misc extends MockMiscAPI {
  final requests = <ListOPReturnRequest>[];

  @override
  Future<List<OPReturn>> listOPReturns(ListOPReturnRequest request) async {
    requests.add(request);
    return request.search == _txid ? [OPReturn(txid: _txid.toLowerCase(), message: 'not a group')] : [];
  }
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? get activeWalletId => 'qa';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _API extends MockAPI {
  _API(this._misc) : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _Misc _misc;

  @override
  _Misc get misc => _misc;
}

void main() {
  late _Misc misc;

  setUp(() async {
    await GetIt.I.reset();
    misc = _Misc();
    GetIt.I.registerLazySingleton<BitwindowRPC>(() => _API(misc));
    await registerTestDependencies();
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<HDWalletProvider>(HDWalletProvider());
  });
  tearDown(() => GetIt.I.reset());

  testWidgets('the import asks the server for its own txid', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final vm = ImportTxidModalViewModel()..txidController.text = _txid;
    addTearDown(vm.dispose);

    await vm.importFromTxid(context);

    expect(misc.requests.single.search, _txid);
    expect(vm.modalError, 'Invalid OP_RETURN format - not a BitDrive transaction', reason: 'the lookup found the tx');
  });
}
