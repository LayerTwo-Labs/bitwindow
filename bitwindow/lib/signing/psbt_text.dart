import 'dart:convert';

const _psbtMagic = [0x70, 0x73, 0x62, 0x74, 0xff];

/// Whether [text] is base64 that starts with the PSBT magic bytes.
bool isBase64Psbt(String text) {
  final List<int> bytes;
  try {
    bytes = base64.decode(text);
  } on FormatException {
    return false;
  }
  if (bytes.length < _psbtMagic.length) {
    return false;
  }
  for (var i = 0; i < _psbtMagic.length; i++) {
    if (bytes[i] != _psbtMagic[i]) {
      return false;
    }
  }
  return true;
}
