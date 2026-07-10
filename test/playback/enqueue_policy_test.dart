import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/playback/enqueue_policy.dart';

void main() {
  group('EnqueuePolicy.mode', () {
    test('replaces queue when playNow is true', () {
      expect(
        EnqueuePolicy.mode(playNow: true, playlistEmpty: false),
        EnqueueMode.replaceAndPlay,
      );
    });

    test('replaces queue when playlist is empty', () {
      expect(
        EnqueuePolicy.mode(playNow: false, playlistEmpty: true),
        EnqueueMode.replaceAndPlay,
      );
    });

    test('appends when queue has items and playNow is false', () {
      expect(
        EnqueuePolicy.mode(playNow: false, playlistEmpty: false),
        EnqueueMode.append,
      );
    });
  });

  group('DropFilePolicy.action', () {
    test('returns none for zero valid paths', () {
      expect(DropFilePolicy.action(validPathCount: 0), DropFileAction.none);
      expect(DropFilePolicy.action(validPathCount: -1), DropFileAction.none);
    });

    test('loads single file when exactly one path is valid', () {
      expect(
        DropFilePolicy.action(validPathCount: 1),
        DropFileAction.loadSingle,
      );
    });

    test('enqueues with playNow when multiple paths are valid', () {
      expect(
        DropFilePolicy.action(validPathCount: 2),
        DropFileAction.enqueuePlayNow,
      );
      expect(
        DropFilePolicy.action(validPathCount: 10),
        DropFileAction.enqueuePlayNow,
      );
    });
  });
}
