import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

const _art = {
  SailSVGAsset.backgroundBlue,
  SailSVGAsset.backgroundContact,
  SailSVGAsset.backgroundFog,
  SailSVGAsset.backgroundForest,
  SailSVGAsset.backgroundHooked,
  SailSVGAsset.backgroundIce,
  SailSVGAsset.backgroundNorthern,
  SailSVGAsset.backgroundNorthernBlue,
  SailSVGAsset.backgroundNorthernDarkGreen,
  SailSVGAsset.backgroundNorthernGreen,
  SailSVGAsset.backgroundOcean,
  SailSVGAsset.backgroundOrange,
  SailSVGAsset.backgroundPurple,
  SailSVGAsset.backgroundSphere,
  SailSVGAsset.backgroundSunrise,
  SailSVGAsset.backgroundSwirlGreen,
  SailSVGAsset.backgroundSwirlOrange,
  SailSVGAsset.backgroundSwirlPurple,
  SailSVGAsset.tabPeg,
  SailSVGAsset.tabBMM,
  SailSVGAsset.tabWithdrawalExplorer,
  SailSVGAsset.tabSidechainSend,
  SailSVGAsset.tabZSideMeltCast,
  SailSVGAsset.tabZSideShieldDeshield,
  SailSVGAsset.tabZSideOperationStatuses,
  SailSVGAsset.tabConsole,
  SailSVGAsset.tabTools,
  SailSVGAsset.tabStarters,
  SailSVGAsset.iconTabShieldDeshield,
  SailSVGAsset.iconTabSend,
  SailSVGAsset.iconTabDepositWithdraw,
  SailSVGAsset.iconTabOperationStatuses,
  SailSVGAsset.iconTabBmm,
  SailSVGAsset.iconTabMeltCast,
  SailSVGAsset.layerTwoLabsLogo,
  SailSVGAsset.meltCastDiagram,
  SailSVGAsset.dividerDot,
};

// The shape of a Phosphor 2.1 SVG: one path, filled with the current color, on a 256 grid.
final _phosphorShape = RegExp(
  r'^<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="[^"]+"/></svg>\s*$',
);

void main() {
  final icons = SailSVGAsset.values.where((a) => !_art.contains(a));

  test('every icon is a Phosphor Light file in assets/icons', () {
    for (final icon in icons) {
      final path = icon.toAssetPath();
      expect(path, startsWith('assets/icons/'), reason: icon.name);
      final svg = File(path).readAsStringSync();
      expect(svg, matches(_phosphorShape), reason: '${icon.name}: $path');
      // Regular and Fill draw 8-unit corner arcs; Light draws 6-unit arcs.
      expect(svg, isNot(contains('a8,8,0,0,')), reason: '${icon.name}: $path is not the Light weight');
    }
  });

  test('assets/icons holds only icons that an enum value uses', () {
    final used = icons.map((a) => a.toAssetPath().split('/').last).toSet();
    final files = Directory(
      'assets/icons',
    ).listSync().map((f) => f.uri.pathSegments.last).where((name) => name.endsWith('.svg')).toSet();
    expect(files, used);
  });
}
