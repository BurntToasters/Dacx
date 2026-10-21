/// Local filesystem paths from file_picker 13 `PlatformFile` / save `Uri`.
abstract final class FilePickerPath {
  /// Absolute path from a picked file, or null if it is not a local file.
  static String? fromPlatformFilePath(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Converts a [FilePicker.saveFile] result to a local path.
  ///
  /// Desktop plugins may return a `file:` URI or a bare path string parsed as
  /// a schemeless URI. Windows drive URIs (`file:///C:/...`) are decoded with
  /// Windows separators even when this code runs on POSIX (and vice versa).
  static String? fromSaveUri(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme == 'file') {
      try {
        final path = uri
            .toFilePath(windows: _fileUriUsesWindowsPath(uri))
            .trim();
        return path.isEmpty ? null : path;
      } on UnsupportedError {
        return null;
      }
    }
    if (uri.scheme.isEmpty) {
      final path = uri.path.trim();
      return path.isEmpty ? null : path;
    }
    if (uri.scheme.length == 1) {
      final drive = '${uri.scheme}:${uri.path}'.trim();
      return drive.isEmpty ? null : drive;
    }
    return null;
  }

  /// `file:///C:/Users/...` or UNC `file://server/share/...`.
  static bool _fileUriUsesWindowsPath(Uri uri) {
    if (uri.host.isNotEmpty) return true;
    final path = uri.path;
    return path.length >= 3 &&
        path.startsWith('/') &&
        path.codeUnitAt(2) == 0x3A && // ':'
        _isDriveLetter(path.codeUnitAt(1));
  }

  static bool _isDriveLetter(int unit) {
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }
}
