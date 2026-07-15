import 'dart:convert';
import 'dart:io';

import 'package:cryptography_plus/cryptography_plus.dart' as cryptography;
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';

Future<({String publicKeyBase64, List<int> signature, List<int> manifestBytes})>
_signedManifest({
  required String version,
  required String assetName,
  required String assetHash,
  String app = 'dacx',
  String platform = 'windows-x64',
  String? releasedAt,
}) async {
  final manifest = jsonEncode({
    'version': version,
    'app': app,
    'platform': platform,
    'released_at': releasedAt ?? DateTime.now().toUtc().toIso8601String(),
    'assets': {assetName: assetHash},
  });
  final manifestBytes = utf8.encode(manifest);
  final algorithm = cryptography.Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final signature = await algorithm.sign(manifestBytes, keyPair: keyPair);
  return (
    publicKeyBase64: base64Encode(publicKey.bytes),
    signature: signature.bytes,
    manifestBytes: manifestBytes,
  );
}

String _msiHash() => 'b' * 64;

void main() {
  group('SelfUpdateService.validateWindowsManifestForTesting', () {
    test(
      'returns signatureInvalid when public key override is empty',
      () async {
        final svc = SelfUpdateService(windowsManifestPublicKeyOverride: '');
        final result = await svc.validateWindowsManifestForTesting(
          manifestBytes: utf8.encode('{}'),
          signatureBytes: const [1, 2, 3],
          version: '0.10.0',
          assetName: 'Dacx-Windows-x64.msi',
        );
        expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
        expect(result.message, contains('public key'));
      },
    );

    test('returns signatureInvalid for tampered manifest bytes', () async {
      final signed = await _signedManifest(
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
        assetHash: _msiHash(),
      );
      final svc = SelfUpdateService(
        windowsManifestPublicKeyOverride: signed.publicKeyBase64,
      );
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: utf8.encode('{"version":"0.10.0"}'),
        signatureBytes: signed.signature,
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
      );
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
    });

    test('returns versionMismatch when manifest version differs', () async {
      final signed = await _signedManifest(
        version: '0.9.0',
        assetName: 'Dacx-Windows-x64.msi',
        assetHash: _msiHash(),
      );
      final svc = SelfUpdateService(
        windowsManifestPublicKeyOverride: signed.publicKeyBase64,
      );
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: signed.manifestBytes,
        signatureBytes: signed.signature,
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
      );
      expect(result.outcome, SelfUpdateOutcome.versionMismatch);
    });

    test('returns signatureInvalid when app field is wrong', () async {
      final signed = await _signedManifest(
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
        assetHash: _msiHash(),
        app: 'other',
      );
      final svc = SelfUpdateService(
        windowsManifestPublicKeyOverride: signed.publicKeyBase64,
      );
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: signed.manifestBytes,
        signatureBytes: signed.signature,
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
      );
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      expect(result.message, contains('app field'));
    });

    test('returns signatureInvalid when platform field is wrong', () async {
      final signed = await _signedManifest(
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
        assetHash: _msiHash(),
        platform: 'linux-amd64',
      );
      final svc = SelfUpdateService(
        windowsManifestPublicKeyOverride: signed.publicKeyBase64,
      );
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: signed.manifestBytes,
        signatureBytes: signed.signature,
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
      );
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      expect(result.message, contains('platform field'));
    });

    test('returns signatureInvalid when released_at is out of range', () async {
      final signed = await _signedManifest(
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
        assetHash: _msiHash(),
        releasedAt: '1999-01-01T00:00:00Z',
      );
      final svc = SelfUpdateService(
        windowsManifestPublicKeyOverride: signed.publicKeyBase64,
      );
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: signed.manifestBytes,
        signatureBytes: signed.signature,
        version: '0.10.0',
        assetName: 'Dacx-Windows-x64.msi',
      );
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      expect(result.message, contains('released_at'));
    });

    test(
      'returns checksumMismatch when MSI asset is missing from manifest',
      () async {
        final signed = await _signedManifest(
          version: '0.10.0',
          assetName: 'Other.msi',
          assetHash: _msiHash(),
        );
        final svc = SelfUpdateService(
          windowsManifestPublicKeyOverride: signed.publicKeyBase64,
        );
        final result = await svc.validateWindowsManifestForTesting(
          manifestBytes: signed.manifestBytes,
          signatureBytes: signed.signature,
          version: '0.10.0',
          assetName: 'Dacx-Windows-x64.msi',
        );
        expect(result.outcome, SelfUpdateOutcome.checksumMismatch);
      },
    );

    test('returns spawned for a valid signed manifest', () async {
      const assetName = 'Dacx-Windows-x64.msi';
      final signed = await _signedManifest(
        version: '0.10.0',
        assetName: assetName,
        assetHash: _msiHash(),
      );
      final svc = SelfUpdateService(
        windowsManifestPublicKeyOverride: signed.publicKeyBase64,
      );
      final result = await svc.validateWindowsManifestForTesting(
        manifestBytes: signed.manifestBytes,
        signatureBytes: signed.signature,
        version: '0.10.0',
        assetName: assetName,
      );
      expect(result.outcome, SelfUpdateOutcome.spawned);
    });
  });

  group('SelfUpdateService.validateWindowsInstallerSignatureForTesting', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dacx-msi-sig-');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'returns signatureInvalid when thumbprint override is empty',
      () async {
        final msi = File('${tempDir.path}/test.msi')..writeAsStringSync('x');
        final svc = SelfUpdateService(
          expectedWindowsSignerThumbprintOverride: '',
        );
        final result = await svc.validateWindowsInstallerSignatureForTesting(
          msi,
        );
        expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
        expect(result.message, contains('THUMBPRINT'));
      },
    );

    test(
      'returns signatureInvalid when Authenticode status is not Valid',
      () async {
        final msi = File('${tempDir.path}/bad.msi')..writeAsStringSync('x');
        final svc = SelfUpdateService(
          expectedWindowsSignerThumbprintOverride: 'ABCD',
          processRun: (_, _) async {
            return ProcessResult(0, 0, 'NotSigned|ABCD|unsigned', '');
          },
        );
        final result = await svc.validateWindowsInstallerSignatureForTesting(
          msi,
        );
        expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
        expect(result.message, contains('unsigned'));
      },
    );

    test('returns signatureInvalid when thumbprint does not match', () async {
      final msi = File('${tempDir.path}/msi.msi')..writeAsStringSync('x');
      final svc = SelfUpdateService(
        expectedWindowsSignerThumbprintOverride: 'AABBCCDD',
        processRun: (_, _) async {
          return ProcessResult(0, 0, 'Valid|11223344|ok', '');
        },
      );
      final result = await svc.validateWindowsInstallerSignatureForTesting(msi);
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      expect(result.message, contains('AABBCCDD'));
      expect(result.message, contains('11223344'));
    });

    test(
      'returns spawned when Authenticode status and thumbprint match',
      () async {
        final msi = File('${tempDir.path}/good.msi')..writeAsStringSync('x');
        final svc = SelfUpdateService(
          expectedWindowsSignerThumbprintOverride: 'A1B2C3',
          processRun: (_, _) async {
            return ProcessResult(0, 0, 'Valid|A1B2C3|ok', '');
          },
        );
        final result = await svc.validateWindowsInstallerSignatureForTesting(
          msi,
        );
        expect(result.outcome, SelfUpdateOutcome.spawned);
      },
    );

    test('returns spawned when Artifact Signing publisher matches', () async {
      final msi = File('${tempDir.path}/publisher.msi')..writeAsStringSync('x');
      List<String>? invokedArguments;
      final svc = SelfUpdateService(
        expectedWindowsSignerPublisherOverride: 'BurntToasters LLC',
        processRun: (_, arguments) async {
          invokedArguments = arguments;
          return ProcessResult(
            0,
            0,
            'Valid|ROTATINGTHUMB|publisher:burnttoasters llc|ok',
            '',
          );
        },
      );
      final result = await svc.validateWindowsInstallerSignatureForTesting(msi);
      expect(result.outcome, SelfUpdateOutcome.spawned);
      expect(
        invokedArguments?.join(' '),
        contains(
          r'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1',
        ),
      );
    });

    test('returns signatureInvalid when PowerShell exits non-zero', () async {
      final msi = File('${tempDir.path}/fail.msi')..writeAsStringSync('x');
      final svc = SelfUpdateService(
        expectedWindowsSignerThumbprintOverride: 'A1B2C3',
        processRun: (_, _) async {
          return ProcessResult(0, 1, '', 'access denied');
        },
      );
      final result = await svc.validateWindowsInstallerSignatureForTesting(msi);
      expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
      expect(result.message, contains('access denied'));
    });
  });
}
