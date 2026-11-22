import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/gen/version.dart';
import 'package:bitwindow/sidechains/sidepot/sidepot_bmm_note.dart';
import 'package:bitwindow/sidechains/sidepot/sidepot_game_page.dart';
import 'package:bitwindow/sidechains/sidepot/sidepot_widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/shell.dart';

/// Sidepot inside BitWindow: the shared sidechain pane, and a Game tab.
///
/// Unlike the other hosted chains, Sidepot has no app of its own to run in a
/// separate window, so this module lives in BitWindow.
class SidepotModule extends SidechainModule {
  @override
  Sidechain get chain => Sidepot();

  @override
  String get appName => 'Sidepot';

  @override
  SidechainAppVersion get version => const SidechainAppVersion(
    version: AppVersion.version,
    versionString: AppVersion.versionString,
    buildDate: AppVersion.buildDate,
    commitFull: AppVersion.commitFull,
    appName: 'Sidepot',
  );

  @override
  RootStackRouter registerRouter(GetIt getIt) {
    if (!getIt.isRegistered<SidepotRouter>()) {
      getIt.registerSingleton<SidepotRouter>(SidepotRouter());
    }
    return getIt.get<SidepotRouter>();
  }

  @override
  SidechainRPC registerRPC(GetIt getIt) {
    if (!getIt.isRegistered<SidepotRPC>()) {
      getIt.registerSingleton<SidepotRPC>(SidepotLive());
    }
    return getIt.get<SidepotRPC>();
  }

  /// Sidepot runs on eCash mainnet only; the other networks keep the same ports.
  @override
  Map<String, String> confPorts(String network) => {
    'rpc-addr': '127.0.0.1:6088',
    'net-addr': '0.0.0.0:4088',
    'mainchain-grpc-url': 'http://localhost:50051',
  };

  @override
  List<String> get defaultHomepageWidgets => [
    'balance_card',
    'receive_card',
    'send_card',
    'sidepot_table',
    'utxo_table',
  ];

  @override
  Map<String, HomepageWidgetInfo> get widgetCatalog => SidepotWidgetCatalog.getCatalogMap();

  @override
  List<ShellTab> get tabs => const [
    ShellTab(label: 'Game', route: SidepotGameRoute(), sourceFiles: ['sidepot_game_page.dart']),
  ];

  @override
  List<AutoRoute> get tabRoutes => [AutoRoute(page: SidepotGameRoute.page)];

  @override
  Widget? bmmNote(BuildContext context) => const SidepotBmmNote();
}

/// The router a module must name. BitWindow hosts the tabs under its own router.
class SidepotRouter extends RootStackRouter {
  SidepotRouter();

  @override
  RouteType get defaultRouteType => const RouteType.adaptive();

  @override
  List<AutoRoute> get routes => sidechainShellRoutes(SidepotModule());
}

/// The route of [SidepotGamePage], written by hand in the shape the route generator gives.
class SidepotGameRoute extends PageRouteInfo<void> {
  const SidepotGameRoute({List<PageRouteInfo>? children}) : super(SidepotGameRoute.name, initialChildren: children);

  static const String name = 'SidepotGameRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SidepotGamePage();
    },
  );
}
