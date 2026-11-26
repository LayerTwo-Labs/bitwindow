import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

class HDWalletTab extends StatelessWidget {
  const HDWalletTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<HDWalletViewModel>.reactive(
      viewModelBuilder: () => HDWalletViewModel(),
      builder: (context, model, child) => SingleChildScrollView(
        child: SailColumn(
          spacing: SailStyleValues.phoneLayout(context) ? SailStyleValues.padding16 : 0,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ControlsCard(model: model),
            _AddressesSection(model: model),
          ],
        ),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  final HDWalletViewModel model;

  const _ControlsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return _PhoneControlsCard(model: model);
    }
    return SailCard(
      title: 'HD Wallet Explorer',
      error: model.errorMessage,
      child: SailColumn(
        spacing: SailStyleValues.padding16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mnemonic input
          SailColumn(
            spacing: SailStyleValues.padding08,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailText.primary13('Mnemonic Seed'),
              Row(
                children: [
                  SailButton(
                    label: 'Use Wallet',
                    onPressed: model.useWalletMnemonic,
                    variant: ButtonVariant.secondary,
                    small: true,
                  ),
                  const SizedBox(width: SailStyleValues.padding08),
                  SailButton(
                    label: 'Random',
                    onPressed: model.generateRandomMnemonic,
                    variant: ButtonVariant.secondary,
                    small: true,
                  ),
                  const SizedBox(width: SailStyleValues.padding16),
                  Expanded(child: _MnemonicField(model: model)),
                  const SizedBox(width: SailStyleValues.padding08),
                  SailButton(
                    label: 'Copy',
                    onPressed: model.mnemonicController.text.isEmpty
                        ? null
                        : () async => await model.copyMnemonic(context),
                    variant: ButtonVariant.secondary,
                    small: true,
                  ),
                  const SizedBox(width: SailStyleValues.padding08),
                  SailButton(
                    label: 'Clear',
                    onPressed: model.mnemonicController.text.isEmpty ? null : () async => model.clearAll(),
                    variant: ButtonVariant.secondary,
                    small: true,
                  ),
                  const SizedBox(width: SailStyleValues.padding08),
                  SailButton(
                    label: model.hideSecrets ? 'Show' : 'Hide',
                    onPressed: () async => model.toggleSecretVisibility(),
                    variant: ButtonVariant.secondary,
                    small: true,
                  ),
                ],
              ),
            ],
          ),
          // Derivation
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SailTextField(
                  label: 'Derivation Path',
                  controller: model.derivationPathController,
                  hintText: model.defaultDerivationPath,
                  size: TextFieldSize.small,
                ),
              ),
              const SizedBox(width: SailStyleValues.padding16),
              SailButton(
                label: 'Derive Addresses',
                onPressed: !model.canDeriveAddresses ? null : model.deriveAddresses,
                variant: model.canDeriveAddresses ? ButtonVariant.primary : ButtonVariant.secondary,
              ),
            ],
          ),
          // Master keys
          const SailSeparator(),
          SailColumn(
            spacing: SailStyleValues.padding08,
            children: [
              for (final (label, value, secret) in model._keyRows)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 160,
                      child: SailText.primary13('$label:', bold: true),
                    ),
                    Expanded(
                      child: SailText.primary13(
                        model._displayKey(value, secret),
                        monospace: true,
                      ),
                    ),
                    const SizedBox(width: SailStyleValues.padding08),
                    SailButton(
                      label: 'Copy',
                      onPressed: value.isEmpty
                          ? null
                          : () async => await model.copyToClipboard(context, value, label, secret: secret),
                      variant: ButtonVariant.secondary,
                      small: true,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MnemonicField extends StatelessWidget {
  final HDWalletViewModel model;

  const _MnemonicField({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailTextField(
      controller: model.mnemonicController,
      hintText: 'Enter mnemonic seed phrase',
      obscureText: model.hideSecrets,
      size: TextFieldSize.small,
    );
  }
}

class _PhoneControlsCard extends StatelessWidget {
  final HDWalletViewModel model;

  const _PhoneControlsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final empty = model.mnemonicController.text.isEmpty;
    return SailCard(
      title: 'HD Wallet Explorer',
      error: model.errorMessage,
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.primary13('Mnemonic Seed'),
          SailRow(
            spacing: SailStyleValues.padding08,
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SailButton(
                label: 'Use Wallet',
                onPressed: model.useWalletMnemonic,
                variant: ButtonVariant.secondary,
                small: true,
              ),
              SailButton(
                label: 'Random',
                onPressed: model.generateRandomMnemonic,
                variant: ButtonVariant.secondary,
                small: true,
              ),
            ],
          ),
          _MnemonicField(model: model),
          SailRow(
            spacing: SailStyleValues.padding08,
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SailButton(
                label: 'Copy',
                onPressed: empty ? null : () async => await model.copyMnemonic(context),
                variant: ButtonVariant.secondary,
                small: true,
              ),
              SailButton(
                label: 'Clear',
                onPressed: empty ? null : () async => model.clearAll(),
                variant: ButtonVariant.secondary,
                small: true,
              ),
              SailButton(
                label: model.hideSecrets ? 'Show' : 'Hide',
                onPressed: () async => model.toggleSecretVisibility(),
                variant: ButtonVariant.secondary,
                small: true,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SailTextField(
                  label: 'Derivation Path',
                  controller: model.derivationPathController,
                  hintText: model.defaultDerivationPath,
                  size: TextFieldSize.small,
                ),
              ),
              const SizedBox(width: SailStyleValues.padding12),
              SailButton(
                label: 'Derive Addresses',
                onPressed: !model.canDeriveAddresses ? null : model.deriveAddresses,
                variant: model.canDeriveAddresses ? ButtonVariant.primary : ButtonVariant.secondary,
              ),
            ],
          ),
          SailColumn(
            spacing: 0,
            withDivider: true,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value, secret) in model._keyRows)
                SailStackedValueRow(
                  label: label,
                  value: model._displayKey(value, secret),
                  strongLabel: true,
                  action: SailButton(
                    label: 'Copy',
                    variant: ButtonVariant.ghost,
                    small: true,
                    onPressed: value.isEmpty
                        ? null
                        : () async => await model.copyToClipboard(context, value, label, secret: secret),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressesSection extends StatelessWidget {
  final HDWalletViewModel model;

  const _AddressesSection({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'Derived Addresses',
      subtitle: '${model.derivedEntries.length} address(es)',
      bottomPadding: false,
      child: SailColumn(
        spacing: SailStyleValues.padding08,
        children: [
          Row(
            children: [
              SailButton(
                label: model.hidePrivateKeys ? 'Show Private Keys' : 'Hide Private Keys',
                onPressed: () async => model.togglePrivateKeyVisibility(),
                variant: ButtonVariant.secondary,
                small: true,
              ),
              const Spacer(),
              SailButton(
                label: 'Prev',
                onPressed: model.canGoPrevious ? () async => await model.changePage(false) : null,
                variant: ButtonVariant.secondary,
                small: true,
              ),
              const SizedBox(width: SailStyleValues.padding08),
              SailText.primary13('Page ${model.currentPage + 1}'),
              const SizedBox(width: SailStyleValues.padding08),
              SailButton(
                label: 'Next',
                onPressed: model.canGoNext ? () async => await model.changePage(true) : null,
                variant: ButtonVariant.secondary,
                small: true,
              ),
            ],
          ),
          AddressTable(entries: model.derivedEntries, hidePrivateKeys: model.hidePrivateKeys),
        ],
      ),
    );
  }
}

class HDWalletViewModel extends BaseViewModel {
  WalletReaderProvider get _reader => GetIt.I.get<WalletReaderProvider>();
  final TextEditingController mnemonicController = TextEditingController();
  BitcoinConfProvider get _conf => GetIt.I.get<BitcoinConfProvider>();
  late final TextEditingController derivationPathController = TextEditingController(text: defaultDerivationPath);

  /// The BIP84 receive chain of the wallet on the active network.
  String get defaultDerivationPath => "m/84'/${_conf.usesMainnetParams ? 0 : 1}'/0'/0";

  List<HDWalletEntry> _derivedEntries = [];
  String? _errorMessage;
  int _currentPage = 0;
  static const int _entriesPerPage = 10;

  String _masterSeed = '';
  String _xpriv = '';
  String _xpub = '';
  String _bip47PaymentCode = '';
  String _watchDescriptor = '';
  // The mnemonic and the path that the keys on the screen come from.
  String? _shownMnemonic;
  String? _shownPath;
  // An answer from an older run, or from before Clear, must not show its keys.
  int _exploreRun = 0;
  bool _hideSecrets = true;
  bool _hidePrivateKeys = true;

  // The orchestrator explores this wallet by its stored seed, so its passphrase counts.
  String? _walletId;
  String _walletMnemonic = '';

  // Getters
  List<HDWalletEntry> get derivedEntries => _derivedEntries;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  String get masterSeed => _masterSeed;
  String get xpriv => _xpriv;
  String get xpub => _xpub;
  String get bip47PaymentCode => _bip47PaymentCode;
  String get watchDescriptor => _watchDescriptor;
  bool get hideSecrets => _hideSecrets;
  bool get hidePrivateKeys => _hidePrivateKeys;
  bool get hasMnemonic => mnemonicController.text.trim().isNotEmpty;
  bool get canGoPrevious => _currentPage > 0 && _derivedEntries.isNotEmpty;
  bool get canGoNext => _derivedEntries.isNotEmpty;
  bool get canDeriveAddresses => hasMnemonic && derivationPathController.text.trim().isNotEmpty;
  bool get _exploresWallet => _walletId != null && mnemonicController.text.trim() == _walletMnemonic;

  List<(String, String, bool)> get _keyRows => [
    ('BIP47 Payment Code', bip47PaymentCode, false),
    ('Master Seed', masterSeed, true),
    ('XPRIV', xpriv, true),
    ('XPUB', xpub, false),
    ('Watch Descriptor', watchDescriptor, false),
  ];

  String _displayKey(String value, bool secret) => secret && hideSecrets && value.isNotEmpty ? _hiddenKey * 2 : value;

  OrchestratorWalletRPC get _orchestratorWallet => GetIt.I.get<OrchestratorRPC>().wallet;

  HDWalletViewModel() {
    mnemonicController.addListener(_onInputChange);
    derivationPathController.addListener(_onInputChange);
    _reader.addListener(_onWalletChange);
  }

  // Keys of another mnemonic or path must not stay on the screen.
  void _onInputChange() {
    if (_shownMnemonic != null && !_inputsAre(_shownMnemonic!, _shownPath!)) {
      _dropKeys();
    }
    notifyListeners();
  }

  bool _inputsAre(String mnemonic, String path) =>
      mnemonicController.text.trim() == mnemonic && derivationPathController.text.trim() == path;

  void _dropKeys() {
    _exploreRun++;
    _shownMnemonic = null;
    _shownPath = null;
    _masterSeed = '';
    _xpriv = '';
    _xpub = '';
    _bip47PaymentCode = '';
    _watchDescriptor = '';
    _derivedEntries = [];
    _currentPage = 0;
  }

  void _onWalletChange() {
    if (_walletId != null && _reader.activeWallet?.id != _walletId) {
      clearAll();
      derivationPathController.text = defaultDerivationPath;
    }
  }

  Future<void> useWalletMnemonic() async {
    _errorMessage = null;
    final wallet = _reader.activeWallet;
    if (wallet == null) {
      _errorMessage = "Couldn't load wallet mnemonic";
      notifyListeners();
      return;
    }

    final run = ++_exploreRun;
    try {
      final explored = await _orchestratorWallet.exploreSeed(
        walletId: wallet.id,
        basePath: '',
        startIndex: 0,
        count: 0,
      );
      if (run != _exploreRun || _reader.activeWallet?.id != wallet.id) {
        return;
      }
      _hideSecrets = true;
      _hidePrivateKeys = true;
      _walletId = wallet.id;
      _walletMnemonic = explored.mnemonic;
      mnemonicController.text = explored.mnemonic;
      derivationPathController.text = explored.basePath;
    } catch (e) {
      if (run == _exploreRun) {
        _errorMessage = 'Error loading wallet mnemonic: ${extractConnectException(e)}';
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> generateRandomMnemonic() async {
    _errorMessage = null;

    try {
      final mnemonic = await _orchestratorWallet.generateMnemonic();
      _hideSecrets = true;
      _hidePrivateKeys = true;
      mnemonicController.text = mnemonic;
    } catch (e) {
      _errorMessage = 'Error generating random mnemonic: ${extractConnectException(e)}';
    } finally {
      notifyListeners();
    }
  }

  Future<void> deriveAddresses() async {
    final mnemonic = mnemonicController.text.trim();
    if (mnemonic.isEmpty) {
      _errorMessage = 'Please enter a mnemonic seed phrase';
      notifyListeners();
      return;
    }

    await _explore(0);
    notifyListeners();
  }

  /// Shows the keys of [page]. A failure keeps the page on the screen.
  Future<void> _explore(int page) async {
    final mnemonic = mnemonicController.text.trim();
    final path = derivationPathController.text.trim();
    final run = ++_exploreRun;
    _errorMessage = null;
    try {
      final walletId = _exploresWallet ? _walletId! : '';
      final explored = await _orchestratorWallet.exploreSeed(
        mnemonic: walletId.isEmpty ? mnemonic : '',
        walletId: walletId,
        basePath: path,
        startIndex: page * _entriesPerPage,
        count: _entriesPerPage,
      );
      if (run != _exploreRun || !_inputsAre(mnemonic, path)) {
        return;
      }
      _shownMnemonic = mnemonic;
      _shownPath = path;
      _currentPage = page;
      _masterSeed = explored.seedHex;
      _xpriv = explored.xprv;
      _xpub = explored.xpub;
      _bip47PaymentCode = explored.bip47PaymentCode;
      _watchDescriptor = explored.watchDescriptor;
      _derivedEntries = [
        for (final key in explored.keys)
          HDWalletEntry(path: key.path, address: key.address, publicKey: key.publicKey, privateKey: key.wif),
      ];
    } catch (e) {
      if (run == _exploreRun) {
        _errorMessage = 'Error deriving keys: ${extractConnectException(e)}';
      }
    }
  }

  Future<void> changePage(bool next) async {
    if (!next && _currentPage == 0) {
      return;
    }
    await _explore(next ? _currentPage + 1 : _currentPage - 1);
    notifyListeners();
  }

  void clearAll() {
    _walletId = null;
    _walletMnemonic = '';
    _hideSecrets = true;
    _hidePrivateKeys = true;
    _dropKeys();
    mnemonicController.clear();
    _errorMessage = null;

    notifyListeners();
  }

  void toggleSecretVisibility() {
    _hideSecrets = !_hideSecrets;
    notifyListeners();
  }

  void togglePrivateKeyVisibility() {
    _hidePrivateKeys = !_hidePrivateKeys;
    notifyListeners();
  }

  Future<void> copyMnemonic(BuildContext context) async {
    await copySecretToClipboard(mnemonicController.text);
    if (context.mounted) {
      showSailToast(context, 'Mnemonic copied to clipboard');
    }
  }

  Future<void> copyToClipboard(BuildContext context, String text, String label, {bool secret = false}) async {
    if (secret) {
      await copySecretToClipboard(text);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
    if (context.mounted) {
      showSailToast(context, '${label.replaceAll(':', '')} copied to clipboard');
    }
  }

  @override
  void dispose() {
    _reader.removeListener(_onWalletChange);
    mnemonicController.removeListener(_onInputChange);
    derivationPathController.removeListener(_onInputChange);
    mnemonicController.dispose();
    derivationPathController.dispose();
    super.dispose();
  }
}

class AddressTable extends StatelessWidget {
  final List<HDWalletEntry> entries;
  final bool hidePrivateKeys;

  const AddressTable({
    super.key,
    required this.entries,
    required this.hidePrivateKeys,
  });

  @override
  Widget build(BuildContext context) {
    return SailTable(
      phoneColumns: hidePrivateKeys ? const [0, 1] : const [0, 1, 3],
      getRowId: (index) => entries.isEmpty ? 'empty$index' : entries[index].path,
      drawGrid: true,
      shrinkWrap: true,
      headerBuilder: (context) => [
        const SailTableHeaderCell(name: 'Path'),
        const SailTableHeaderCell(name: 'Address'),
        const SailTableHeaderCell(name: 'Public Key'),
        const SailTableHeaderCell(name: 'Private Key (WIF)'),
      ],
      rowBuilder: (context, row, selected) {
        final entry = entries[row];
        return [
          SailTableCell(value: entry.path, monospace: true, hugContent: true),
          SailTableCell(value: entry.address, monospace: true, hugContent: true),
          _keyCell(entry.publicKey, fill: true),
          hidePrivateKeys
              ? const SailTableCell(value: _hiddenKey, monospace: true, hugContent: true)
              : _keyCell(entry.privateKey),
        ];
      },
      rowCount: entries.isEmpty ? 0 : entries.length,
      emptyPlaceholder: 'Enter a mnemonic and derivation path to derive addresses',
    );
  }
}

const _hiddenKey = '••••••••••••••••';

/// A key cell. A key longer than the column ends with an ellipsis, and a copy gives the full key.
SailTableCell _keyCell(String key, {bool fill = false}) => SailTableCell(
  value: key.characters.take(_hiddenKey.length).toString(),
  copyValue: key,
  monospace: true,
  fill: fill,
  hugContent: !fill,
  child: SailText.primary13(key, monospace: true, overflow: TextOverflow.ellipsis),
);

class HDWalletEntry {
  final String path;
  final String address;
  final String publicKey;
  final String privateKey;

  HDWalletEntry({
    required this.path,
    required this.address,
    required this.publicKey,
    required this.privateKey,
  });
}
