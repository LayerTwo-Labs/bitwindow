import 'dart:convert';

import 'package:bitwindow/providers/bitdrive_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sidechain_core/utils/share_file.dart';
import 'package:sidechain_core/gen/bitdrive/v1/bitdrive.pb.dart' as bitdrivepb;
import 'package:sail_ui/sail_ui.dart';

class BitDriveTab extends StatelessWidget {
  const BitDriveTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<BitDriveViewModel>.reactive(
      viewModelBuilder: () => BitDriveViewModel(),
      builder: (context, model, child) {
        if (!SailStyleValues.phoneLayout(context)) {
          return _DesktopBitDrive(model: model);
        }
        return SailCard(
          title: 'Store Data on ${activeTicker.name} Forever',
          subtitle:
              'BitDrive lets you permanently store files and text on the ${activeTicker.name} blockchain. Your data becomes part of ${activeTicker.name} history.',
          bottomPadding: false,
          widgetHeaderEnd: model.bitdriveDir != null && !SailStyleValues.phoneLayout(context)
              ? SailButton(
                  label: 'Open Folder',
                  variant: ButtonVariant.secondary,
                  icon: SailSVGAsset.folderOpen,
                  onPressed: () async => model.openBitdriveDir(),
                )
              : null,
          child: InlineTabBar(
            tabs: [
              SingleTabItem(
                label: 'Store',
                child: _StoreTab(model: model),
              ),
              SingleTabItem(
                label: 'My Files',
                child: _MyFilesTab(model: model),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The phone Store tab: the steps above the form.
class _StoreTab extends StatelessWidget {
  final BitDriveViewModel model;

  const _StoreTab({required this.model});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(SailStyleValues.padding20),
        child: SailColumn(
          spacing: SailStyleValues.padding20,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _StoreIntro(),
            _StoreForm(model: model),
          ],
        ),
      ),
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  final BitDriveViewModel model;

  const _AdvancedToggle({required this.model});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => model.toggleAdvancedSettings(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SailRow(
          spacing: SailStyleValues.padding04,
          children: [
            SailSVG.fromAsset(
              model.showAdvancedSettings ? SailSVGAsset.chevronDown : SailSVGAsset.chevronRight,
              width: 16,
              color: context.sailTheme.colors.textSecondary,
            ),
            SailText.secondary12('Advanced settings'),
          ],
        ),
      ),
    );
  }
}

class _StoreButton extends StatelessWidget {
  final BitDriveViewModel model;

  const _StoreButton({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailButton(
      label: 'Store on ${activeTicker.name}',
      variant: model.canStore ? ButtonVariant.primary : ButtonVariant.secondary,
      disabled: !model.canStore,
      loading: model.isBusy,
      loadingLabel: 'Storing...',
      onPressed: () async => model.store(context),
    );
  }
}

class _StoreIntro extends StatelessWidget {
  final bool showTitle;

  const _StoreIntro({this.showTitle = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[SailText.primary15('How It Works'), const SailSpacing(SailStyleValues.padding08)],
        SailText.secondary13(
          '1. Enter text or choose a file (max 1 MB)\n'
          '2. Optionally encrypt with your wallet key\n'
          '3. Click "Store on ${activeTicker.name}" to save forever\n'
          '4. Data is embedded in ${activeTicker.name} transactions',
        ),
        const SailSpacing(SailStyleValues.padding20),
        SailText.primary15('Why Use BitDrive?'),
        const SailSpacing(SailStyleValues.padding08),
        SailText.secondary13(
          '• Permanent storage - data lives as long as ${activeTicker.name}\n'
          '• Censorship resistant - no one can delete it\n'
          '• Encryption option for private data\n'
          '• Prove you knew something at a specific time',
        ),
      ],
    );
  }
}

class _StoreForm extends StatelessWidget {
  final BitDriveViewModel model;
  final bool showTitle;

  /// Puts "Store on" as a full-width button under the inputs.
  final bool fullWidthStore;

  const _StoreForm({required this.model, this.showTitle = true, this.fullWidthStore = false});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding16,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) SailText.primary15('What do you want to store?', bold: true),
        SailTextField(
          controller: model.textController,
          maxLines: 4,
          hintText: 'Write anything here...',
        ),
        if (model.textError != null) SailInlineError(model.textError!),
        Row(
          children: [
            Expanded(child: Container(height: 1, color: context.sailTheme.colors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding16),
              child: SailText.secondary12('OR'),
            ),
            Expanded(child: Container(height: 1, color: context.sailTheme.colors.divider)),
          ],
        ),
        SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            SailButton(
              label: 'Choose File',
              variant: ButtonVariant.secondary,
              icon: SailSVGAsset.upload,
              onPressed: () async => model.pickFile(context),
            ),
            if (model.selectedFileName != null) ...[
              Expanded(child: SailText.primary13(model.selectedFileName!)),
              SailButton(
                variant: ButtonVariant.ghost,
                icon: SailSVGAsset.iconClose,
                onPressed: () async => model.clearSelectedFile(),
              ),
            ] else
              Expanded(child: SailText.secondary12('No file selected')),
          ],
        ),
        if (model.fileError != null) SailInlineError(model.fileError!),
        if (fullWidthStore)
          _AdvancedToggle(model: model)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _AdvancedToggle(model: model),
              _StoreButton(model: model),
            ],
          ),
        if (!fullWidthStore && model.storeError != null) SailInlineError(model.storeError!),
        if (model.showAdvancedSettings)
          SailCard(
            padding: true,
            secondary: true,
            child: SailColumn(
              spacing: SailStyleValues.padding12,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailCheckbox(
                  value: model.shouldEncrypt,
                  onChanged: model.onEncryptChanged,
                  label: 'Encrypt content (uses your wallet key)',
                ),
                SailRow(
                  spacing: SailStyleValues.padding08,
                  children: [
                    SizedBox(
                      width: 150,
                      child: NumericField(
                        label: 'Fee rate (sat/vB)',
                        controller: model.feeController,
                        hintText: '1',
                        textFieldType: TextFieldType.number,
                      ),
                    ),
                    SailButton(
                      variant: ButtonVariant.icon,
                      icon: SailSVGAsset.arrowUp,
                      onPressed: () async => model.adjustFeeRate(1),
                    ),
                    SailButton(
                      variant: ButtonVariant.icon,
                      icon: SailSVGAsset.arrowDown,
                      onPressed: () async => model.adjustFeeRate(-1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (fullWidthStore) ...[
          SizedBox(
            width: double.infinity,
            child: _StoreButton(model: model),
          ),
          if (model.storeError != null) SailInlineError(model.storeError!),
        ],
      ],
    );
  }
}

/// The desktop page: a top strip, then Store and My Files under one segmented control.
class _DesktopBitDrive extends StatelessWidget {
  final BitDriveViewModel model;

  const _DesktopBitDrive({required this.model});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailStrip(
          stats: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SailText.primary15('Store Data on ${activeTicker.name} Forever', bold: true),
                SailText.secondary13(
                  'BitDrive lets you permanently store files and text on the ${activeTicker.name} blockchain. Your data becomes part of ${activeTicker.name} history.',
                ),
              ],
            ),
          ],
          actions: [
            if (model.bitdriveDir != null)
              SailButton(
                label: 'Open Folder',
                variant: ButtonVariant.outline,
                icon: SailSVGAsset.folderOpen,
                onPressed: () async => model.openBitdriveDir(),
              ),
          ],
        ),
        const SizedBox(height: SailStyleValues.padding12),
        Expanded(
          child: InlineTabBar(
            tabs: [
              SingleTabItem(
                label: 'Store',
                child: _DesktopStore(model: model),
              ),
              SingleTabItem(
                label: 'My Files',
                child: _MyFilesTab(model: model),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopStore extends StatelessWidget {
  final BitDriveViewModel model;

  const _DesktopStore({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailPageWithPanel(
      panel: SailSidePanel(
        title: 'How It Works',
        child: const _StoreIntro(showTitle: false),
      ),
      child: SingleChildScrollView(
        child: SailCard(
          title: 'What do you want to store?',
          child: _StoreForm(model: model, showTitle: false, fullWidthStore: true),
        ),
      ),
    );
  }
}

class _MyFilesTab extends StatelessWidget {
  final BitDriveViewModel model;

  const _MyFilesTab({required this.model});

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return _PhoneMyFiles(model: model);
    }
    final pending = model.pendingDownloadsCount;
    return SailCard(
      title: 'Your files stored on ${activeTicker.name}',
      subtitle: '${model.downloadedFiles.length} files downloaded${pending > 0 ? ', $pending pending' : ''}',
      bottomPadding: false,
      widgetHeaderEnd: SailRow(
        spacing: SailStyleValues.padding08,
        children: [
          SailButton(
            label: 'Scan for new',
            variant: ButtonVariant.secondary,
            loading: model.isScanning,
            loadingLabel: 'Scanning...',
            onPressed: () async => model.scanFiles(),
          ),
          SailRowMenuButton(
            items: () => [
              SailMenuItem(
                onSelected: pending == 0 || model.isDownloading ? null : () => model.downloadFiles(),
                child: SailText.primary12(
                  model.isDownloading ? 'Downloading...' : 'Download all',
                  color: pending == 0 ? context.sailTheme.colors.textTertiary : null,
                ),
              ),
            ],
          ),
        ],
      ),
      child: model.downloadedFiles.isEmpty
          ? Center(
              child: SailColumn(
                spacing: SailStyleValues.padding16,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SailSVG.fromAsset(SailSVGAsset.folder, color: context.sailTheme.colors.textTertiary, width: 48),
                  SailText.secondary13('No files downloaded yet'),
                  SailText.secondary12(
                    'Click "Scan for new" to find files stored on ${activeTicker.name}',
                    color: context.sailTheme.colors.textTertiary,
                  ),
                ],
              ),
            )
          : SailTable(
              getRowId: (index) => model.downloadedFiles[index].txid,
              headerBuilder: (context) => [
                const SailTableHeaderCell(name: 'Date'),
                const SailTableHeaderCell(name: 'Name'),
                const SailTableHeaderCell(name: 'Size', alignment: Alignment.centerRight),
              ],
              rowBuilder: (context, row, selected) {
                final file = model.downloadedFiles[row];
                return [
                  SailTableCell(value: DateFormat('MMM d, yyyy').format(_fileDate(file))),
                  SailTableCell(value: file.filename),
                  SailTableCell(value: _formatFileSize(file.sizeBytes.toInt()), alignment: Alignment.centerRight),
                ];
              },
              rowCount: model.downloadedFiles.length,
              emptyPlaceholder: 'No files downloaded yet',
            ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

DateTime _fileDate(bitdrivepb.BitDriveFile file) =>
    file.hasCreatedAt() ? file.createdAt.toDateTime() : DateTime.fromMillisecondsSinceEpoch(file.timestamp * 1000);

class _PhoneMyFiles extends StatelessWidget {
  final BitDriveViewModel model;

  const _PhoneMyFiles({required this.model});

  @override
  Widget build(BuildContext context) {
    final files = model.downloadedFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailText.primary15('Your files stored on ${activeTicker.name}', bold: true),
        SailText.secondary12(
          '${files.length} files downloaded${model.pendingDownloadsCount > 0 ? ', ${model.pendingDownloadsCount} pending' : ''}',
        ),
        const SizedBox(height: SailStyleValues.padding04),
        SailRow(
          spacing: SailStyleValues.padding08,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SailButton(
              label: 'Scan for new',
              variant: model.pendingDownloadsCount > 0 ? ButtonVariant.secondary : ButtonVariant.primary,
              small: true,
              loading: model.isScanning,
              loadingLabel: 'Scanning...',
              onPressed: () async => model.scanFiles(),
            ),
            SailButton(
              label: 'Download all',
              variant: model.pendingDownloadsCount > 0 ? ButtonVariant.primary : ButtonVariant.secondary,
              small: true,
              disabled: model.pendingDownloadsCount == 0,
              loading: model.isDownloading,
              loadingLabel: 'Downloading...',
              onPressed: () async => model.downloadFiles(),
            ),
          ],
        ),
        const SizedBox(height: SailStyleValues.padding12),
        Expanded(
          child: files.isEmpty
              ? Center(child: SailText.secondary13('No files downloaded yet'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 1, color: SailTheme.of(context).colors.divider),
                    Expanded(
                      child: SailDividedList(
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return SailTappable(
                            onTap: () async {
                              try {
                                await model.shareDownloadedFile(file.filename);
                              } catch (e) {
                                if (context.mounted) {
                                  showSailToast(context, '$e', variant: SailToastVariant.destructive);
                                }
                              }
                            },
                            child: SailListRow(
                              title: file.filename,
                              subtitle: DateFormat('MMM d, yyyy').format(_fileDate(file)),
                              trailing: SailRow(
                                spacing: SailStyleValues.padding12,
                                children: [
                                  SailText.primary13(_formatFileSize(file.sizeBytes.toInt())),
                                  SailSVG.fromAsset(
                                    SailSVGAsset.share,
                                    width: 14,
                                    color: SailTheme.of(context).colors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class BitDriveViewModel extends BaseViewModel {
  @visibleForTesting
  static Future<void> Function(String path) share = shareFile;

  final BitDriveProvider provider = GetIt.I.get<BitDriveProvider>();
  final TextEditingController textController = TextEditingController();
  late final TextEditingController feeController = TextEditingController(text: '${provider.feeSatPerVbyte}');
  Logger get log => GetIt.I.get<Logger>();
  String? selectedFileName;
  Uint8List? selectedFileContent;
  String? fileError;
  String? textError;
  String? storeError;
  bool get shouldEncrypt => provider.shouldEncrypt;
  bool get canStore =>
      ((textController.text.isNotEmpty && textError == null) || selectedFileContent != null) && feeRate != null;
  int? get feeRate {
    final rate = int.tryParse(feeController.text);
    return rate != null && rate >= 1 ? rate : null;
  }

  String? _bitdriveDir;
  String? get bitdriveDir => _bitdriveDir;

  bool showAdvancedSettings = false;
  List<bitdrivepb.BitDriveFile> downloadedFiles = [];

  bool get isScanning => provider.isScanning;
  bool get isDownloading => provider.isDownloading;
  int get pendingDownloadsCount => provider.pendingDownloadsCount;

  BitwindowRPC get bitwindowd => GetIt.I.get<BitwindowRPC>();

  BitDriveViewModel() {
    provider.addListener(_onProviderChanged);
    textController.addListener(() => onTextChanged(textController.text));
    feeController.addListener(_onFeeRateChanged);
    _initBitdrive();
  }

  Future<void> _initBitdrive() async {
    // Initialize the BitDrive provider when the user opens the BitDrive tab
    // This triggers filesystem access only when needed (see issue #842)
    await provider.init();
    await _initBitdriveDir();
  }

  void _onProviderChanged() {
    notifyListeners();
  }

  void _onFeeRateChanged() {
    storeError = null;
    final rate = feeRate;
    if (rate != null) {
      provider.setFeeRate(rate);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    provider.removeListener(_onProviderChanged);
    textController.dispose();
    feeController.dispose();
    super.dispose();
  }

  void toggleAdvancedSettings() {
    showAdvancedSettings = !showAdvancedSettings;
    notifyListeners();
  }

  Future<void> scanFiles() async {
    notifyListeners();
    await provider.scanForFiles();
    notifyListeners();
  }

  Future<void> downloadFiles() async {
    notifyListeners();
    await provider.downloadPendingFiles();
    await _loadDownloadedFiles();
    notifyListeners();
  }

  Future<void> _initBitdriveDir() async {
    try {
      _bitdriveDir = await bitwindowd.bitdrive.getBitdriveDir();
    } catch (e) {
      log.e('Error getting bitdrive dir from backend: $e');
    }
    await _loadDownloadedFiles();
    notifyListeners();
  }

  Future<void> _loadDownloadedFiles() async {
    try {
      final files = await provider.listFiles();
      // Sort by createdAt descending (newest first)
      files.sort((a, b) {
        final aTime = a.hasCreatedAt() ? a.createdAt.toDateTime() : DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.hasCreatedAt() ? b.createdAt.toDateTime() : DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      downloadedFiles = files;
      notifyListeners();
    } catch (e) {
      log.e('Error loading downloaded files: $e');
    }
  }

  /// Opens the phone share sheet for a downloaded file.
  Future<void> shareDownloadedFile(String filename) async {
    final dir = _bitdriveDir;
    if (dir == null) {
      throw StateError('the BitDrive folder is not known yet');
    }
    await share(p.join(dir, filename));
  }

  Future<void> openBitdriveDir() async {
    if (_bitdriveDir == null) {
      return;
    }
    try {
      await bitwindowd.bitdrive.openBitdriveDir();
    } catch (e) {
      log.e('Error opening BitDrive directory: $e');
    }
  }

  void adjustFeeRate(int delta) {
    final rate = (feeRate ?? 1) + delta;
    feeController.text = '${rate < 1 ? 1 : rate}';
  }

  void onTextChanged(String value) {
    fileError = null;
    storeError = null;
    textError = utf8.encode(value).length > BitDriveProvider.maxContentBytes ? BitDriveProvider.textSizeError : null;
    provider.setTextContent(value);
    if (value.isNotEmpty) {
      selectedFileName = null;
      selectedFileContent = null;
    }
    notifyListeners();
  }

  void onEncryptChanged(bool? value) {
    if (value != null) {
      provider.setEncryption(value);
      storeError = null;
      notifyListeners();
    }
  }

  Future<void> clearSelectedFile() async {
    selectedFileName = null;
    selectedFileContent = null;
    notifyListeners();
  }

  Future<void> pickFile(BuildContext context) async {
    fileError = null;
    storeError = null;
    notifyListeners();
    try {
      final file = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (file != null) {
        final size = await file.length();
        if (size == null) {
          fileError = 'Could not read file size';
          notifyListeners();
          return;
        }
        if (size > 1024 * 1024) {
          fileError = 'File size must be less than 1MB';
          notifyListeners();
          return;
        }

        final Uint8List fileContents;
        try {
          fileContents = await file.readAsBytes();
        } catch (e) {
          Logger().e('Error reading file: $e');
          fileError = 'Error reading file: $e';
          notifyListeners();
          return;
        }

        final extension = p.extension(file.name).replaceFirst('.', '');
        selectedFileContent = fileContents;
        selectedFileName = file.name;
        textController.clear();
        await provider.setFileContent(
          fileContents,
          name: file.name,
          type: extension.isNotEmpty ? 'application/$extension' : 'application/octet-stream',
        );
        notifyListeners();
      }
    } catch (e) {
      Logger().e('Error picking file: $e');
      fileError = 'Error picking file: $e';
      notifyListeners();
    }
  }

  Future<void> store(BuildContext context) async {
    storeError = null;
    setBusy(true);
    try {
      await provider.store();
      if (context.mounted) {
        showSailToast(context, 'Content stored on ${activeTicker.name}!');
        textController.clear();
        selectedFileName = null;
        selectedFileContent = null;
      }
    } catch (e) {
      storeError = 'Failed to store content: $e';
    } finally {
      setBusy(false);
    }
  }
}
