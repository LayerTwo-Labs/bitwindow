import 'dart:async';

import 'package:bitwindow/utils/explorer_url.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

const _ticker = 'ECX';
const _checkDebounce = Duration(milliseconds: 400);

enum ClaimEcxStage { idle, invalid, checking, funds, empty, claiming, claimed, failed }

/// Self-contained claim of an investor ECX key: paste it, see what it holds,
/// choose where it lands, sweep it.
class ClaimEcxCard extends StatefulWidget {
  const ClaimEcxCard({super.key});

  @override
  State<ClaimEcxCard> createState() => _ClaimEcxCardState();
}

class _ClaimEcxCardState extends State<ClaimEcxCard> {
  final BitwindowRPC _bitwindow = GetIt.I.get<BitwindowRPC>();
  final OrchestratorWalletRPC _orchestratorWallet = GetIt.I.get<OrchestratorRPC>().wallet;
  final WalletReaderProvider _walletReader = GetIt.I.get<WalletReaderProvider>();

  final TextEditingController _wifController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  ClaimEcxStage _stage = ClaimEcxStage.idle;
  SweepPreview? _preview;
  String? _previewedWif;
  String? _walletAddress;
  String? _walletAddressFor;
  bool _editingDestination = false;
  String? _txid;
  int _claimedSats = 0;
  String _failure = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _wifController.dispose();
    _destController.dispose();
    super.dispose();
  }

  String get _wif => _wifController.text.trim();

  String get _destination => _editingDestination ? _destController.text.trim() : (_walletAddress ?? '');

  bool get _destinationReady => _destination.length >= 26;

  void _onWifChanged(String value) {
    _debounce?.cancel();
    final wif = value.trim();

    if (wif.isEmpty) {
      setState(() {
        _stage = ClaimEcxStage.idle;
        _preview = null;
        _previewedWif = null;
      });
      return;
    }

    if (_previewedWif != null && _previewedWif != wif) {
      setState(() {
        _stage = ClaimEcxStage.checking;
        _preview = null;
        _previewedWif = null;
      });
    }

    _debounce = Timer(_checkDebounce, _check);
  }

  Future<void> _check() async {
    final wif = _wif;
    if (wif.isEmpty) {
      return;
    }

    try {
      final validity = await _bitwindow.utils.validateWIF(wif);
      if (!mounted || _wif != wif) {
        return;
      }
      if (!validity.valid) {
        setState(() {
          _stage = ClaimEcxStage.invalid;
          _preview = null;
          _previewedWif = null;
        });
        return;
      }

      setState(() => _stage = ClaimEcxStage.checking);

      final preview = await _bitwindow.wallet.previewSweep(wif);
      if (!mounted || _wif != wif) {
        return;
      }

      if (preview.hasFunds) {
        await _loadWalletAddress();
        if (!mounted) {
          return;
        }
      }

      setState(() {
        _preview = preview;
        _previewedWif = wif;
        _stage = preview.hasFunds ? ClaimEcxStage.funds : ClaimEcxStage.empty;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = ClaimEcxStage.failed;
        _failure = _reason(e);
      });
    }
  }

  Future<void> _loadWalletAddress() async {
    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      return;
    }
    if (_walletAddress != null && _walletAddressFor == walletId) {
      return;
    }

    final address = await _orchestratorWallet.getNewAddress(walletId);
    if (!mounted) {
      return;
    }
    setState(() {
      _walletAddress = address.address;
      _walletAddressFor = walletId;
    });
  }

  Future<void> _claim() async {
    final preview = _preview;
    final previewedWif = _previewedWif;
    if (preview == null || previewedWif == null || previewedWif != _wif) {
      return;
    }

    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      setState(() {
        _stage = ClaimEcxStage.failed;
        _failure = 'No wallet is open.';
      });
      return;
    }

    if (!_editingDestination) {
      await _loadWalletAddress();
      if (!mounted) {
        return;
      }
    }

    setState(() => _stage = ClaimEcxStage.claiming);

    try {
      final result = await _bitwindow.wallet.sweepCheque(
        walletId,
        previewedWif,
        _destination,
        preview.feeSatPerVbyte,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _txid = result.txid;
        _claimedSats = preview.receiveSats;
        _stage = ClaimEcxStage.claimed;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      if (e.toString().toLowerCase().contains('wallet is locked')) {
        await _unlockThenClaim();
        return;
      }

      setState(() {
        _stage = ClaimEcxStage.failed;
        _failure = _reason(e);
      });
    }
  }

  Future<void> _unlockThenClaim() async {
    setState(() => _stage = ClaimEcxStage.funds);

    final unlocked = await showUnlockWalletDialog(
      context,
      title: 'Unlock your wallet',
      message: 'Your wallet must be open to receive the claim.',
      wrongPasswordText: 'That password is wrong',
    );
    if (!mounted || !unlocked) {
      return;
    }

    await _claim();
  }

  void _reset() {
    _debounce?.cancel();
    _wifController.clear();
    _destController.clear();
    setState(() {
      _stage = ClaimEcxStage.idle;
      _preview = null;
      _previewedWif = null;
      _editingDestination = false;
      _walletAddress = null;
      _walletAddressFor = null;
      _txid = null;
      _claimedSats = 0;
      _failure = '';
    });
  }

  String _reason(Object e) {
    final text = e is WalletException ? e.message : e.toString();
    return text.replaceFirst(RegExp(r'^\w+_error: ', caseSensitive: false), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return switch (_stage) {
      ClaimEcxStage.claimed => _ClaimedCard(
        amountSats: _claimedSats,
        txid: _txid ?? '',
        destination: _destination,
        onAnother: _reset,
      ),
      ClaimEcxStage.failed => _FailedCard(
        reason: _failure,
        onRetry: _preview?.hasFunds == true ? _claim : _check,
        onDifferentKey: _reset,
      ),
      _ => _formCard(theme),
    };
  }

  Widget _formCard(SailThemeData theme) {
    final preview = _preview;
    final showFunds =
        preview != null && preview.hasFunds && (_stage == ClaimEcxStage.funds || _stage == ClaimEcxStage.claiming);

    return SailCard(
      child: SailColumn(
        spacing: 0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Head(title: 'Claim your $_ticker'),
          const SailSpacing(SailStyleValues.padding04),
          SailText.secondary13(
            'Paste the private key from your investor letter. Nothing moves until you see the amount.',
          ),
          const SailSpacing(SailStyleValues.padding16),
          SailText.primary12('Private key', bold: true),
          const SailSpacing(SailStyleValues.padding08),
          SailTextField(
            controller: _wifController,
            hintText: 'L1aW… or 5K…',
            monospace: true,
            maxLines: 1,
            enabled: _stage != ClaimEcxStage.claiming,
            onChanged: _onWifChanged,
            suffixWidget: PasteButton(
              onPaste: (text) {
                _wifController.text = text.trim();
                _onWifChanged(text);
              },
            ),
          ),
          const SailSpacing(SailStyleValues.padding10),
          _hint(theme),
          if (showFunds) ...[
            const SailSpacing(SailStyleValues.padding16),
            Divider(height: 1, color: theme.colors.divider),
            const SailSpacing(SailStyleValues.padding16),
            _ClaimAmount(formatEcx(preview.amountSats)),
            const SailSpacing(SailStyleValues.padding04),
            SailText.secondary12(
              '${preview.outputCount} ${preview.outputCount == 1 ? 'output' : 'outputs'} · ${shortenAddress(preview.address)}',
            ),
            const SailSpacing(SailStyleValues.padding16),
            SailText.secondary12('SEND TO'),
            const SailSpacing(SailStyleValues.padding08),
            _destinationField(theme),
            const SailSpacing(SailStyleValues.padding12),
            _totalRow('Network fee', formatEcx(preview.feeSats), theme.colors.textSecondary),
            const SailSpacing(SailStyleValues.padding04),
            _totalRow('You receive', formatEcx(preview.receiveSats), theme.colors.text, bold: true),
          ],
          const SailSpacing(SailStyleValues.padding16),
          _actionButton(),
        ],
      ),
    );
  }

  Widget _hint(SailThemeData theme) {
    return switch (_stage) {
      ClaimEcxStage.invalid => _HintRow(
        icon: SailSVGAsset.circleAlert,
        color: theme.colors.error,
        text: 'Not a private key — check for a missing character.',
      ),
      ClaimEcxStage.empty => _HintRow(
        icon: SailSVGAsset.circleAlert,
        color: theme.colors.textTertiary,
        text: 'This key is empty — nothing to claim.',
      ),
      ClaimEcxStage.funds || ClaimEcxStage.claiming => _HintRow(
        icon: SailSVGAsset.circleCheck,
        color: theme.colors.success,
        text: 'This key has funds to claim.',
      ),
      _ => SailText.secondary12('The key stays on this computer.'),
    };
  }

  Widget _destinationField(SailThemeData theme) {
    if (_editingDestination) {
      return SailColumn(
        spacing: SailStyleValues.padding08,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailTextField(
            controller: _destController,
            hintText: 'Paste an address you control',
            monospace: true,
            maxLines: 1,
            enabled: _stage != ClaimEcxStage.claiming,
            onChanged: (_) => setState(() {}),
            suffixWidget: PasteButton(
              onPaste: (text) => setState(() => _destController.text = text.trim()),
            ),
          ),
          SailButton(
            label: 'Use my wallet address',
            variant: ButtonVariant.link,
            small: true,
            onPressed: () async => setState(() {
              _editingDestination = false;
              _destController.clear();
            }),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SailStyleValues.padding12,
        vertical: SailStyleValues.padding10,
      ),
      decoration: BoxDecoration(
        color: theme.colors.background,
        borderRadius: context.sailTheme.chrome.radius,
        border: Border.all(color: theme.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: SailColumn(
              spacing: SailStyleValues.padding04,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary13('Your wallet', bold: true),
                SailText.secondary12(_walletAddress ?? 'Loading an address…'),
              ],
            ),
          ),
          SailButton(
            label: 'Change',
            variant: ButtonVariant.link,
            small: true,
            onPressed: () async => setState(() => _editingDestination = true),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SailText.secondary12(label),
        SailText.primary13(value, bold: bold, color: color),
      ],
    );
  }

  Widget _actionButton() {
    final preview = _preview;

    return switch (_stage) {
      ClaimEcxStage.checking => const _WideButton(
        label: 'Checking if the key has funds…',
        loading: true,
      ),
      ClaimEcxStage.claiming => _WideButton(
        label: 'Claiming ${formatEcx(preview?.receiveSats ?? 0)}…',
        loading: true,
      ),
      ClaimEcxStage.empty => _WideButton(
        label: 'Check again',
        icon: SailSVGAsset.refreshCw,
        onPressed: _check,
      ),
      ClaimEcxStage.funds => _WideButton(
        label: 'Claim ${formatEcx(preview?.receiveSats ?? 0)}',
        icon: SailSVGAsset.coins,
        disabled: !_destinationReady,
        onPressed: _claim,
      ),
      _ => const _WideButton(label: 'Claim $_ticker', icon: SailSVGAsset.coins, disabled: true),
    };
  }
}

