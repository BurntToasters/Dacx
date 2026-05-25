import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/chapter_list_loader.dart';

void main() {
  test('loads chapter titles and times from property reader', () async {
    Future<String?> read(String name) async {
      if (name == 'chapter-list/count') return '2';
      if (name == 'chapter-list/0/title') return 'Intro';
      if (name == 'chapter-list/0/time') return '0';
      if (name == 'chapter-list/1/title') return '';
      if (name == 'chapter-list/1/time') return '12.5';
      return null;
    }

    final chapters = await ChapterListLoader.load(readProperty: read);
    expect(chapters, hasLength(2));
    expect(chapters[0].title, 'Intro');
    expect(chapters[0].time, Duration.zero);
    expect(chapters[1].title, 'Chapter 2');
    expect(chapters[1].time, const Duration(milliseconds: 12500));
  });

  test('returns empty list when count is zero', () async {
    final chapters = await ChapterListLoader.load(
      readProperty: (_) async => '0',
    );
    expect(chapters, isEmpty);
  });
}
