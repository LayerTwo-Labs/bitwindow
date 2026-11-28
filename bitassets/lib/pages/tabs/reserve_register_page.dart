import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:thirds/blake3.dart';

@RoutePage()
class BitAssetsTabPage extends StatelessWidget {
  const BitAssetsTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<BitAssetsViewModel>.reactive(
        viewModelBuilder: () => BitAssetsViewModel(),
        builder: (context, model, child) {
          final details = model.detailsEntry;
          final tabs = InlineTabBar(
            onTabChanged: (_) => model.closeDetails(),
            tabs: [
              TabItem(
                label: 'My Assets',
                child: MyAssetsTab(model: model),
              ),
              TabItem(
                label: 'Send',
                child: SendBitAssetTab(model: model),
              ),
              TabItem(
                label: 'Receive',
                child: ReceiveBitAssetTab(),
              ),
              TabItem(
                label: 'All Assets',
                child: AllAssetsTab(model: model),
              ),
              TabItem(
                label: 'Register',
                child: RegisterBitAssetTab(model: model),
              ),
            ],
            initialIndex: 0,
          );
          final showPanel = details != null && !SailStyleValues.phoneLayout(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tabs),
              if (showPanel) ...[
                const SizedBox(width: SailStyleValues.padding12),
                BitAssetDetailsPanel(entry: details, onClose: () async => model.closeDetails()),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Tab showing user's owned BitAssets
class MyAssetsTab extends StatelessWidget {
  final BitAssetsViewModel model;

  const MyAssetsTab({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'Your BitAssets',
      subtitle: 'The BitAssets your wallet holds',
      widgetHeaderEnd: SizedBox(
        width: 240,
        child: SailTextField(hintText: 'Search your bitassets...', controller: model.searchController),
      ),
      child: SailSkeletonizer(
        description: 'Loading bitassets...',
        enabled: model.isLoading,
        child: SailTable(
          getRowId: (index) => model.myEntries[index].hash,
          selectedRowId: model.detailsEntry?.hash,
          onSelectedRow: (rowId) => model.showDetailsById(context, model.myEntries, rowId),
          headerBuilder: (context) => [
            SailTableHeaderCell(name: 'Name'),
            SailTableHeaderCell(name: 'Hash'),
            SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight),
            SailTableHeaderCell(name: 'Sequence ID'),
            SailTableHeaderCell(name: 'Encryption Key'),
            SailTableHeaderCell(name: 'Signing Key'),
          ],
          rowBuilder: (context, row, selected) {
            final entry = model.myEntries[row];
            final shortHash = '${entry.hash.substring(0, 10)}..';
            return [
              SailTableCell(value: entry.plaintextName ?? '<unknown>'),
              SailTableCell(value: shortHash, copyValue: entry.hash),
              SailTableCell(
                value: model.amountOf(entry.hash).toString(),
                monospace: true,
                alignment: Alignment.centerRight,
              ),
              SailTableCell(value: entry.sequenceID.toString()),
              SailTableCell(value: entry.details.encryptionPubkey != null ? 'Set' : '-'),
              SailTableCell(value: entry.details.signingPubkey != null ? 'Set' : '-'),
            ];
          },
          contextMenuItems: (rowId) {
            final entry = model.myEntries.firstWhereOrNull((e) => e.hash == rowId);
            if (entry == null) return [];
            return [
              SailMenuItem(
                onSelected: () async => model.showDetails(context, entry),
                child: SailText.primary12('Show Details'),
              ),
            ];
          },
          rowCount: model.myEntries.length,
          drawGrid: true,
        ),
      ),
    );
  }
}

/// Tab for sending/transferring BitAssets
class SendBitAssetTab extends StatefulWidget {
  final BitAssetsViewModel model;

  const SendBitAssetTab({super.key, required this.model});

  @override
  State<SendBitAssetTab> createState() => _SendBitAssetTabState();
}

class _SendBitAssetTabState extends State<SendBitAssetTab> {
  final BitAssetsRPC _rpc = GetIt.I.get<BitAssetsRPC>();
  final NotificationProvider _notifications = GetIt.I.get<NotificationProvider>();

  final TextEditingController _destController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  String? _selectedAssetId;
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _destController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_selectedAssetId == null) {
      setState(() => _error = 'Please select a BitAsset');
      return;
    }
    if (_destController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a destination address');
      return;
    }
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter a valid amount');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final txid = await _rpc.transferBitAsset(
        assetId: _selectedAssetId!,
        dest: _destController.text.trim(),
        amount: amount,
        feeSats: 1000, // Fixed fee for now
      );

      _notifications.add(
        title: 'Success',
        content: 'BitAsset transferred successfully! TXID: $txid',
        dialogType: DialogType.success,
      );

      // Clear form
      _destController.clear();
      _amountController.clear();
      setState(() => _selectedAssetId = null);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myAssets = widget.model.myEntries;

    return _FormColumn(
      child: SailCard(
        title: 'Send BitAsset',
        subtitle: 'Transfer BitAsset tokens to another address',
        error: _error,
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SailDropdownButton<String>(
              value: _selectedAssetId,
              items: myAssets
                  .map(
                    (a) => SailDropdownItem<String>(
                      value: a.hash,
                      label: '${a.plaintextName ?? '${a.hash.substring(0, 10)}...'} (${widget.model.amountOf(a.hash)})',
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedAssetId = v),
            ),
            SailTextField(
              label: 'Destination Address',
              hintText: 'Enter recipient address',
              controller: _destController,
            ),
            NumericField(
              label: 'Amount',
              hintText: '0',
              controller: _amountController,
            ),
            SailButton(
              label: 'Send',
              onPressed: _send,
              loading: _isSending,
              disabled: myAssets.isEmpty,
            ),
            if (myAssets.isEmpty)
              SailText.secondary13(
                'Your wallet holds no BitAssets.',
                color: context.sailTheme.colors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

/// Tab for receiving BitAssets (showing address)
class ReceiveBitAssetTab extends StatefulWidget {
  const ReceiveBitAssetTab({super.key});

  @override
  State<ReceiveBitAssetTab> createState() => _ReceiveBitAssetTabState();
}

class _ReceiveBitAssetTabState extends State<ReceiveBitAssetTab> {
  final BitAssetsRPC _rpc = GetIt.I.get<BitAssetsRPC>();
  String? _address;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    try {
      final address = await _rpc.getSideAddress();
      if (mounted) {
        setState(() {
          _address = address;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormColumn(
      child: SailCard(
        title: 'Receive BitAssets',
        subtitle: 'Share this address to receive BitAsset tokens',
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          mainAxisSize: MainAxisSize.min,
          children: [
            SailTextField(
              label: 'Your Sidechain Address',
              loading: LoadingDetails(
                enabled: _isLoading,
                description: 'Generating address...',
              ),
              controller: TextEditingController(text: _address ?? ''),
              hintText: 'Generating deposit address...',
              readOnly: true,
              suffixWidget: CopyButton(text: _address ?? ''),
            ),
            SailText.secondary13(
              'This is your sidechain address. Send BitAsset tokens to this address to receive them.',
              color: context.sailTheme.colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab showing all registered BitAssets
class AllAssetsTab extends StatelessWidget {
  final BitAssetsViewModel model;

  const AllAssetsTab({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'All BitAssets',
      subtitle: 'All registered BitAssets on the network',
      widgetHeaderEnd: SizedBox(
        width: 240,
        child: SailTextField(hintText: 'Search bitassets...', controller: model.searchController),
      ),
      child: SailSkeletonizer(
        description: 'Loading bitassets...',
        enabled: model.isLoading,
        child: SailTable(
          getRowId: (index) => model.entries[index].hash,
          selectedRowId: model.detailsEntry?.hash,
          onSelectedRow: (rowId) => model.showDetailsById(context, model.entries, rowId),
          headerBuilder: (context) => [
            SailTableHeaderCell(name: 'Name'),
            SailTableHeaderCell(name: 'Hash'),
            SailTableHeaderCell(name: 'Sequence ID'),
            SailTableHeaderCell(name: 'Commitment'),
            SailTableHeaderCell(name: 'Encryption Key'),
            SailTableHeaderCell(name: 'Signing Key'),
          ],
          rowBuilder: (context, row, selected) {
            final entry = model.entries[row];
            final shortHash = '${entry.hash.substring(0, 10)}..';
            return [
              SailTableCell(value: entry.plaintextName ?? '<unknown>'),
              SailTableCell(value: shortHash, copyValue: entry.hash),
              SailTableCell(value: entry.sequenceID.toString()),
              entry.details.commitment == null
                  ? const SailTableCell(value: '-')
                  : SailTableCell(
                      value: entry.details.commitment!.length > 36
                          ? '${entry.details.commitment!.substring(0, 36)}...'
                          : entry.details.commitment!,
                      copyValue: entry.details.commitment,
                    ),
              SailTableCell(value: entry.details.encryptionPubkey != null ? 'Set' : '-'),
              SailTableCell(value: entry.details.signingPubkey != null ? 'Set' : '-'),
            ];
          },
          contextMenuItems: (rowId) {
            final entry = model.entries.firstWhereOrNull((e) => e.hash == rowId);
            if (entry == null) return [];
            return [
              SailMenuItem(
                onSelected: () async => model.showDetails(context, entry),
                child: SailText.primary12('Show Details'),
              ),
            ];
          },
          rowCount: model.entries.length,
          drawGrid: true,
        ),
      ),
    );
  }
}

class RegisterBitAssetTab extends StatelessWidget {
  final BitAssetsViewModel model;

  const RegisterBitAssetTab({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final reserve = SailCard(
      title: 'Reserve',
      subtitle: 'Reserve a name before registering',
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailTextField(
            label: 'Plaintext Name',
            hintText: 'Enter name to reserve',
            controller: model.reserveNameController,
            enabled: !model.reserveLoading,
            errorText: model.reserveError,
          ),
          SailButton(
            label: 'Reserve',
            onPressed: () => model.reserveBitname(context),
            loading: model.reserveLoading,
          ),
        ],
      ),
    );
    final register = SailCard(
      title: 'Register',
      subtitle: 'Register a reserved name with data',
      error: model.registerError,
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Pair(
            first: SailTextField(
              label: 'Plaintext Name',
              hintText: 'Enter name to register',
              controller: model.registerNameController,
            ),
            second: SailTextField(
              label: 'Initial Supply',
              hintText: 'Enter initial supply',
              controller: model.initialSupplyController,
            ),
          ),
          SailTextField(
            label: 'Commitment (optional)',
            hintText: '64-character hex Blake3 hash',
            controller: model.commitmentController,
          ),
          _Pair(
            first: SailTextField(
              label: 'IPv4 Address (optional)',
              hintText: 'Enter IPv4 address',
              controller: model.ipv4Controller,
            ),
            second: SailTextField(
              label: 'IPv6 Address (optional)',
              hintText: 'Enter IPv6 address',
              controller: model.ipv6Controller,
            ),
          ),
          SailCheckbox(
            label: 'Set Encryption Pubkey',
            value: model.useEncryptionKey,
            onChanged: (value) {
              model.useEncryptionKey = value;
              model.notifyListeners();
            },
          ),
          if (model.useEncryptionKey && model.encryptionKey != null)
            SailTextField(
              label: 'Encryption Pubkey',
              controller: TextEditingController(text: model.encryptionKey),
              hintText: 'Encryption Pubkey',
              readOnly: true,
            ),
          SailCheckbox(
            label: 'Set Signing Pubkey',
            value: model.useSigningKey,
            onChanged: (value) {
              model.useSigningKey = value;
              model.notifyListeners();
            },
          ),
          if (model.useSigningKey && model.signingKey != null)
            SailTextField(
              label: 'Signing Pubkey',
              controller: TextEditingController(text: model.signingKey),
              hintText: 'Signing Pubkey',
              readOnly: true,
            ),
          SailButton(
            label: 'Register',
            onPressed: () => model.registerBitAsset(context),
            loading: model.registerLoading,
          ),
        ],
      ),
    );

    if (SailStyleValues.phoneLayout(context)) {
      return SingleChildScrollView(
        child: SailColumn(spacing: SailStyleValues.padding12, children: [reserve, register]),
      );
    }
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: reserve),
          const SizedBox(width: SailStyleValues.padding12),
          Expanded(flex: 2, child: register),
        ],
      ),
    );
  }
}

/// Two fields side by side; a phone stacks them.
class _Pair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _Pair({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: SailStyleValues.padding12),
        Expanded(child: second),
      ],
    );
  }
}

/// Holds a form card at the top left, at a readable width.
class _FormColumn extends StatelessWidget {
  final Widget child;

  const _FormColumn({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
      ),
    );
  }
}

/// The 380 px panel with every field of one BitAsset.
class BitAssetDetailsPanel extends StatelessWidget {
  final BitAssetEntry entry;
  final Future<void> Function() onClose;

  const BitAssetDetailsPanel({super.key, required this.entry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SailSidePanel(
      key: ValueKey('bitasset_details_${entry.hash}'),
      title: 'BitAsset Details',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.primary24(entry.plaintextName ?? '<unknown>', bold: true),
          const SizedBox(height: SailStyleValues.padding12),
          SailDetailGroup(children: _detailLines(entry)),
        ],
      ),
    );
  }
}

List<Widget> _detailLines(BitAssetEntry entry) => [
  SailStackedDetail(label: 'Hash', value: entry.hash),
  SailStackedDetail(label: 'Sequence ID', value: entry.sequenceID.toString()),
  if (entry.plaintextName != null) SailStackedDetail(label: 'Name', value: entry.plaintextName!),
  if (entry.details.commitment != null) SailStackedDetail(label: 'Commitment', value: entry.details.commitment!),
  if (entry.details.socketAddrV4 != null)
    SailStackedDetail(label: 'Socket Address (IPv4)', value: entry.details.socketAddrV4!),
  if (entry.details.socketAddrV6 != null)
    SailStackedDetail(label: 'Socket Address (IPv6)', value: entry.details.socketAddrV6!),
  if (entry.details.encryptionPubkey != null)
    SailStackedDetail(label: 'Encryption Public Key', value: entry.details.encryptionPubkey!),
  if (entry.details.signingPubkey != null)
    SailStackedDetail(label: 'Signing Public Key', value: entry.details.signingPubkey!),
];

Future<void> showBitAssetDetails(BuildContext context, BitAssetEntry entry) async {
  await Future.microtask(() async {
    if (!context.mounted) return;
    return showThemedDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: true,
          child: SailModal(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SailCard(
              title: 'BitAsset Details',
              subtitle: entry.plaintextName ?? entry.hash,
              withCloseButton: true,
              child: SingleChildScrollView(child: SailDetailGroup(children: _detailLines(entry))),
            ),
          ),
        );
      },
    );
  });
}