class _ClaimedCard extends StatelessWidget {
  final int amountSats;
  final String txid;
  final String destination;
  final VoidCallback onAnother;

  const _ClaimedCard({
    required this.amountSats,
    required this.txid,
    required this.destination,
    required this.onAnother,
  });

  @override
  Widget build(BuildContext context) {
    final network = GetIt.I.get<BitcoinConfProvider>().network;
    final url = mempoolTxUrl(txid, network);

    return SailCard(
      child: SailColumn(
        spacing: 0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(
            title: '$_ticker claimed',
            menuItems: () => [
              SailMenuItem(onSelected: onAnother, child: SailText.primary12('Claim another key')),
            ],
          ),
          const SailSpacing(SailStyleValues.padding04),
          SailText.secondary13('Your $_ticker is on the way to your wallet. It lands in the next block.'),
          const SailSpacing(SailStyleValues.padding16),
          _ClaimAmount(formatEcx(amountSats)),
          const SailSpacing(SailStyleValues.padding04),
          SailText.secondary12('To ${shortenAddress(destination)}'),
          const SailSpacing(SailStyleValues.padding16),
          SailDetailGroup(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [SailDetailLine(label: 'TXID', value: shortenAddress(txid), wrap: true, gap: 16)],
          ),
          const SailSpacing(SailStyleValues.padding16),
          _WideButton(
            label: 'View on explorer',
            icon: SailSVGAsset.externalLink,
            onPressed: () async => openUrl(Uri.parse(url)),
          ),
        ],
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  final String reason;
  final Future<void> Function() onRetry;
  final VoidCallback onDifferentKey;

  const _FailedCard({required this.reason, required this.onRetry, required this.onDifferentKey});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return SailCard(
      child: SailColumn(
        spacing: 0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Head(
            title: 'Claim failed',
            menuItems: () => [
              SailMenuItem(onSelected: onDifferentKey, child: SailText.primary12('Use a different key')),
            ],
          ),
          const SailSpacing(SailStyleValues.padding04),
          SailText.secondary13('The network refused the transaction. Your key is untouched and nothing moved.'),
          const SailSpacing(SailStyleValues.padding12),
          SailText.primary12(reason, color: theme.colors.error, overflow: TextOverflow.visible),
          const SailSpacing(SailStyleValues.padding16),
          _WideButton(label: 'Try again', icon: SailSVGAsset.refreshCw, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String title;

  /// The actions of the "…" menu. Null hides the menu.
  final List<SailMenuEntity> Function()? menuItems;

  const _Head({required this.title, this.menuItems});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SailText.primary16(title, bold: true)),
        if (menuItems != null) SailRowMenuButton(items: menuItems!),
      ],
    );
  }
}

class _HintRow extends StatelessWidget {
  final SailSVGAsset icon;
  final Color color;
  final String text;

