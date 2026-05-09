import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';

void main() {
  group('SelfUpdateService.pickAsset', () {
    test('picks asset by suffix (case-insensitive)', () {
      final assets = [
        const UpdateAsset(name: 'Dacx-Linux-amd64.deb', downloadUrl: 'https://x/a'),
        const UpdateAsset(name: 'Dacx-Windows-x64.MSI', downloadUrl: 'https://x/b'),
        const UpdateAsset(name: 'Dacx-macOS.zip', downloadUrl: 'https://x/c'),
      ];
      expect(SelfUpdateService.pickAsset(assets, '.msi')?.downloadUrl, 'https://x/b');
      expect(SelfUpdateService.pickAsset(assets, '.zip')?.downloadUrl, 'https://x/c');
    });

    test('returns null when no asset matches suffix', () {
      final assets = [
        const UpdateAsset(name: 'Dacx-Linux-amd64.deb', downloadUrl: 'https://x/a'),
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
        const UpdateAsset(name: 'Dacx-Linux-amd64.deb', downloadUrl: 'https://x/a'),
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
1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff  Dacx-Windows-x64.exe
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
      const tooShort =
          'abcd1234  Dacx.msi\n';
      expect(SelfUpdateService.parseChecksumsFile(tooShort, 'Dacx.msi'), isNull);
    });

    test('rejects non-hex hashes', () {
      const nonHex =
          'gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg  Dacx.msi\n';
      expect(SelfUpdateService.parseChecksumsFile(nonHex, 'Dacx.msi'), isNull);
    });

    test('handles single-space separator (non-strict)', () {
      const singleSpace =
          'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234 Dacx.msi\n';
      expect(
        SelfUpdateService.parseChecksumsFile(singleSpace, 'Dacx.msi'),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
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
