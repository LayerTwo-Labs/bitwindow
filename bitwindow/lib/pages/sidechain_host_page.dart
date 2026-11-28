import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/pages/sidechain_activation_management_page.dart';
import 'package:bitwindow/pages/sidechains_page.dart';
import 'package:bitwindow/providers/sidechain_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:bitwindow/sidechains/hosted_modules.dart';
import 'package:bitwindow/log_window.dart';
import 'package:bitwindow/sidechains/hosted_chains.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/router.gr.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/shell.dart';

/// Opens the view of [chain] inside BitWindow.
Future<void> openSidechainHere(Sidechain chain) {
  return GetIt.I.get<AppRouter>().navigate(SidechainsRoute(children: [SidechainHostRoute(chain: chain.registryKey)]));
}

/// Shows the sidechains tab. A click on the tab while it shows goes back to the slot list.
Future<void> openSidechainsTab(TabsRouter tabs, int index) async {
  if (tabs.activeIndex != index) {
    tabs.setActiveIndex(index);
    return;
  }
  await GetIt.I.get<AppRouter>().navigate(SidechainsRoute(children: [const SidechainSlotsRoute()]));
}

/// The navigator of a chain that BitWindow hosts, on the router of BitWindow.
class HostChainNavigator implements ChainNavigator {
  final Sidechain chain;

  const HostChainNavigator(this.chain);

  AppRouter get _router => GetIt.I.get<AppRouter>();

  @override
  Future<void> openTab(PageRouteInfo tab) => _router.navigate(
    SidechainsRoute(
      children: [
        SidechainHostRoute(chain: chain.registryKey, children: [tab]),
      ],
    ),
  );

  @override
  Future<void> push(PageRouteInfo route) => _router.push(route);

  @override
  Future<void> pop() => _router.maybePop();
}

/// One sidechain inside BitWindow.
@RoutePage()
class SidechainHostPage extends StatelessWidget {
  final String chain;

  const SidechainHostPage({super.key, @PathParam('chain') required this.chain});

  @override
  Widget build(BuildContext context) {
    final module = hostedModuleByKey(chain);
    if (module == null) {
      return Center(child: SailText.secondary13('BitWindow cannot open $chain here.'));
    }
    return KeyedSubtree(
      key: ValueKey(module.chain.registryKey),
      child: SidechainScopeHost(
        module: module,
        child: _ShownWithSidechainsTab(child: HostedChainView(module: module)),
      ),
    );
  }
}

/// Stops the tickers and refreshes of the chain view while another BitWindow tab shows.
class _ShownWithSidechainsTab extends StatelessWidget {
  final Widget child;

  const _ShownWithSidechainsTab({required this.child});

  @override
  Widget build(BuildContext context) {
    final tabs = TabsRouterScope.of(context, watch: true)?.controller;
    return TickerMode(enabled: tabs == null || tabs.current.name == SidechainsRoute.name, child: child);
  }
}

/// Puts the view scope of [module] on top while the chain is on screen.
class SidechainScopeHost extends StatefulWidget {
  final SidechainModule module;
  final Widget child;

  const SidechainScopeHost({super.key, required this.module, required this.child});

  @override
  State<SidechainScopeHost> createState() => _SidechainScopeHostState();
}

class _SidechainScopeHostState extends State<SidechainScopeHost> {
  final HostedChains _hosted = GetIt.I.get<HostedChains>();
  late final Future<void> _entered;

  @override
  void initState() {
    super.initState();
    _entered = _hosted.openView(widget.module);
  }

  @override
  void dispose() {
    unawaited(_hosted.closeView(widget.module));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _entered,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: SailText.secondary13('Could not open ${widget.module.appName}: ${snapshot.error}'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LoadingIndicator());
        }
        return widget.child;
      },
    );
  }
}

/// The tabs of the open chain, its strip, and the page of the active tab.
class HostedChainView extends StatelessWidget {
  final SidechainModule module;

