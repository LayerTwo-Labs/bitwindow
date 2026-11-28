import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:bitnames/providers/bitnames_provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/utils/commitment_validation.dart';
import 'package:sidechain_core/utils/data_server_address.dart';
import 'package:thirds/blake3.dart';

@RoutePage()
class BitnamesTabPage extends StatelessWidget {
  const BitnamesTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<BitnamesViewModel>.reactive(
        viewModelBuilder: () => BitnamesViewModel(),
        builder: (context, model, child) {
          if (SailStyleValues.phoneLayout(context)) {
            return _PhoneLayout(model: model);
          }
          final details = model.detailsEntry;
          final panel = switch (model.panel) {
            BitnamesPanel.form => _FormPanel(model: model),
            BitnamesPanel.details when details != null => BitnameDetailsPanel(
              entry: details,
              onClose: () async => model.closePanel(),
            ),
            _ => null,
          };
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _YourBitnamesCard(model: model)),
                    const SizedBox(height: SailStyleValues.padding12),
                    Expanded(child: _AllBitnamesCard(model: model)),
                  ],
                ),
              ),
              if (panel != null) ...[const SizedBox(width: SailStyleValues.padding12), panel],
            ],
          );
        },
      ),
    );
  }
}

/// A phone stacks the tables and both forms, and shows the details in a dialog.
class _PhoneLayout extends StatelessWidget {
  final BitnamesViewModel model;

  const _PhoneLayout({required this.model});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        children: [
          SizedBox(height: 320, child: _YourBitnamesCard(model: model)),
          SailCard(
            title: 'Reserve',
            subtitle: _reserveSubtitle,
            child: _ReserveForm(model: model),
          ),
          SailCard(
            title: 'Register',
            subtitle: _registerSubtitle,
            child: _RegisterForm(model: model),
          ),
          SizedBox(height: 420, child: _AllBitnamesCard(model: model)),
        ],
      ),
    );
  }
}

const _reserveSubtitle =
    'Reserve a bitname you want without needing a ipv4/v6-address. Can be registered later, but only by you.';
const _registerSubtitle = 'Register a reserved bitname';

class _YourBitnamesCard extends StatelessWidget {
  final BitnamesViewModel model;

  const _YourBitnamesCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    return SailCard(
      title: 'Your Bitnames',
      subtitle: 'View your registered bitnames',
      error: model.loadError,
      widgetHeaderEnd: SailRow(
        spacing: SailStyleValues.padding08,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: SailTextField(hintText: 'Search bitnames...', controller: model.mySearchController),
          ),
          if (model.loadError != null) SailButton(label: 'Retry', onPressed: model.provider.fetch),
          if (!phone)
            SailButton(
              label: 'Register New Bitname',
              variant: ButtonVariant.outline,
              onPressed: () async => model.openForm(BitnamesForm.register),
            ),
        ],
      ),
      child: _BitnamesTable(model: model, entries: model.myEntries),
    );
  }
}

class _AllBitnamesCard extends StatelessWidget {
  final BitnamesViewModel model;

  const _AllBitnamesCard({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'All Bitnames',
      subtitle: 'View and manage all registered bitnames',
      error: model.loadError,
      widgetHeaderEnd: SailRow(
        spacing: SailStyleValues.padding08,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: SailTextField(hintText: 'Search bitnames...', controller: model.searchController),
          ),
          if (model.loadError != null) SailButton(label: 'Retry', onPressed: model.provider.fetch),
        ],
      ),
      child: _BitnamesTable(model: model, entries: model.entries),
    );
  }
}

class _BitnamesTable extends StatelessWidget {
  final BitnamesViewModel model;
  final List<BitnameEntry> entries;

  const _BitnamesTable({required this.model, required this.entries});

