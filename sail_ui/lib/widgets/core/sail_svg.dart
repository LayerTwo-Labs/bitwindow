import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:sail_ui/sail_ui.dart';

enum SailSVGAsset {
  // Wallet backgrounds
  backgroundBlue,
  backgroundContact,
  backgroundFog,
  backgroundForest,
  backgroundHooked,
  backgroundIce,
  backgroundNorthern,
  backgroundNorthernBlue,
  backgroundNorthernDarkGreen,
  backgroundNorthernGreen,
  backgroundOcean,
  backgroundOrange,
  backgroundPurple,
  backgroundSphere,
  backgroundSunrise,
  backgroundSwirlGreen,
  backgroundSwirlOrange,
  backgroundSwirlPurple,

  // Tab art
  tabPeg,
  tabBMM,
  tabWithdrawalExplorer,
  tabSidechainSend,
  tabZSideMeltCast,
  tabZSideShieldDeshield,
  tabZSideOperationStatuses,
  tabConsole,
  tabTools,
  tabStarters,
  iconTabShieldDeshield,
  iconTabSend,
  iconTabDepositWithdraw,
  iconTabOperationStatuses,
  iconTabBmm,
  iconTabMeltCast,

  layerTwoLabsLogo,
  meltCastDiagram,
  dividerDot,

  // Phosphor Light icons, in assets/icons
  activity,
  arrowDown,
  arrowDownUp,
  arrowLeft,
  arrowRight,
  arrowRightLeft,
  arrowUp,
  atSign,
  badgeCheck,
  bell,
  bitcoin,
  blocks,
  bookOpen,
  boxes,
  bug,
  calendar,
  check,
  chevronDown,
  chevronLeft,
  chevronRight,
  chevronUp,
  circle,
  circleAlert,
  circleCheck,
  circleHelp,
  circleX,
  clipboardPaste,
  clock,
  clockClockwise,
  coins,
  copy,
  darkMode,
  dollarSign,
  download,
  ellipsis,
  ellipsisVertical,
  externalLink,
  eye,
  eyeOff,
  fileArrowUp,
  fileText,
  filter,
  filterX,
  flaskConical,
  folder,
  folderOpen,
  gem,
  hourglass,
  iconArrow,
  iconCalendar,
  iconCast,
  iconCheck,
  iconClose,
  iconCoins,
  iconConnectionStatus,
  iconCopy,
  iconDelete,
  iconDeposit,
  iconDownload,
  iconGlobe,
  iconInfo,
  iconMelt,
  iconNetwork,
  iconNewWindow,
  iconPeers,
  iconPen,
  iconPending,
  iconQuestion,
  iconRestart,
  iconSearch,
  iconSuccess,
  iconTerminal,
  iconTools,
  iconTransactions,
  iconWallet,
  iconWarning,
  iconWithdraw,
  info,
  key,
  landmark,
  layers,
  lightDarkMode,
  lightMode,
  lock,
  menu,
  messageCircle,
  messageCircleWarning,
  minus,
  newspaper,
  pickaxe,
  plus,
  qrCode,
  refreshCw,
  scale,
  scatterChart,
  search,
  settings,
  share,
  shield,
  shuffle,
  snowflake,
  spade,
  split,
  square,
  star,
  tabSettings,
  telegram,
  trash,
  triangleAlert,
  upload,
  wallet,
  x,
  zap,
}

enum SailPNGAsset { meltCastDiagram, articleBeginner }

class SailSVG {
  static Widget icon(
    SailSVGAsset asset, {
    bool isHighlighted = false,
    double? width,
    double? height,
    Color? color,
  }) {
    return Builder(
      builder: (context) {
        final colors = SailTheme.of(context).colors;
        final statusColor = switch (asset) {
          SailSVGAsset.iconSuccess => colors.success,
          SailSVGAsset.iconPending => colors.warning,
          SailSVGAsset.iconInfo => colors.info,
          _ => null,
        };

        return SailSVG.fromAsset(
          asset,
          color: color ?? statusColor ?? (isHighlighted ? colors.primary : colors.icon),
          width: width ?? SailStyleValues.iconSizePrimary,
          height: height ?? SailStyleValues.iconSizePrimary,
        );
      },
    );
  }

