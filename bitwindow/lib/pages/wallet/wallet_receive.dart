import 'package:bitwindow/models/burn_ecx_amount.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/utils/bitcoin_uri.dart';
import 'package:bitwindow/utils/explorer_url.dart';
import 'package:bitwindow/widgets/burn_ecx_card.dart';
import 'package:bitwindow/widgets/claim_ecx_card.dart';
import 'package:fixnum/fixnum.dart';
import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/pages/wallet/widgets/wallet_v2_parts.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;
import 'package:sail_ui/sail_ui.dart';

const _claimCardWidth = 420.0;

const _maxSats = 21000000 * 100000000;

/// Below this the claim card drops under the address card instead of beside it.
const _claimBesideAddress = 1100.0;

class ReceiveTab extends StatelessWidget {
  const ReceiveTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return ViewModelBuilder.reactive(
      viewModelBuilder: () => ReceivePageViewModel(),
      onViewModelReady: (model) => model.init(),
      builder: (context, model, child) {
        if (!SailStyleValues.phoneLayout(context)) {
          return ReceiveDesktop(model: model);
        }
        return SingleChildScrollView(
          child: SailColumn(
            spacing: 16,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final conf = GetIt.I.get<BitcoinConfProvider>();
                  final actionCards = ListenableBuilder(
                    listenable: conf,
                    builder: (context, child) => SailColumn(
                      spacing: SailStyleValues.padding16,
                      children: [
                        const ClaimEcxCard(),
                        if (conf.network == BitcoinNetwork.BITCOIN_NETWORK_ECASH &&
                            burnEcxNetworks.containsKey(
                              conf.ecashNetworkId.isNotEmpty ? conf.ecashNetworkId : conf.currentNetworkOptionId,
                            ))
                          const BurnEcxCard(),
                      ],
                    ),
                  );
                  final addressRow = SailRow(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: SailStyleValues.padding08,
                    children: [
                      Expanded(
                        child: SailCard(
                          title: 'Receive ${activeTicker.name} on L1',
                          error: model.addressError,
                          child: SailColumn(
                            spacing: SailStyleValues.padding16,
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // A wallet that derives one kind has nothing to choose.
                              if (model.addressTypes.length > 1)
                                SailDropdownButton<wmpb.AddressType>(
                                  value: model.addressType,
                                  onChanged: (type) {
                                    if (type != null) {
                                      model.setAddressType(type);
                                    }
                                  },
                                  items: model.addressTypes
                                      .map(
                                        (type) => SailDropdownItem<wmpb.AddressType>(
                                          value: type,
                                          label: addressTypeLabel(type),
                                        ),
                                      )
                                      .toList(),
                                ),
                              SailRow(
                                spacing: SailStyleValues.padding08,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SailColumn(
                                      spacing: SailStyleValues.padding08,
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SailTextField(
                                          loading: LoadingDetails(
                                            enabled: model.address.isEmpty && model.addressError == null,
                                            description: 'Waiting for enforcer to start and wallet to sync..',
                                          ),
                                          controller: TextEditingController(text: model.address),
                                          hintText: 'A Drivechain address',
                                          readOnly: true,
                                          minLines: SailStyleValues.phoneLayout(context) ? 1 : null,
                                          maxLines: SailStyleValues.phoneLayout(context) ? null : 1,
                                          suffixWidget: CopyButton(text: model.address),
                                        ),
                                        if (model.addressDerivationPath.isNotEmpty)
                                          SailText.secondary12(model.addressDerivationPath, monospace: true),
                                        if (model.address.isNotEmpty) PaymentRequestFields(model: model),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 128,
                                    child: SailCard(
                                      padding: true,
                                      child: QrImageView(
                                        key: ValueKey(model.paymentRequest),
                                        padding: EdgeInsets.zero,
                                        eyeStyle: QrEyeStyle(
                                          color: theme.colors.text,
                                          eyeShape: QrEyeShape.square,
                                        ),
                                        dataModuleStyle: QrDataModuleStyle(color: theme.colors.text),
                                        data: model.paymentRequest,
                                        version: QrVersions.auto,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (model.address.isEmpty)
                                SailButton(label: 'Generate new address', onPressed: model.generateNewAddress),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );

                  if (constraints.maxWidth < _claimBesideAddress) {
                    return SailColumn(spacing: SailStyleValues.padding16, children: [addressRow, actionCards]);
                  }

                  return SailRow(
                    spacing: SailStyleValues.padding08,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: addressRow),
                      SizedBox(width: _claimCardWidth, child: actionCards),
                    ],
                  );
                },
              ),

              if (!model.hideBip47)
                SailCard(
                  title: 'Your BIP47 v3 Payment Code',
                  child: SailColumn(
                    spacing: SailStyleValues.padding16,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SailRow(
                        spacing: SailStyleValues.padding08,
                        children: [
                          Expanded(child: PaymentCodeField(code: model.bip47PaymentCode)),
                        ],
                      ),
                    ],
                  ),
                ),

              ReceiveAddressesTable(model: model),
            ],
          ),
        );
      },
    );
  }
}

/// The claim card, and the Betanet burn card on a network that burns.
class ReceiveActionCards extends StatelessWidget {
  const ReceiveActionCards({super.key});