  @override
  Widget build(BuildContext context) {
    return SailSkeletonizer(
      description: 'Loading bitnames...',
      enabled: model.isLoading,
      child: SailTable(
        getRowId: (index) => entries[index].hash,
        selectedRowId: model.panel == BitnamesPanel.details ? model.detailsEntry?.hash : null,
        onSelectedRow: (rowId) {
          final entry = entries.firstWhereOrNull((e) => e.hash == rowId);
          if (entry != null) {
            model.showDetails(context, entry);
          }
        },
        headerBuilder: (context) => [
          SailTableHeaderCell(name: 'Plaintext Name'),
          SailTableHeaderCell(name: 'Hash'),
          SailTableHeaderCell(name: 'Sequence ID'),
          SailTableHeaderCell(name: 'Commitment'),
          SailTableHeaderCell(name: 'Encryption Key'),
          SailTableHeaderCell(name: 'Signing Key'),
          SailTableHeaderCell(name: 'Paymail Fee', alignment: Alignment.centerRight),
        ],
        rowBuilder: (context, row, selected) {
          final entry = entries[row];
          return [
            SailTableCell(value: entry.plaintextName ?? '<unknown>'),
            SailTableCell(value: '${entry.hash.substring(0, 10)}..', copyValue: entry.hash),
            SailTableCell(value: entry.details.seqId),
            _shortCell(entry.details.commitment, 21),
            _shortCell(entry.details.encryptionPubkey, 16),
            _shortCell(entry.details.signingPubkey, 16),
            SailTableCell(
              value: entry.details.paymailFeeSats?.toString() ?? '-',
              alignment: Alignment.centerRight,
            ),
          ];
        },
        contextMenuItems: (rowId) {
          final entry = entries.firstWhereOrNull((e) => e.hash == rowId);
          if (entry == null) return [];
          return [
            SailMenuItem(
              onSelected: () async => model.showDetails(context, entry),
              child: SailText.primary12('Show Details'),
            ),
          ];
        },
        rowCount: entries.length,
        drawGrid: true,
      ),
    );
  }
}

/// A long key or digest as its first [length] characters; a copy takes the full value.
SailTableCell _shortCell(String? value, int length) {
  if (value == null) {
    return const SailTableCell(value: '-');
  }
  return SailTableCell(
    value: value.length <= length ? value : '${value.substring(0, length)}...',
    copyValue: value,
  );
}

/// The side panel with the Reserve and the Register forms.
class _FormPanel extends StatelessWidget {
  final BitnamesViewModel model;

  const _FormPanel({required this.model});

  @override
  Widget build(BuildContext context) {
    final register = model.form == BitnamesForm.register;
    return SailSidePanel(
      title: register ? 'Register' : 'Reserve',
      onClose: () async => model.closePanel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SailSegments(
              labels: const ['Reserve', 'Register'],
              activeIndex: register ? 1 : 0,
              onSelect: (index) => model.openForm(index == 0 ? BitnamesForm.reserve : BitnamesForm.register),
            ),
          ),
          const SizedBox(height: SailStyleValues.padding12),
          SailText.secondary12(register ? _registerSubtitle : _reserveSubtitle),
          const SizedBox(height: SailStyleValues.padding12),
          if (register) _RegisterForm(model: model) else _ReserveForm(model: model),
        ],
      ),
    );
  }
}

class _ReserveForm extends StatelessWidget {
  final BitnamesViewModel model;

