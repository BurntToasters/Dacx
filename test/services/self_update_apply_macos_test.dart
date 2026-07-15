import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';

UpdateInfo _macosUpdateInfo({
  List<UpdateAsset> assets = const [],
  String version = '0.10.0',
}) {
  return UpdateInfo(
    version: version,
    url: 'https://github.com/BurntToasters/Dacx/releases/tag/v$version',
    notes: '',
    assets: assets,
  );
}

String _zipHash() => 'a' * 64;

String _checksumsBody() => '${_zipHash()}  Dacx-macOS.zip\n';

List<UpdateAsset> _fullMacosAssets() {
  return [
    const UpdateAsset(
      name: 'Dacx-macOS.zip',
      downloadUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-macOS.zip',
    ),
    const UpdateAsset(
      name: 'SHA256SUMS-macOS.txt',
      downloadUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/SHA256SUMS-macOS.txt',
    ),
  ];
}

void main() {
  group('SelfUpdateService.mapMacInstallRejection', () {
    test('maps codesign errors to signatureInvalid', () {
      final result = SelfUpdateService.mapMacInstallRejection(
        'codesign: invalid signature',
      );
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
    });

    test('maps gatekeeper errors to signatureInvalid', () {
      final result = SelfUpdateService.mapMacInstallRejection(
        'gatekeeper: blocked',
      );
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
    });

    test('maps checksum errors to checksumMismatch', () {
      final result = SelfUpdateService.mapMacInstallRejection(
        'SHA256 mismatch for zip',
      );
      expect(result.outcome, SelfUpdateOutcome.checksumMismatch);
    });

    test('maps ditto errors to extractionFailed', () {
      final result = SelfUpdateService.mapMacInstallRejection(
        'ditto: could not extract',
      );
      expect(result.outcome, SelfUpdateOutcome.extractionFailed);
    });

    test('maps unknown errors to spawnFailed', () {
      final result = SelfUpdateService.mapMacInstallRejection('helper busy');
      expect(result.outcome, SelfUpdateOutcome.spawnFailed);
    });
  });

  group('SelfUpdateService.applyMacosUpdate', () {
    test('returns gatekeeperRejected when team id is empty', () async {
      final svc = SelfUpdateService(expectedTeamIdOverride: '');
      final result = await svc.applyMacosUpdate(
        _macosUpdateInfo(assets: _fullMacosAssets()),
      );
      expect(result.outcome, SelfUpdateOutcome.gatekeeperRejected);
      expect(result.message, contains('DACX_APPLE_TEAM_ID'));
    });

    test('returns missingAsset when zip asset is absent', () async {
      final svc = SelfUpdateService(expectedTeamIdOverride: 'TEAM123');
      final result = await svc.applyMacosUpdate(
        _macosUpdateInfo(
          assets: const [
            UpdateAsset(
              name: 'SHA256SUMS-macOS.txt',
              downloadUrl: 'https://github.com/x/sums',
            ),
          ],
        ),
      );
      expect(result.outcome, SelfUpdateOutcome.missingAsset);
    });

    test('returns missingChecksums when SHA256SUMS asset is absent', () async {
      final svc = SelfUpdateService(expectedTeamIdOverride: 'TEAM123');
      final result = await svc.applyMacosUpdate(
        _macosUpdateInfo(
          assets: const [
            UpdateAsset(
              name: 'Dacx-macOS.zip',
              downloadUrl: 'https://github.com/x/zip',
            ),
          ],
        ),
      );
      expect(result.outcome, SelfUpdateOutcome.missingChecksums);
    });

    test('returns downloadFailed when checksum fetch throws', () async {
      final svc = SelfUpdateService(
        expectedTeamIdOverride: 'TEAM123',
        fetchText: (_) async => throw StateError('network down'),
      );
      final result = await svc.applyMacosUpdate(
        _macosUpdateInfo(assets: _fullMacosAssets()),
      );
      expect(result.outcome, SelfUpdateOutcome.downloadFailed);
      expect(result.message, contains('network down'));
    });

    test(
      'returns checksumMismatch when asset missing from sums file',
      () async {
        final svc = SelfUpdateService(
          expectedTeamIdOverride: 'TEAM123',
          fetchText: (_) async => 'abc123  Other-Asset.zip\n',
        );
        final result = await svc.applyMacosUpdate(
          _macosUpdateInfo(assets: _fullMacosAssets()),
        );
        expect(result.outcome, SelfUpdateOutcome.checksumMismatch);
        expect(result.message, contains('No entry'));
      },
    );

    test('returns spawned when XPC helper accepts install', () async {
      final svc = SelfUpdateService(
        expectedTeamIdOverride: 'TEAM123',
        fetchText: (_) async => _checksumsBody(),
        macUpdateInstall:
            ({
              required zipUrl,
              required checksumHex,
              required installedAppPath,
              required expectedTeamId,
              required expectedVersion,
              required relaunch,
            }) async {
              expect(zipUrl, contains('Dacx-macOS.zip'));
              expect(checksumHex, _zipHash());
              expect(expectedTeamId, 'TEAM123');
              expect(expectedVersion, '0.10.0');
              expect(relaunch, isTrue);
              return {'accepted': true};
            },
      );

      final result = await svc.applyMacosUpdate(
        _macosUpdateInfo(assets: _fullMacosAssets()),
      );
      expect(result.outcome, SelfUpdateOutcome.spawned);
    });

    test(
      'returns signatureInvalid when helper rejects with codesign error',
      () async {
        final svc = SelfUpdateService(
          expectedTeamIdOverride: 'TEAM123',
          fetchText: (_) async => _checksumsBody(),
          macUpdateInstall:
              ({
                required zipUrl,
                required checksumHex,
                required installedAppPath,
                required expectedTeamId,
                required expectedVersion,
                required relaunch,
              }) async {
                return {'accepted': false, 'error': 'codesign: bad sig'};
              },
        );

        final result = await svc.applyMacosUpdate(
          _macosUpdateInfo(assets: _fullMacosAssets()),
        );
        expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      },
    );

    test('returns spawnFailed on PlatformException from helper', () async {
      final svc = SelfUpdateService(
        expectedTeamIdOverride: 'TEAM123',
        fetchText: (_) async => _checksumsBody(),
        macUpdateInstall:
            ({
              required zipUrl,
              required checksumHex,
              required installedAppPath,
              required expectedTeamId,
              required expectedVersion,
              required relaunch,
            }) async {
              throw PlatformException(
                code: 'channel_error',
                message: 'not found',
              );
            },
      );

      final result = await svc.applyMacosUpdate(
        _macosUpdateInfo(assets: _fullMacosAssets()),
      );
      expect(result.outcome, SelfUpdateOutcome.spawnFailed);
      expect(result.message, contains('not found'));
    });
  });
}
