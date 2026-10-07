import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/playable_source.dart';
import 'player_path_utils.dart';

/// Local playlist file helpers (`.m3u` / `.pls`). HLS `.m3u8` stays a media
/// source for mpv; not expanded here.
abstract final class M3uPlaylist {
  static const extensions = {'m3u', 'pls'};

  static bool isPlaylistPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return extensions.contains(ext);
  }

  /// Parses playlist [content]. Relative file entries resolve against [baseDir]
  /// when provided. Unsafe / empty entries are skipped.
  static List<PlayableSource> parse(String content, {String? baseDir}) {
    final trimmed = content.trimLeft();
    if (trimmed.toLowerCase().startsWith('[playlist]')) {
      return _parsePls(content, baseDir: baseDir);
    }
    return _parseM3u(content, baseDir: baseDir);
  }

  static const maxBytes = 8 * 1024 * 1024;

  static Future<List<PlayableSource>> parseFile(String playlistPath) async {
    final file = File(playlistPath);
    final length = await file.length();
    if (length > maxBytes) {
      throw const FileSystemException('Playlist file is too large');
    }
    final content = decodeBytes(await file.readAsBytes());
    return parse(content, baseDir: p.dirname(playlistPath));
  }

  /// UTF-16 when a UTF-16 BOM is present. Otherwise UTF-8 first (BOM
  /// stripped), falling back to Latin-1 for the legacy
  /// single-byte `.m3u` files many Windows tools still write. Latin-1 maps
  /// every byte, so decoding never throws.
  static String decodeBytes(List<int> bytes) {
    if (bytes.length >= 2) {
      final littleEndian = bytes[0] == 0xFF && bytes[1] == 0xFE;
      final bigEndian = bytes[0] == 0xFE && bytes[1] == 0xFF;
      if (littleEndian || bigEndian) {
        final units = <int>[];
        for (var i = 2; i + 1 < bytes.length; i += 2) {
          units.add(
            littleEndian
                ? bytes[i] | (bytes[i + 1] << 8)
                : (bytes[i] << 8) | bytes[i + 1],
          );
        }
        return String.fromCharCodes(units);
      }
    }
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final body = start == 0 ? bytes : bytes.sublist(start);
    try {
      return utf8.decode(body);
    } on FormatException {
      return latin1.decode(body);
    }
  }

  /// Serializes [sources] as an `#EXTM3U` playlist (absolute paths / URLs).
  static String encode(List<PlayableSource> sources) {
    final buf = StringBuffer('#EXTM3U\n');
    for (final source in sources) {
      final value = source.value.trim();
      if (value.isEmpty) continue;
      if (source.isUrl && !PlayableSource.isSupportedUrl(value)) continue;
      if (source.isFile && PlayerPathUtils.isUnsafeOpenPath(value)) continue;
      buf.writeln(value);
    }
    return buf.toString();
  }

  static Future<void> writeFile(
    String playlistPath,
    List<PlayableSource> sources,
  ) async {
    final file = File(playlistPath);
    await file.writeAsString(encode(sources), flush: true);
  }

  static List<PlayableSource> _parseM3u(String content, {String? baseDir}) {
    final out = <PlayableSource>[];
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final source = _entryToSource(line, baseDir: baseDir);
      if (source != null) out.add(source);
    }
    return out;
  }

  static List<PlayableSource> _parsePls(String content, {String? baseDir}) {
    final out = <PlayableSource>[];
    final fileRe = RegExp(r'^File(\d+)=(.+)$', caseSensitive: false);
    final byIndex = <int, String>{};
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      final match = fileRe.firstMatch(line);
      if (match == null) continue;
      final index = int.tryParse(match.group(1)!);
      final value = match.group(2)?.trim();
      if (index == null || value == null || value.isEmpty) continue;
      byIndex[index] = value;
    }
    final keys = byIndex.keys.toList()..sort();
    for (final key in keys) {
      final source = _entryToSource(byIndex[key]!, baseDir: baseDir);
      if (source != null) out.add(source);
    }
    return out;
  }

  static PlayableSource? _entryToSource(String entry, {String? baseDir}) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!PlayableSource.isSupportedUrl(trimmed)) {
        return null;
      }
      return PlayableSource.url(trimmed);
    }
    var path = trimmed;
    // file:/// URIs → local path
    if (uri != null && uri.scheme == 'file') {
      path = uri.toFilePath();
    } else if (!p.isAbsolute(path) && baseDir != null && baseDir.isNotEmpty) {
      path = p.normalize(p.join(baseDir, path));
    }
    if (PlayerPathUtils.isUnsafeOpenPath(path)) return null;
    return PlayableSource.file(path);
  }
}