  @override
  Widget build(BuildContext context) {
    final conf = GetIt.I.get<BitcoinConfProvider>();
    return ListenableBuilder(
      listenable: conf,
      builder: (context, child) => SailColumn(
        spacing: walletGap,
        children: [
          const ClaimEcxCard(),
          if (conf.network == BitcoinNetwork.BITCOIN_NETWORK_ECASH &&
              burnEcxNetworks.containsKey(
                conf.ecashNetworkId.isNotEmpty ? conf.ecashNetworkId : conf.currentNetworkOptionId,
              ))
            const BurnEcxCard(),
        ],
      ),
    );
  }
}

/// The desktop Receive tab: the address strip over the addresses, with claim and burn at the right.
class ReceiveDesktop extends StatelessWidget {
  final ReceivePageViewModel model;

  const ReceiveDesktop({super.key, required this.model});

  static const double _narrowTableHeight = 420;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final strip = WalletStripScroll(minWidth: 760, child: ReceiveAddressStrip(model: model));
        if (constraints.maxWidth < walletNarrowWidth) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                strip,
                const SizedBox(height: walletGap),
                SizedBox(
                  height: _narrowTableHeight,
                  child: ReceiveAddressesTable(model: model),
                ),
                const SizedBox(height: walletGap),
                const ReceiveActionCards(),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            strip,
            const SizedBox(height: walletGap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ReceiveAddressesTable(model: model)),
                  const SizedBox(width: walletGap),
                  const SizedBox(
                    width: SailSidePanel.width,
                    child: SingleChildScrollView(child: ReceiveActionCards()),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

const double _requestFieldsWidth = 640;

/// The top strip of the Receive tab: QR code, address type, address, path, payment code, and Copy and New address.
class ReceiveAddressStrip extends StatelessWidget {
  final ReceivePageViewModel model;

  const ReceiveAddressStrip({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final waiting = model.address.isEmpty && model.addressError == null;
    final used = model.receiveAddresses.firstWhereOrNull((a) => a.address == model.address);
    final pathLine = [
      if (model.addressDerivationPath.isNotEmpty) model.addressDerivationPath,
      if (used != null && used.lastUsedAt.seconds == 0) 'never used',
    ].join(' \u00b7 ');

    return DecoratedBox(
      decoration: theme.chrome.panel(theme.colors),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Opacity(
              opacity: model.address.isEmpty ? 0.15 : 1,
              child: SizedBox(
                width: 100,
                height: 100,
                child: model.address.isEmpty
                    ? const SizedBox.shrink()
                    : QrImageView(
                        key: ValueKey(model.paymentRequest),
                        padding: EdgeInsets.zero,
                        eyeStyle: QrEyeStyle(color: theme.colors.text, eyeShape: QrEyeShape.square),
                        dataModuleStyle: QrDataModuleStyle(color: theme.colors.text),
                        data: model.paymentRequest,
                        version: QrVersions.auto,
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SailText.primary13('Your address', color: theme.colors.textSecondary),
                      // A wallet that derives one kind has nothing to choose.
                      if (model.addressTypes.length > 1) ...[
                        const SizedBox(width: 8),
                        SailDropdownButton<wmpb.AddressType>(
                          value: model.addressType,
                          onChanged: (type) {
                            if (type != null) {
                              model.setAddressType(type);
                            }
                          },
                          items: model.addressTypes
                              .map(
                                (type) =>
                                    SailDropdownItem<wmpb.AddressType>(value: type, label: addressTypeLabel(type)),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (model.addressError case final error?)
                    SailText.primary13(error, color: theme.colors.error, overflow: TextOverflow.visible),
                  if (model.address.isNotEmpty || waiting)
                    SelectionArea(
                      child: Text(
                        waiting ? 'Waiting for enforcer to start and wallet to sync..' : model.address,
                        style: walletTextStyle(
                          context,
                          SailStyleValues.eighteen,
                          color: waiting ? theme.colors.textHint : null,
                        ),
                      ),
                    ),
                  if (pathLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SailText.secondary12(pathLine),
                  ],
                  if (!model.hideBip47) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SailText.secondary12('BIP47 payment code'),
                        const SizedBox(width: 6),
                        Flexible(
                          child: SailText.primary12(
                            model.bip47PaymentCode.isEmpty
                                ? 'Waiting for wallet to sync..'
                                : middleEllipsis(model.bip47PaymentCode, keep: 12),
                            color: model.bip47PaymentCode.isEmpty ? theme.colors.textHint : null,
                          ),
                        ),
                        if (model.bip47PaymentCode.isNotEmpty) CopyButton(text: model.bip47PaymentCode),
                      ],
                    ),
                  ],
                  if (model.address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _requestFieldsWidth),
                      child: PaymentRequestFields(model: model),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (model.address.isEmpty)
              SailButton(label: 'Generate new address', onPressed: model.generateNewAddress)
            else ...[
              SailButton(
                label: 'Copy',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: model.paymentRequest));
                  if (context.mounted) {
                    showSailToast(context, 'Address copied to clipboard');
                  }
                },
              ),
              const SizedBox(width: 8),
              SailButton(label: 'New address', variant: ButtonVariant.secondary, onPressed: model.generateNewAddress),
            ],
          ],
        ),
      ),
    );
  }
}

/// Amount, label and message of a payment request, and the request with a copy button.
class PaymentRequestFields extends StatelessWidget {
  final ReceivePageViewModel model;

