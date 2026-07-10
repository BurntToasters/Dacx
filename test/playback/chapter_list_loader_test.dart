import 'package:dacx/playback/chapter_list_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChapterListLoader', () {
    test('loads chapters from property reader', () async {
      final properties = <String, String?>{
        'chapter-list/count': '3',
        'chapter-list/0/title': 'Intro',
        'chapter-list/0/time': '0.0',
        'chapter-list/1/title': 'Verse 1',
        'chapter-list/1/time': '30.5',
        'chapter-list/2/title': 'Chorus',
        'chapter-list/2/time': '65.123',
      };

      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => properties[name],
      );

      expect(chapters.length, 3);
      expect(chapters[0].index, 0);
      expect(chapters[0].title, 'Intro');
      expect(chapters[0].time, Duration.zero);
      expect(chapters[1].index, 1);
      expect(chapters[1].title, 'Verse 1');
      expect(chapters[1].time, const Duration(milliseconds: 30500));
      expect(chapters[2].index, 2);
      expect(chapters[2].title, 'Chorus');
      expect(chapters[2].time, const Duration(milliseconds: 65123));
    });

    test('uses expectedCount instead of reading count property', () async {
      final properties = <String, String?>{
        'chapter-list/0/title': 'Only',
        'chapter-list/0/time': '0',
      };

      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => properties[name],
        expectedCount: 1,
      );

      expect(chapters.length, 1);
      expect(chapters[0].title, 'Only');
    });

    test('uses fallback title when title is null or empty', () async {
      final properties = <String, String?>{
        'chapter-list/count': '2',
        'chapter-list/0/title': null,
        'chapter-list/0/time': '0',
        'chapter-list/1/title': '',
        'chapter-list/1/time': '10',
      };

      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => properties[name],
      );

      expect(chapters[0].title, 'Chapter 1');
      expect(chapters[1].title, 'Chapter 2');
    });

    test('custom fallbackTitle function is used', () async {
      final properties = <String, String?>{
        'chapter-list/count': '1',
        'chapter-list/0/title': null,
        'chapter-list/0/time': '0',
      };

      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => properties[name],
        fallbackTitle: (i) => 'Part ${i + 1}',
      );

      expect(chapters[0].title, 'Part 1');
    });

    test('returns empty list when count is 0', () async {
      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => '0',
      );
      expect(chapters, isEmpty);
    });

    test('returns empty list when count is null', () async {
      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => null,
      );
      expect(chapters, isEmpty);
    });

    test('handles non-numeric time gracefully', () async {
      final properties = <String, String?>{
        'chapter-list/count': '1',
        'chapter-list/0/title': 'Bad Time',
        'chapter-list/0/time': 'not-a-number',
      };

      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => properties[name],
      );

      expect(chapters[0].time, Duration.zero);
    });

    test('negative count returns empty list', () async {
      final chapters = await ChapterListLoader.load(
        readProperty: (name) async => '-1',
      );
      expect(chapters, isEmpty);
    });
  });
}
