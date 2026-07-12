import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:dacx/services/headless_player_service.dart';

void main() {
  group('HeadlessPlayerService', () {
    test('exposes broadcast streams without native player', () {
      final service = HeadlessPlayerService();
      expect(service.positionStream.isBroadcast, isTrue);
      expect(service.tracksStream.isBroadcast, isTrue);
      expect(service.videoWidthStream.isBroadcast, isTrue);
    });

    test('emitPosition pushes to positionStream listeners', () async {
      final service = HeadlessPlayerService();
      final positions = <Duration>[];
      final sub = service.positionStream.listen(positions.add);

      service.emitPosition(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);

      expect(positions, const [Duration(seconds: 3)]);
      await sub.cancel();
      await service.dispose();
    });

    test('setProperty round-trips through getProperty', () async {
      final service = HeadlessPlayerService();
      await service.setProperty('chapter-list/count', '2');
      expect(await service.getProperty('chapter-list/count'), '2');
      await service.dispose();
    });

    test('emitTracks updates currentTracks snapshot', () async {
      final service = HeadlessPlayerService();
      final tracks = const Tracks(
        audio: [AudioTrack('1', 'eng', null)],
        video: [],
        subtitle: [],
      );
      service.emitTracks(tracks);
      expect(service.currentTracks.audio.length, 1);
      await service.dispose();
    });

    test('playPause toggles playing stream', () async {
      final service = HeadlessPlayerService();
      final states = <bool>[];
      final sub = service.playingStream.listen(states.add);

      await service.playPause();
      await service.playPause();
      await Future<void>.delayed(Duration.zero);

      expect(states, const [true, false]);
      await sub.cancel();
      await service.dispose();
    });

    test('open records calls for harness assertions', () async {
      final service = HeadlessPlayerService();
      await service.open('/media/song.mp3', play: false);
      await service.open('/media/other.mp3');

      expect(service.openCalls.length, 2);
      expect(service.openCalls.first.path, '/media/song.mp3');
      expect(service.openCalls.first.play, isFalse);
      expect(service.openCalls.last.play, isTrue);
      await service.dispose();
    });

    test('setAudioTrack records calls and emits track stream', () async {
      final service = HeadlessPlayerService();
      final tracks = <Track>[];
      final sub = service.trackStream.listen(tracks.add);
      const next = AudioTrack('jpn', 'Japanese', null);

      expect(await service.setAudioTrack(next), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(service.audioTrackCalls.single.id, 'jpn');
      expect(tracks.single.audio.id, 'jpn');
      await sub.cancel();
      await service.dispose();
    });

    test('setAudioTrack returns false when failAudioTrack is set', () async {
      final service = HeadlessPlayerService()..failAudioTrack = true;
      expect(
        await service.setAudioTrack(const AudioTrack('eng', 'English', null)),
        isFalse,
      );
      expect(service.audioTrackCalls, hasLength(1));
      await service.dispose();
    });

    test('emitTrack pushes to trackStream listeners', () async {
      final service = HeadlessPlayerService();
      final tracks = <Track>[];
      final sub = service.trackStream.listen(tracks.add);
      final track = Track(
        audio: const AudioTrack('eng', 'English', null),
        video: const VideoTrack('auto', 'auto', null),
        subtitle: SubtitleTrack.no(),
      );

      service.emitTrack(track);
      await Future<void>.delayed(Duration.zero);

      expect(tracks.single.audio.id, 'eng');
      await sub.cancel();
      await service.dispose();
    });

    test('setSubtitleTrack records calls and emits track stream', () async {
      final service = HeadlessPlayerService();
      final tracks = <Track>[];
      final sub = service.trackStream.listen(tracks.add);
      const next = SubtitleTrack('eng', 'English', null);

      await service.setSubtitleTrack(next);
      await Future<void>.delayed(Duration.zero);

      expect(service.subtitleTrackCalls.single.id, 'eng');
      expect(tracks.single.subtitle.id, 'eng');
      await sub.cancel();
      await service.dispose();
    });

    test('open throws configured openError', () async {
      final service = HeadlessPlayerService()
        ..openError = Exception('decoder failed');

      await expectLater(
        service.open('/media/broken.mkv'),
        throwsA(isA<Exception>()),
      );
      expect(service.openCalls, isEmpty);
      await service.dispose();
    });

    test('openDelay defers recorded calls', () async {
      final service = HeadlessPlayerService()
        ..openDelay = const Duration(milliseconds: 40);
      final pending = service.open('/media/slow.mp3');
      expect(service.openCalls, isEmpty);
      await pending;
      expect(service.openCalls.single.path, '/media/slow.mp3');
      await service.dispose();
    });
  });
}
