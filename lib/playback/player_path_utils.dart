import 'dart:io';

class OpenFileRequest {
  final String path;
  final String? bookmark;
  const OpenFileRequest({required this.path, this.bookmark});
}

/// Path normalization and error classification for open-file / drag-drop flows.
abstract final class PlayerPathUtils {
  static const audioExtensions = {
    'mp3',
    'flac',
    'wav',
    'ogg',
    'aac',
    'm4a',
    'wma',
    'opus',
    'ape',
    'alac',
    'aiff',
    'aif',
    'wv',
    'mpc',
  };

  static const videoExtensions = {
    'mp4',
    'mkv',
    'avi',
    'webm',
    'mov',
    'wmv',
    'flv',
    'm4v',
    'ts',
    'm2ts',
    'mts',
    'mpg',
    'mpeg',
    'vob',
    'ogv',
  };

  static const supportedExtensions = {...audioExtensions, ...videoExtensions};

  /// True for Windows UNC (`\\server\share\...`) or extended UNC (`\\?\UNC\...`).
  static bool isUncPath(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith(r'\\')) return true;
    // Forward-slash UNC seen in some drag/URI normalizations.
    if (trimmed.startsWith('//') &&
        !trimmed.toLowerCase().startsWith('//./') &&
        trimmed.length > 2 &&
        trimmed[2] != '/') {
      return true;
    }
    return false;
  }

  /// Rejects paths that must never be handed to the media engine from IPC /
  /// Open With (UNC → NTLM / remote decoder surface).
  static bool isUnsafeOpenPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.contains('\x00')) return true;
    if (isUncPath(trimmed)) return true;
    return false;
  }

  /// Coerces platform bridge payloads to a trimmed path string.
  static String? coerceOpenPath(Object? value) {
    return coerceOpenRequest(value)?.path;
  }

  /// Coerces platform bridge payloads to path plus optional native bookmark.
  static OpenFileRequest? coerceOpenRequest(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (isUnsafeOpenPath(trimmed)) return null;
      return OpenFileRequest(path: trimmed);
    }
    if (value is Map) {
      final rawPath = value['path'];
      if (rawPath is! String) return null;
      final path = rawPath.trim();
      if (path.isEmpty) return null;
      if (isUnsafeOpenPath(path)) return null;
      final rawBookmark = value['bookmark'];
      final bookmark = rawBookmark is String && rawBookmark.trim().isNotEmpty
          ? rawBookmark.trim()
          : null;
      return OpenFileRequest(path: path, bookmark: bookmark);
    }
    return null;
  }

  /// Decodes `file://` URIs from drag-and-drop payloads.
  static String normalizeDropPath(String raw, {required bool windows}) {
    final trimmed = raw.trim();
    if (!trimmed.toLowerCase().startsWith('file:')) return trimmed;
    try {
      return Uri.parse(trimmed).toFilePath(windows: windows);
    } catch (_) {
      return trimmed;
    }
  }

  static bool isAudioExtension(String ext) =>
      audioExtensions.contains(ext.toLowerCase());

  static bool isSupportedExtension(String ext) =>
      supportedExtensions.contains(ext.toLowerCase());

  static bool isPermissionDeniedError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('permission denied') ||
        lower.contains('access is denied') ||
        lower.contains('operation not permitted')) {
      return true;
    }
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code == 1 || code == 5 || code == 13) {
        return true;
      }
    }
    return false;
  }
}
