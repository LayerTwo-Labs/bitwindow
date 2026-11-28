import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:bitwindow/utils/wallet_picture_path.dart';
import 'package:sail_ui/sail_ui.dart';

/// Opens the edit dialog for one wallet: its name, its picture, and the
/// choice to delete it.
Future<void> editWallet(BuildContext context, WalletMetadata wallet) async {
  final result = await showEditWalletDialog(
    context,
    currentName: wallet.name,
    gradient: wallet.gradient,
    onChangePicture: () async => _pickWalletPicture(context),
    onConfirmDelete: () async => _confirmDeleteWallet(context, wallet),
    deleteBlockedReason: deleteBlockedReason(GetIt.I.get<WalletReaderProvider>().wallets, wallet),
  );
  if (result == null) {
    return;
  }

  if (result.delete) {
    try {
      await GetIt.I.get<OrchestratorRPC>().wallet.deleteWallet(wallet.id);
    } catch (e) {
      if (context.mounted) {
        showSailToast(
          context,
          'Could not delete ${wallet.name}: ${extractConnectException(e)}',
          variant: SailToastVariant.destructive,
        );
      }
      return;
    }
    await _deleteWalletPicture(wallet.gradient.picturePath);
    return;
  }

  var gradient = wallet.gradient;
  if (result.removePicture) {
    gradient = gradient.withoutPicture();
  }
  final picture = result.picture;
  File? written;
  if (picture != null) {
    written = await _saveWalletPicture(wallet.id, picture);
    gradient = gradient.copyWith(picturePath: written.path);
  }

  try {
    await GetIt.I.get<WalletReaderProvider>().updateWalletMetadata(wallet.id, result.name, gradient);
  } catch (e) {
    // Nothing points at the new file, so it does not stay on the disk.
    await _deleteWalletPicture(written?.path);
    if (context.mounted) {
      showSailToast(
        context,
        'Could not save ${wallet.name}: ${extractConnectException(e)}',
        variant: SailToastVariant.destructive,
      );
    }
    return;
  }

  // The old file goes only once the wallet no longer points at it.
  if (result.removePicture || written != null) {
    await _deleteWalletPicture(wallet.gradient.picturePath);
  }
}

/// The reason the backend refuses to delete [wallet], or null when it allows it.
String? deleteBlockedReason(List<WalletData> wallets, WalletMetadata wallet) {
  final starter = wallets.any((w) => w.id == wallet.id && w.isStarter);
  if (!starter || wallets.length < 2) {
    return null;
  }
  return '${wallet.name} makes the sidechain starters. Delete the other wallets first.';
}

/// The confirm text for a delete of [name], which holds [sats] in total.
String deleteWalletSubtitle(String name, int sats) {
  const leaves = 'The wallet leaves this computer. Its backup is the only way back.';
  if (sats <= 0) {
    return leaves;
  }
  return '$name holds ${formatBitcoin(satoshiToBTC(sats))}. $leaves';
}

Future<bool> _confirmDeleteWallet(BuildContext context, WalletMetadata wallet) async {
  String subtitle;
  var canDelete = true;
  try {
    final balance = await GetIt.I.get<OrchestratorRPC>().wallet.getBalance(wallet.id);
    final sats = balance.confirmedSats + balance.unconfirmedSats + balance.immatureSats;
    subtitle = deleteWalletSubtitle(wallet.name, sats.round());
  } catch (e) {
    subtitle =
        'Could not read the balance of ${wallet.name}: ${extractConnectException(e)}. '
        'Delete is off until the balance shows.';
    canDelete = false;
  }
  if (!context.mounted) {
    return false;
  }
  final go = await showThemedDialog<bool>(
    context: context,
    builder: (context) => SailAlertCard(
      title: 'Delete ${wallet.name}?',
      subtitle: subtitle,
      confirmText: 'Delete wallet',
      confirmButtonVariant: ButtonVariant.destructive,
      confirmDisabled: !canDelete,
      onConfirm: () async => Navigator.of(context).pop(true),
      onCancel: () async => Navigator.of(context).pop(false),
    ),
  );
  return go ?? false;
}

/// Asks for an image file, then lets the user place it in the round window.
Future<Uint8List?> _pickWalletPicture(BuildContext context) async {
  final picked = await FilePicker.pickFile(
    dialogTitle: 'Choose a wallet picture',
    type: FileType.image,
  );
  final path = picked?.path;
  if (path == null || !context.mounted) {
    return null;
  }
  return showPlacePictureDialog(context, File(path));
}

/// Takes the picture off the disk. A user who removes a picture, or deletes
/// the wallet, does not leave the photo behind.
Future<void> _deleteWalletPicture(String? path) async {
  if (path == null || path.isEmpty) {
    return;
  }
  // A restored wallet carries whatever path its old computer wrote, so only
  // a file this app put in its own folder goes.
  final appDir = GetIt.I.get<WindowProvider>().appDir;
  final owned = Directory([appDir.path, 'wallet_pictures'].join(Platform.pathSeparator));
  final file = File(path);
  if (!isInsideWalletPictures(file.absolute.path, owned.absolute.path)) {
    return;
  }
  if (!await file.exists()) {
    return;
  }
  await file.delete();
  await FileImage(file).evict();
}

/// Writes the placed picture beside the wallet metadata. Each save takes its
/// own name, so a replacement never overwrites the picture it replaces.
Future<File> _saveWalletPicture(String walletId, Uint8List png) async {
  final appDir = GetIt.I.get<WindowProvider>().appDir;
  final dir = Directory([appDir.path, 'wallet_pictures'].join(Platform.pathSeparator));
  await dir.create(recursive: true);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final file = File([dir.path, '$walletId-$stamp.png'].join(Platform.pathSeparator));
  await file.writeAsBytes(png, flush: true);
  return file;
}
