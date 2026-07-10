import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/playback_controller.dart';

void main() {
  test('load generation invalidates stale opens after dispose', () {
    final controller = PlaybackController();
    final gen = controller.beginLoad();
    expect(controller.isLoadCurrent(gen), isTrue);
    controller.dispose();
    expect(controller.isLoadCurrent(gen), isFalse);
  });

  test('beginLoad increments generation', () {
    final controller = PlaybackController();
    expect(controller.beginLoad(), 1);
    expect(controller.beginLoad(), 2);
    controller.dispose();
  });

  test('new beginLoad invalidates prior generation', () {
    final controller = PlaybackController();
    final first = controller.beginLoad();
    expect(controller.isLoadCurrent(first), isTrue);
    controller.beginLoad();
    expect(controller.isLoadCurrent(first), isFalse);
    controller.dispose();
  });
}