  const PaymentRequestFields({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final unit = model.unit;
    final amount = SailTextField(
      label: 'Amount',
      controller: model.amountController,
      hintText: 'Optional',
      size: TextFieldSize.small,
      textFieldType: unit == BitcoinUnit.btc ? TextFieldType.bitcoin : TextFieldType.number,
      suffix: unit.symbol,
    );
    final label = SailTextField(
      label: 'Label',
      controller: model.labelController,
      focusNode: model.labelFocus,
      hintText: 'Optional',
      size: TextFieldSize.small,
      onSubmitted: (_) => model.saveRequestLabel(),
    );
    final message = SailTextField(
      label: 'Message',
      controller: model.messageController,
      hintText: 'Optional',
      size: TextFieldSize.small,
    );
    final fields = SailStyleValues.phoneLayout(context)
        ? SailColumn(spacing: SailStyleValues.padding08, children: [amount, label, message])
        : SailRow(
            spacing: SailStyleValues.padding08,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: amount),
              Expanded(child: label),
              Expanded(child: message),
            ],
          );
    final request = model.paymentRequest;

    return SailColumn(
      spacing: SailStyleValues.padding08,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fields,
        if (model.amountError case final error?) SailInlineError(error),
        if (model.labelError case final error?) SailInlineError(error),
        if (request != model.address)
          SailTextField(
            label: 'Payment request',
            controller: TextEditingController(text: request),
            hintText: '',
            readOnly: true,
            minLines: 1,
            maxLines: null,
            alignSuffixTop: true,
            suffixWidget: CopyButton(text: request),
          ),
      ],
    );
  }
}

