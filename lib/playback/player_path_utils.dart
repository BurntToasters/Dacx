import 'dart:io';

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
  };

  static const supportedExtensions = {...audioExtensions, ...videoExtensions};

  /// Coerces platform bridge payloads to a trimmed path string.
  static String? coerceOpenPath(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
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