class BitAssetsViewModel extends BaseViewModel {
  final NotificationProvider notificationProvider = GetIt.I.get<NotificationProvider>();
  final BitAssetsProvider provider = GetIt.I.get<BitAssetsProvider>();
  final BitAssetsRPC bitassetsRPC = GetIt.I.get<BitAssetsRPC>();

  String? reserveError;
  bool reserveLoading = false;

  final TextEditingController searchController = TextEditingController();
  final TextEditingController reserveNameController = TextEditingController();
  final TextEditingController initialSupplyController = TextEditingController();
  final TextEditingController registerNameController = TextEditingController();
  final TextEditingController commitmentController = TextEditingController();
  final TextEditingController ipv4Controller = TextEditingController();
  final TextEditingController ipv6Controller = TextEditingController();
  final TextEditingController paymailFeeController = TextEditingController();

  // Keys
  String? encryptionKey;
  String? signingKey;

  // Register state
  bool registerLoading = false;
  String? registerError;

  /// The asset the side panel shows. Null hides the panel.
  BitAssetEntry? detailsEntry;

  // New state variables
  bool useEncryptionKey = false;
  bool useSigningKey = false;

  BitAssetsViewModel() {
    searchController.addListener(notifyListeners);
    provider.addListener(notifyListeners);
    provider.fetch();
    reserveNameController.addListener(() {
      reserveError = null;
      notifyListeners();
    });

    generateKeysWithRetry();
  }

