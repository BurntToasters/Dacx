import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/chapter_refresh_gate.dart';

void main() {
  test('skips refresh when path and count unchanged', () {
    final gate = ChapterRefreshGate();
    expect(
      gate.shouldRefresh(path: '/a.mp4', chapterCount: 3),
      isTrue,
    );
    expect(
      gate.shouldRefresh(path: '/a.mp4', chapterCount: 3),
      isFalse,
    );
    gate.invalidate();
    expect(
      gate.shouldRefresh(path: '/a.mp4', chapterCount: 3),
      isTrue,
    );
  });

  test('refresh when count changes for same path', () {
    final gate = ChapterRefreshGate();
    gate.shouldRefresh(path: '/a.mp4', chapterCount: 2);
    expect(
      gate.shouldRefresh(path: '/a.mp4', chapterCount: 5),
      isTrue,
    );
  });
}
