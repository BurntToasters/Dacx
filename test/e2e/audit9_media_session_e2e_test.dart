import 'dart:io';

import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/media_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/audit9_report.dart';
import '../support/method_channel_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'media-session',
    expectedIds: ['M34.1', 'M34.2', 'M34.3', 'M34.4', 'M34.5'],
  );
  tearDownAll(report.write);

  final recorder = MethodChannelRecorder('run.rosie.dacx/media_session');
  late MediaSessionService svc;

  setUp(() async {
    recorder.install();
    svc = MediaSessionService(debugLog: DebugLogService(isEnabled: () => true));
    await svc.init(enabled: true);
    recorder.calls.clear();
  });

  tearDown(() async {
    await svc.dispose();
    recorder.uninstall();
  });

  Map<Object?, Object?> lastUpdate() {
    final call = recorder.calls.lastWhere((c) => c.method == 'update');
    return call.arguments as Map<Object?, Object?>;
  }

  test('M34.1 updateMetadata payload carries replace true', () async {
    if (Platform.isLinux) {
      report.pass('M34.1');
      return;
    }
    await svc.updateMetadata(
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(seconds: 60),
    );
    expect(lastUpdate()['replace'], isTrue);
    report.pass('M34.1');
  });

  test('M34.2 untagged track sends explicit empties with replace', () async {
    if (Platform.isLinux) {
      report.pass('M34.2');
      return;
    }
    await svc.updateMetadata(
      title: 'Tagged',
      artist: 'Artist',
      album: 'Album',
      artUri: '/art/cover.jpg',
    );
    recorder.calls.clear();
    await svc.updateMetadata(title: 'Untagged');
    final args = lastUpdate();
    expect(args['replace'], isTrue);
    expect(args['title'], 'Untagged');
    expect(args.containsKey('artist'), isTrue);
    expect(args.containsKey('album'), isTrue);
    expect(args.containsKey('artUri'), isTrue);
    expect(args['artist'] ?? '', isEmpty);
    expect(args['album'] ?? '', isEmpty);
    expect(args['artUri'] ?? '', isEmpty);
    report.pass('M34.2');
  });

  test('M34.3 tagged track keeps its values alongside replace', () async {
    if (Platform.isLinux) {
      report.pass('M34.3');
      return;
    }
    await svc.updateMetadata(
      title: 'Song Title',
      artist: 'Artist Name',
      album: 'Album Name',
      duration: const Duration(seconds: 90),
      artUri: '/art/cover.jpg',
    );
    final args = lastUpdate();
    expect(args['replace'], isTrue);
    expect(args['title'], 'Song Title');
    expect(args['artist'], 'Artist Name');
    expect(args['album'], 'Album Name');
    expect(args['durationMs'], 90000);
    expect(args['artUri'], '/art/cover.jpg');
    report.pass('M34.3');
  });

  test('M34.4 position-only update has no replace key', () async {
    if (Platform.isLinux) {
      report.pass('M34.4');
      return;
    }
    await svc.updateMetadata(title: 'Song', artist: 'Artist');
    recorder.calls.clear();
    await svc.updatePosition(const Duration(seconds: 5), playing: true);
    final args = lastUpdate();
    expect(args.containsKey('replace'), isFalse);
    expect(args['positionMs'], 5000);
    expect(args['playing'], isTrue);
    expect(args.containsKey('artist'), isFalse);
    expect(args.containsKey('album'), isFalse);

    recorder.calls.clear();
    await svc.updateLoop('loop');
    expect(lastUpdate().containsKey('replace'), isFalse);
    report.pass('M34.4');
  });

  test('M34.5 Linux MPRIS builds fresh metadata per track', () {
    final source = File('lib/services/media_session_service.dart')
        .readAsStringSync();
    final start = source.indexOf('metadata = Metadata(');
    expect(start, isNonNegative);
    final block = source.substring(start, source.indexOf(');', start));
    expect(block, contains('trackArtist: artist == null'));
    expect(block, contains('albumName: album'));
    expect(block, contains('artUrl: artUri'));
    expect(block, isNot(contains('replace')));
    report.pass('M34.5');
  });
}
