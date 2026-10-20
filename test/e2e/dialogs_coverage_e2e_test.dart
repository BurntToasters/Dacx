import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/chapter_info.dart';
import 'package:dacx/widgets/equalizer_dialog.dart';
import 'package:dacx/widgets/track_pickers.dart';

import '../support/player_screen_harness.dart';

Widget _host(void Function(BuildContext context) onOpen) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => onOpen(context),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('equalizer dialog', () {
    testWidgets('enable, preset, slider, reset all apply and persist', (
      tester,
    ) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      final settings = services.settings;
      var applies = 0;
      await tester.pumpWidget(
        _host(
          (context) => showEqualizerDialog(
            context: context,
            settings: settings,
            onApply: () async => applies++,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(settings.eqEnabled, isTrue);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.eqPresetBassBoost).last);
      await tester.pumpAndSettle();
      expect(settings.eqPreset, 'bass_boost');
      expect(settings.eqBands.first, 6);

      await tester.drag(find.byType(Slider).at(5), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(settings.eqPreset, 'custom');
      expect(settings.eqBands[5], isNot(0));

      await tester.tap(find.text(l10n.actionReset));
      await tester.pumpAndSettle();
      expect(settings.eqPreset, 'flat');
      expect(settings.eqBands.every((g) => g == 0), isTrue);
      expect(applies, greaterThanOrEqualTo(4));

      await tester.tap(find.text(l10n.actionClose));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('dialog opens when a custom curve is already saved', (
      tester,
    ) async {
      PlayerScreenHarness.configureDesktopViewport(tester);
      final services = await PlayerScreenHarness.createServices();
      addTearDown(services.settings.dispose);
      services.settings.eqPreset = 'custom';
      services.settings.eqBands = [3, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      await tester.pumpWidget(
        _host(
          (context) => showEqualizerDialog(
            context: context,
            settings: services.settings,
            onApply: () async {},
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('track pickers', () {
    testWidgets('audio picker marks current track and returns the choice', (
      tester,
    ) async {
      AudioTrack? picked;
      await tester.pumpWidget(
        _host((context) async {
          picked = await pickAudioTrack(
            context,
            tracks: const [
              AudioTrack('1', 'Commentary', 'en'),
              AudioTrack('2', 'Main', 'ja'),
            ],
            currentId: '2',
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.tap(find.textContaining('Commentary'));
      await tester.pumpAndSettle();
      expect(picked?.id, '1');
    });

    testWidgets('subtitle picker labels the off entry and returns it', (
      tester,
    ) async {
      SubtitleTrack? picked;
      await tester.pumpWidget(
        _host((context) async {
          picked = await pickSubtitleTrack(
            context,
            tracks: [
              SubtitleTrack.no(),
              const SubtitleTrack('3', 'Signs', 'en'),
            ],
            currentId: '3',
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SimpleDialog)),
      );
      await tester.tap(find.text(l10n.subtitleTrackOff));
      await tester.pumpAndSettle();
      expect(picked?.id, 'no');
    });

    testWidgets('chapter picker returns the chapter index', (tester) async {
      int? picked;
      await tester.pumpWidget(
        _host((context) async {
          picked = await pickChapter(context, const [
            ChapterInfo(index: 0, title: 'Intro', time: Duration.zero),
            ChapterInfo(
              index: 1,
              title: 'Act One',
              time: Duration(minutes: 3, seconds: 5),
            ),
          ]);
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('03:05'), findsOneWidget);
      await tester.tap(find.text('Act One'));
      await tester.pumpAndSettle();
      expect(picked, 1);
    });
  });
}
