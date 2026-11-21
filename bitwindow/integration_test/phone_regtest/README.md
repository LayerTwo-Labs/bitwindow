# Phone regtest test

`integration_test/phone_regtest_test.dart` drives BitWindow on a phone through
the hot paths: first start, new wallet, receive, send, confirm, UTXOs, side nav,
bump fee and cancel. The phone runs light mode against a regtest stack on the Mac.

1. Start the stack. It runs Bitcoin Core, the enforcer and an Esplora server
   with test routes. Build the enforcer at the commit that thunder pins in its
   `bip300301_enforcer` submodule: the Thunder test needs `ProposeWithdrawalBundle`.
   The enforcer mines the blocks of the test routes:

   ```sh
   cd bitwindow
   ENFORCER_BIN=<path to bip300301_enforcer> scripts/phone-regtest.sh start
   ```

   The deposit step needs an active sidechain in slot 9:

   ```sh
   scripts/phone-regtest.sh activate 9 Thunder
   ```

2. Build the backend library for regtest:

   ```sh
   BITWINDOW_DEFAULT_NETWORK=regtest just ios-backend      # or android-backend
   ```

3. Remove the app from the device, so the test starts with no wallet.

4. Run the test. iOS reaches the Mac at 127.0.0.1, so give a port offset that
   no other BitWindow uses. Android reaches it at 10.0.2.2:

   ```sh
   PHONE_QA_SHOTS=/tmp/phone-qa/ios flutter drive -d <simulator> \
     --driver test_driver/phone_regtest_driver.dart \
     --target integration_test/phone_regtest_test.dart \
     --dart-define=BITWINDOW_PORT_OFFSET=5200 $(scripts/phone-regtest.sh defines ios)

   PHONE_QA_SHOTS=/tmp/phone-qa/android flutter drive -d <emulator> \
     --driver test_driver/phone_regtest_driver.dart \
     --target integration_test/phone_regtest_test.dart \
     $(scripts/phone-regtest.sh defines android)
   ```

`integration_test/phone_peer_test.dart` runs two phones on one stack: Android also uses
`scripts/phone-regtest.sh defines android` of the iOS stack. Run it three times, in order, with
`--dart-define=PHONE_QA_ROLE=first` (iOS, fresh install, `--keep-app-running`), `second` (Android,
fresh install), then `back` (iOS, same install, `--keep-app-running`). It covers notes, UTXO labels,
checks, encryption and unlock, and payments both ways.

`integration_test/phone_menus_test.dart` opens and closes every side nav item.
Run it the same way, with `--target integration_test/phone_menus_test.dart`.

The tests fail on a layout overflow that is not in their list of known faults, and write one screenshot per step to
`PHONE_QA_SHOTS`. Run one device at a time: the test counts the regtest mempool.

`integration_test/phone_thunder_test.dart` runs Thunder in the app process: it starts Thunder from the row menu
of the Sidechains page, deposits 0.5 BTC, starts BMM, pays 0.1 BTC on Thunder and withdraws 0.2 BTC to an L1
address of the phone wallet. It mines until the bundle pays out. Build the Thunder library first, and give the
RPC address of the Thunder node in the app, which is 6009 plus the port offset:

```sh
BITWINDOW_DEFAULT_NETWORK=regtest just ios-backend ios-thunder    # or android-backend android-thunder

PHONE_QA_SHOTS=/tmp/phone-qa/thunder/ios flutter drive -d <simulator> \
  --driver test_driver/phone_regtest_driver.dart \
  --target integration_test/phone_thunder_test.dart \
  --dart-define=BITWINDOW_PORT_OFFSET=5300 --dart-define=PHONE_THUNDER_RPC_URL=http://127.0.0.1:11309 \
  $(scripts/phone-regtest.sh defines ios)
```

Run it on a stack that you reset: an old Thunder chain on the stack does not match the new node in the app.
