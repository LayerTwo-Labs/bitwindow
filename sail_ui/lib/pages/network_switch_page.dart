import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// Page shown when a sidechain app is launched on an unsupported network.
/// Drivechain is not enabled on mainnet/testnet yet, so sidechains can only
/// run on eCash, signet, or regtest.
@RoutePage()
class NetworkSwitchPage extends StatefulWidget {
  const NetworkSwitchPage({super.key});

  @override
  State<NetworkSwitchPage> createState() => _NetworkSwitchPageState();
}

class _NetworkSwitchPageState extends State<NetworkSwitchPage> {
  BitcoinConfProvider get _confProvider => GetIt.I.get<BitcoinConfProvider>();

  String _selectedNetworkId = 'signet';
  bool _isSwitching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default to signet as the recommended network
    _selectedNetworkId = 'signet';
  }

  /// The row the selector shows. The catalog decides the rows, so the default
  /// may not be among them; the switch has to submit what the user sees, or it
  /// sends an id no row carries and the page pops as though it worked.
  String get _effectiveNetworkId {
    final options = _confProvider.drivechainNetworkOptions;
    if (options.isEmpty) {
      return _selectedNetworkId;
    }
    if (options.any((o) => o.id == _selectedNetworkId)) {
      return _selectedNetworkId;
    }
    return options.first.id;
  }

  Future<void> _handleSwitch() async {
    setState(() {
      _isSwitching = true;
      _errorMessage = null;
    });

    try {
      await _confProvider.swapNetworkById(context, _effectiveNetworkId);

      if (mounted) {
        context.router.pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error switching network: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSwitching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final currentNetwork = _confProvider.network.toDisplayName();
    final dropdown = SailDropdownButton<String>(
      value: _effectiveNetworkId,
      items: [
        for (final option in _confProvider.drivechainNetworkOptions)
          SailDropdownItem<String>(
            value: option.id,
            label: option.id == 'signet' ? '${option.displayName} (Recommended)' : option.displayName,
          ),
      ],
      onChanged: (String? id) async {
        if (id != null) {
          setState(() {
            _selectedNetworkId = id;
          });
        }
      },
    );

    if (SailStyleValues.phoneLayout(context)) {
      return Scaffold(
        backgroundColor: theme.colors.background,
        body: SafeArea(
          child: DrivechainsNotEnabledPanel(
            currentNetwork: currentNetwork,
            networkSelector: dropdown,
            switching: _isSwitching,
            error: _errorMessage,
            onSwitch: _handleSwitch,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SailStyleValues.padding32),
            child: Container(
              key: const Key('drivechains-not-enabled-card'),
              width: 560,
              padding: const EdgeInsets.all(SailStyleValues.padding16),
              decoration: BoxDecoration(
                color: theme.colors.backgroundSecondary,
                borderRadius: theme.chrome.radiusLarge,
                border: Border.all(color: theme.colors.border),
              ),
              child: SailColumn(
                spacing: SailStyleValues.padding12,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SailText.primary20('Drivechains Not Enabled', bold: true),
                  SailText.secondary13(
                    'Drivechains are not enabled on $currentNetwork yet.\n'
                    'You must switch to eCash, Signet, or Regtest to use sidechains.',
                  ),
                  SailText.primary13('Select a network with drivechain support:'),
                  dropdown,
                  if (_errorMessage != null) SailText.secondary12(_errorMessage!, color: theme.colors.error),
                  SizedBox(
                    width: double.infinity,
                    child: SailButton(
                      label: 'Switch Network',
                      variant: ButtonVariant.primary,
                      loading: _isSwitching,
                      onPressed: _handleSwitch,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone form of the Drivechains Not Enabled page: one panel with the network selector and the switch button.
class DrivechainsNotEnabledPanel extends StatelessWidget {
  final String currentNetwork;
  final Widget networkSelector;
  final bool switching;
  final String? error;
  final Future<void> Function() onSwitch;

  const DrivechainsNotEnabledPanel({
    super.key,
    required this.currentNetwork,
    required this.networkSelector,
    required this.switching,
    required this.error,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailPanelPage(
      title: 'Drivechains Not Enabled',
      subtitle:
          'Drivechains are not enabled on $currentNetwork yet.\n'
          'You must switch to eCash, Signet, or Regtest to use sidechains.',
      actions: Align(
        alignment: Alignment.centerLeft,
        child: SailButton(
          label: 'Switch Network',
          variant: ButtonVariant.primary,
          loading: switching,
          onPressed: onSwitch,
        ),
      ),
      children: [
        SailText.secondary13('Select a network with drivechain support:'),
        const SizedBox(height: 8),
        networkSelector,
        if (error != null) ...[
          const SizedBox(height: 8),
          SailText.secondary12(error!, color: theme.colors.error),
        ],
      ],
    );
  }
}
