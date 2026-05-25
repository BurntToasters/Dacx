import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/load_queue.dart';

void main() {
  test('runs tasks sequentially', () async {
    final queue = LoadQueue();
    final log = <int>[];

    final first = queue.enqueue(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      log.add(1);
    });
    final second = queue.enqueue(() async {
      log.add(2);
    });

    await Future.wait([first, second]);
    expect(log, [1, 2]);
  });

  test('continues after task failure when onError is set', () async {
    final queue = LoadQueue();
    final log = <int>[];

    final first = queue.enqueue(
      () async => throw StateError('boom'),
      onError: (_, _) {},
    );
    final second = queue.enqueue(() async {
      log.add(1);
    });

    await Future.wait([first, second]);
    expect(log, [1]);
  });
}