/// The BIP47 payment code with a copy button. A phone wraps the code over more lines.
class PaymentCodeField extends StatelessWidget {
  final String code;

  const PaymentCodeField({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    return SailTextField(
      loading: LoadingDetails(enabled: code.isEmpty, description: 'Waiting for wallet to sync..'),
      controller: TextEditingController(text: code),
      hintText: 'A Drivechain address',
      readOnly: true,
      minLines: phone ? 1 : null,
      maxLines: phone ? null : 1,
      alignSuffixTop: phone,
      suffixWidget: CopyButton(text: code),
    );
  }
}

/// The address filter of the Addresses table.
enum ReceiveAddressKind {
  all('All types'),
  receive('Receive'),
  change('Change');

  final String label;

  const ReceiveAddressKind(this.label);

  bool matches(ReceiveAddress address) => switch (this) {
    ReceiveAddressKind.all => true,
    ReceiveAddressKind.receive => !address.isChange,
    ReceiveAddressKind.change => address.isChange,
  };
}

class ReceiveAddressesTable extends StatefulWidget {
  final ReceivePageViewModel model;

  const ReceiveAddressesTable({super.key, required this.model});

  @override
  State<ReceiveAddressesTable> createState() => _ReceiveAddressesTableState();
}

/// Resolves an address's display type from its encoding, so the column works for
/// any backend (electrum, Core, enforcer). bech32/bech32m carry a witness-version
/// character right after the HRP ('q' = segwit v0, 'p' = taproot v1); base58
/// addresses are classified by their version prefix.
String receiveAddressType(String address) {
  final lower = address.toLowerCase();
  for (final hrp in ['bcrt1', 'bc1', 'tb1']) {
    if (lower.startsWith(hrp)) {
      switch (lower[hrp.length]) {
        case 'q':
          return 'Segwit';
        case 'p':
          return 'Taproot';
        default:
          return '';
      }
    }
  }
  switch (address.isEmpty ? '' : address[0]) {
    case '1':
    case 'm':
    case 'n':
      return 'Legacy';
    case '2':
    case '3':
      return 'P2SH';
    default:
      return '';
  }
}

class _ReceiveAddressesTableState extends State<ReceiveAddressesTable> {
  // One list, so a new column can't be added to the header and forgotten in
  // the sort lookups.
  static const _columns = ['last_used_at', 'address', 'path', 'type', 'chain', 'label', 'current_balance_sat'];

  static const _desktopColumns = ['address', 'path', 'type', 'last_used_at', 'current_balance_sat'];

  String sortColumn = 'last_used_at';
  bool sortAscending = false;
  final TextEditingController _search = TextEditingController();

  ReceiveAddressKind _kind = ReceiveAddressKind.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch() => setState(() {});