  const HostedChainView({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final labels = shellTabLabels(module);
    final phone = SailStyleValues.phoneLayout(context);

    return AutoTabsRouter(
      homeIndex: ShellTabIndex.of(module).homepage,
      routes: shellTabRoutes(module),
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        // The Parent Chain page holds its own Deposit card.
        final showDeposit = tabsRouter.activeIndex != ShellTabIndex.of(module).parentChain;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SailStyleValues.padding12,
                SailStyleValues.padding12,
                SailStyleValues.padding12,
                0,
              ),
              child: ChainTabRow(
                labels: labels,
                activeIndex: tabsRouter.activeIndex,
                onSelect: tabsRouter.setActiveIndex,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SailStyleValues.padding12,
                SailStyleValues.padding12,
                SailStyleValues.padding12,
                0,
              ),
              child: ViewModelBuilder<HostedChainViewModel>.reactive(
                viewModelBuilder: () => HostedChainViewModel(module),
                builder: (context, model, _) => phone
                    ? HostedChainHeader(model: model, showDeposit: showDeposit)
                    : HostedChainStrip(model: model, showDeposit: showDeposit),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

/// The tabs of a chain as one segmented control.
class ChainTabRow extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final void Function(int index) onSelect;

  const ChainTabRow({super.key, required this.labels, required this.activeIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SidechainSegments(labels: labels, activeIndex: activeIndex, onSelect: onSelect),
      ),
    );
  }
}

/// The top strip of the open chain: the chain dropdown, the balances, the state, Deposit and the chain menu.
class HostedChainStrip extends StatelessWidget {
  final HostedChainViewModel model;
  final bool showDeposit;

  const HostedChainStrip({super.key, required this.model, required this.showDeposit});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final slotBalance = model.slotBalance;

    return SailStrip(
      lead: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SidechainIconTile(chain: model.chain),
          const SizedBox(width: SailStyleValues.padding08),
          ChainDropdown(module: model.module),
        ],
      ),
      stats: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailText.primary12('Balance', bold: true, color: theme.colors.textSecondary),
            SailText.primary24(model.running ? model.balance : '—', bold: true),
          ],
        ),
        if (slotBalance != null) SailStat(label: 'Sidechain balance', value: slotBalance),
      ],
      status: SailStatusPill(label: model.stateLabel, tone: model.stateTone),
      actions: [
        if (showDeposit)
          SailButton(
            label: 'Deposit',
            onPressed: () => showDepositModal(context, model.chain.slot, model.chain.name),
          ),
        SailRowMenuButton(items: () => chainMenuItems(context, model)),
      ],
    );
  }
}

/// The actions of the chain menu in the strip.
/// False leaves out the window, Start and Stop items, for a head that shows them as buttons.
List<SailMenuEntity> chainMenuItems(BuildContext context, HostedChainViewModel model, {bool nodeItems = true}) {
  SailMenuItem item(String label, VoidCallback run) => SailMenuItem(onSelected: run, child: SailText.primary13(label));
  return [
    if (nodeItems) ...[
      if (model.hasWindow) item('Open in separate window', () => unawaited(model.openWindow())),
      if (model.running || model.starting)
        item('Stop', () => unawaited(model.stop()))
      else
        item('Start', () => unawaited(model.start())),
      const SailMenuItemDivider(),
    ],
    item('Edit homepage', () {
      AutoTabsRouter.of(context).setActiveIndex(ShellTabIndex.of(model.module).homepage);
      model.editHomepage();
    }),
    if (model.module.hasConfEditor) item('Edit configuration', model.editConf),
    item('View logs', model.viewLogs),
    item('Debug window', () => unawaited(model.openDebugWindow(context))),
    item('Node settings', () => unawaited(model.openNodeSettings(context))),
  ];
}

/// The name of the open chain. A tap lists the other chains, All slots and Add or remove.
class ChainDropdown extends StatelessWidget {
  final SidechainModule module;