  const _HintRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SailSVG.icon(icon, width: 14, height: 14, color: color),
        const SizedBox(width: SailStyleValues.padding08),
        Flexible(child: SailText.primary12(text, color: color)),
      ],
    );
  }
}

class _WideButton extends StatelessWidget {
  final String label;
  final SailSVGAsset? icon;
  final bool loading;
  final bool disabled;
  final Future<void> Function()? onPressed;

  const _WideButton({
    required this.label,
    this.icon,
    this.loading = false,
    this.disabled = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SailButton(
        label: label,
        icon: icon,
        loading: loading,
        disabled: disabled || onPressed == null,
        onPressed: onPressed ?? () async {},
      ),
    );
  }
}

/// Renders sats as a grouped 8-decimal ECX amount.
String formatEcx(int sats) {
  final whole = (sats ~/ 100000000).toString();
  final grouped = whole.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  final fraction = (sats % 100000000).toString().padLeft(8, '0');
  return '$grouped.$fraction $_ticker';
}

/// Elides the middle of an address or txid.
String shortenAddress(String value) {
  if (value.length <= 24) {
    return value;
  }
  return '${value.substring(0, 12)}…${value.substring(value.length - 8)}';
}

class _ClaimAmount extends StatelessWidget {
  final String amount;

  const _ClaimAmount(this.amount);

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return SailText.primary18(amount);
    }
    return SailText.primary24(amount);
  }
}
