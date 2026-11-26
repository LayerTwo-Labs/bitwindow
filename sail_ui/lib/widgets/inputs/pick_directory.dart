import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

/// Asks the user for a directory. Gives its path with no separator at the end,
/// or null when the user cancels.
Future<String?> pickDirectoryPath({String? dialogTitle, String? initialDirectory}) async {
  final directory = await FilePicker.pickDirectory(dialogTitle: dialogTitle, initialDirectory: initialDirectory);
  return directory == null ? null : path.normalize(directory.toFilePath());
}
