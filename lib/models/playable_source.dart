import 'package:path/path.dart' as p;

enum PlayableSourceType { file, url }

class PlayableSource {
  const PlayableSource._(this.type, this.value);

  factory PlayableSource.file(String path) =>
      PlayableSource._(PlayableSourceType.file, path.trim());

  factory PlayableSource.url(String url) =>
      PlayableSource._(PlayableSourceType.url, url.trim());

  final PlayableSourceType type;
  final String value;

  bool get isFile => type == PlayableSourceType.file;
  bool get isUrl => type == PlayableSourceType.url;

  String get displayName {
    if (isFile) {
      final name = p.basename(value).trim();
      return name.isEmpty ? value : name;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    final pathName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (pathName.trim().isNotEmpty) return pathName.trim();
    return uri.host.isEmpty ? value : uri.host;
  }

  String? get extension {
    final sourcePath = isUrl ? Uri.tryParse(value)?.path ?? value : value;
    return p.extension(sourcePath).toLowerCase().replaceFirst('.', '');
  }

  static PlayableSource? fromStored(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (isSupportedUrl(trimmed)) return PlayableSource.url(trimmed);
    return PlayableSource.file(trimmed);
  }

  static bool isSupportedUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    // Refuse embedded credentials (logging/UI redaction is not enough).
    if (uri.userInfo.isNotEmpty) return false;
    return true;
  }

  static bool isDisplaySafeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !isSupportedUrl(value)) return false;
    return uri.userInfo.isEmpty && uri.query.isEmpty && uri.fragment.isEmpty;
  }

  static String displaySafeUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !isSupportedUrl(trimmed)) return trimmed;
    var base = uri.replace(userInfo: '').toString();
    final queryIndex = base.indexOf('?');
    final fragmentIndex = base.indexOf('#');
    final cutIndexes = [queryIndex, fragmentIndex].where((index) => index >= 0);
    if (cutIndexes.isNotEmpty) {
      base = base.substring(0, cutIndexes.reduce((a, b) => a < b ? a : b));
    }
    if (uri.query.isNotEmpty) base = '$base?<redacted>';
    if (uri.fragment.isNotEmpty) base = '$base#<redacted>';
    return base;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayableSource &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          value == other.value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => value;
}
