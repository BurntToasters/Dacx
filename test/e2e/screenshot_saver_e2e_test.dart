import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/screenshot_saver.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dacx-shot-'));
  tearDown(() => dir.deleteSync(recursive: true));

  ScreenshotSaver saver({
    Uint8List? bytes,
    List<String>? released,
    String? scopedPath,
  }) => ScreenshotSaver(
    capture: (mime) async => bytes,
    resolveScope: (requested) async =>
        (path: scopedPath ?? requested, token: 'tok'),
    releaseScope: (token) async => released?.add(token),
    defaultDirectory: () => p.join(dir.path, 'Pictures', 'Dacx'),
  );

  test('saves into the default folder and names it after the source', () async {
    final result = await saver(bytes: Uint8List.fromList([1, 2, 3])).save(
      source: PlayableSource.file('/m/Movie Night.mkv'),
      format: 'png',
      customDirectory: null,
    );
    expect(result.outcome, ScreenshotSaveOutcome.saved);
    expect(p.dirname(result.path!), p.join(dir.path, 'Pictures', 'Dacx'));
    expect(p.extension(result.path!), '.png');
    expect(File(result.path!).readAsBytesSync(), [1, 2, 3]);
  });

  test(
    'custom folder is opened through its scope and always released',
    () async {
      final released = <String>[];
      final custom = p.join(dir.path, 'custom');
      final result =
          await saver(bytes: Uint8List.fromList([9]), released: released).save(
            source: PlayableSource.file('/m/a.mkv'),
            format: 'jpg',
            customDirectory: custom,
          );
      expect(result.outcome, ScreenshotSaveOutcome.saved);
      expect(p.dirname(result.path!), custom);
      expect(released, ['tok']);
    },
  );

  test('scope is released when the folder cannot be created', () async {
    final released = <String>[];
    final blocker = File(p.join(dir.path, 'file'))..writeAsStringSync('x');
    final result =
        await saver(bytes: Uint8List.fromList([9]), released: released).save(
          source: PlayableSource.file('/m/a.mkv'),
          format: 'jpg',
          customDirectory: p.join(blocker.path, 'sub'),
        );
    expect(result.outcome, ScreenshotSaveOutcome.directoryUnavailable);
    expect(released, ['tok']);
  });

  test('no frame from the player is reported, nothing written', () async {
    final result = await saver().save(
      source: PlayableSource.file('/m/a.mkv'),
      format: 'png',
      customDirectory: null,
    );
    expect(result.outcome, ScreenshotSaveOutcome.noFrame);
    expect(Directory(p.join(dir.path, 'Pictures')).existsSync(), isFalse);
  });

  test('legacy DACX folder is reused when present', () {
    final pictures = p.join(dir.path, 'Pictures');
    expect(ScreenshotSaver.folderIn(pictures), p.join(pictures, 'Dacx'));
    Directory(p.join(pictures, 'DACX')).createSync(recursive: true);
    expect(ScreenshotSaver.folderIn(pictures), p.join(pictures, 'DACX'));
  });
}
