import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the user picked, already size-checked and read into memory.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Thrown when the picked file exceeds the caller's size limit.
class FileTooLargeException implements Exception {
  const FileTooLargeException(this.maxBytes);
  final int maxBytes;
}

/// Opens the system picker for one file with one of [extensions].
/// Returns null if the user cancels. The size is checked before the bytes are
/// read, so an oversized file is never loaded into memory.
Future<PickedFile?> pickSingleFile({
  required List<String> extensions,
  required int maxBytes,
}) async {
  final f = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  return f == null ? null : readPickedFile(f, maxBytes: maxBytes);
}

/// Size-checks and reads [f]. Split out from [pickSingleFile] for testing.
Future<PickedFile> readPickedFile(
  PlatformFile f, {
  required int maxBytes,
}) async {
  final size = f.lengthSync() ?? await f.length();
  if (size != null && size > maxBytes) throw FileTooLargeException(maxBytes);
  final bytes = await f.readAsBytes();
  if (bytes.length > maxBytes) throw FileTooLargeException(maxBytes);
  return PickedFile(f.name, bytes);
}
