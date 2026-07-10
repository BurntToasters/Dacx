import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/seek_preview_service.dart';

void main() {
  group('SeekPreviewService gating', () {
    test('disabled by default', () {
      final svc = SeekPreviewService();
      expect(svc.enabled, isFalse);
      expect(svc.isReady, isFalse);
      expect(svc.loadedPath, isNull);
    });

    test('requestPreview returns null when disabled', () async {
      final svc = SeekPreviewService();
      final bytes = await svc.requestPreview(const Duration(seconds: 5));
      expect(bytes, isNull);
    });

    test('setSource is a no-op when disabled and clears loadedPath', () async {
      final svc = SeekPreviewService();
      await svc.setSource('/some/path.mp4');
      expect(svc.loadedPath, isNull);
      expect(svc.isReady, isFalse);
    });

    test('setEnabled(false) twice is idempotent', () async {
      final svc = SeekPreviewService();
      await svc.setEnabled(false);
      await svc.setEnabled(false);
      expect(svc.enabled, isFalse);
    });

    test('dispose tolerates never-enabled instance', () async {
      final svc = SeekPreviewService();
      await svc.dispose();
      final bytes = await svc.requestPreview(const Duration(seconds: 1));
      expect(bytes, isNull);
    });

    test('dispose tolerates double-call', () async {
      final svc = SeekPreviewService();
      await svc.dispose();
      await svc.dispose();
    });

    test('setEnabled(true) does not eagerly create a player', () async {
      final svc = SeekPreviewService();
      await svc.setEnabled(true);
      addTearDown(svc.dispose);
      expect(svc.enabled, isTrue);
      // No source loaded yet, so still not ready.
      expect(svc.isReady, isFalse);
      expect(svc.loadedPath, isNull);
    });

    test('setSource("") clears state when enabled', () async {
      final svc = SeekPreviewService();
      await svc.setEnabled(true);
      addTearDown(svc.dispose);
      await svc.setSource('   ');
      expect(svc.loadedPath, isNull);
      expect(svc.isReady, isFalse);
    });

    test(
      'setEnabled(false) after setEnabled(true) resets enabled flag',
      () async {
        final svc = SeekPreviewService();
        await svc.setEnabled(true);
        expect(svc.enabled, isTrue);
        await svc.setEnabled(false);
        expect(svc.enabled, isFalse);
        expect(svc.isReady, isFalse);
        await svc.dispose();
      },
    );

    test(
      'setEnabled(true) after setEnabled(false) restores enabled flag',
      () async {
        final svc = SeekPreviewService();
        await svc.setEnabled(true);
        await svc.setEnabled(false);
        await svc.setEnabled(true);
        expect(svc.enabled, isTrue);
        await svc.dispose();
      },
    );

    test('after dispose, setEnabled is a no-op', () async {
      final svc = SeekPreviewService();
      await svc.dispose();
      await svc.setEnabled(true);
      expect(svc.enabled, isFalse);
    });

    test('after dispose, setSource is a no-op', () async {
      final svc = SeekPreviewService();
      await svc.dispose();
      await svc.setSource('/some/path.mp4');
      expect(svc.loadedPath, isNull);
      expect(svc.isReady, isFalse);
    });

    test('setSource(null) triggers teardown when enabled', () async {
      final svc = SeekPreviewService();
      await svc.setEnabled(true);
      addTearDown(svc.dispose);
      await svc.setSource(null);
      expect(svc.loadedPath, isNull);
      expect(svc.isReady, isFalse);
    });

    test('requestPreview returns null after dispose', () async {
      final svc = SeekPreviewService();
      await svc.setEnabled(true);
      await svc.dispose();
      final bytes = await svc.requestPreview(const Duration(seconds: 3));
      expect(bytes, isNull);
    });

    test(
      'multiple concurrent requestPreview calls when not ready return null',
      () async {
        final svc = SeekPreviewService();
        await svc.setEnabled(true);
        addTearDown(svc.dispose);
        final results = await Future.wait([
          svc.requestPreview(const Duration(seconds: 1)),
          svc.requestPreview(const Duration(seconds: 2)),
          svc.requestPreview(const Duration(seconds: 3)),
        ]);
        expect(results, everyElement(isNull));
      },
    );

    test(
      'requestPreview returns null when enabled but no source loaded',
      () async {
        final svc = SeekPreviewService();
        await svc.setEnabled(true);
        addTearDown(svc.dispose);
        final bytes = await svc.requestPreview(
          const Duration(milliseconds: 2500),
        );
        expect(bytes, isNull);
      },
    );
  });
}