  const _ReserveForm({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding12,
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
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final BitnamesViewModel model;

  const _RegisterForm({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailColumn(
      spacing: SailStyleValues.padding12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailTextField(
          label: 'Name',
          hintText: 'Enter name to register',
          controller: model.registerNameController,
        ),
        const _FormHeading(
          title: 'Where your record lives',
          subtitle: 'Your server answers with your record. The chain holds the addresses below.',
        ),
        const _LabelWithHelp(
          label: 'Quick Lookup With Domain',
          message:
              'Your server answers the JSON-RPC method bitname_commit with your '
              'email, your keys, anything you publish. The chain holds only a hash '
              'of that record.',
        ),
        SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            Expanded(
              child: SailTextField(
                hintText: 'psztorc.com',
                controller: model.websiteController,
                loading: LoadingDetails(enabled: model.readLoading, description: 'Reading your server...'),
                onSubmitted: (_) {
                  model.readCommitmentFromServer();
                },
              ),
            ),
            SailButton(
              label: 'Get IP addresses',
              variant: ButtonVariant.outline,
              loading: model.readLoading,
              onPressed: () => model.readCommitmentFromServer(),
            ),
          ],
        ),
        SailText.secondary12(
          'Reads the addresses behind the domain, and fills them in below. '
          'The chain never holds the domain.',
        ),
        SailRow(
          spacing: SailStyleValues.padding08,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SailTextField(
                label: 'IPv4 address',
                hintText: '203.0.113.7:6002',
                controller: model.ipv4Controller,
              ),
            ),
            Expanded(
              child: SailTextField(
                label: 'IPv6 address',
                hintText: '[2606:4700:4700::1111]:6002',
                controller: model.ipv6Controller,
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailSVG.fromAsset(SailSVGAsset.info, color: theme.colors.info, width: 14),
            const SizedBox(width: SailStyleValues.padding08),
            Expanded(
              child: SailText.secondary12(
                'The chain holds the IPv4 and IPv6 addresses above. You can update '
                'them at any time after registering.',
              ),
            ),
          ],
        ),
        if (model.readError != null) SailText.primary13(model.readError!, color: theme.colors.error),
        if (model.commitmentData != null) ...[
          SailText.primary13('Your server answered with the following commitment', bold: true),
          SailTextField(
            hintText: '',
            controller: TextEditingController(text: model.commitmentData),
            readOnly: true,
            maxLines: 4,
            monospace: true,
          ),
          SailTextField(
            label: 'Commitment',
            hintText: '',
            controller: model.commitmentController,
            readOnly: true,
            monospace: true,
          ),
        ],
        const _FormHeading(
          title: 'Messages',
          subtitle: 'What a stranger pays to reach you, and the keys they use.',
        ),
        const _LabelWithHelp(
          label: 'Message postage in sats',
          message:
              'The smallest payment you accept with a message. Somebody sends you a '
              'coin with a memo, and your wallet hides a message that pays less. '
              'Nobody pays this to a miner.',
        ),
        SailTextField(
          hintText: 'Minimum you accept per message',
          controller: model.paymailFeeController,
          errorText: model.postageError,
        ),
        _CheckboxWithHelp(
          label: 'Private messages',
          message: 'People can send you a message only you can read.',
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
        _CheckboxWithHelp(
          label: 'Signed messages',
          message: 'People can check that a message really comes from you.',
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
        if (model.registerError != null) SailText.primary13(model.registerError!, color: theme.colors.error),
        SailButton(
          label: 'Register',
          onPressed: () => model.registerBitname(context),
          loading: model.registerLoading,
        ),
      ],
    );
  }
}

class _FormHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _FormHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SailStyleValues.padding04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailText.primary13(title, bold: true),
          const SizedBox(height: 2),
          SailText.secondary12(subtitle),
        ],
      ),
    );
  }
}

class _CheckboxWithHelp extends StatelessWidget {
  final String label;
  final String message;
  final bool value;
  final void Function(bool value) onChanged;

  const _CheckboxWithHelp({required this.label, required this.message, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SailRow(
      spacing: SailStyleValues.padding04,
      children: [
        SailCheckbox(label: label, value: value, onChanged: onChanged),
        SailTooltip(
          message: message,
          child: SailSVG.fromAsset(
            SailSVGAsset.circleHelp,
            color: SailTheme.of(context).colors.textSecondary,
            width: 12,
          ),
        ),
      ],
    );
  }
}

/// The 380 px panel with every field of one bitname, and the data its address serves.
class BitnameDetailsPanel extends StatelessWidget {
  final BitnameEntry entry;
  final Future<void> Function() onClose;

  const BitnameDetailsPanel({super.key, required this.entry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SailSidePanel(
      key: ValueKey('bitname_details_${entry.hash}'),
      title: 'Bitname Details',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.secondary12(entry.hash, monospace: true),
          const SizedBox(height: SailStyleValues.padding12),
          SailDetailGroup(children: _detailLines(entry)),
          if (entry.details.commitment != null) ...[
            const SizedBox(height: SailStyleValues.padding16),
            _ResolvedCommitment(key: ValueKey('resolved_${entry.hash}'), bitname: entry.hash),
          ],
        ],
      ),
    );
  }
}

List<Widget> _detailLines(BitnameEntry entry) => [
  SailStackedDetail(label: 'Hash', value: entry.hash),
  SailStackedDetail(label: 'Sequence ID', value: entry.details.seqId),
  if (entry.details.commitment != null) SailStackedDetail(label: 'Commitment', value: entry.details.commitment!),
  if (entry.details.socketAddrV4 != null)
    SailStackedDetail(label: 'Socket Address (IPv4)', value: entry.details.socketAddrV4!),
  if (entry.details.socketAddrV6 != null)
    SailStackedDetail(label: 'Socket Address (IPv6)', value: entry.details.socketAddrV6!),
  if (entry.details.socketAddrHost != null) SailStackedDetail(label: 'Host', value: entry.details.socketAddrHost!),
  if (entry.details.encryptionPubkey != null)
    SailStackedDetail(label: 'Encryption Public Key', value: entry.details.encryptionPubkey!),
  if (entry.details.signingPubkey != null)
    SailStackedDetail(label: 'Signing Public Key', value: entry.details.signingPubkey!),
  if (entry.details.paymailFeeSats != null)
    SailStackedDetail(label: 'Paymail Fee (sats)', value: entry.details.paymailFeeSats!.toString()),
];

