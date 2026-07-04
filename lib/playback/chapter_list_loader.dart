import '../screens/chapter_info.dart';

typedef MpvPropertyReader = Future<String?> Function(String name);

/// Loads chapter metadata from mpv via [readProperty].
abstract final class ChapterListLoader {
  static Future<List<ChapterInfo>> load({
    required MpvPropertyReader readProperty,
    int? expectedCount,
    String Function(int index)? fallbackTitle,
  }) async {
    final count =
        expectedCount ??
        (int.tryParse(await readProperty('chapter-list/count') ?? '') ?? 0);
    if (count <= 0) return const [];

    final fallback = fallbackTitle ?? (i) => 'Chapter ${i + 1}';
    final list = <ChapterInfo>[];
    for (var i = 0; i < count; i++) {
      final title = await readProperty('chapter-list/$i/title');
      final timeStr = await readProperty('chapter-list/$i/time');
      final time = double.tryParse(timeStr ?? '') ?? 0;
      list.add(
        ChapterInfo(
          index: i,
          title: (title == null || title.isEmpty) ? fallback(i) : title,
          time: Duration(milliseconds: (time * 1000).round()),
        ),
      );
    }
    return list;
  }
}
