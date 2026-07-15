import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/services/windows_process_ffi.dart';

UpdateInfo _windowsUpdateInfo({
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

List<UpdateAsset> _fullWindowsAssets({required String msiHash}) {
  return [
    const UpdateAsset(
      name: 'Dacx-Windows-x64.msi',
      downloadUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-Windows-x64.msi',
    ),
    const UpdateAsset(
      name: 'SHA256SUMS-Windows-x64.txt',
      downloadUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/SHA256SUMS-Windows-x64.txt',
    ),
    const UpdateAsset(
      name: 'Dacx-update-manifest-Windows-x64.json',
      downloadUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-update-manifest-Windows-x64.json',
    ),
    const UpdateAsset(
      name: 'Dacx-update-manifest-Windows-x64.json.sig',
      downloadUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-update-manifest-Windows-x64.json.sig',
    ),
  ];
}

String _sha256Hex(List<int> bytes) {
  return sha256.convert(bytes).toString();
}

void main() {
  group('SelfUpdateService.applyWindowsUpdate', () {
    setUp(() {
      SelfUpdateService.windowsUpdateHelperPathOverride =
          r'C:\Program Files\Dacx\dacx-update-helper.exe';
    });
    tearDown(() {
      SelfUpdateService.windowsUpdateHelperPathOverride = null;
    });

    test('returns missingAsset when MSI asset is absent', () async {
      final svc = SelfUpdateService();
      final result = await svc.applyWindowsUpdate(
        _windowsUpdateInfo(
          assets: const [
            UpdateAsset(
              name: 'SHA256SUMS-Windows-x64.txt',
              downloadUrl: 'https://github.com/x/sums',
            ),
          ],
        ),
      );
      expect(result.outcome, SelfUpdateOutcome.missingAsset);
    });

    test('returns missingChecksums when SHA256SUMS asset is absent', () async {
      final svc = SelfUpdateService();
      final result = await svc.applyWindowsUpdate(
        _windowsUpdateInfo(
          assets: const [
            UpdateAsset(
              name: 'Dacx-Windows-x64.msi',
              downloadUrl: 'https://github.com/x/msi',
            ),
          ],
        ),
      );
      expect(result.outcome, SelfUpdateOutcome.missingChecksums);
    });

    test(
      'returns missingSignature when manifest signature asset is absent',
      () async {
        final svc = SelfUpdateService();
        final result = await svc.applyWindowsUpdate(
          _windowsUpdateInfo(
            assets: const [
              UpdateAsset(
                name: 'Dacx-Windows-x64.msi',
                downloadUrl: 'https://github.com/x/msi',
              ),
              UpdateAsset(
                name: 'SHA256SUMS-Windows-x64.txt',
                downloadUrl: 'https://github.com/x/sums',
              ),
              UpdateAsset(
                name: 'Dacx-update-manifest-Windows-x64.json',
                downloadUrl: 'https://github.com/x/manifest',
              ),
            ],
          ),
        );
        expect(result.outcome, SelfUpdateOutcome.missingSignature);
      },
    );

    test('returns downloadFailed when download hook throws', () async {
      final svc = SelfUpdateService(
        downloadTo: (_, _, {onProgress}) async {
          throw StateError('network down');
        },
      );
      final result = await svc.applyWindowsUpdate(
        _windowsUpdateInfo(assets: _fullWindowsAssets(msiHash: 'deadbeef')),
      );
      expect(result.outcome, SelfUpdateOutcome.downloadFailed);
      expect(result.message, contains('network down'));
    });

    test(
      'returns signatureInvalid when manifest signature is invalid',
      () async {
        final msiBytes = utf8.encode('fake-msi-payload');
        final svc = SelfUpdateService(
          downloadTo: (url, outFile, {onProgress}) async {
            await outFile.writeAsBytes(msiBytes);
          },
          fetchText: (url) async {
            if (url.contains('SHA256SUMS')) {
              return '${_sha256Hex(msiBytes)}  Dacx-Windows-x64.msi\n';
            }
            if (url.contains('.sig')) {
              return base64Encode([1, 2, 3]);
            }
            return '';
          },
          fetchBytes: (url) async => utf8.encode('{"version":"0.10.0"}'),
        );

        final result = await svc.applyWindowsUpdate(
          _windowsUpdateInfo(
            assets: _fullWindowsAssets(msiHash: _sha256Hex(msiBytes)),
          ),
        );
        expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      },
    );

    test(
      'returns checksumMismatch when SHA256SUMS hash does not match MSI',
      () async {
        final msiBytes = utf8.encode('dacx-msi');
        final manifestBytes = utf8.encode(
          jsonEncode({
            'version': '0.10.0',
            'app': 'dacx',
            'platform': 'windows-x64',
            'released_at': DateTime.now().toUtc().toIso8601String(),
            'assets': {'Dacx-Windows-x64.msi': _sha256Hex(msiBytes)},
          }),
        );

        final svc = SelfUpdateService(
          downloadTo: (url, outFile, {onProgress}) async {
            await outFile.writeAsBytes(msiBytes);
          },
          fetchText: (url) async {
            if (url.contains('SHA256SUMS')) {
              return '${'a' * 64}  Dacx-Windows-x64.msi\n';
            }
            if (url.contains('.sig')) {
              return base64Encode([9, 9, 9]);
            }
            return '';
          },
          fetchBytes: (url) async => manifestBytes,
          validateWindowsManifest:
              ({
                required manifestBytes,
                required signatureBytes,
                required version,
                required assetName,
              }) async {
                return const SelfUpdateResult(SelfUpdateOutcome.spawned);
              },
        );

        final result = await svc.applyWindowsUpdate(
          _windowsUpdateInfo(
            assets: _fullWindowsAssets(msiHash: _sha256Hex(msiBytes)),
          ),
        );
        expect(result.outcome, SelfUpdateOutcome.checksumMismatch);
        expect(result.message, contains('expected'));
      },
    );

    test(
      'returns spawned when downloads verify and watchdog spawn succeeds',
      () async {
        final msiBytes = Uint8List.fromList(utf8.encode('verified-msi'));
        final hash = _sha256Hex(msiBytes);
        final manifestBytes = utf8.encode(
          jsonEncode({
            'version': '0.10.0',
            'app': 'dacx',
            'platform': 'windows-x64',
            'released_at': DateTime.now().toUtc().toIso8601String(),
            'assets': {'Dacx-Windows-x64.msi': hash},
          }),
        );

        final svc = SelfUpdateService(
          downloadTo: (url, outFile, {onProgress}) async {
            await outFile.writeAsBytes(msiBytes);
            onProgress?.call(
              SelfUpdateProgress(msiBytes.length, msiBytes.length),
            );
          },
          fetchText: (url) async {
            if (url.contains('SHA256SUMS')) {
              return '$hash  Dacx-Windows-x64.msi\n';
            }
            if (url.contains('.sig')) {
              return base64Encode([1, 2, 3]);
            }
            return '';
          },
          fetchBytes: (url) async => manifestBytes,
          validateWindowsManifest:
              ({
                required manifestBytes,
                required signatureBytes,
                required version,
                required assetName,
              }) async {
                return const SelfUpdateResult(SelfUpdateOutcome.spawned);
              },
          windowsSpawn: (_, {applicationName}) async {
            return const WindowsSpawnResult(launched: true, exitCode: 0);
          },
        );

        final result = await svc.applyWindowsUpdate(
          _windowsUpdateInfo(assets: _fullWindowsAssets(msiHash: hash)),
          onProgress: (progress) {
            expect(progress.fraction, 1.0);
          },
        );
        expect(result.outcome, SelfUpdateOutcome.spawned);
      },
    );

    test('rejects an unsigned MSI when signer pinning is configured', () async {
      final msiBytes = utf8.encode('verified-msi');
      final hash = _sha256Hex(msiBytes);
      final manifestBytes = utf8.encode(
        jsonEncode({
          'version': '0.10.0',
          'app': 'dacx',
          'platform': 'windows-x64',
          'released_at': DateTime.now().toUtc().toIso8601String(),
          'assets': {'Dacx-Windows-x64.msi': hash},
        }),
      );
      final svc = SelfUpdateService(
        expectedWindowsSignerThumbprintOverride: 'A1B2C3',
        downloadTo: (url, outFile, {onProgress}) async {
          await outFile.writeAsBytes(msiBytes);
        },
        fetchText: (url) async {
          if (url.contains('SHA256SUMS')) {
            return '$hash  Dacx-Windows-x64.msi\n';
          }
          if (url.contains('.sig')) return base64Encode([1, 2, 3]);
          return '';
        },
        fetchBytes: (url) async => manifestBytes,
        validateWindowsManifest:
            ({
              required manifestBytes,
              required signatureBytes,
              required version,
              required assetName,
            }) async => const SelfUpdateResult(SelfUpdateOutcome.spawned),
        processRun: (_, _) async =>
            ProcessResult(0, 0, 'NotSigned|A1B2C3|unsigned', ''),
      );

      final result = await svc.applyWindowsUpdate(
        _windowsUpdateInfo(assets: _fullWindowsAssets(msiHash: hash)),
      );

      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      expect(result.message, contains('unsigned'));
    });

    test('returns spawnFailed when update helper is missing', () async {
      SelfUpdateService.windowsUpdateHelperPathOverride = '';
      final msiBytes = utf8.encode('verified-msi');
      final hash = _sha256Hex(msiBytes);
      final manifestBytes = utf8.encode(
        jsonEncode({
          'version': '0.10.0',
          'app': 'dacx',
          'platform': 'windows-x64',
          'released_at': DateTime.now().toUtc().toIso8601String(),
          'assets': {'Dacx-Windows-x64.msi': hash},
        }),
      );

      final svc = SelfUpdateService(
        downloadTo: (url, outFile, {onProgress}) async {
          await outFile.writeAsBytes(msiBytes);
        },
        fetchText: (url) async {
          if (url.contains('SHA256SUMS')) {
            return '$hash  Dacx-Windows-x64.msi\n';
          }
          if (url.contains('.sig')) return base64Encode([1, 2, 3]);
          return '';
        },
        fetchBytes: (url) async => manifestBytes,
        validateWindowsManifest:
            ({
              required manifestBytes,
              required signatureBytes,
              required version,
              required assetName,
            }) async => const SelfUpdateResult(SelfUpdateOutcome.spawned),
      );

      final result = await svc.applyWindowsUpdate(
        _windowsUpdateInfo(assets: _fullWindowsAssets(msiHash: hash)),
      );
      expect(result.outcome, SelfUpdateOutcome.spawnFailed);
      expect(result.message, contains('dacx-update-helper.exe'));
    });

    test('returns spawnFailed when watchdog spawn fails', () async {
      final msiBytes = utf8.encode('verified-msi');
      final hash = _sha256Hex(msiBytes);
      final manifestBytes = utf8.encode(
        jsonEncode({
          'version': '0.10.0',
          'app': 'dacx',
          'platform': 'windows-x64',
          'released_at': DateTime.now().toUtc().toIso8601String(),
          'assets': {'Dacx-Windows-x64.msi': hash},
        }),
      );

      final svc = SelfUpdateService(
        downloadTo: (url, outFile, {onProgress}) async {
          await outFile.writeAsBytes(msiBytes);
        },
        fetchText: (url) async {
          if (url.contains('SHA256SUMS')) {
            return '$hash  Dacx-Windows-x64.msi\n';
          }
          if (url.contains('.sig')) {
            return base64Encode([1, 2, 3]);
          }
          return '';
        },
        fetchBytes: (url) async => manifestBytes,
        validateWindowsManifest:
            ({
              required manifestBytes,
              required signatureBytes,
              required version,
              required assetName,
            }) async {
              return const SelfUpdateResult(SelfUpdateOutcome.spawned);
            },
        windowsSpawn: (_, {applicationName}) async {
          return const WindowsSpawnResult(
            launched: false,
            error: 'CreateProcessW failed',
          );
        },
      );

      final result = await svc.applyWindowsUpdate(
        _windowsUpdateInfo(assets: _fullWindowsAssets(msiHash: hash)),
      );
      expect(result.outcome, SelfUpdateOutcome.spawnFailed);
      expect(result.message, contains('CreateProcessW'));
    });
  });
}