Future<void> showBitnameDetails(BuildContext context, BitnameEntry entry) async {
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
              title: 'Bitname Details',
              subtitle: entry.hash,
              withCloseButton: true,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SailDetailGroup(children: _detailLines(entry)),
                    if (entry.details.commitment != null) ...[
                      const SizedBox(height: SailStyleValues.padding16),
                      _ResolvedCommitment(bitname: entry.hash),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  });
  return;
}

class _LabelWithHelp extends StatelessWidget {
  final String label;
  final String message;

  const _LabelWithHelp({required this.label, required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SailText.primary13(label, bold: true),
        const SizedBox(width: SailStyleValues.padding04),
        SailTooltip(
          message: message,
          child: SailSVG.fromAsset(
            SailSVGAsset.circleHelp,
            color: SailTheme.of(context).colors.textSecondary,
            width: 12,
          ),
        ),
      ],
    );
  }
}

class _ResolvedCommitment extends StatefulWidget {
  final String bitname;

  const _ResolvedCommitment({super.key, required this.bitname});

  @override
  State<_ResolvedCommitment> createState() => _ResolvedCommitmentState();
}

class _ResolvedCommitmentState extends State<_ResolvedCommitment> {
  late final Future<ResolveCommitResult> _result = GetIt.I.get<BitnamesRPC>().resolveCommit(widget.bitname);

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return FutureBuilder<ResolveCommitResult>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError) {
          return _CheckLine(ok: false, text: 'Could not read the data: ${snapshot.error}');
        }

        final result = snapshot.data!;
        return SailColumn(
          spacing: SailStyleValues.padding08,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SailText.primary13('Data from address', bold: true),
            Container(
              padding: const EdgeInsets.all(SailStyleValues.padding12),
              decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
              child: SailText.primary12(result.dataJson, monospace: true, overflow: TextOverflow.visible),
            ),
            _CheckLine(
              ok: result.matches,
              text: result.matches
                  ? 'This data hashes to the commitment on the chain.'
                  : 'This data does not match the commitment on the chain.',
            ),
          ],
        );
      },
    );
  }
}

class _CheckLine extends StatelessWidget {
  final bool ok;
  final String text;

  const _CheckLine({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final color = ok ? theme.colors.success : theme.colors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailSVG.fromAsset(ok ? SailSVGAsset.check : SailSVGAsset.x, color: color, width: 14),
        const SizedBox(width: SailStyleValues.padding08),
        Expanded(
          child: SailText.primary12(text, color: color, overflow: TextOverflow.visible),
        ),
      ],
    );
  }
}

/// What the side panel of the BitNames tab shows.
enum BitnamesPanel { form, details, closed }

/// The form in the side panel.
enum BitnamesForm { reserve, register }

class BitnamesViewModel extends BaseViewModel {
  final NotificationProvider notificationProvider = GetIt.I.get<NotificationProvider>();
  final BitnamesProvider provider = GetIt.I.get<BitnamesProvider>();
  final BitnamesRPC bitnamesRPC = GetIt.I.get<BitnamesRPC>();

  String? reserveError;
  bool reserveLoading = false;

  final TextEditingController searchController = TextEditingController();
  final TextEditingController mySearchController = TextEditingController();
  final TextEditingController reserveNameController = TextEditingController();
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
  String? postageError;

  BitnamesPanel panel = BitnamesPanel.form;
  BitnamesForm form = BitnamesForm.register;
  BitnameEntry? detailsEntry;

  // New state variables
  bool useEncryptionKey = false;
  bool useSigningKey = false;

  // The JSON the address served, and the state of that read
  String? commitmentData;
  bool readLoading = false;
  String? readError;

  // The address the digest describes. A later edit makes the digest stale.
  String? commitmentAddress;

  // The address fields as the read left them. The chain holds these, and the
  // domain does not, so an edit to either one makes the digest stale.
  String? commitmentFields;

  // A bare domain gets the sidechain RPC port, which is 6000 + sidechain 2.
  static const int defaultDataPort = 6002;

  final TextEditingController websiteController = TextEditingController();