  List<ReceiveAddress> get sortedEntries {
    final query = _search.text.trim().toLowerCase();
    final entries = widget.model.receiveAddresses
        .where((a) => _kind.matches(a))
        .where((a) => query.isEmpty || a.address.toLowerCase().contains(query) || a.label.toLowerCase().contains(query))
        .toList();
    entries.sort((a, b) {
      dynamic aValue, bValue;
      switch (sortColumn) {
        case 'last_used_at':
          if (a.lastUsedAt.seconds == 0 && b.lastUsedAt.seconds == 0) {
            return sortAscending ? a.address.compareTo(b.address) : b.address.compareTo(a.address);
          } else if (a.lastUsedAt.seconds == 0) {
            return sortAscending ? 1 : -1;
          } else if (b.lastUsedAt.seconds == 0) {
            return sortAscending ? -1 : 1;
          }
          aValue = a.lastUsedAt.toDateTime();
          bValue = b.lastUsedAt.toDateTime();
          int cmp = aValue.compareTo(bValue);
          if (cmp == 0) {
            return sortAscending ? a.address.compareTo(b.address) : b.address.compareTo(a.address);
          }
          return sortAscending ? cmp : -cmp;
        case 'address':
          aValue = a.address;
          bValue = b.address;
          break;
        case 'path':
          aValue = a.derivationPath;
          bValue = b.derivationPath;
          break;
        case 'type':
          aValue = receiveAddressType(a.address);
          bValue = receiveAddressType(b.address);
          break;
        case 'chain':
          aValue = a.isChange ? 'Change' : 'Receive';
          bValue = b.isChange ? 'Change' : 'Receive';
          break;
        case 'label':
          aValue = a.label;
          bValue = b.label;
          break;
        case 'current_balance_sat':
          aValue = a.currentBalanceSat;
          bValue = b.currentBalanceSat;
          break;
      }
      return sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });
    return entries;
  }

