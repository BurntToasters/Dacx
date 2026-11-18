import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/services/release_notes_formatter.dart';
import 'package:dacx/services/self_update_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/widgets/update_available_dialog.dart';
import 'package:dacx/widgets/update_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../support/audit9_report.dart';

const _releaseUrl = 'https://github.com/BurntToasters/Dacx/releases/tag/v1.0.2';

class _RecordingUpdateService extends UpdateService {
  final List<String> opened = [];

  @override
  Future<void> openReleasePage(String url) async {
    opened.add(url);
  }
}

class _FakeCancelService extends SelfUpdateService {
  _FakeCancelService(this.completer, {this.progress}) : super();

  final Completer<SelfUpdateResult> completer;
  final SelfUpdateProgress? progress;
  int cancelCalls = 0;

  @override
  Future<SelfUpdateResult> applyUpdate(
    UpdateInfo info, {
    void Function(SelfUpdateProgress)? onProgress,
  }) {
    final p = progress;
    if (p != null) onProgress?.call(p);
    return completer.future;
  }

  @override
  bool cancelUpdate() {
    cancelCalls++;
    if (!completer.isCompleted) {
      completer.complete(const SelfUpdateResult(SelfUpdateOutcome.cancelled));
    }
    return true;
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

String _bullets(int count) {
  final b = StringBuffer('## Changes in `v3.0.0:`\n');
  for (var i = 0; i < count; i++) {
    b.writeln('- **Item $i:** text number $i');
  }
  return b.toString();
}

const _msiUrl =
    'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-Windows-x64.msi';

UpdateInfo _winInfo() => const UpdateInfo(
  version: '0.10.0',
  url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.10.0',
  notes: '',
  assets: [
    UpdateAsset(name: 'Dacx-Windows-x64.msi', downloadUrl: _msiUrl),
    UpdateAsset(
      name: 'SHA256SUMS-Windows-x64.txt',
      downloadUrl: 'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/SHA256SUMS-Windows-x64.txt',
    ),
    UpdateAsset(
      name: 'Dacx-update-manifest-Windows-x64.json',
      downloadUrl: 'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-update-manifest-Windows-x64.json',
    ),
    UpdateAsset(
      name: 'Dacx-update-manifest-Windows-x64.json.sig',
      downloadUrl: 'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-update-manifest-Windows-x64.json.sig',
    ),
  ],
);

void main() {
  final report = Audit9Report(
    'updater',
    expectedIds: [for (var i = 1; i <= 15; i++) 'M26.$i'],
  );
  tearDownAll(report.write);

  late String changelog;

  setUpAll(() {
    changelog = File('CHANGELOG.md').readAsStringSync();
  });

  group('release notes formatter', () {
    test('M26.1 picks the section for the offered version', () {
      final s101 = formatReleaseNotes(changelog, version: '1.0.1');
      expect(s101.sectionVersion, '1.0.1');
      expect(s101.entries, hasLength(3));
      expect(s101.entries.first, 'Flutter: Updated Flutter to 3.47.9.');
      expect(s101.hiddenCount, 0);

      final s100 = formatReleaseNotes(changelog, version: 'v1.0.0');
      expect(s100.sectionVersion, '1.0.0');
      expect(s100.entries.length, greaterThan(3));
      for (final e in s100.entries) {
        expect(e, isNot(contains('|')));
        expect(e, isNot(contains('**')));
        expect(e, isNot(contains('`')));
        expect(e, isNot(contains('releases/download')));
      }
      expect(
        s100.entries.any((e) => e.contains('Stalled update downloads')),
        isTrue,
      );
      expect(
        s100.entries.any((e) => e.contains('Updated Dependency')),
        isFalse,
      );

      const variants = [
        '## Changes in v2.5.0\n- one',
        '### Changes in `2.5.0`:\n- one',
        '## Changes in `v2.5.0:`\n- one\n## Changes in `v2.4.0:`\n- two',
        '# changes in V2.5.0\n* one',
      ];
      for (final body in variants) {
        final s = formatReleaseNotes(body, version: '2.5.0');
        expect(s.entries, ['one'], reason: body);
      }

      final beta = formatReleaseNotes(
        '## Changes in `v1.1.0-beta.2:`\n- beta thing\n'
        '## Changes in `v1.1.0:`\n- stable thing',
        version: '1.1.0-beta.2',
      );
      expect(beta.entries, ['beta thing']);
      report.pass('M26.1');
    });

    test('M26.2 falls back to the first section, then to nothing', () {
      final fallback = formatReleaseNotes(
        '## Changes in `v2.0.0:`\n- newest\n## Changes in `v1.0.0:`\n- old',
        version: '9.9.9',
      );
      expect(fallback.sectionVersion, '2.0.0');
      expect(fallback.entries, ['newest']);

      final none = formatReleaseNotes(
        '# Downloads\n- not a changelog\n',
        version: '1.0.0',
      );
      expect(none.entries, isEmpty);
      expect(none.hiddenCount, 0);
      expect(none.isEmpty, isTrue);

      final real = formatReleaseNotes(changelog, version: '1.1.0');
      expect(real.entries, isEmpty);
      report.pass('M26.2');
    });

    test('M26.3 strips markup and keeps bullet text', () {
      const body = '''
## Changes in `v2.0.0:`
- **Fix - Thing:** Uses [the docs](https://example.com/a_b) and `code` and *emph* and __bold__.
- <b>HTML</b> &amp; entity <br/> text
- ![logo](https://x.example/y.png) image
  continuation line
-   spaced   out    words
- [![badge](https://x.example/b.svg)](https://x.example/) badge link
''';
      final s = formatReleaseNotes(body, version: '2.0.0');
      expect(s.entries, [
        'Fix - Thing: Uses the docs and code and emph and bold.',
        'HTML & entity text',
        'image continuation line',
        'spaced out words',
        'badge link',
      ]);
      report.pass('M26.3');
    });

    test('M26.4 caps entries and entry length', () {
      final s = formatReleaseNotes(_bullets(30), version: '3.0.0');
      expect(s.entries, hasLength(12));
      expect(s.hiddenCount, 18);
      expect(s.entries.first, 'Item 0: text number 0');

      final custom = formatReleaseNotes(
        _bullets(5),
        version: '3.0.0',
        maxEntries: 2,
      );
      expect(custom.entries, hasLength(2));
      expect(custom.hiddenCount, 3);

      final long = formatReleaseNotes(
        '## Changes in `v3.0.0:`\n- ${'word ' * 400}',
        version: '3.0.0',
      );
      expect(long.entries, hasLength(1));
      expect(long.entries.single.length, lessThanOrEqualTo(220));
      expect(long.entries.single, endsWith('…'));
      report.pass('M26.4');
    });

    test('M26.5 empty and garbage input never throws', () {
      final inputs = <String?>[
        null,
        '',
        '   \n\t  ',
        '## Changes in',
        '## Changes in ``',
        '## Changes in `v1.0.0:`',
        '\u0000\uFFFF### \u0000',
        '- - -\n- \n-\n*\n',
        '[**<<<>>>![](](&;&#x;`\n- [**<a',
        '## Changes in `v1.0.0:`\n- [unclosed(link\n- **unclosed\n- <unclosed',
        '\ud800 lone surrogate ## Changes in v1\n- x',
        'a' * 3000000,
        '## Changes in `v1.0.0:`\n${'- x\n' * 200000}',
      ];
      for (final input in inputs) {
        late ReleaseNotesSummary s;
        expect(
          () => s = formatReleaseNotes(input, version: '1.0.0'),
          returnsNormally,
          reason: '${input?.length}',
        );
        expect(s.entries.length, lessThanOrEqualTo(12));
      }
      expect(formatReleaseNotes(null, version: '1.0.0').entries, isEmpty);
      expect(formatReleaseNotes('', version: '').entries, isEmpty);
      expect(
        formatReleaseNotes('## Changes in `v1.0.0:`', version: '1.0.0').entries,
        isEmpty,
      );
      report.pass('M26.5');
    });

    test('M26.6 only https GitHub release URLs are accepted', () {
      const good = [
        _releaseUrl,
        'https://www.github.com/BurntToasters/Dacx/releases',
        'https://GitHub.com/BurntToasters/Dacx/releases',
      ];
      const bad = [
        'http://github.com/BurntToasters/Dacx',
        'https://evil.example/github.com/x',
        'https://github.com.evil.example/x',
        'https://notgithub.com/x',
        'https://rosie.run/dacx/update?from=v1.0.0',
        'https://githubusercontent.com/x',
        'https://objects.githubusercontent.com/x',
        'javascript:alert(1)',
        'file:///c:/windows',
        'github.com/x',
        '',
        '   ',
        'not a url',
        'https://',
        'https:///x',
      ];
      for (final url in good) {
        expect(isGithubReleaseUrl(url), isTrue, reason: url);
      }
      for (final url in bad) {
        expect(isGithubReleaseUrl(url), isFalse, reason: url);
      }
      report.pass('M26.6');
    });
  });

  group('update available dialog', () {
    testWidgets('M26.7 shows scrollable notes, more line and link', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      final summary = formatReleaseNotes(_bullets(20), version: '3.0.0');

      await tester.pumpWidget(
        _app(
          UpdateAvailableDialog(
            info: const UpdateInfo(
              version: '3.0.0',
              url: _releaseUrl,
              notes: '',
              releaseUrl: _releaseUrl,
            ),
            summary: summary,
            confirmLabel: 'Install',
            releaseNotesUrl: _releaseUrl,
            onOpenReleaseNotes: opened.add,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.textContaining('Item 0: text number 0'), findsOneWidget);
      final list = find.byKey(const Key('update-whats-new-list'));
      expect(list, findsOneWidget);
      expect(
        find.descendant(of: list, matching: find.byType(Scrollable)),
        findsWidgets,
      );
      await tester.drag(list, const Offset(0, -2000));
      await tester.pump();
      expect(find.text('+8 more'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('update-release-notes-button')));
      await tester.pump();
      expect(opened, [_releaseUrl]);

      await tester.pumpWidget(
        _app(
          UpdateAvailableDialog(
            info: const UpdateInfo(
              version: '3.0.0',
              url: _releaseUrl,
              notes: '',
            ),
            summary: summary,
            confirmLabel: 'Install',
            releaseNotesUrl: null,
            onOpenReleaseNotes: opened.add,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('update-release-notes-button')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      report.pass('M26.7');
    });

    testWidgets('M26.8 show helper resolves confirm and later', (tester) async {
      final service = _RecordingUpdateService();
      bool? result;
      const info = UpdateInfo(
        version: '1.0.2',
        url: 'https://rosie.run/dacx/update?from=v1.0.0',
        notes: '## Changes in `v1.0.2:`\n- **PKG:** Updated packages.',
        releaseUrl: _releaseUrl,
      );

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showUpdateAvailableDialog(
                  context: context,
                  info: info,
                  updateService: service,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PKG: Updated packages.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-release-notes-button')));
      await tester.pumpAndSettle();
      expect(service.opened, [_releaseUrl]);
      expect(find.byKey(const Key('update-available-confirm')), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.byKey(const Key('update-available-confirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('update-available-later')));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      const rosieOnly = UpdateInfo(
        version: '1.0.2',
        url: 'https://rosie.run/dacx/update?from=v1.0.0',
        notes: '## Changes in `v1.0.2:`\n- x',
        releaseUrl: 'https://rosie.run/dacx/update',
      );
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateAvailableDialog(
                context: context,
                info: rosieOnly,
                updateService: service,
              ),
              child: const Text('open2'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('update-release-notes-button')),
        findsNothing,
      );
      report.pass('M26.8');
    });
  });

  group('windows download cancel', () {
    late Directory tempRoot;
    late Directory cacheDir;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('dacx-updater-e2e-');
      cacheDir = Directory('${tempRoot.path}${Platform.pathSeparator}updates');
      SelfUpdateService.updateCacheDirOverride = cacheDir;
    });

    tearDown(() {
      SelfUpdateService.updateCacheDirOverride = null;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    File msi() =>
        File('${cacheDir.path}${Platform.pathSeparator}Dacx-Windows-x64.msi');

    test('M26.9 cancel stops the stream, deletes the partial file', () async {
      final controller = StreamController<List<int>>();
      var streamCancelled = false;
      controller.onCancel = () {
        streamCancelled = true;
      };
      var verificationCalls = 0;
      final gotProgress = Completer<void>();
      final svc = SelfUpdateService(
        httpStream: (request) async {
          expect(request.url.toString(), _msiUrl);
          return http.StreamedResponse(
            controller.stream,
            200,
            contentLength: 1000,
          );
        },
        fetchText: (_) async {
          verificationCalls++;
          return '';
        },
        fetchBytes: (_) async {
          verificationCalls++;
          return <int>[];
        },
        validateWindowsManifest:
            ({
              required manifestBytes,
              required signatureBytes,
              required version,
              required assetName,
            }) async {
              verificationCalls++;
              return const SelfUpdateResult(SelfUpdateOutcome.spawned);
            },
      );

      final future = svc.applyWindowsUpdate(
        _winInfo(),
        onProgress: (p) {
          if (!gotProgress.isCompleted) gotProgress.complete();
        },
      );
      controller.add(List<int>.filled(100, 7));
      await gotProgress.future;
      expect(svc.cancelUpdate(), isTrue);
      final result = await future;

      expect(result.outcome, SelfUpdateOutcome.cancelled);
      expect(streamCancelled, isTrue);
      expect(msi().existsSync(), isFalse);
      expect(verificationCalls, 0);
      await controller.close();
      report.pass('M26.9');
    });

    test('M26.10 cancel while waiting for headers returns cancelled', () async {
      final headers = Completer<http.StreamedResponse>();
      var verificationCalls = 0;
      final svc = SelfUpdateService(
        httpStream: (request) => headers.future,
        fetchText: (_) async {
          verificationCalls++;
          return '';
        },
      );
      final future = svc.applyWindowsUpdate(_winInfo());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(svc.cancelUpdate(), isTrue);
      final result = await future.timeout(const Duration(seconds: 5));

      expect(result.outcome, SelfUpdateOutcome.cancelled);
      expect(msi().existsSync(), isFalse);
      expect(verificationCalls, 0);
      headers.complete(http.StreamedResponse(const Stream.empty(), 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      report.pass('M26.10');
    });

    test(
      'M26.11 cancel refused during verification, which still runs',
      () async {
        final msiBytes = utf8.encode('fake-msi-payload');
        final sums = '${sha256.convert(msiBytes)}  Dacx-Windows-x64.msi\n';
        var validateCalls = 0;
        bool? cancelDuringVerification;
        late SelfUpdateService svc;
        svc = SelfUpdateService(
          httpStream: (request) async => http.StreamedResponse(
            Stream<List<int>>.fromIterable([msiBytes]),
            200,
            contentLength: msiBytes.length,
          ),
          fetchText: (url) async {
            if (url.contains('SHA256SUMS')) return sums;
            return base64Encode([1, 2, 3]);
          },
          fetchBytes: (url) async => utf8.encode('{"version":"0.10.0"}'),
          validateWindowsManifest:
              ({
                required manifestBytes,
                required signatureBytes,
                required version,
                required assetName,
              }) async {
                validateCalls++;
                cancelDuringVerification = svc.cancelUpdate();
                return const SelfUpdateResult(
                  SelfUpdateOutcome.signatureInvalid,
                );
              },
        );

        final result = await svc.applyWindowsUpdate(_winInfo());

        expect(validateCalls, 1);
        expect(cancelDuringVerification, isFalse);
        expect(result.outcome, SelfUpdateOutcome.signatureInvalid);
        expect(msi().existsSync(), isTrue);
        expect(svc.cancelUpdate(), isFalse);
        report.pass('M26.11');
      },
    );

    test('M26.12 cancel refused when idle and on the macOS path', () async {
      final idle = SelfUpdateService();
      expect(idle.cancelUpdate(), isFalse);
      expect(SelfUpdateService.supportsCancel, Platform.isWindows);

      final entered = Completer<void>();
      final release = Completer<void>();
      late SelfUpdateService mac;
      mac = SelfUpdateService(
        expectedTeamIdOverride: 'TEAM123',
        fetchText: (_) async => '${'a' * 64}  Dacx-macOS.zip\n',
        macUpdateInstall:
            ({
              required zipUrl,
              required checksumHex,
              required installedAppPath,
              required expectedTeamId,
              required expectedVersion,
              required relaunch,
            }) async {
              entered.complete();
              await release.future;
              return {'accepted': true};
            },
      );
      final future = mac.applyMacosUpdate(
        const UpdateInfo(
          version: '0.10.0',
          url: 'https://github.com/BurntToasters/Dacx/releases/tag/v0.10.0',
          notes: '',
          assets: [
            UpdateAsset(
              name: 'Dacx-macOS.zip',
              downloadUrl: 'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/Dacx-macOS.zip',
            ),
            UpdateAsset(
              name: 'SHA256SUMS-macOS.txt',
              downloadUrl: 'https://github.com/BurntToasters/Dacx/releases/download/v0.10.0/SHA256SUMS-macOS.txt',
            ),
          ],
        ),
      );
      await entered.future;
      expect(mac.cancelUpdate(), isFalse);
      release.complete();
      final result = await future;
      expect(result.outcome, SelfUpdateOutcome.spawned);
      report.pass('M26.12');
    });
  });

  group('progress dialog cancel', () {
    Future<SelfUpdateResult?> openDialog(
      WidgetTester tester,
      SelfUpdateService service, {
      required bool cancelSupported,
    }) async {
      SelfUpdateResult? result;
      var done = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<SelfUpdateResult>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => UpdateProgressDialog(
                    info: const UpdateInfo(
                      version: '1.0.2',
                      url: _releaseUrl,
                      notes: '',
                    ),
                    service: service,
                    onManualDownload: () {},
                    cancelSupported: cancelSupported,
                  ),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();
      expect(done, isFalse);
      return result;
    }

    testWidgets('M26.13 cancel button cancels and shows no failure', (
      tester,
    ) async {
      final service = _FakeCancelService(
        Completer<SelfUpdateResult>(),
        progress: const SelfUpdateProgress(1024 * 1024, 4 * 1024 * 1024),
      );
      await openDialog(tester, service, cancelSupported: true);

      final cancel = find.byKey(const Key('update-cancel-button'));
      expect(cancel, findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(service.cancelCalls, 1);
      expect(find.text('Update failed'), findsNothing);
      expect(find.byType(UpdateProgressDialog), findsNothing);
      report.pass('M26.13');
    });

    testWidgets('M26.14 no cancel when unsupported or verifying', (
      tester,
    ) async {
      final unsupported = _FakeCancelService(
        Completer<SelfUpdateResult>(),
        progress: const SelfUpdateProgress(1024, 4096),
      );
      await openDialog(tester, unsupported, cancelSupported: false);
      expect(find.byKey(const Key('update-cancel-button')), findsNothing);
      expect(find.text('Cancel'), findsNothing);

      final verifying = _FakeCancelService(
        Completer<SelfUpdateResult>(),
        progress: const SelfUpdateProgress(4096, 4096),
      );
      await tester.pumpWidget(const SizedBox());
      await openDialog(tester, verifying, cancelSupported: true);
      expect(find.byKey(const Key('update-cancel-button')), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      report.pass('M26.14');
    });
  });

  group('update info', () {
    test('M26.15 UpdateInfo carries the GitHub release URL', () async {
      const releaseJson = {
        'tag_name': 'v1.0.2',
        'html_url': _releaseUrl,
        'body': '## Changes in `v1.0.2:`\n- **PKG:** Updated.',
        'assets': <Object?>[],
      };
      final svc = UpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'Dacx',
          packageName: 'run.rosie.dacx',
          version: '1.0.0',
          buildNumber: '1',
          buildSignature: '',
          installerStore: null,
        ),
        currentVersionLoader: (_) async => '1.0.0',
        httpGet: (uri, {headers}) async =>
            http.Response(jsonEncode(releaseJson), 200),
      );
      final info = await svc.checkForUpdate(channel: UpdateChannel.stable);
      expect(info, isNotNull);
      expect(info!.releaseUrl, _releaseUrl);
      expect(info.url, startsWith('https://rosie.run/'));
      expect(formatReleaseNotes(info.notes, version: info.version).entries, [
        'PKG: Updated.',
      ]);

      const bare = UpdateInfo(version: '1.0.0', url: _releaseUrl, notes: '');
      expect(bare.releaseUrl, '');
      report.pass('M26.15');
    });
  });
}
