import 'package:sail_ui/sail_ui.dart';

/// The reason of a failed call, as one sentence with no exception class name.
String errorText(Object error) {
  final reason = error is BitwindowException ? error.message : error.toString();
  return reason.isEmpty ? reason : '${reason[0].toUpperCase()}${reason.substring(1)}';
}