  void onSort(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
    });
  }

  List<SailMenuEntity> _menuItems(BuildContext context, ReceiveAddress entry) {
    final network = GetIt.I.get<BitcoinConfProvider>().network;
    return [
      SailMenuItem(
        onSelected: () {
          showThemedDialog(
            context: context,
            builder: (context) => SailModal(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SailCardEditValues(
                title: entry.label.isEmpty ? 'Add Label' : 'Edit Label',
                subtitle: "${entry.label.isEmpty ? "Set a" : "Update the"} label and click Save when you're done",
                fields: [EditField(name: 'Label', currentValue: entry.label)],
                onSave: (updatedFields) async {
                  final newLabel = updatedFields.firstWhere((f) => f.name == 'Label').currentValue;
                  return widget.model.saveLabel(context, entry.address, newLabel);
                },
              ),
            ),
          );
        },
        child: SailText.primary12(entry.label.isEmpty ? 'Add Label' : 'Update Label'),
      ),
      SailMenuItem(
        onSelected: () => openUrl(Uri.parse(mempoolAddressUrl(entry.address, network))),
        child: SailText.primary12('View on mempool.space'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!SailStyleValues.phoneLayout(context)) {
      final theme = SailTheme.of(context);
      final entries = sortedEntries;
      return WalletTableCard(
        title: 'Addresses',
        error: widget.model.listError,
        toolbar: [
          WalletSearchField(controller: _search, hintText: 'Search address or label'),
          SizedBox(
            width: 130,
            child: SailDropdownButton<ReceiveAddressKind>(
              value: _kind,
              onChanged: (value) => setState(() => _kind = value ?? ReceiveAddressKind.all),
              items: [
                for (final kind in ReceiveAddressKind.values) SailDropdownItem(value: kind, label: kind.label),
              ],
            ),
          ),
        ],
        child: SailSkeletonizer(
          description: 'Waiting for enforcer to start and wallet to sync..',
          enabled: widget.model.receiveAddresses.isEmpty && widget.model.listError == null,
          child: SailTable(
            getRowId: (index) => entries[index].address,
            cellHeight: 52,
            headerBuilder: (context) => [
              SailTableHeaderCell(name: 'Address', onSort: () => onSort('address')),
              SailTableHeaderCell(name: 'Path', onSort: () => onSort('path')),
              SailTableHeaderCell(name: 'Type', onSort: () => onSort('type')),
              SailTableHeaderCell(name: 'Last used', onSort: () => onSort('last_used_at')),
              SailTableHeaderCell(
                name: 'Balance',
                alignment: Alignment.centerRight,
                onSort: () => onSort('current_balance_sat'),
              ),
            ],
            rowBuilder: (context, row, selected) {
              final entry = entries[row];
              final used = entry.lastUsedAt.seconds == 0 ? null : entry.lastUsedAt.toDateTime().toLocal();
              return [
                SailTableCell(
                  value: entry.address,
                  secondaryValue: entry.label.isEmpty ? 'No label' : entry.label,
                  copyValue: entry.address,
                ),
                SailTableCell(
                  value: entry.derivationPath.isEmpty ? '—' : entry.derivationPath,
                  copyValue: entry.derivationPath,
                  monospace: true,
                ),
                SailTableCell(
                  value: receiveAddressType(entry.address).isEmpty ? '—' : receiveAddressType(entry.address),
                  secondaryValue: entry.isChange ? 'Change' : 'Receive',
                ),
                SailTableCell(
                  value: used == null ? 'Never' : walletRowDate(used),
                  secondaryValue: used == null ? null : walletRowTime(used),
                ),
                SailTableCell(
                  value: walletAmountText(entry.currentBalanceSat.toInt()),
                  secondaryValue: walletUnitText(),
                  alignment: Alignment.centerRight,
                  textColor: entry.currentBalanceSat == 0 ? theme.colors.textSecondary : null,
                ),
              ];
            },
            rowCount: entries.length,
            emptyPlaceholder: 'No receive addresses yet',
            sortColumnIndex: _desktopColumns.indexOf(sortColumn),
            sortAscending: sortAscending,
            onSort: (columnIndex, ascending) => onSort(_desktopColumns[columnIndex]),
            contextMenuItems: (rowId) => _menuItems(context, entries.firstWhere((e) => e.address == rowId)),
          ),
        ),
      );
    }
    final formatter = GetIt.I<FormatterProvider>();
    final entries = sortedEntries;

    return SailCard(
      title: 'Receive Addresses',
      error: widget.model.listError,
      bottomPadding: false,
      child: Column(
        children: [
          SizedBox(
            height: 300,
            child: SailSkeletonizer(
              description: 'Waiting for enforcer to start and wallet to sync..',
              enabled: widget.model.receiveAddresses.isEmpty && widget.model.listError == null,
              child: ListenableBuilder(
                listenable: formatter,
                builder: (context, child) => SailTable(
                  getRowId: (index) => entries[index].address,
                  headerBuilder: (context) => [
                    SailTableHeaderCell(name: 'Last Used', onSort: () => onSort('last_used_at')),
                    SailTableHeaderCell(name: 'Address', onSort: () => onSort('address')),
                    SailTableHeaderCell(name: 'Path', onSort: () => onSort('path')),
                    SailTableHeaderCell(name: 'Type', onSort: () => onSort('type')),
                    SailTableHeaderCell(name: 'Change', onSort: () => onSort('chain')),
                    SailTableHeaderCell(name: 'Label', onSort: () => onSort('label')),
                    SailTableHeaderCell(name: 'Balance', onSort: () => onSort('current_balance_sat')),
                  ],
                  rowBuilder: (context, row, selected) {
                    final utxo = entries[row];
                    final formattedAmount = formatter.formatSats(utxo.currentBalanceSat.toInt());
                    return [
                      SailTableCell(
                        value: utxo.lastUsedAt.seconds == 0
                            ? 'Never'
                            : formatDate(utxo.lastUsedAt.toDateTime().toLocal()),
                      ),
                      SailTableCell(value: utxo.address, copyValue: utxo.address),
                      SailTableCell(
                        value: utxo.derivationPath.isEmpty ? '—' : utxo.derivationPath,
                        copyValue: utxo.derivationPath,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SailText.primary12(
                            utxo.derivationPath.isEmpty ? '—' : utxo.derivationPath,
                            monospace: true,
                          ),
                        ),
                      ),
                      SailTableCell(value: receiveAddressType(utxo.address)),
                      SailTableCell(
                        value: utxo.isChange ? 'Yes' : '',
                        child: utxo.isChange
                            ? SailSVG.fromAsset(SailSVGAsset.check, width: 12)
                            : const SizedBox.shrink(),
                      ),
                      SailTableCell(value: utxo.label),
                      SailTableCell(value: formattedAmount, monospace: true),
                    ];
                  },
                  rowCount: entries.length,
                  emptyPlaceholder: 'No receive addresses yet',
                  drawGrid: true,
                  sortColumnIndex: _columns.indexOf(sortColumn),
                  sortAscending: sortAscending,
                  onSort: (columnIndex, ascending) => onSort(_columns[columnIndex]),
                  contextMenuItems: (rowId) => _menuItems(context, entries.firstWhere((e) => e.address == rowId)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Orchestrator migration status: COMPLETE
/// - getNewAddress: via TransactionProvider (orchestrator)
/// - listReceiveAddresses: via TransactionProvider (orchestrator)
/// - Address book labels: STAYS on bitwindowd — BW-only SQLite
/// The label the Receive tab shows for an address type.
String addressTypeLabel(wmpb.AddressType type) => switch (type) {
  wmpb.AddressType.ADDRESS_TYPE_TAPROOT => 'Taproot (bech32m)',
  _ => 'Segwit (bech32)',
};

class ReceivePageViewModel extends BaseViewModel {
  final AddressBookProvider _addressBookProvider = GetIt.I<AddressBookProvider>();
  final BitwindowRPC _bitwindowRPC = GetIt.I<BitwindowRPC>();
  final HDWalletProvider _hdWalletProvider = GetIt.I<HDWalletProvider>();
  TransactionProvider get transactionsProvider => GetIt.I<TransactionProvider>();

  String get address => transactionsProvider.address;

  String? get addressError => switch (transactionsProvider.addressError) {
    final error? => 'Could not get a receive address: $error',
    null => null,
  };

  String? get listError => switch (transactionsProvider.error) {
    final error? => 'Could not read the wallet: $error',
    null => null,
  };
  String get addressDerivationPath => transactionsProvider.addressDerivationPath;
  String get bip47PaymentCode => _hdWalletProvider.bip47PaymentCode;

  wmpb.AddressType get addressType => transactionsProvider.addressType;
  List<wmpb.AddressType> get addressTypes => transactionsProvider.addressTypes;
  Future<void> setAddressType(wmpb.AddressType type) => transactionsProvider.setAddressType(type);

  /// Hide the BIP47 card for the wallets the backend derives no code for, so
  /// the receive tab shows no row that can never fill.
  bool get hideBip47 {
    final reader = GetIt.I.get<WalletReaderProvider>();
    final active = reader.activeWallet;
    return active != null && (active.isWatchOnly || active.isMultisig);
  }

  /// The wallet addresses, with the label from the address book where it has one.
  List<ReceiveAddress> get receiveAddresses {
    final labels = labelsByAddress(_addressBookProvider.receiveEntries);
    return transactionsProvider.receiveAddresses
        .map(
          (address) => switch (labels[address.address]) {
            final label? => address.deepCopy()..label = label,
            null => address,
          },
        )
        .toList();
  }

  AddressBookEntry get matchingEntry => _addressBookProvider.receiveEntries.firstWhere(
    (e) => e.address == address,
    orElse: () => AddressBookEntry(id: Int64(0), label: '', address: '', direction: Direction.DIRECTION_RECEIVE),
  );
  bool get hasExistingLabel => matchingEntry.label.isNotEmpty;

  String sortColumn = 'address';
  bool sortAscending = true;

  final amountController = TextEditingController();
  final labelController = TextEditingController();
  final messageController = TextEditingController();
  final labelFocus = FocusNode();

  /// The save error of the request label, or null.
  String? labelError;

  String _requestAddress = '';
  String _savedLabel = '';
  BitcoinUnit _amountUnit = BitcoinUnit.btc;

  BitcoinUnit get unit => GetIt.I<SettingsProvider>().bitcoinUnit;

  int? get _amountSats {
    final text = amountController.text.trim();
    return text.isEmpty ? null : parseAmountToSatoshis(text, unit);
  }

  /// The field error of the request amount, or null.
  String? get amountError => switch (_amountSats) {
    null => null,
    <= 0 => 'Enter an amount above zero, or leave the field empty',
    > _maxSats => 'The amount is more than 21 million ${activeTicker.symbol}',
    _ => null,
  };

  /// The BIP-0021 request for the shown address. With a bad amount, the plain address.
  String get paymentRequest {
    if (address.isEmpty || amountError != null) {
      return address;
    }
    return BitcoinURI(
      address: address,
      amountSats: _amountSats,
      label: labelController.text.trim(),
      message: messageController.text.trim(),
    ).format();
  }

  /// Load a new request when the shown address changes, and the saved label when it loads.
  void _syncRequest() {
    final saved = matchingEntry.label;
    if (address != _requestAddress) {
      _requestAddress = address;
      amountController.clear();
      messageController.clear();
      labelController.text = saved;
      _savedLabel = saved;
      labelError = null;
    } else if (saved != _savedLabel && labelController.text == _savedLabel) {
      labelController.text = saved;
      _savedLabel = saved;
    }
  }

  void _onChanged() {
    _syncRequest();
    notifyListeners();
  }

  /// Keep the request amount when the display unit changes.
  void _onUnitChanged() {
    final text = amountController.text.trim();
    if (unit != _amountUnit && text.isNotEmpty) {
      final sats = parseAmountToSatoshis(text, _amountUnit);
      amountController.text = unit == BitcoinUnit.btc ? bip21Amount(sats) : '$sats';
    }
    _amountUnit = unit;
    notifyListeners();
  }

  void _onLabelFocus() {
    if (!labelFocus.hasFocus) {
      saveRequestLabel();
    }
  }

  /// Save the request label as the label of the shown address.
  Future<void> saveRequestLabel() async {
    final label = labelController.text.trim();
    final target = address;
    if (target.isEmpty || label == _savedLabel) {
      return;
    }
    try {
      await _addressBookProvider.createEntry(label, target, Direction.DIRECTION_RECEIVE);
      if (target == address) {
        _savedLabel = label;
        labelError = null;
      }
    } catch (error) {
      labelError = 'Could not save the label: $error';
    }
    notifyListeners();
  }

  void init() {
    // bitwindowrpc has a health stream that notifies listener. when it changes, we should try to
    // regenerate an address!
    _bitwindowRPC.addListener(generateNewAddress);
    transactionsProvider.addListener(_onChanged);
    _addressBookProvider.addListener(_onChanged);
    _hdWalletProvider.addListener(notifyListeners);
    amountController.addListener(notifyListeners);
    labelController.addListener(notifyListeners);
    messageController.addListener(notifyListeners);
    labelFocus.addListener(_onLabelFocus);
    _amountUnit = unit;
    GetIt.I<SettingsProvider>().addListener(_onUnitChanged);
    _syncRequest();
    if (!_hdWalletProvider.isInitialized) {
      _hdWalletProvider.init();
    }
    generateNewAddress();
  }

  @override
  void dispose() {
    _bitwindowRPC.removeListener(generateNewAddress);
    transactionsProvider.removeListener(_onChanged);
    _addressBookProvider.removeListener(_onChanged);
    _hdWalletProvider.removeListener(notifyListeners);
    labelFocus.removeListener(_onLabelFocus);
    GetIt.I<SettingsProvider>().removeListener(_onUnitChanged);
    amountController.dispose();
    labelController.dispose();
    messageController.dispose();
    labelFocus.dispose();
    super.dispose();
  }

  Future<void> generateNewAddress() => transactionsProvider.fetch();

  /// Returns the error to show in the label dialog, or null on success.
  Future<String?> saveLabel(BuildContext context, String address, String label) async {
    try {
      setBusy(true);
      await _addressBookProvider.createEntry(label, address, Direction.DIRECTION_RECEIVE);

      // Fetch the transactions provider to update the receiveAddresses list
      await transactionsProvider.fetch();

      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return null;
    } catch (error) {
      return error.toString();
    } finally {
      setBusy(false);
    }
  }
}