  BitnamesViewModel() {
    searchController.addListener(notifyListeners);
    mySearchController.addListener(notifyListeners);
    paymailFeeController.addListener(() {
      if (postageError == null) return;
      postageError = null;
      notifyListeners();
    });
    provider.addListener(notifyListeners);
    provider.fetch();
    reserveNameController.addListener(() {
      reserveError = null;
      notifyListeners();
    });
    websiteController.addListener(dropStaleCommitment);
    ipv4Controller.addListener(dropStaleCommitment);
    ipv6Controller.addListener(dropStaleCommitment);

    generateKeysWithRetry();
  }

  Future<void> generateKeysWithRetry() async {
    encryptionKey = null;
    signingKey = null;

    while (encryptionKey == null || signingKey == null) {
      try {
        if (encryptionKey == null) {
          encryptionKey = await bitnamesRPC.getNewEncryptionKey();
          notifyListeners();
        }

        if (signingKey == null) {
          signingKey = await bitnamesRPC.getNewVerifyingKey();
          notifyListeners();
        }
      } catch (e) {
        // If there's an error, wait a bit before retrying
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  List<BitnameEntry> get entries => _search(provider.entries, searchController.text);

  List<BitnameEntry> _search(List<BitnameEntry> list, String text) {
    final query = text.trim();
    if (query.isEmpty) {
      return list;
    }
    final searchText = query.toLowerCase();
    final searchHash = blake3Hex(utf8.encode(query));

    return list.where((entry) {
      if (entry.hash.toLowerCase() == searchHash) {
        if (entry.plaintextName == null) {
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
      if (entry.details.seqId.toLowerCase().contains(searchText)) {
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
      // Search in paymail fee
      if (entry.details.paymailFeeSats?.toString().contains(searchText) ?? false) {
        return true;
      }
      return false;
    }).toList();
  }

  List<BitnameEntry> get myEntries => _search(
    provider.entries.where((entry) => provider.ownedHashes.contains(entry.hash)).toList(),
    mySearchController.text,
  );

  /// Opens [form] in the side panel.
  void openForm(BitnamesForm next) {
    panel = BitnamesPanel.form;
    form = next;
    notifyListeners();
  }

  void closePanel() {
    panel = BitnamesPanel.closed;
    detailsEntry = null;
    notifyListeners();
  }

  /// Shows [entry] in the side panel, or in a dialog on a phone.
  Future<void> showDetails(BuildContext context, BitnameEntry entry) async {
    if (SailStyleValues.phoneLayout(context)) {
      await showBitnameDetails(context, entry);
      return;
    }
    panel = BitnamesPanel.details;
    detailsEntry = entry;
    notifyListeners();
  }

  bool get isLoading => provider.isLoading;
  String? get loadError => provider.error;

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
      final txid = await bitnamesRPC.reserveBitName(name);
      await provider.saveHashNameMapping(name);
      reserveLoading = false;
      notifyListeners();
      if (context.mounted) {
        notificationProvider.add(
          title: 'Success',
          content: 'Bitname "$name" reserved successfully in $txid!',
          dialogType: DialogType.success,
        );
      }
      await provider.fetch();
      reserveNameController.clear();
    } catch (e) {
      reserveError = e.toString();
      reserveLoading = false;
      notifyListeners();
    }
  }

  Future<void> registerBitname(BuildContext context) async {
    // A slow read leaves the button live, and a second press sends a second
    // registration transaction.
    if (registerLoading) {
      return;
    }
    registerLoading = true;
    registerError = null;
    postageError = null;
    notifyListeners();
    try {
      await _registerBitname(context);
    } finally {
      registerLoading = false;
      notifyListeners();
    }
    // generateKeysWithRetry never gives up, so it runs after the button frees.
    // The checkboxes stay off until it answers, so no stale key reaches a form.
    if (registerError == null && postageError == null) {
      useEncryptionKey = false;
      useSigningKey = false;
      notifyListeners();
      await generateKeysWithRetry();
    }
  }

  Future<void> _registerBitname(BuildContext context) async {
    final name = registerNameController.text.trim();
    if (name.isEmpty) {
      registerError = 'Name cannot be empty';
      notifyListeners();
      return;
    }

    final address = dataAddress();
    if (address.isNotEmpty && commitmentAddress != address) {
      await readCommitmentFromServer();
      if (readError != null) {
        registerError = readError;
        notifyListeners();
        return;
      }
      if (commitmentAddress != address || commitmentFields != addressFields()) {
        registerError = 'The address changed while the read ran. Press Register again.';
        notifyListeners();
        return;
      }
    }

    final commitment = commitmentController.text.trim().isEmpty ? null : commitmentController.text.trim();
    final ipv4 = ipv4Controller.text.trim().isEmpty ? null : ipv4Controller.text.trim();
    final ipv6 = ipv6Controller.text.trim().isEmpty ? null : ipv6Controller.text.trim();

    final commitmentError = validateCommitment(commitment: commitment, website: null, ipv4: ipv4, ipv6: ipv6);
    if (commitmentError != null) {
      registerError = commitmentError;
      notifyListeners();
      return;
    }

    final paymailFeeText = paymailFeeController.text.trim();
    int? paymailFeeSats;
    if (paymailFeeText.isNotEmpty) {
      paymailFeeSats = int.tryParse(paymailFeeText);
      if (paymailFeeSats == null || paymailFeeSats < 0) {
        postageError = 'Paymail fee must be a whole number of sats, and zero or more';
        notifyListeners();
        return;
      }
    }

    try {
      final txid = await bitnamesRPC.registerBitName(
        name,
        BitNameData(
          commitment: commitment,
          encryptionPubkey: useEncryptionKey ? encryptionKey : null,
          paymailFeeSats: paymailFeeSats,
          signingPubkey: useSigningKey ? signingKey : null,
          socketAddrV4: ipv4,
          socketAddrV6: ipv6,
        ),
      );
      await provider.saveHashNameMapping(name);
      if (context.mounted) {
        notificationProvider.add(
          title: 'Success',
          content: 'Bitname "$name" registered successfully in $txid!',
          dialogType: DialogType.success,
        );
      }
      await provider.fetch();
      registerNameController.clear();
      websiteController.clear();
      commitmentController.clear();
      ipv4Controller.clear();
      ipv6Controller.clear();
      paymailFeeController.clear();
      useEncryptionKey = false;
      useSigningKey = false;
      commitmentData = null;
      readError = null;
    } catch (e) {
      registerError = e.toString();
    }
  }

  /// The fields the chain holds, as one value. A digest describes these.
  String addressFields() => '${ipv4Controller.text.trim()}|${ipv6Controller.text.trim()}';

  /// A digest describes one address. An edit makes it describe nothing.
  void dropStaleCommitment() {
    if (commitmentAddress == null) {
      return;
    }

    if (dataAddress() == commitmentAddress && addressFields() == commitmentFields) {
      return;
    }

    commitmentAddress = null;
    commitmentFields = null;
    commitmentData = null;
    commitmentController.clear();
    notifyListeners();
  }

  /// The address the lookup reads from. The domain wins, because the button
  /// looks a domain up. A typed address serves when no domain is set.
  String dataAddress() {
    final domain = hostWithPort(websiteController.text, defaultDataPort);
    if (domain != null) {
      return domain;
    }
    return dataServerAddress(
      website: '',
      ipv4: ipv4Controller.text,
      ipv6: ipv6Controller.text,
      defaultPort: defaultDataPort,
    );
  }

  Future<void> readCommitmentFromServer() async {
    final address = dataAddress();
    // A lookup owns the address fields only when it starts from a domain. A
    // typed address is the user's own, so the read leaves it alone.
    final fromDomain = hostWithPort(websiteController.text, defaultDataPort) != null;

    if (address.isEmpty) {
      readError = 'Set a website or an address first';
      notifyListeners();
      return;
    }

    readLoading = true;
    readError = null;
    notifyListeners();

    try {
      final result = await bitnamesRPC.readCommitment(address);
      // An edit during the read leaves the digest describing an address the
      // fields no longer hold.
      if (dataAddress() != address) {
        return;
      }
      // The chain holds a socket address, so the lookup writes what it reached
      // into the fields the user sends. A family the lookup did not reach must
      // not keep the address of a server the user left behind. Both writes run
      // before the digest, because each one drops a stale digest.
      if (fromDomain) {
        ipv4Controller.text = result.socketAddrV4;
        ipv6Controller.text = result.socketAddrV6;
      }
      commitmentData = result.dataJson;
      commitmentAddress = address;
      commitmentFields = addressFields();
      commitmentController.text = result.commitment;
    } catch (e) {
      if (dataAddress() != address) {
        return;
      }
      commitmentAddress = null;
      commitmentFields = null;
      commitmentData = null;
      commitmentController.clear();
      readError = e.toString();
    } finally {
      readLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    mySearchController.dispose();
    reserveNameController.dispose();
    registerNameController.dispose();
    websiteController.dispose();
    commitmentController.dispose();
    ipv4Controller.dispose();
    ipv6Controller.dispose();
    paymailFeeController.dispose();
    provider.removeListener(notifyListeners);
    super.dispose();
  }
}
