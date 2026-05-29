import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/widgets/update_progress_dialog.dart';

const _info = UpdateInfo(
  version: '0.8.0-beta.2',
  url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0-beta.2',
  notes: '',
);

class _FakeSelfUpdateService extends SelfUpdateService {
  _FakeSelfUpdateService(this.handler) : super();

  final Future<SelfUpdateResult> Function(
    UpdateInfo info,
    void Function(SelfUpdateProgress)? onProgress,
  )
  handler;

  @override
  Future<SelfUpdateResult> applyUpdate(
    UpdateInfo info, {
    void Function(SelfUpdateProgress)? onProgress,
  }) {
    return handler(info, onProgress);
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('UpdateProgressDialog', () {
    testWidgets('shows download progress before a failed result', (
      tester,
    ) async {
      final result = Completer<SelfUpdateResult>();
      final service = _FakeSelfUpdateService((info, onProgress) {
        onProgress?.call(
          const SelfUpdateProgress(1024 * 1024, 2 * 1024 * 1024),
        );
        return result.future;
      });

      await tester.pumpWidget(
        _wrap(
          UpdateProgressDialog(
            info: _info,
            service: service,
            onFallbackToBrowser: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Installing Dacx 0.8.0-beta.2'), findsOneWidget);
      expect(find.text('Downloading 1.0 MB / 2.0 MB'), findsOneWidget);

      result.complete(
        const SelfUpdateResult(SelfUpdateOutcome.checksumMismatch),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update failed'), findsOneWidget);
      expect(
        find.text(
          'Downloaded file failed checksum verification. Refusing to install.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows verifying text when download reaches total size', (
      tester,
    ) async {
      final result = Completer<SelfUpdateResult>();
      final service = _FakeSelfUpdateService((info, onProgress) {
        onProgress?.call(const SelfUpdateProgress(2048, 2048));
        return result.future;
      });

      await tester.pumpWidget(
        _wrap(
          UpdateProgressDialog(
            info: _info,
            service: service,
            onFallbackToBrowser: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Verifying signature...'), findsOneWidget);

      result.complete(const SelfUpdateResult(SelfUpdateOutcome.downloadFailed));
      await tester.pumpAndSettle();
    });

    testWidgets('renders failure labels and optional diagnostic message', (
      tester,
    ) async {
      const cases = <SelfUpdateOutcome, String>{
        SelfUpdateOutcome.unsupportedPlatform:
            'Self-update is not supported on this platform.',
        SelfUpdateOutcome.missingAsset:
            'The release does not include an installer for this platform.',
        SelfUpdateOutcome.missingChecksums:
            'The release does not include a checksums file. Cannot verify download.',
        SelfUpdateOutcome.missingSignature:
            'The release does not include a signed update manifest. Cannot verify update authenticity.',
        SelfUpdateOutcome.downloadFailed: 'Download failed.',
        SelfUpdateOutcome.extractionFailed:
            'Could not extract the update package.',
        SelfUpdateOutcome.signatureInvalid:
            'Downloaded app failed code-signature verification.',
        SelfUpdateOutcome.bundleIdentifierMismatch:
            'Downloaded app has an unexpected bundle identifier. Refusing to install.',
        SelfUpdateOutcome.versionMismatch:
            'Downloaded app version does not match the selected update. Refusing to install.',
        SelfUpdateOutcome.teamIdMismatch:
            'Downloaded app is signed by an unexpected developer. Refusing to install.',
        SelfUpdateOutcome.gatekeeperRejected:
            'Self-update is not available on this build (missing signing configuration).',
        SelfUpdateOutcome.spawnFailed: 'Could not launch the installer.',
      };

      for (final entry in cases.entries) {
        final service = _FakeSelfUpdateService(
          (info, onProgress) async => SelfUpdateResult(
            entry.key,
            message: entry.key == SelfUpdateOutcome.spawnFailed
                ? 'helper missing'
                : null,
          ),
        );

        await tester.pumpWidget(
          _wrap(
            UpdateProgressDialog(
              key: ValueKey(entry.key),
              info: _info,
              service: service,
              onFallbackToBrowser: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Update failed'), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
        if (entry.key == SelfUpdateOutcome.spawnFailed) {
          expect(find.text('helper missing'), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('open release page action invokes fallback and closes dialog', (
      tester,
    ) async {
      var fallbackCalled = false;
      final service = _FakeSelfUpdateService(
        (info, onProgress) async =>
            const SelfUpdateResult(SelfUpdateOutcome.missingAsset),
      );

      await tester.pumpWidget(
        _wrap(
          UpdateProgressDialog(
            info: _info,
            service: service,
            onFallbackToBrowser: () => fallbackCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open release page'));
      await tester.pumpAndSettle();

      expect(fallbackCalled, isTrue);
      expect(find.text('Update failed'), findsNothing);
    });
  });

  group('updateActionLabel', () {
    test('matches self-update platform support', () {
      expect(
        updateActionLabel(),
        SelfUpdateService.isSupported() ? 'Install' : 'View',
      );
    });
  });

  group('UpdatePendingMarker', () {
    test('writes, reads, and clears pending update marker', () async {
      UpdatePendingMarker.readAndClear();

      await UpdatePendingMarker.write(
        targetVersion: '0.8.0-beta.2',
        channel: 'beta',
      );

      final marker = UpdatePendingMarker.readAndClear();
      expect(marker, isNotNull);
      expect(marker?['target_version'], '0.8.0-beta.2');
      expect(marker?['channel'], 'beta');
      expect(marker?['started_at_ms'], isA<int>());
      expect(UpdatePendingMarker.readAndClear(), isNull);
    });
  });
}
