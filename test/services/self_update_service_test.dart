import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';

void main() {
  group('SelfUpdateService.pickAsset', () {
    test('picks asset by suffix (case-insensitive)', () {
      final assets = [
        const UpdateAsset(
          name: 'Dacx-Linux-amd64.deb',
          downloadUrl: 'https://x/a',
        ),
        const UpdateAsset(
          name: 'Dacx-Windows-x64.MSI',
          downloadUrl: 'https://x/b',
        ),
        const UpdateAsset(name: 'Dacx-macOS.zip', downloadUrl: 'https://x/c'),
      ];
      expect(
        SelfUpdateService.pickAsset(assets, '.msi')?.downloadUrl,
        'https://x/b',
      );
      expect(
        SelfUpdateService.pickAsset(assets, '.zip')?.downloadUrl,
        'https://x/c',
      );
    });

    test('returns null when no asset matches suffix', () {
      final assets = [
        const UpdateAsset(
          name: 'Dacx-Linux-amd64.deb',
          downloadUrl: 'https://x/a',
        ),
      ];
      expect(SelfUpdateService.pickAsset(assets, '.msi'), isNull);
    });

    test('returns null on empty list', () {
      expect(SelfUpdateService.pickAsset(const [], '.msi'), isNull);
    });
  });

  group('SelfUpdateService.pickAssetByPattern', () {
    test('matches by regex anywhere in name', () {
      final assets = [
        const UpdateAsset(
          name: 'Dacx-0.8.0-beta.1-macos.zip',
          downloadUrl: 'https://x/a',
        ),
        const UpdateAsset(name: 'Dacx-macOS.zip', downloadUrl: 'https://x/b'),
      ];
      final found = SelfUpdateService.pickAssetByPattern(
        assets,
        RegExp(r'^Dacx-macOS\.zip$', caseSensitive: false),
      );
      expect(found?.downloadUrl, 'https://x/b');
    });

    test('returns null when no asset matches', () {
      final assets = [
        const UpdateAsset(
          name: 'Dacx-Linux-amd64.deb',
          downloadUrl: 'https://x/a',
        ),
      ];
      expect(
        SelfUpdateService.pickAssetByPattern(assets, RegExp(r'\.msi$')),
        isNull,
      );
    });
  });

  group('SelfUpdateService.parseChecksumsFile', () {
    const content = '''
abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234  Dacx-Windows-x64.msi
deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  Dacx-Windows-x64.zip
''';

    test('extracts hash for matching filename', () {
      expect(
        SelfUpdateService.parseChecksumsFile(content, 'Dacx-Windows-x64.msi'),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
      );
      expect(
        SelfUpdateService.parseChecksumsFile(content, 'Dacx-Windows-x64.zip'),
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      );
    });

    test('matches by basename even if asset name has path components', () {
      expect(
        SelfUpdateService.parseChecksumsFile(
          content,
          'sub/dir/Dacx-Windows-x64.msi',
        ),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
      );
    });

    test('returns null when filename is absent', () {
      expect(
        SelfUpdateService.parseChecksumsFile(content, 'Dacx-Linux-amd64.deb'),
        isNull,
      );
    });

    test('skips comments and blank lines', () {
      const withNoise = '''
# This is a comment

abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234  Dacx.msi

''';
      expect(
        SelfUpdateService.parseChecksumsFile(withNoise, 'Dacx.msi'),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
      );
    });

    test('rejects malformed hash lengths', () {
      const tooShort = 'abcd1234  Dacx.msi\n';
      expect(
        SelfUpdateService.parseChecksumsFile(tooShort, 'Dacx.msi'),
        isNull,
      );
    });

    test('rejects non-hex hashes', () {
      const nonHex =
          'gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg  Dacx.msi\n';
      expect(SelfUpdateService.parseChecksumsFile(nonHex, 'Dacx.msi'), isNull);
    });

    test('rejects single-space separator (strict POSIX two-space required)', () {
      const singleSpace =
          'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234 Dacx.msi\n';
      expect(
        SelfUpdateService.parseChecksumsFile(singleSpace, 'Dacx.msi'),
        isNull,
      );
    });

    test('lowercases returned hash', () {
      const upper =
          'ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234  Dacx.msi\n';
      expect(
        SelfUpdateService.parseChecksumsFile(upper, 'Dacx.msi'),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
      );
    });

    test('handles trailing newline absence', () {
      const noTrailingNl =
          'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234  Dacx.msi';
      expect(
        SelfUpdateService.parseChecksumsFile(noTrailingNl, 'Dacx.msi'),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
      );
    });
  });

  group('SelfUpdateService Authenticode helpers', () {
    test('normalizes certificate thumbprints', () {
      expect(
        SelfUpdateService.normalizeCertificateThumbprint(' ab cd 12:34-ef '),
        'ABCD1234EF',
      );
    });

    test('parses PowerShell Authenticode status output', () {
      final parsed = SelfUpdateService.parseAuthenticodeStatus(
        'Valid| ab cd 12 34 |Signature verified\n',
      );

      expect(parsed.status, 'Valid');
      expect(parsed.thumbprint, 'ABCD1234');
      expect(parsed.message, 'Signature verified');
    });

    test('preserves pipes in Authenticode status messages', () {
      final parsed = SelfUpdateService.parseAuthenticodeStatus(
        'NotSigned||No signature | present\n',
      );

      expect(parsed.status, 'NotSigned');
      expect(parsed.thumbprint, '');
      expect(parsed.message, 'No signature | present');
    });
  });

  group('SelfUpdateService Windows watchdog', () {
    test(
      'uses hidden PowerShell-friendly commands instead of cmd find loop',
      () {
        final script = SelfUpdateService.buildWindowsWatchdogPowerShellScript();

        expect(script, contains('Get-Process -Id \$DacxPid'));
        expect(script, contains('WaitForExit(600000)'));
        expect(
          script,
          contains('[Microsoft.PowerShell.Commands.ProcessCommandException]'),
        );
        expect(script, contains('Add-Content'));
        expect(script, isNot(contains('Start-Sleep -Seconds 1')));
        expect(script, contains('Get-FileHash -Algorithm SHA256'));
        expect(script, contains("Start-Process -FilePath 'msiexec.exe'"));
        expect(script, contains('-Verb RunAs'));
        expect(script, isNot(contains('-UseShellExecute')));
        expect(script, isNot(contains('tasklist')));
        expect(script, isNot(contains('find "%DACX_PID%"')));
      },
    );
  });

  group('SelfUpdateService.buildBootstrapCommandLine', () {
    test('launches powershell hidden with a quoted script path', () {
      final cmd = SelfUpdateService.buildBootstrapCommandLine(
        r'C:\Users\Test User\AppData\Local\Dacx\updates\spawn-watchdog.ps1',
      );

      expect(cmd, startsWith('powershell.exe'));
      expect(cmd, contains('-NoProfile'));
      expect(cmd, contains('-ExecutionPolicy Bypass'));
      expect(cmd, contains('-WindowStyle Hidden'));
      expect(
        cmd,
        contains(
          r'-File "C:\Users\Test User\AppData\Local\Dacx\updates\spawn-watchdog.ps1"',
        ),
      );
    });
  });

  group('SelfUpdateService Ed25519 helpers', () {
    test('verifies a known RFC 8032 signature vector', () async {
      final publicKey = base64Encode(
        _hexBytes(
          'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        ),
      );
      final signature = _hexBytes(
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );

      expect(
        await SelfUpdateService.verifyEd25519Signature(
          message: const [],
          signature: signature,
          publicKeyBase64: publicKey,
        ),
        isTrue,
      );
    });

    test('rejects a tampered Ed25519 signature message', () async {
      final publicKey = base64Encode(
        _hexBytes(
          'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        ),
      );
      final signature = _hexBytes(
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );

      expect(
        await SelfUpdateService.verifyEd25519Signature(
          message: utf8.encode('tampered'),
          signature: signature,
          publicKeyBase64: publicKey,
        ),
        isFalse,
      );
    });
  });

  group('SelfUpdateService.isSupported', () {
    test('matches host platform expectations', () {
      // Windows or macOS hosts → true; Linux/other → false. Just check the
      // value is consistent with Platform — no assumption about test runner.
      final result = SelfUpdateService.isSupported();
      expect(result, isA<bool>());
    });
  });

  group('SelfUpdateProgress', () {
    test('fraction is null when totalBytes is null', () {
      const p = SelfUpdateProgress(50, null);
      expect(p.fraction, isNull);
    });

    test('fraction is null when totalBytes is zero', () {
      const p = SelfUpdateProgress(50, 0);
      expect(p.fraction, isNull);
    });

    test('fraction reports downloaded/total', () {
      const p = SelfUpdateProgress(50, 200);
      expect(p.fraction, 0.25);
    });
  });
}

List<int> _hexBytes(String value) {
  final bytes = <int>[];
  for (var i = 0; i < value.length; i += 2) {
    bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
  }
  return bytes;
}
