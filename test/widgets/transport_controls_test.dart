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
  });
}
