import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:thunder_bridge/src/rust/frb_generated.dart';

export 'package:thunder_bridge/src/rust/api/node.dart' show NodeStatus, nodeStatus, startNode, stopNode;

bool _loaded = false;

/// Loads the bridge library. iOS links it into the app binary, Android loads it from the APK.
Future<void> loadThunderBridge() async {
  if (_loaded) {
    return;
  }
  final library = Platform.isIOS
      ? ExternalLibrary.process(iKnowHowToUseIt: true)
      : ExternalLibrary.open('libthunder_bridge.so');
  await RustLib.init(externalLibrary: library);
  _loaded = true;
}
