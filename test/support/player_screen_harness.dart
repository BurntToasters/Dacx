import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dacx/l10n/app_localizations.dart';
import 'package:dacx/models/chapter_info.dart';
import 'package:dacx/models/playable_source.dart';
import 'package:dacx/screens/player_screen.dart';
import 'package:dacx/services/debug_log_service.dart';
import 'package:dacx/services/open_file_bridge.dart';
import 'package:dacx/services/headless_player_service.dart';
import 'package:dacx/services/player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/theme/window_visuals.dart';

/// Shared harness for [PlayerScreen] widget tests.
abstract final class PlayerScreenHarness {
  static const windowManagerChannel = MethodChannel('window_manager');
  static bool _fullscreen = false;
  static final List<bool> fullscreenCalls = <bool>[];

  static const mediaSessionChannel = MethodChannel(
    'run.rosie.dacx/media_session',
  );
  static const windowMethodsChannel = MethodChannel(
    'run.rosie.dacx/window/methods',
  );
  static const openFileMethodsChannel = MethodChannel(
    OpenFileBridge.methodChannelName,
  );

  static Future<
    ({
      SettingsService settings,
      DebugLogService debugLog,
      UpdateService updates,
    })
  >
  createServices({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    final settings = SettingsService(shared);
    final debugLog = DebugLogService(isEnabled: () => false);
    final updates = UpdateService(
      debugLog: debugLog,
      debugSource: 'player_screen_test',
      httpGet: (_, {headers}) async => throw Exception('offline'),
    );
    return (settings: settings, debugLog: debugLog, updates: updates);
  }

  static void installChannelMocks() {
    _fullscreen = false;
    fullscreenCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
      switch (call.method) {
        case 'isMaximized':
          return false;
        case 'isFullScreen':
          return _fullscreen;
        case 'setFullScreen':
          final args = call.arguments;
          final enabled = args is bool
              ? args
              : (args as Map<Object?, Object?>)['isFullScreen'] as bool? ??
                    false;
          _fullscreen = enabled;
          fullscreenCalls.add(enabled);
          return null;
        case 'getTitleBarHeight':
          return 0;
        case 'waitUntilReadyToShow':
        case 'setTitleBarStyle':
        case 'setPreventClose':
        case 'setAsFrameless':
        case 'setBackgroundColor':
        case 'setAlwaysOnTop':
        case 'show':
        case 'focus':
        case 'startDragging':
        case 'minimize':
        case 'maximize':
        case 'unmaximize':
        case 'close':
          return null;
        default:
          return null;
      }
    });

    messenger.setMockMethodCallHandler(
      mediaSessionChannel,
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      windowMethodsChannel,
      (call) async => true,
    );
    messenger.setMockMethodCallHandler(openFileMethodsChannel, (call) async {
      if (call.method == 'getPendingFiles') return <dynamic>[];
      return null;
    });
  }

  static void uninstallChannelMocks() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    messenger.setMockMethodCallHandler(mediaSessionChannel, null);
    messenger.setMockMethodCallHandler(windowMethodsChannel, null);
    messenger.setMockMethodCallHandler(openFileMethodsChannel, null);
  }

  static Widget wrap({
    required SettingsService settings,
    required DebugLogService debugLog,
    required UpdateService updates,
    IPlayerService? playerService,
    bool headlessMediaSurface = false,
    PlayableSource? initialLoadedSource,
    List<PlayableSource>? initialPlaylistSources,
    List<ChapterInfo>? initialChapters,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blueGrey);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        extensions: [
          WindowVisuals.fromScheme(scheme, blurEnabled: false, blurStrength: 0),
        ],
      ),
      home: PlayerScreen(
        settings: settings,
        debugLog: debugLog,
        updateService: updates,
        playerService: playerService ?? HeadlessPlayerService(),
        headlessMediaSurface: headlessMediaSurface || playerService != null,
        initialLoadedSource: initialLoadedSource,
        initialPlaylistSources: initialPlaylistSources,
        initialChapters: initialChapters,
      ),
    );
  }

  static void configureDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
}