  Future<void> generateKeysWithRetry() async {
    encryptionKey = null;
    signingKey = null;

    while (encryptionKey == null || signingKey == null) {
      try {
        if (encryptionKey == null) {
          encryptionKey = await bitassetsRPC.getNewEncryptionKey();
          notifyListeners();
        }

        if (signingKey == null) {
          signingKey = await bitassetsRPC.getNewVerifyingKey();
          notifyListeners();
        }
      } catch (e) {
        // If there's an error, wait a bit before retrying
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  List<BitAssetEntry> get entries {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      return provider.entries;
    }
    final searchText = query.toLowerCase();
    final searchHash = blake3Hex(utf8.encode(query));

    return provider.entries.where((entry) {
      if (entry.hash.toLowerCase() == searchHash) {
        if (entry.plaintextName == null && provider.hashNameMapping.nameFromHash(entry.hash) == null) {
          unawaited(provider.saveHashNameMapping(query));
        }
        return true;
      }
      if (entry.plaintextName?.toLowerCase().contains(searchText) ?? false) {
        return true;
      }

      // Search in hash
      if (entry.hash.toLowerCase().contains(searchText)) {
        return true;
      }
      // Search in sequence ID
      if (entry.sequenceID.toString().toLowerCase().contains(searchText)) {
        return true;
      }
      // Search in encryption key
      if (entry.details.encryptionPubkey?.toLowerCase().contains(searchText) ?? false) {
        return true;
      }
      // Search in signing key
      if (entry.details.signingPubkey?.toLowerCase().contains(searchText) ?? false) {
        return true;
      }
      // Search in socket address (IPv4)
      if (entry.details.socketAddrV4?.toLowerCase().contains(searchText) ?? false) {
        return true;
      }
      // Search in socket address (IPv6)
      if (entry.details.socketAddrV6?.toLowerCase().contains(searchText) ?? false) {
        return true;
      }
      // Search in commitment
      if (entry.details.commitment?.toLowerCase().contains(searchText) ?? false) {
        return true;
      }

      return false;
    }).toList();
  }

  List<BitAssetEntry> get myEntries {
    return provider.entries.where((entry) => provider.ownedHashes.contains(entry.hash)).toList();
  }

  /// The amount of one asset that the wallet holds.
  int amountOf(String hash) => provider.ownedAmounts[hash] ?? 0;

  bool get isLoading => !provider.initialized;

  /// Shows [entry] in the side panel, or in a dialog on a phone.
  Future<void> showDetails(BuildContext context, BitAssetEntry entry) async {
    if (SailStyleValues.phoneLayout(context)) {
      await showBitAssetDetails(context, entry);
      return;
    }
    detailsEntry = entry;
    notifyListeners();
  }

  Future<void> showDetailsById(BuildContext context, List<BitAssetEntry> list, String? rowId) async {
    final entry = list.firstWhereOrNull((e) => e.hash == rowId);
    if (entry == null) {
      return;
    }
    await showDetails(context, entry);
  }

  void closeDetails() {
    if (detailsEntry == null) {
      return;
    }
    detailsEntry = null;
    notifyListeners();
  }

  Future<void> reserveBitname(BuildContext context) async {
    final name = reserveNameController.text.trim();
    if (name.isEmpty) {
      reserveError = 'Name cannot be empty';
      notifyListeners();
      return;
    }
    reserveLoading = true;
    reserveError = null;
    notifyListeners();
    try {
      final txid = await bitassetsRPC.reserveBitAsset(name);
      await provider.saveHashNameMapping(name, isMine: true);

      reserveLoading = false;
      notifyListeners();
      if (context.mounted) {
        notificationProvider.add(
          title: 'Success',
          content: 'BitAsset "$name" reserved successfully in $txid!',
          dialogType: DialogType.success,
        );
      }
      reserveNameController.clear();
    } catch (e) {
      reserveError = e.toString();
      reserveLoading = false;
      notifyListeners();
    }
  }

  Future<void> registerBitAsset(BuildContext context) async {
    final name = registerNameController.text.trim();
    if (name.isEmpty) {
      registerError = 'Name cannot be empty';
      notifyListeners();
      return;
    }

    final initialSupply = int.tryParse(initialSupplyController.text.trim());
    if (initialSupply == null) {
      registerError = 'Initial supply must be set';
      notifyListeners();
      return;
    }

    final commitment = commitmentController.text.trim().isEmpty ? null : commitmentController.text.trim();
    final ipv4 = ipv4Controller.text.trim().isEmpty ? null : ipv4Controller.text.trim();
    final ipv6 = ipv6Controller.text.trim().isEmpty ? null : ipv6Controller.text.trim();

    if (commitment != null) {
      // Check if commitment is a valid hex string
      if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(commitment)) {
        registerError = 'Commitment must be a valid hex string';
        notifyListeners();
        return;
      }

      // Check if commitment is a valid Blake3 hash (64 characters)
      if (commitment.length != 64) {
        registerError = 'Commitment must be a valid Blake3 hash (64 characters)';
        notifyListeners();
        return;
      }
    }

    registerLoading = true;
    registerError = null;
    notifyListeners();
    try {
      final txid = await bitassetsRPC.registerBitAsset(
        name,
        BitAssetRequest(
          initialSupply: initialSupply,
          commitment: commitment,
          encryptionPubkey: useEncryptionKey ? encryptionKey : null,
          signingPubkey: useSigningKey ? signingKey : null,
          socketAddrV4: ipv4,
          socketAddrV6: ipv6,
        ),
      );
      registerLoading = false;
      notifyListeners();
      if (context.mounted) {
        notificationProvider.add(
          title: 'Success',
          content: 'BitAsset "$name" with $initialSupply initial supply registered successfully in $txid!',
          dialogType: DialogType.success,
        );
      }
      await provider.fetch();
      registerNameController.clear();
      commitmentController.clear();
      ipv4Controller.clear();
      ipv6Controller.clear();
      useEncryptionKey = false;
      useSigningKey = false;
      await provider.saveHashNameMapping(name, isMine: true);
      await generateKeysWithRetry();
    } catch (e) {
      registerError = e.toString();
      registerLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    reserveNameController.dispose();
    registerNameController.dispose();
    commitmentController.dispose();
    ipv4Controller.dispose();
    ipv6Controller.dispose();
    paymailFeeController.dispose();
    provider.removeListener(notifyListeners);
    super.dispose();
  }
}