  const ChainDropdown({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return ViewModelBuilder<SidechainSidebarViewModel>.reactive(
      viewModelBuilder: () => SidechainSidebarViewModel(),
      builder: (context, model, _) => DecoratedBox(
        decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
        child: SailTappable(
          key: const ValueKey('chain_dropdown'),
          borderRadius: theme.chrome.radius,
          onTap: () => _open(context, model),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SailText.primary15(module.chain.name, bold: true),
                const SizedBox(width: SailStyleValues.padding08),
                SailSVG.fromAsset(SailSVGAsset.chevronDown, width: 12, height: 12, color: theme.colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, SidechainSidebarViewModel model) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(box.size.bottomLeft(const Offset(0, 4)), ancestor: overlay);
    await showSailMenu(
      context: context,
      preferredAnchorPoint: anchor,
      menu: SailMenu(
        title: 'Sidechain balance ${model.total}',
        items: [
          for (final entry in model.entries(open: module))
            SailMenuItem(
              onSelected: () => unawaited(openSidechainHere(entry.module.chain)),
              child: Row(
                key: ValueKey('chain_entry_${entry.module.chain.registryKey}'),
                children: [
                  SidechainIconTile(chain: entry.module.chain, size: 18),
                  const SizedBox(width: SailStyleValues.padding08),
                  Expanded(
                    child: SailText.primary13(entry.module.chain.name, bold: entry.module == module),
                  ),
                  const SizedBox(width: SailStyleValues.padding12),
                  SailText.secondary12(entry.trailing),
                ],
              ),
            ),
          const SailMenuItemDivider(),
          SailMenuItem(
            onSelected: () =>
                unawaited(GetIt.I.get<AppRouter>().navigate(SidechainsRoute(children: [const SidechainSlotsRoute()]))),
            child: SailText.primary13('All slots'),
          ),
          if (!model.sidechainManagementUnavailable)
            SailMenuItem(
              onSelected: () => unawaited(showSidechainActivationManagementModal(context)),
              child: SailText.primary13('Add or remove'),
            ),
        ],
      ),
    );
  }
}

/// The phone head of the open chain: the title line, and the buttons on a line under it.
class HostedChainHeader extends StatelessWidget {
  final HostedChainViewModel model;
  final bool showDeposit;

  const HostedChainHeader({super.key, required this.model, this.showDeposit = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SailText.primary15(model.chain.name, bold: true),
            const SizedBox(width: SailStyleValues.padding12),
            SailBadge(
              model.stateLabel,
              tone: model.stateTone == SailStatusTone.success
                  ? SailBadgeTone.success
                  : model.stateTone == SailStatusTone.warning
                  ? SailBadgeTone.warning
                  : SailBadgeTone.neutral,
            ),
            const SizedBox(width: SailStyleValues.padding12),
            if (model.running) SailText.secondary13(model.balance),
          ],
        ),
        const SizedBox(height: SailStyleValues.padding08),
        Wrap(
          spacing: SailStyleValues.padding08,
          runSpacing: SailStyleValues.padding08,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showDeposit)
              SailButton(
                label: 'Deposit',
                variant: ButtonVariant.outline,
                onPressed: () => showDepositModal(context, model.chain.slot, model.chain.name),
              ),
            if (model.hasWindow)
              SailButton(label: 'Open in separate window', variant: ButtonVariant.outline, onPressed: model.openWindow),
            if (model.running || model.starting)
              SailButton(label: 'Stop', variant: ButtonVariant.outline, onPressed: model.stop)
            else
              SailButton(label: 'Start', variant: ButtonVariant.primary, onPressed: model.start),
            Builder(
              builder: (context) => SailButton(
                variant: ButtonVariant.icon,
                icon: SailSVGAsset.ellipsisVertical,
                // The icon is tall and thin, so a width alone makes it taller than the buttons beside it.
                iconHeight: 14,
                small: true,
                onPressed: () => _showChainMenu(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showChainMenu(BuildContext context) async {
    final bounds = getGlobalBoundsForContext(context);
    await showSailMenu(
      context: context,
      preferredAnchorPoint: bounds.bottomRight,
      alignment: Alignment.topRight,
      menu: SailMenu(items: chainMenuItems(context, model, nodeItems: false)),
    );
  }
}

class HostedChainViewModel extends BaseViewModel {
  final SidechainModule module;
  final BinaryProvider _binaries = GetIt.I.get<BinaryProvider>();
  final SidechainBalanceProvider _balance = GetIt.I.get<SidechainBalanceProvider>();
  final FormatterProvider _formatter = GetIt.I.get<FormatterProvider>();
  final SidechainProvider _slots = GetIt.I.get<SidechainProvider>();

  HostedChainViewModel(this.module) {
    _binaries.addListener(notifyListeners);
    _balance.addListener(notifyListeners);
    _formatter.addListener(notifyListeners);
    _slots.addListener(notifyListeners);
  }

  Sidechain get chain =>
      (_binaries.binaries.firstWhereOrNull((b) => b.type == module.chain.type) ?? module.chain) as Sidechain;

  bool get running => _binaries.isConnected(chain);
  bool get starting => !running && _binaries.isInitializing(chain);
  bool get hasWindow => _binaries.hasWindow(chain);

  String get stateLabel => running
      ? 'Running'
      : starting
      ? 'Starting'
      : 'Stopped';

  SailStatusTone get stateTone => running
      ? SailStatusTone.success
      : starting
      ? SailStatusTone.warning
      : SailStatusTone.neutral;

  String get balance => _formatter.formatBTC(_balance.balance);

  /// The coins in the slot of the chain, or null before the slot list loads.
  String? get slotBalance {
    final sats = _slots.sidechains[chain.slot]?.info.balanceSatoshi.toInt();
    return sats == null ? null : _formatter.formatSats(sats);
  }

  Future<void> start() => _binaries.start(chain, background: true);
  Future<void> stop() => _binaries.stop(chain);
  Future<void> openWindow() => _binaries.start(chain);

  AppRouter get _router => GetIt.I.get<AppRouter>();

  void editHomepage() => GetIt.I.get<SidechainHomepageProvider>().startEdit();

  void editConf() => unawaited(_router.push(SidechainConfEditorRoute()));

  void viewLogs() => unawaited(openLogWindow('${module.appName} Logs', chain.logPath(), chain.type));

  Future<void> openDebugWindow(BuildContext context) => showThemedDialog(
    context: context,
    builder: (context) => SailDialog(
      title: '${module.appName} debug window',
      maxWidth: 900,
      maxHeight: 640,
      child: SidechainDebugWindow(rpc: GetIt.I.get<SidechainRPC>(), sidechainName: module.fullName),
    ),
  );

  Future<void> openNodeSettings(BuildContext context) => showThemedDialog(
    context: context,
    builder: (context) => ChainSettingsModal(
      connection: GetIt.I.get<SidechainRPC>(),
      onOpenConfConfigurator: module.hasConfEditor ? editConf : null,
    ),
  );

  @override
  void dispose() {
    _binaries.removeListener(notifyListeners);
    _balance.removeListener(notifyListeners);
    _formatter.removeListener(notifyListeners);
    _slots.removeListener(notifyListeners);
    super.dispose();
  }
}

/// One chain in the chain dropdown.
class SidechainSidebarEntry {
  final SidechainModule module;
  final bool running;

  /// The balance of a running chain, else its state.
  final String trailing;

  const SidechainSidebarEntry({
    required this.module,
    required this.running,
    required this.trailing,
  });
}

/// The chains of the chain dropdown.
class SidechainSidebarViewModel extends BaseViewModel {
  final BinaryProvider _binaries = GetIt.I.get<BinaryProvider>();
  final HostedChains _hosted = GetIt.I.get<HostedChains>();
  final SyncProvider? _sync = GetIt.I.isRegistered<SyncProvider>() ? GetIt.I.get<SyncProvider>() : null;
  final SidechainProvider _slots = GetIt.I.get<SidechainProvider>();
  final FormatterProvider _formatter = GetIt.I.get<FormatterProvider>();

  SidechainSidebarViewModel() {
    _binaries.addListener(notifyListeners);
    _hosted.addListener(notifyListeners);
    _sync?.addListener(notifyListeners);
    _slots.addListener(notifyListeners);
    _formatter.addListener(notifyListeners);
  }

  bool get sidechainManagementUnavailable => !NodeModeProvider.runsLocalBackends;

  Binary _binary(SidechainModule module) =>
      _binaries.binaries.firstWhereOrNull((b) => b.type == module.chain.type) ?? module.chain;

  bool _running(SidechainModule module) => _binaries.isConnected(_binary(module));

  double _balance(SidechainModule module) => _hosted.session(module)?.balance.balance ?? 0;

  String _trailing(SidechainModule module) {
    final binary = _binary(module);
    if (!_running(module)) {
      if (_binaries.isInitializing(binary)) {
        return 'Starting';
      }
      return binary.isDownloaded ? 'Stopped' : 'Not downloaded';
    }
    final sync = _sync?.sidechainSyncInfo(binary);
    if (sync != null && sync.progressGoal > 0 && !sync.isSynced) {
      return 'Syncing ${(sync.progress * 100).floor()}%';
    }
    return _formatter.formatBTC(_balance(module));
  }

  /// The hosted chains in an active slot, and [open] in all cases.
  List<SidechainSidebarEntry> entries({SidechainModule? open}) => [
    for (final module in hostedModules)
      if (module == open || _slots.sidechains[module.chain.slot] != null)
        SidechainSidebarEntry(
          module: module,
          running: _running(module),
          trailing: _trailing(module),
        ),
  ];

  String get total =>
      _formatter.formatBTC(hostedModules.where(_running).fold(0.0, (sum, module) => sum + _balance(module)));

  @override
  void dispose() {
    _binaries.removeListener(notifyListeners);
    _hosted.removeListener(notifyListeners);
    _sync?.removeListener(notifyListeners);
    _slots.removeListener(notifyListeners);
    _formatter.removeListener(notifyListeners);
    super.dispose();
  }
}
