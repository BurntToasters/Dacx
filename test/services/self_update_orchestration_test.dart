import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/services/windows_process_ffi.dart';

void main() {
  group('SelfUpdateService.isAllowedDownloadUrl', () {
    test('allows GitHub release and objects hosts', () {
      expect(
        SelfUpdateService.isAllowedDownloadUrl(
          'https://github.com/BurntToasters/Dacx/releases/download/v1/Dacx.msi',
        ),
        isTrue,
      );
      expect(
        SelfUpdateService.isAllowedDownloadUrl(
          'https://objects.githubusercontent.com/github-production-release-asset/abc',
        ),
        isTrue,
      );
    });

    test('allows current GitHub release-assets CDN host', () {
      // GitHub now redirects release-asset downloads to this host.
      expect(
        SelfUpdateService.isAllowedDownloadUrl(
          'https://release-assets.githubusercontent.com/github-production-release-asset/123/abc?sig=x',
        ),
        isTrue,
      );
    });

    test('rejects non-HTTPS and unknown hosts', () {
      expect(
        SelfUpdateService.isAllowedDownloadUrl('http://github.com/x'),
        isFalse,
      );
      expect(
        SelfUpdateService.isAllowedDownloadUrl('https://evil.example/msi'),
        isFalse,
      );
      expect(SelfUpdateService.isAllowedDownloadUrl('not-a-url'), isFalse);
    });

    test('rejects look-alike hosts that only suffix-spoof githubusercontent', () {
      // Must not match a domain that merely ends with the string without the dot.
      expect(
        SelfUpdateService.isAllowedDownloadUrl(
          'https://evilgithubusercontent.com/github-production-release-asset/x',
        ),
        isFalse,
      );
      expect(
        SelfUpdateService.isAllowedDownloadUrl(
          'https://githubusercontent.com.evil.example/x',
        ),
        isFalse,
      );
    });
  });

  group('SelfUpdateService.hashFromWindowsManifest', () {
    test('reads MSI hash from signed manifest JSON', () {
      final manifest = utf8.encode(
        jsonEncode({
          'version': '0.8.0',
          'assets': {
            'Dacx-Windows-x64.msi':
                'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
          },
        }),
      );
      expect(
        SelfUpdateService.hashFromWindowsManifest(
          manifest,
          'Dacx-Windows-x64.msi',
        ),
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234',
      );
    });

    test('returns null for missing or invalid hash', () {
      final manifest = utf8.encode(
        jsonEncode({'version': '0.8.0', 'assets': {}}),
      );
      expect(
        SelfUpdateService.hashFromWindowsManifest(
          manifest,
          'Dacx-Windows-x64.msi',
        ),
        isNull,
      );
    });
  });

  group('SelfUpdateService.applyUpdate', () {
    test('returns unsupportedPlatform on Linux CI hosts', () async {
      if (!Platform.isLinux) return;

      final svc = SelfUpdateService();
      final result = await svc.applyUpdate(
        const UpdateInfo(
          version: '9.9.9',
          url: 'https://github.com/BurntToasters/Dacx/releases/tag/v9.9.9',
          notes: '',
          assets: [],
        ),
      );
      expect(result.outcome, SelfUpdateOutcome.unsupportedPlatform);
    });

    test('returns missingAsset when no MSI on Windows', () async {
      if (!Platform.isWindows) return;

      final svc = SelfUpdateService();
      final result = await svc.applyUpdate(
        const UpdateInfo(
          version: '0.8.0',
          url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.8.0',
          notes: '',
          assets: [
            UpdateAsset(
              name: 'SHA256SUMS-Windows-x64.txt',
              downloadUrl:
                  'https://github.com/BurntToasters/Dacx/releases/download/v0.8.0/SHA256SUMS-Windows-x64.txt',
            ),
          ],
        ),
      );
      expect(result.outcome, SelfUpdateOutcome.missingAsset);
    });
  });

  group('WindowsProcessFfi.runAsync', () {
    test('returns a not-launched guard result on non-Windows hosts', () async {
      if (Platform.isWindows) return;

      final result = await WindowsProcessFfi.runAsync('powershell.exe -NoExit');
      expect(result.launched, isFalse);
      expect(result.error, contains('Windows-only'));
    });
  });
}
