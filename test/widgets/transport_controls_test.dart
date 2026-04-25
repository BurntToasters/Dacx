import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/services/settings_service.dart';
import 'package:dacx/widgets/transport_controls.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('TransportControls', () {
    testWidgets('reopen button is visible and enabled', (tester) async {
      var reopenPressed = false;

      await tester.pumpWidget(
        _wrap(
          TransportControls(
            isPlaying: false,
            volume: 50,
            hasMedia: false,
            speed: 1.0,
            loopMode: LoopMode.none,
            recentFiles: const [],
            onPlayPause: () {},
            onStop: () {},
            onOpenFile: () {},
            onReopenLast: () => reopenPressed = true,
            onVolumeChanged: (_) {},
            onLoopModeChanged: (_) {},
            onRecentFileSelected: (_) {},
            onSettingsPressed: () {},
          ),
        ),
      );

      final buttonFinder = find.byKey(
        const Key('reopen-last-transport-button'),
      );
      expect(buttonFinder, findsOneWidget);

      final button = tester.widget<IconButton>(buttonFinder);
      expect(button.onPressed, isNotNull);

      await tester.tap(buttonFinder);
      expect(reopenPressed, isTrue);
    });

    testWidgets('recent dropdown hidden when there are no recent files', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TransportControls(
            isPlaying: false,
            volume: 50,
            hasMedia: false,
            speed: 1.0,
            loopMode: LoopMode.none,
            recentFiles: const [],
            onPlayPause: () {},
            onStop: () {},
            onOpenFile: () {},
            onReopenLast: () {},
            onVolumeChanged: (_) {},
            onLoopModeChanged: (_) {},
            onRecentFileSelected: (_) {},
            onSettingsPressed: () {},
          ),
        ),
      );

      expect(find.byTooltip('Recent files'), findsNothing);
    });

    testWidgets(
      'recent dropdown appears when at least one recent file exists',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            TransportControls(
              isPlaying: false,
              volume: 50,
              hasMedia: false,
              speed: 1.0,
              loopMode: LoopMode.none,
              recentFiles: const ['/tmp/song.mp3'],
              onPlayPause: () {},
              onStop: () {},
              onOpenFile: () {},
              onReopenLast: () {},
              onVolumeChanged: (_) {},
              onLoopModeChanged: (_) {},
              onRecentFileSelected: (_) {},
              onSettingsPressed: () {},
            ),
          ),
        );

        expect(find.byTooltip('Recent files'), findsOneWidget);
      },
    );
  });
}
