import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dacx/services/update_installer_service.dart';
import 'package:dacx/services/update_service.dart';

void main() {
  group('UpdateInstallerService.downloadWindowsInstaller', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dacx_update_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    UpdateInfo updateWithInstaller({
      int? size = 3,
      String? url,
      String? sha256,
    }) => UpdateInfo(
      version: '0.6.0',
      url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0',
      notes: '',
      windowsInstallerUrl:
          url ??
          'https://github.com/BurntToasters/Dacx/releases/download/v0.6.0/Dacx-Windows-x64.msi',
      windowsInstallerAssetName: 'Dacx-Windows-x64.msi',
      windowsInstallerSize: size,
      windowsInstallerSha256: sha256,
    );

    test('downloads the MSI to a versioned temp directory', () async {
      final service = UpdateInstallerService(
        isWindows: () => true,
        tempDirectoryProvider: () => tempDir,
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2, 3], 200),
      );

      final file = await service.downloadWindowsInstaller(
        updateWithInstaller(),
      );

      expect(file.path, contains('Dacx-update-0.6.0'));
      expect(file.path, endsWith('Dacx-Windows-x64.msi'));
      expect(await file.readAsBytes(), [1, 2, 3]);
    });

    test('accepts a download when SHA-256 matches release metadata', () async {
      final service = UpdateInstallerService(
        isWindows: () => true,
        tempDirectoryProvider: () => tempDir,
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2, 3], 200),
      );

      final file = await service.downloadWindowsInstaller(
        updateWithInstaller(
          sha256:
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
      );

      expect(await file.readAsBytes(), [1, 2, 3]);
    });

    test('throws when SHA-256 does not match release metadata', () async {
      final service = UpdateInstallerService(
        isWindows: () => true,
        tempDirectoryProvider: () => tempDir,
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2, 3], 200),
      );

      expect(
        service.downloadWindowsInstaller(
          updateWithInstaller(
            sha256:
                '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        ),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('throws on non-200 download response', () async {
      final service = UpdateInstallerService(
        isWindows: () => true,
        tempDirectoryProvider: () => tempDir,
        httpGet: (uri, {headers}) async => http.Response('nope', 404),
      );

      expect(
        service.downloadWindowsInstaller(updateWithInstaller()),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('throws when downloaded size does not match asset metadata', () async {
      final service = UpdateInstallerService(
        isWindows: () => true,
        tempDirectoryProvider: () => tempDir,
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2], 200),
      );

      expect(
        service.downloadWindowsInstaller(updateWithInstaller()),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('rejects invalid installer urls before download', () async {
      var requested = false;
      final service = UpdateInstallerService(
        isWindows: () => true,
        tempDirectoryProvider: () => tempDir,
        httpGet: (uri, {headers}) async {
          requested = true;
          return http.Response.bytes([1, 2, 3], 200);
        },
      );

      expect(
        service.downloadWindowsInstaller(
          updateWithInstaller(url: 'https://evil.example.com/update.msi'),
        ),
        throwsArgumentError,
      );
      expect(requested, isFalse);
    });
  });

  group('UpdateInstallerService.launchWindowsInstaller', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dacx_launch_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('launches msiexec with passive no-restart install arguments', () async {
      String? executable;
      List<String>? arguments;
      final service = UpdateInstallerService(
        isWindows: () => true,
        installerLauncher: (exe, args) async {
          executable = exe;
          arguments = args;
        },
      );
      final installer = File(
        '${tempDir.path}${Platform.pathSeparator}Dacx-Windows-x64.msi',
      );
      await installer.writeAsBytes([1, 2, 3]);
      const update = UpdateInfo(
        version: '0.6.0',
        url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0',
        notes: '',
        windowsInstallerUrl:
            'https://github.com/BurntToasters/Dacx/releases/download/v0.6.0/Dacx-Windows-x64.msi',
        windowsInstallerAssetName: 'Dacx-Windows-x64.msi',
        windowsInstallerSize: 3,
      );

      await service.launchWindowsInstaller(installer, update);

      expect(executable, 'msiexec.exe');
      expect(arguments, [
        '/i',
        installer.path,
        '/passive',
        '/norestart',
        '/l*vx',
        '${tempDir.path}${Platform.pathSeparator}Dacx-update-0.6.0.log',
      ]);
    });
  });

  group('UpdateInstallerService macOS zip updates', () {
    late Directory tempDir;
    late Directory currentApp;
    final processCalls = <String>[];

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dacx_macos_update_test_');
      currentApp = Directory('${tempDir.path}${Platform.pathSeparator}Dacx.app')
        ..createSync(recursive: true);
      processCalls.clear();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    UpdateInfo macUpdate({String? sha256}) => UpdateInfo(
      version: '0.6.0',
      url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.6.0',
      notes: '',
      macOsZipUrl:
          'https://github.com/BurntToasters/Dacx/releases/download/v0.6.0/Dacx-macOS.zip',
      macOsZipAssetName: 'Dacx-macOS.zip',
      macOsZipSize: 3,
      macOsZipSha256: sha256,
    );

    Future<ProcessResult> fakeProcessRunner(
      String executable,
      List<String> arguments,
    ) async {
      processCalls.add('$executable ${arguments.join(' ')}');
      if (executable == 'ditto' && arguments.contains('-x')) {
        final extractDir = Directory(arguments.last);
        Directory(
          '${extractDir.path}${Platform.pathSeparator}Dacx.app',
        ).createSync(recursive: true);
      }
      return ProcessResult(123, 0, '', '');
    }

    Future<MacOsBundleInfo> bundleInfo(Directory appBundle) async {
      return const MacOsBundleInfo(
        bundleId: 'run.rosie.dacx',
        shortVersion: '0.6.0',
        buildNumber: '600',
      );
    }

    test('prepares a verified Dacx.app from the macOS zip', () async {
      final service = UpdateInstallerService(
        isMacOS: () => true,
        tempDirectoryProvider: () => tempDir,
        currentAppBundleProvider: () => currentApp,
        processRunner: fakeProcessRunner,
        bundleInfoReader: bundleInfo,
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2, 3], 200),
      );

      final prepared = await service.prepareMacOsZipUpdate(
        macUpdate(
          sha256:
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
      );

      expect(prepared.currentApp.path, currentApp.path);
      expect(prepared.newApp.path, endsWith('Dacx.app'));
      expect(
        processCalls.any((call) => call.startsWith('codesign --verify')),
        isTrue,
      );
      expect(
        processCalls.any((call) => call.startsWith('spctl --assess')),
        isTrue,
      );
    });

    test(
      'continues when spctl reports internal code-signing subsystem errors',
      () async {
        var spctlCalls = 0;
        Future<ProcessResult> flakyProcessRunner(
          String executable,
          List<String> arguments,
        ) async {
          processCalls.add('$executable ${arguments.join(' ')}');
          if (executable == 'ditto' && arguments.contains('-x')) {
            final extractDir = Directory(arguments.last);
            Directory(
              '${extractDir.path}${Platform.pathSeparator}Dacx.app',
            ).createSync(recursive: true);
          }
          if (executable == 'spctl') {
            spctlCalls += 1;
            return ProcessResult(
              123,
              1,
              '',
              '${arguments.last}: internal error in Code Signing subsystem',
            );
          }
          return ProcessResult(123, 0, '', '');
        }

        final service = UpdateInstallerService(
          isMacOS: () => true,
          tempDirectoryProvider: () => tempDir,
          currentAppBundleProvider: () => currentApp,
          processRunner: flakyProcessRunner,
          bundleInfoReader: bundleInfo,
          httpGet: (uri, {headers}) async =>
              http.Response.bytes([1, 2, 3], 200),
        );

        final prepared = await service.prepareMacOsZipUpdate(macUpdate());

        expect(prepared.newApp.path, endsWith('Dacx.app'));
        expect(spctlCalls, 2);
        expect(
          processCalls.any((call) => call.startsWith('xattr -cr')),
          isTrue,
        );
      },
    );

    test(
      'continues when xattr normalization fails during spctl internal-error retry',
      () async {
        var spctlCalls = 0;
        Future<ProcessResult> flakyProcessRunner(
          String executable,
          List<String> arguments,
        ) async {
          processCalls.add('$executable ${arguments.join(' ')}');
          if (executable == 'ditto' && arguments.contains('-x')) {
            final extractDir = Directory(arguments.last);
            Directory(
              '${extractDir.path}${Platform.pathSeparator}Dacx.app',
            ).createSync(recursive: true);
          }
          if (executable == 'spctl') {
            spctlCalls += 1;
            return ProcessResult(
              123,
              1,
              '',
              '${arguments.last}: internal error in Code Signing subsystem',
            );
          }
          if (executable == 'xattr') {
            return ProcessResult(
              123,
              1,
              '',
              "xattr: [Errno 1] Operation not permitted: 'CodeResources'",
            );
          }
          return ProcessResult(123, 0, '', '');
        }

        final service = UpdateInstallerService(
          isMacOS: () => true,
          tempDirectoryProvider: () => tempDir,
          currentAppBundleProvider: () => currentApp,
          processRunner: flakyProcessRunner,
          bundleInfoReader: bundleInfo,
          httpGet: (uri, {headers}) async =>
              http.Response.bytes([1, 2, 3], 200),
        );

        final prepared = await service.prepareMacOsZipUpdate(macUpdate());

        expect(prepared.newApp.path, endsWith('Dacx.app'));
        expect(spctlCalls, 2);
        expect(
          processCalls.any((call) => call.startsWith('xattr -cr')),
          isTrue,
        );
      },
    );

    test('fails when spctl reports a real Gatekeeper rejection', () async {
      Future<ProcessResult> rejectingProcessRunner(
        String executable,
        List<String> arguments,
      ) async {
        processCalls.add('$executable ${arguments.join(' ')}');
        if (executable == 'ditto' && arguments.contains('-x')) {
          final extractDir = Directory(arguments.last);
          Directory(
            '${extractDir.path}${Platform.pathSeparator}Dacx.app',
          ).createSync(recursive: true);
        }
        if (executable == 'spctl') {
          return ProcessResult(123, 1, '', '${arguments.last}: rejected');
        }
        return ProcessResult(123, 0, '', '');
      }

      final service = UpdateInstallerService(
        isMacOS: () => true,
        tempDirectoryProvider: () => tempDir,
        currentAppBundleProvider: () => currentApp,
        processRunner: rejectingProcessRunner,
        bundleInfoReader: bundleInfo,
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2, 3], 200),
      );

      expect(
        service.prepareMacOsZipUpdate(macUpdate()),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('rejects a macOS update with a mismatched bundle id', () async {
      final service = UpdateInstallerService(
        isMacOS: () => true,
        tempDirectoryProvider: () => tempDir,
        currentAppBundleProvider: () => currentApp,
        processRunner: fakeProcessRunner,
        bundleInfoReader: (appBundle) async {
          if (appBundle.path == currentApp.path) {
            return const MacOsBundleInfo(
              bundleId: 'run.rosie.dacx',
              shortVersion: '0.5.0',
              buildNumber: '500',
            );
          }
          return const MacOsBundleInfo(
            bundleId: 'example.other.app',
            shortVersion: '0.6.0',
            buildNumber: '600',
          );
        },
        httpGet: (uri, {headers}) async => http.Response.bytes([1, 2, 3], 200),
      );

      expect(
        service.prepareMacOsZipUpdate(macUpdate()),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('launches the detached macOS helper with app paths', () async {
      String? executable;
      List<String>? arguments;
      final service = UpdateInstallerService(
        isMacOS: () => true,
        processRunner: fakeProcessRunner,
        installerLauncher: (exe, args) async {
          executable = exe;
          arguments = args;
        },
      );
      final newApp = Directory(
        '${tempDir.path}${Platform.pathSeparator}new${Platform.pathSeparator}Dacx.app',
      )..createSync(recursive: true);
      final prepared = MacOsPreparedUpdate(
        currentApp: currentApp,
        newApp: newApp,
        helperScript: File(
          '${tempDir.path}${Platform.pathSeparator}Dacx-macos-update-helper.sh',
        ),
        logFile: File('${tempDir.path}${Platform.pathSeparator}update.log'),
      );

      await service.launchMacOsUpdater(prepared);

      expect(executable, '/bin/sh');
      expect(arguments?[0], prepared.helperScript.path);
      expect(arguments?[1], currentApp.path);
      expect(arguments?[2], newApp.path);
      expect(arguments?[4], prepared.logFile.path);
      expect(prepared.helperScript.existsSync(), isTrue);
    });

    test(
      'launches osascript with admin privileges when update requires elevation',
      () async {
        String? executable;
        List<String>? arguments;
        final service = UpdateInstallerService(
          isMacOS: () => true,
          processRunner: fakeProcessRunner,
          installerLauncher: (exe, args) async {
            executable = exe;
            arguments = args;
          },
        );
        final newApp = Directory(
          '${tempDir.path}${Platform.pathSeparator}new${Platform.pathSeparator}Dacx.app',
        )..createSync(recursive: true);
        final prepared = MacOsPreparedUpdate(
          currentApp: currentApp,
          newApp: newApp,
          helperScript: File(
            '${tempDir.path}${Platform.pathSeparator}Dacx-macos-update-helper.sh',
          ),
          logFile: File('${tempDir.path}${Platform.pathSeparator}update.log'),
          requiresAdminPrivileges: true,
        );

        await service.launchMacOsUpdater(prepared);

        expect(executable, '/usr/bin/osascript');
        expect(arguments?[0], '-e');
        expect(arguments?[1], contains('with administrator privileges'));
        // Full shell command is passed through _escapeAppleScriptString, which
        // doubles backslashes; Windows temp paths must match the escaped form.
        final helperPathInAppleScript = prepared.helperScript.path
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"');
        expect(arguments?[1], contains(helperPathInAppleScript));
      },
    );
  });
}
