import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/models/playable_source.dart';
import 'package:dacx/playback/advanced_playback_models.dart';
import 'package:dacx/services/advanced_playback_controller.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/settings_service.dart';

import '../support/audit9_report.dart';

class _CountingSettings extends SettingsService {
  _CountingSettings(super.prefs);

  int markerLookups = 0;

  @override
  List<PlaybackMarker> playbackMarkersFor(String source) {
    markerLookups += 1;
    return super.playbackMarkersFor(source);
  }
}

class _Rig {
  _Rig(this.settings, this.player, this.controller) {
    controller.addListener(() => notifications += 1);
  }

  final _CountingSettings settings;
  final HeadlessPlayerService player;
  final AdvancedPlaybackController controller;
  int notifications = 0;
}

const _sourceA = '/e2e/advanced-a.mp3';
const _sourceB = '/e2e/advanced-b.mp3';

Future<_Rig> _rig({bool enabled = true, String? source = _sourceA}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = _CountingSettings(prefs);
  settings.advancedPlaybackToolsEnabled = enabled;
  final player = HeadlessPlayerService();
  final controller = AdvancedPlaybackController(
    settings: settings,
    player: player,
  );
  addTearDown(controller.dispose);
  if (source != null) {
    await controller.setSource(PlayableSource.file(source));
  }
  return _Rig(settings, player, controller);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = Audit9Report(
    'advanced',
    expectedIds: [
      'M12.1',
      'M12.2',
      'M12.3',
      'M12.4',
      'M12.5',
      'M12.6',
      'M12.7',
      'M12.8',
    ],
  );
  tearDownAll(report.write);

  test('M12.1 ticks with tools off do not notify', () async {
    final rig = await _rig(enabled: false);
    final before = rig.notifications;
    for (var i = 1; i <= 50; i += 1) {
      rig.controller.setPosition(Duration(milliseconds: i * 250));
    }
    expect(rig.notifications, before);
    expect(rig.controller.position, const Duration(milliseconds: 12500));
    report.pass('M12.1');
  });

  test('M12.2 ticks with tools on and no loop do not notify', () async {
    final rig = await _rig();
    final before = rig.notifications;
    for (var i = 1; i <= 50; i += 1) {
      rig.controller.setPosition(Duration(milliseconds: i * 250));
    }
    expect(rig.notifications, before);
    expect(rig.controller.position, const Duration(milliseconds: 12500));
    rig.controller.setPosition(const Duration(seconds: -3));
    expect(rig.controller.position, Duration.zero);
    report.pass('M12.2');
  });

  test(
    'M12.3 loop transitions notify and ticks inside the loop do not',
    () async {
      final rig = await _rig();
      rig.controller.setPosition(const Duration(seconds: 10));
      var before = rig.notifications;
      await rig.controller.cycleLoop();
      expect(rig.notifications, before + 1);
      expect(rig.controller.loopStage, AdvancedLoopStage.aSet);

      rig.controller.setPosition(const Duration(seconds: 20));
      before = rig.notifications;
      await rig.controller.cycleLoop();
      expect(rig.notifications, before + 1);
      expect(rig.controller.loopStage, AdvancedLoopStage.active);
      expect(rig.player.properties['ab-loop-a'], '10.000');
      expect(rig.player.properties['ab-loop-b'], '20.000');

      before = rig.notifications;
      for (final seconds in [12, 15, 19, 20, 10, 11]) {
        rig.controller.setPosition(Duration(seconds: seconds));
      }
      expect(rig.notifications, before);
      expect(rig.controller.a, const Duration(seconds: 10));
      expect(rig.controller.b, const Duration(seconds: 20));
      expect(rig.controller.loopStage, AdvancedLoopStage.active);
      expect(rig.player.properties['ab-loop-a'], '10.000');
      expect(rig.player.properties['ab-loop-b'], '20.000');

      before = rig.notifications;
      await rig.controller.cycleLoop();
      expect(rig.notifications, before + 1);
      expect(rig.controller.loopStage, AdvancedLoopStage.clear);
      expect(rig.player.properties['ab-loop-a'], 'no');
      report.pass('M12.3');
    },
  );

  test('M12.4 duration and source changes notify and refilter', () async {
    final rig = await _rig();
    rig.settings.addPlaybackMarker(
      _sourceA,
      const PlaybackMarker(id: 'early', positionMs: 1000, label: 'Early'),
    );
    rig.settings.addPlaybackMarker(
      _sourceA,
      const PlaybackMarker(id: 'late', positionMs: 300000, label: 'Late'),
    );

    var before = rig.notifications;
    rig.controller.setDuration(const Duration(minutes: 2));
    expect(rig.notifications, before + 1);
    expect(rig.controller.markers.map((m) => m.id), ['early']);

    before = rig.notifications;
    rig.controller.setDuration(const Duration(minutes: 10));
    expect(rig.notifications, before + 1);
    expect(rig.controller.markers.map((m) => m.id), ['early', 'late']);

    before = rig.notifications;
    await rig.controller.setSource(PlayableSource.file(_sourceB));
    expect(rig.notifications, greaterThan(before));
    report.pass('M12.4');
  });

  test('M12.5 repeated marker reads decode once', () async {
    final rig = await _rig();
    rig.settings.addPlaybackMarker(
      _sourceA,
      const PlaybackMarker(id: 'one', positionMs: 1000, label: 'One'),
    );
    rig.controller.setDuration(const Duration(minutes: 10));
    final baseline = rig.settings.markerLookups;
    final first = rig.controller.markers;
    expect(rig.settings.markerLookups, baseline + 1);
    expect(first, hasLength(1));
    for (var i = 1; i <= 100; i += 1) {
      rig.controller.setPosition(Duration(milliseconds: i * 250));
      expect(identical(rig.controller.markers, first), isTrue);
    }
    expect(rig.settings.markerLookups, baseline + 1);
    report.pass('M12.5');
  });

  test('M12.6 add, rename and delete invalidate the cache', () async {
    final rig = await _rig();
    rig.controller.setDuration(const Duration(minutes: 10));
    rig.controller.setPosition(const Duration(seconds: 30));
    expect(rig.controller.markers, isEmpty);

    final marker = rig.controller.addMarker(label: 'First');
    expect(marker, isNotNull);
    expect(rig.controller.markers.map((m) => m.label), ['First']);

    rig.controller.renameMarker(marker!.id, 'Renamed');
    expect(rig.controller.markers.map((m) => m.label), ['Renamed']);

    rig.controller.deleteMarker(marker.id);
    expect(rig.controller.markers, isEmpty);

    final lookups = rig.settings.markerLookups;
    rig.controller.markers;
    rig.controller.markers;
    expect(rig.settings.markerLookups, lookups);
    report.pass('M12.6');
  });

  test('M12.7 external writes and reset invalidate the cache', () async {
    final rig = await _rig();
    rig.controller.setDuration(const Duration(minutes: 10));
    expect(rig.controller.markers, isEmpty);

    rig.settings.addPlaybackMarker(
      _sourceA,
      const PlaybackMarker(id: 'ext', positionMs: 2000, label: 'External'),
    );
    expect(rig.controller.markers.map((m) => m.id), ['ext']);

    await rig.settings.resetAll();
    expect(rig.controller.markers, isEmpty);
    report.pass('M12.7');
  });

  test('M12.8 source switch uses the matching markers', () async {
    final rig = await _rig();
    rig.controller.setDuration(const Duration(minutes: 10));
    rig.settings.addPlaybackMarker(
      _sourceA,
      const PlaybackMarker(id: 'a1', positionMs: 1000, label: 'A one'),
    );
    rig.settings.addPlaybackMarker(
      _sourceB,
      const PlaybackMarker(id: 'b1', positionMs: 2000, label: 'B one'),
    );
    expect(rig.controller.markers.map((m) => m.id), ['a1']);

    await rig.controller.setSource(PlayableSource.file(_sourceB));
    rig.controller.setDuration(const Duration(minutes: 10));
    expect(rig.controller.markers.map((m) => m.id), ['b1']);

    rig.settings.addPlaybackMarker(
      _sourceA,
      const PlaybackMarker(id: 'a2', positionMs: 3000, label: 'A two'),
    );
    await rig.controller.setSource(PlayableSource.file(_sourceA));
    rig.controller.setDuration(const Duration(minutes: 10));
    expect(rig.controller.markers.map((m) => m.id), ['a1', 'a2']);

    await rig.controller.setSource(null);
    expect(rig.controller.markers, isEmpty);
    report.pass('M12.8');
  });
}
