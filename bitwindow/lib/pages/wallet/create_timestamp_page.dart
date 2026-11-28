import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/providers/timestamp_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

class CreateTimestampViewModel extends BaseViewModel {
  final TimestampProvider _timestampProvider = GetIt.I.get<TimestampProvider>();

  File? selectedFile;
  String? selectedFilename;
  int? selectedFileSize;
  bool isCreating = false;
  @override
  String? modelError;

  String get fileSizeFormatted {
    if (selectedFileSize == null) {
      return '';
    }
    final kb = selectedFileSize! / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> pickFile() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (result?.path != null) {
        final file = File(result!.path!);
        final size = await file.length();

        if (size > maxFileSizeBytes) {
          modelError = 'File too large. Maximum size: 1MB';
          notifyListeners();
          return;
        }

        selectedFile = file;
        selectedFilename = result.name;
        selectedFileSize = size;
        modelError = null;
        notifyListeners();
      }
    } catch (e) {
      modelError = 'Failed to pick file: $e';
      notifyListeners();
    }
  }

  /// [onCreated] gets the new timestamp. Null opens its details page.
  Future<void> timestampFile(BuildContext context, {void Function(FileTimestamp timestamp)? onCreated}) async {
    if (selectedFile == null) {
      modelError = 'Please select a file first';
      notifyListeners();
      return;
    }

    isCreating = true;
    modelError = null;
    notifyListeners();

    try {
      final bytes = await selectedFile!.readAsBytes();
      final timestamp = await _timestampProvider.timestampFile(
        selectedFilename!,
        bytes,
      );

      if (timestamp != null && context.mounted && onCreated != null) {
        onCreated(timestamp);
      } else if (timestamp != null && context.mounted) {
        await GetIt.I.get<AppRouter>().replace(TimestampDetailRoute(timestampId: timestamp.id.toInt()));
      } else {
        modelError = _timestampProvider.modelError ?? 'Failed to timestamp file';
      }
    } catch (e) {
      modelError = 'Error: $e';
    } finally {
      isCreating = false;
      notifyListeners();
    }
  }
}

@RoutePage()
class CreateTimestampPage extends StatelessWidget {
  const CreateTimestampPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<CreateTimestampViewModel>.reactive(
      viewModelBuilder: () => CreateTimestampViewModel(),
      builder: (context, model, child) {
        return SailScaffold(
          backgroundColor: SailTheme.of(context).colors.background,
          appBar: SailAppBar.build(context, title: SailText.primary20('Timestamp a File')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  padding: const EdgeInsets.all(SailStyleValues.padding20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: SailStyleValues.padding20,
                    children: [
                      SailText.secondary13(
                        'Upload a file (max 1MB) to timestamp on the Bitcoin blockchain. '
                        'This will create a permanent, verifiable proof that the file existed at this time.',
                      ),
                      if (model.selectedFile == null)
                        Column(
                          spacing: SailStyleValues.padding12,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SailSVG.icon(
                              SailSVGAsset.iconDownload,
                              width: 48,
                              color: context.sailTheme.colors.text.withValues(alpha: 0.5),
                            ),
                            SailText.secondary13('No file selected'),
                          ],
                        )
                      else
                        Column(
                          spacing: SailStyleValues.padding08,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SailSVG.icon(
                                  SailSVGAsset.iconSuccess,
                                  width: 24,
                                ),
                                const SizedBox(width: SailStyleValues.padding08),
                                Expanded(
                                  child: SailText.primary13(
                                    model.selectedFilename ?? 'Unknown',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            SailText.secondary12('Size: ${model.fileSizeFormatted}'),
                          ],
                        ),
                      SailButton(
                        label: model.selectedFile == null ? 'Choose File' : 'Change File',
                        variant: ButtonVariant.secondary,
                        onPressed: () async => model.pickFile(),
                        icon: SailSVGAsset.iconSearch,
                      ),
                      if (model.modelError != null)
                        Container(
                          padding: const EdgeInsets.all(SailStyleValues.padding12),
                          decoration: BoxDecoration(
                            color: context.sailTheme.colors.error.withValues(alpha: 0.1),
                            borderRadius: context.sailTheme.chrome.radiusSmall,
                            border: Border.all(color: context.sailTheme.colors.error),
                          ),
                          child: SailText.secondary13(
                            model.modelError!,
                            color: context.sailTheme.colors.error,
                          ),
                        ),
                      Row(
                        spacing: SailStyleValues.padding08,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SailButton(
                            label: 'Cancel',
                            variant: ButtonVariant.ghost,
                            onPressed: () async => GetIt.I.get<AppRouter>().pop(),
                          ),
                          SailButton(
                            label: 'Timestamp File',
                            loading: model.isCreating,
                            disabled: model.selectedFile == null,
                            onPressed: () async => model.timestampFile(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens "Timestamp a File" as a dialog. Returns the new timestamp, or null.
Future<FileTimestamp?> showCreateTimestampDialog(BuildContext context) {
  return showThemedDialog<FileTimestamp>(context: context, builder: (context) => const CreateTimestampDialog());
}

class CreateTimestampDialog extends StatelessWidget {
  const CreateTimestampDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<CreateTimestampViewModel>.reactive(
      viewModelBuilder: () => CreateTimestampViewModel(),
      builder: (context, model, child) {
        final theme = SailTheme.of(context);
        final chosen = model.selectedFile != null;
        return SailDialog(
          title: 'Timestamp a File',
          withCloseButton: true,
          maxWidth: 480,
          child: SailColumn(
            spacing: SailStyleValues.padding12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SailText.secondary13(
                'Upload a file (max 1MB) to timestamp on the Bitcoin blockchain. '
                'This will create a permanent, verifiable proof that the file existed at this time.',
              ),
              DecoratedBox(
                decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      SailSVG.fromAsset(
                        SailSVGAsset.fileText,
                        width: 14,
                        height: 14,
                        color: theme.colors.textSecondary,
                      ),
                      const SizedBox(width: SailStyleValues.padding08),
                      Expanded(
                        child: chosen
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SailText.primary13(model.selectedFilename ?? 'Unknown'),
                                  SailText.secondary12('Size: ${model.fileSizeFormatted}'),
                                ],
                              )
                            : SailText.primary13('No file selected', color: theme.colors.textHint),
                      ),
                      SailButton(
                        label: chosen ? 'Change File' : 'Choose File',
                        variant: ButtonVariant.ghost,
                        onPressed: () async => model.pickFile(),
                      ),
                    ],
                  ),
                ),
              ),
              if (model.modelError != null) SailText.primary12(model.modelError!, color: theme.colors.error),
              SailButton(
                label: 'Timestamp File',
                loading: model.isCreating,
                disabled: !chosen,
                onPressed: () async =>
                    model.timestampFile(context, onCreated: (timestamp) => Navigator.of(context).pop(timestamp)),
              ),
            ],
          ),
        );
      },
    );
  }
}
