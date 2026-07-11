import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/widgets/transport_controls.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
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

    testWidgets('folder button appears when callback is provided', (
      tester,
    ) async {
      var folderPressed = false;
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
            onOpenFolder: () => folderPressed = true,
            onReopenLast: () {},
            onVolumeChanged: (_) {},
            onLoopModeChanged: (_) {},
            onRecentFileSelected: (_) {},
            onSettingsPressed: () {},
          ),
        ),
      );

      final button = find.byKey(const Key('open-folder-transport-button'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      expect(folderPressed, isTrue);
    });

    testWidgets('url button is hidden unless callback is provided', (
      tester,
    ) async {
      Widget build({VoidCallback? onOpenUrl}) {
        return _wrap(
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
            onOpenUrl: onOpenUrl,
            onReopenLast: () {},
            onVolumeChanged: (_) {},
            onLoopModeChanged: (_) {},
            onRecentFileSelected: (_) {},
            onSettingsPressed: () {},
          ),
        );
      }

      await tester.pumpWidget(build());
      expect(find.byKey(const Key('open-url-transport-button')), findsNothing);

      await tester.pumpWidget(build(onOpenUrl: () {}));
      expect(
        find.byKey(const Key('open-url-transport-button')),
        findsOneWidget,
      );
    });

    testWidgets('more menu is enabled without media', (tester) async {
      var morePressed = false;
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            onMoreActions: () => morePressed = true,
          ),
        ),
      );

      final moreIcon = find.byIcon(Icons.more_vert);
      expect(moreIcon, findsOneWidget);
      final button = tester.widget<IconButton>(
        find.ancestor(of: moreIcon, matching: find.byType(IconButton)).first,
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(moreIcon);
      expect(morePressed, isTrue);
    });

    testWidgets('speed chip cycles when tapped', (tester) async {
      var cycles = 0;
      await tester.pumpWidget(
        _wrap(
          TransportControls(
            isPlaying: false,
            volume: 50,
            hasMedia: true,
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
            onCycleSpeed: () => cycles++,
          ),
        ),
      );

      final chip = find.byKey(const Key('transport-speed-chip'));
      expect(chip, findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      await tester.tap(chip);
      expect(cycles, 1);
    });
  });
}