  static SvgPicture fromAsset(
    SailSVGAsset asset, {
    double? height,
    double? width,
    Color? color,
  }) {
    return SvgPicture.asset(
      asset.toAssetPath(),
      package: 'sail_ui',
      width: width,
      colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
      height: height,
    );
  }

  static Widget png(
    SailPNGAsset asset, {
    double? width,
    double? height,
    BoxFit? fit,
  }) {
    return Image.asset(
      asset.toAssetPath(),
      package: 'sail_ui',
      width: width,
      height: height,
      fit: fit ?? BoxFit.contain,
    );
  }
}

extension AsAssetPath on SailSVGAsset {
  String toAssetPath() {
    switch (this) {
      // Wallet backgrounds
      case SailSVGAsset.backgroundBlue:
        return 'assets/svgs/background_blue.svg';
      case SailSVGAsset.backgroundContact:
        return 'assets/svgs/background_contact.svg';
      case SailSVGAsset.backgroundFog:
        return 'assets/svgs/background_fog.svg';
      case SailSVGAsset.backgroundForest:
        return 'assets/svgs/background_forest.svg';
      case SailSVGAsset.backgroundHooked:
        return 'assets/svgs/background_hooked.svg';
      case SailSVGAsset.backgroundIce:
        return 'assets/svgs/background_ice.svg';
      case SailSVGAsset.backgroundNorthern:
        return 'assets/svgs/background_northern.svg';
      case SailSVGAsset.backgroundNorthernBlue:
        return 'assets/svgs/background_northern_blue.svg';
      case SailSVGAsset.backgroundNorthernDarkGreen:
        return 'assets/svgs/background_northern_dark_green.svg';
      case SailSVGAsset.backgroundNorthernGreen:
        return 'assets/svgs/background_northern_green.svg';
      case SailSVGAsset.backgroundOcean:
        return 'assets/svgs/background_ocean.svg';
      case SailSVGAsset.backgroundOrange:
        return 'assets/svgs/background_orange.svg';
      case SailSVGAsset.backgroundPurple:
        return 'assets/svgs/background_purple.svg';
      case SailSVGAsset.backgroundSphere:
        return 'assets/svgs/background_sphere.svg';
      case SailSVGAsset.backgroundSunrise:
        return 'assets/svgs/background_sunrise.svg';
      case SailSVGAsset.backgroundSwirlGreen:
        return 'assets/svgs/background_swirl_green.svg';
      case SailSVGAsset.backgroundSwirlOrange:
        return 'assets/svgs/background_swirl_orange.svg';
      case SailSVGAsset.backgroundSwirlPurple:
        return 'assets/svgs/background_swirl_purple.svg';

      case SailSVGAsset.tabPeg:
        return 'assets/svgs/icon_tab_peg.svg';
      case SailSVGAsset.tabBMM:
        return 'assets/svgs/icon_tab_bmm.svg';
      case SailSVGAsset.tabWithdrawalExplorer:
        return 'assets/svgs/icon_tab_withdrawal_explorer.svg';
      case SailSVGAsset.tabSidechainSend:
        return 'assets/svgs/icon_tab_send.svg';
      case SailSVGAsset.tabZSideMeltCast:
        return 'assets/svgs/icon_tab_melt_cast.svg';
      case SailSVGAsset.tabZSideShieldDeshield:
        return 'assets/svgs/icon_tab_shield_deshield.svg';
      case SailSVGAsset.tabZSideOperationStatuses:
        return 'assets/svgs/icon_tab_operation_statuses.svg';
      case SailSVGAsset.tabConsole:
        return 'assets/svgs/icon_tab_console.svg';
      case SailSVGAsset.tabTools:
        return 'assets/svgs/icon_tab_tools.svg';
      case SailSVGAsset.tabStarters:
        return 'assets/svgs/icon_tab_starters.svg';
      case SailSVGAsset.iconTabShieldDeshield:
        return 'assets/svgs/icon_tab_shield_deshield.svg';
      case SailSVGAsset.iconTabSend:
        return 'assets/svgs/icon_tab_send.svg';
      case SailSVGAsset.iconTabDepositWithdraw:
        return 'assets/svgs/icon_tab_deposit_withdraw.svg';
      case SailSVGAsset.iconTabOperationStatuses:
        return 'assets/svgs/icon_tab_operation_statuses.svg';
      case SailSVGAsset.iconTabBmm:
        return 'assets/svgs/icon_tab_bmm.svg';
      case SailSVGAsset.iconTabMeltCast:
        return 'assets/svgs/icon_tab_melt_cast.svg';

      case SailSVGAsset.layerTwoLabsLogo:
        return 'assets/svgs/layertwolabs.svg';
      case SailSVGAsset.meltCastDiagram:
        return 'assets/pngs/meltcastdiagram.png';
      case SailSVGAsset.dividerDot:
        return 'assets/svgs/divider_dot.svg';

      case SailSVGAsset.activity:
        return 'assets/icons/pulse.svg';
      case SailSVGAsset.arrowDown:
        return 'assets/icons/arrow-down.svg';
      case SailSVGAsset.arrowDownUp:
        return 'assets/icons/arrows-down-up.svg';
      case SailSVGAsset.arrowLeft:
        return 'assets/icons/arrow-left.svg';
      case SailSVGAsset.arrowRight:
        return 'assets/icons/arrow-right.svg';
      case SailSVGAsset.arrowRightLeft:
        return 'assets/icons/arrows-left-right.svg';
      case SailSVGAsset.arrowUp:
        return 'assets/icons/arrow-up.svg';
      case SailSVGAsset.atSign:
        return 'assets/icons/at.svg';
      case SailSVGAsset.badgeCheck:
        return 'assets/icons/seal-check.svg';
      case SailSVGAsset.bell:
        return 'assets/icons/bell.svg';
      case SailSVGAsset.bitcoin:
        return 'assets/icons/currency-btc.svg';
      case SailSVGAsset.blocks:
        return 'assets/icons/cube.svg';
      case SailSVGAsset.bookOpen:
        return 'assets/icons/book-open.svg';
      case SailSVGAsset.boxes:
        return 'assets/icons/package.svg';
      case SailSVGAsset.bug:
        return 'assets/icons/bug.svg';
      case SailSVGAsset.calendar:
        return 'assets/icons/calendar-blank.svg';
      case SailSVGAsset.check:
        return 'assets/icons/check.svg';
      case SailSVGAsset.chevronDown:
        return 'assets/icons/caret-down.svg';
      case SailSVGAsset.chevronLeft:
        return 'assets/icons/caret-left.svg';
      case SailSVGAsset.chevronRight:
        return 'assets/icons/caret-right.svg';
      case SailSVGAsset.chevronUp:
        return 'assets/icons/caret-up.svg';
      case SailSVGAsset.circle:
        return 'assets/icons/circle.svg';
      case SailSVGAsset.circleAlert:
        return 'assets/icons/warning-circle.svg';
      case SailSVGAsset.circleCheck:
        return 'assets/icons/check-circle.svg';
      case SailSVGAsset.circleHelp:
        return 'assets/icons/question.svg';
      case SailSVGAsset.circleX:
        return 'assets/icons/x-circle.svg';
      case SailSVGAsset.clipboardPaste:
        return 'assets/icons/clipboard-text.svg';
      case SailSVGAsset.clock:
        return 'assets/icons/clock.svg';
      case SailSVGAsset.clockClockwise:
        return 'assets/icons/clock-clockwise.svg';
      case SailSVGAsset.coins:
        return 'assets/icons/coins.svg';
      case SailSVGAsset.copy:
        return 'assets/icons/copy.svg';
      case SailSVGAsset.darkMode:
        return 'assets/icons/moon.svg';
      case SailSVGAsset.dollarSign:
        return 'assets/icons/currency-dollar.svg';
      case SailSVGAsset.download:
        return 'assets/icons/download-simple.svg';
      case SailSVGAsset.ellipsis:
        return 'assets/icons/dots-three.svg';
      case SailSVGAsset.ellipsisVertical:
        return 'assets/icons/dots-three-vertical.svg';
      case SailSVGAsset.externalLink:
        return 'assets/icons/arrow-square-out.svg';
      case SailSVGAsset.eye:
        return 'assets/icons/eye.svg';
      case SailSVGAsset.eyeOff:
        return 'assets/icons/eye-slash.svg';
      case SailSVGAsset.fileArrowUp:
        return 'assets/icons/file-arrow-up.svg';
      case SailSVGAsset.fileText:
        return 'assets/icons/file-text.svg';
      case SailSVGAsset.filter:
        return 'assets/icons/funnel.svg';
      case SailSVGAsset.filterX:
        return 'assets/icons/funnel-x.svg';
      case SailSVGAsset.flaskConical:
        return 'assets/icons/flask.svg';
      case SailSVGAsset.folder:
        return 'assets/icons/folder.svg';
      case SailSVGAsset.folderOpen:
        return 'assets/icons/folder-open.svg';
      case SailSVGAsset.gem:
        return 'assets/icons/diamond.svg';
      case SailSVGAsset.hourglass:
        return 'assets/icons/hourglass.svg';
      case SailSVGAsset.iconArrow:
        return 'assets/icons/caret-down.svg';
      case SailSVGAsset.iconCalendar:
        return 'assets/icons/money.svg';
      case SailSVGAsset.iconCast:
        return 'assets/icons/hammer.svg';
      case SailSVGAsset.iconCheck:
        return 'assets/icons/seal-check.svg';
      case SailSVGAsset.iconClose:
        return 'assets/icons/x.svg';
      case SailSVGAsset.iconCoins:
        return 'assets/icons/coin-vertical.svg';
      case SailSVGAsset.iconConnectionStatus:
        return 'assets/icons/broadcast.svg';
      case SailSVGAsset.iconCopy:
        return 'assets/icons/copy.svg';
      case SailSVGAsset.iconDelete:
        return 'assets/icons/trash.svg';
      case SailSVGAsset.iconDeposit:
        return 'assets/icons/link.svg';
      case SailSVGAsset.iconDownload:
        return 'assets/icons/cloud-arrow-down.svg';
      case SailSVGAsset.iconGlobe:
        return 'assets/icons/globe.svg';
      case SailSVGAsset.iconInfo:
        return 'assets/icons/info.svg';
      case SailSVGAsset.iconMelt:
        return 'assets/icons/shield-check.svg';
      case SailSVGAsset.iconNetwork:
        return 'assets/icons/network.svg';
      case SailSVGAsset.iconNewWindow:
        return 'assets/icons/app-window.svg';
      case SailSVGAsset.iconPeers:
        return 'assets/icons/user-list.svg';
      case SailSVGAsset.iconPen:
        return 'assets/icons/pencil-simple.svg';
      case SailSVGAsset.iconPending:
        return 'assets/icons/circle.svg';
      case SailSVGAsset.iconQuestion:
        return 'assets/icons/question.svg';
      case SailSVGAsset.iconRestart:
        return 'assets/icons/arrows-clockwise.svg';
      case SailSVGAsset.iconSearch:
        return 'assets/icons/magnifying-glass.svg';
      case SailSVGAsset.iconSuccess:
        return 'assets/icons/check-circle.svg';
      case SailSVGAsset.iconTerminal:
        return 'assets/icons/terminal-window.svg';
      case SailSVGAsset.iconTools:
        return 'assets/icons/wrench.svg';
      case SailSVGAsset.iconTransactions:
        return 'assets/icons/arrows-left-right.svg';
      case SailSVGAsset.iconWallet:
        return 'assets/icons/wallet.svg';
      case SailSVGAsset.iconWarning:
        return 'assets/icons/warning.svg';
      case SailSVGAsset.iconWithdraw:
        return 'assets/icons/link-break.svg';
      case SailSVGAsset.info:
        return 'assets/icons/info.svg';
      case SailSVGAsset.key:
        return 'assets/icons/key.svg';
      case SailSVGAsset.landmark:
        return 'assets/icons/bank.svg';
      case SailSVGAsset.layers:
        return 'assets/icons/stack.svg';
      case SailSVGAsset.lightDarkMode:
        return 'assets/icons/circle-half.svg';
      case SailSVGAsset.lightMode:
        return 'assets/icons/sun.svg';
      case SailSVGAsset.lock:
        return 'assets/icons/lock.svg';
      case SailSVGAsset.menu:
        return 'assets/icons/list.svg';
      case SailSVGAsset.messageCircle:
        return 'assets/icons/chat-circle.svg';
      case SailSVGAsset.messageCircleWarning:
        return 'assets/icons/warning-circle.svg';
      case SailSVGAsset.minus:
        return 'assets/icons/minus.svg';
      case SailSVGAsset.newspaper:
        return 'assets/icons/newspaper.svg';
      case SailSVGAsset.pickaxe:
        return 'assets/icons/hammer.svg';
      case SailSVGAsset.plus:
        return 'assets/icons/plus.svg';
      case SailSVGAsset.qrCode:
        return 'assets/icons/qr-code.svg';
      case SailSVGAsset.refreshCw:
        return 'assets/icons/arrows-clockwise.svg';
      case SailSVGAsset.scale:
        return 'assets/icons/scales.svg';
      case SailSVGAsset.scatterChart:
        return 'assets/icons/chart-scatter.svg';
      case SailSVGAsset.search:
        return 'assets/icons/magnifying-glass.svg';
      case SailSVGAsset.settings:
        return 'assets/icons/gear.svg';
      case SailSVGAsset.share:
        return 'assets/icons/export.svg';
      case SailSVGAsset.shield:
        return 'assets/icons/shield.svg';
      case SailSVGAsset.shuffle:
        return 'assets/icons/shuffle.svg';
      case SailSVGAsset.snowflake:
        return 'assets/icons/snowflake.svg';
      case SailSVGAsset.spade:
        return 'assets/icons/spade.svg';
      case SailSVGAsset.split:
        return 'assets/icons/arrows-split.svg';
      case SailSVGAsset.square:
        return 'assets/icons/square.svg';
      case SailSVGAsset.star:
        return 'assets/icons/star.svg';
      case SailSVGAsset.tabSettings:
        return 'assets/icons/gear.svg';
      case SailSVGAsset.telegram:
        return 'assets/icons/telegram-logo.svg';
      case SailSVGAsset.trash:
        return 'assets/icons/trash.svg';
      case SailSVGAsset.triangleAlert:
        return 'assets/icons/warning.svg';
      case SailSVGAsset.upload:
        return 'assets/icons/upload-simple.svg';
      case SailSVGAsset.wallet:
        return 'assets/icons/wallet.svg';
      case SailSVGAsset.x:
        return 'assets/icons/x.svg';
      case SailSVGAsset.zap:
        return 'assets/icons/lightning.svg';
    }
  }
}

extension PNGAsAssetPath on SailPNGAsset {
  String toAssetPath() {
    switch (this) {
      case SailPNGAsset.meltCastDiagram:
        return 'assets/pngs/meltcastdiagram.png';
      case SailPNGAsset.articleBeginner:
        return 'assets/pngs/article-beginner.png';
    }
  }
}
