import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

class _Picker extends FilePickerPlatform {
  _Picker(this.directory);

  final Uri? directory;
  String? title;
  String? start;

  @override
  Future<Uri?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    title = dialogTitle;
    start = initialDirectory;
    return directory;
  }
}

void main() {
  late FilePickerPlatform previous;

  setUp(() => previous = FilePickerPlatform.instance);
  tearDown(() => FilePickerPlatform.instance = previous);

  test('the path of a picked directory has no separator at the end', () async {
    final picker = _Picker(Uri.directory('/home/qa/Bitcoin Data'));
    FilePickerPlatform.instance = picker;

    expect(await pickDirectoryPath(dialogTitle: 'Save', initialDirectory: '/home/qa'), '/home/qa/Bitcoin Data');
    expect(picker.title, 'Save');
    expect(picker.start, '/home/qa');
  });

  test('a cancelled pick gives null', () async {
    FilePickerPlatform.instance = _Picker(null);
    expect(await pickDirectoryPath(), isNull);
  });
}
