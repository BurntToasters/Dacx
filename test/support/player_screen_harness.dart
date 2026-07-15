import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
import 'package:dacx/services/media_session_service.dart';
import 'package:dacx/services/player_service.dart';
import 'package:dacx/services/settings_service.dart';
import 'package:dacx/services/update_service.dart';
import 'package:dacx/theme/window_visuals.dart';

/// Shared harness for [PlayerScreen] widget tests.
abstract final class PlayerScreenHarness {
  static const windowManagerChannel = MethodChannel('window_manager');
  static bool _fullscreen = false;
  static final List<bool> fullscreenCalls = <bool>[];
  static Size _windowSize = const Size(1200, 800);
  static Offset _windowPosition = Offset.zero;
  static final List<MethodCall> windowManagerCalls = <MethodCall>[];
  static final List<MethodCall> windowMethodsCalls = <MethodCall>[];

  /// Force the mocked window-manager fullscreen flag (without going through F).
  @visibleForTesting
  static void setFullscreenForTesting(bool value) {
    _fullscreen = value;
  }

  static const mediaSessionChannel = MethodChannel(
    'run.rosie.dacx/media_session',
  );
  static const windowMethodsChannel = MethodChannel(
    'run.rosie.dacx/window/methods',
  );
  static const openFileMethodsChannel = MethodChannel(
    OpenFileBridge.methodChannelName,
  );
  static const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  static const bookmarkChannel = MethodChannel('run.rosie.dacx/bookmarks');

  /// When non-null, [FilePicker.pickFile] returns the first path. Empty list = cancel.
  static List<String>? filePickerPaths;

  /// When non-null, [FilePicker.saveFile] returns this path.
  static String? filePickerSavePath;

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
    _windowSize = const Size(1200, 800);
    _windowPosition = Offset.zero;
    windowManagerCalls.clear();
    windowMethodsCalls.clear();
    filePickerPaths = null;
    filePickerSavePath = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
      windowManagerCalls.add(call);
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
        case 'getBounds':
          return {
            'x': _windowPosition.dx,
            'y': _windowPosition.dy,
            'width': _windowSize.width,
            'height': _windowSize.height,
          };
        case 'setBounds':
          final args = call.arguments as Map<Object?, Object?>;
          final width = args['width'];
          final height = args['height'];
          final x = args['x'];
          final y = args['y'];
          if (width is num && height is num) {
            _windowSize = Size(width.toDouble(), height.toDouble());
          }
          if (x is num && y is num) {
            _windowPosition = Offset(x.toDouble(), y.toDouble());
          }
          return null;
        case 'setAlwaysOnTop':
          return null;
        case 'getTitleBarHeight':
          return 0;
        case 'waitUntilReadyToShow':
        case 'setTitleBarStyle':
        case 'setPreventClose':
        case 'setAsFrameless':
        case 'setBackgroundColor':
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
    messenger.setMockMethodCallHandler(windowMethodsChannel, (call) async {
      windowMethodsCalls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(openFileMethodsChannel, (call) async {
      if (call.method == 'getPendingFiles') return <dynamic>[];
      return null;
    });
    messenger.setMockMethodCallHandler(filePickerChannel, (call) async {
      switch (call.method) {
        case 'any':
        case 'audio':
        case 'image':
        case 'video':
        case 'media':
        case 'custom':
          final paths = filePickerPaths;
          if (paths == null || paths.isEmpty) return null;
          return paths
              .map(
                (path) => {
                  'path': path,
                  'name': path.split('/').last,
                  'size': 0,
                  'bytes': null,
                },
              )
              .toList(growable: false);
        case 'dir':
          return null;
        case 'save':
          final path = filePickerSavePath;
          if (path == null || path.isEmpty) return null;
          final args = call.arguments;
          if (args is Map) {
            final raw = args['bytes'];
            if (raw is Uint8List) {
              File(path).writeAsBytesSync(raw);
            } else if (raw is List) {
              File(path).writeAsBytesSync(List<int>.from(raw));
            }
          }
          return path;
        case 'pickFiles':
          final paths = filePickerPaths;
          if (paths == null || paths.isEmpty) return null;
          return paths;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(bookmarkChannel, (call) async => null);
  }

  static void uninstallChannelMocks() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    messenger.setMockMethodCallHandler(mediaSessionChannel, null);
    messenger.setMockMethodCallHandler(windowMethodsChannel, null);
    messenger.setMockMethodCallHandler(openFileMethodsChannel, null);
    messenger.setMockMethodCallHandler(filePickerChannel, null);
    messenger.setMockMethodCallHandler(bookmarkChannel, null);
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
    List<String>? initialDropPaths,
    PlayableSource? initialPendingLoad,
    ValueNotifier<String?>? osdMessageProbe,
    Completer<void>? screenshotOperationForTesting,
    StreamController<MediaSessionCommand>? mediaSessionCommandsForTesting,
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
        initialDropPaths: initialDropPaths,
        initialPendingLoad: initialPendingLoad,
        osdMessageProbe: osdMessageProbe,
        screenshotOperationForTesting: screenshotOperationForTesting,
        mediaSessionCommandsForTesting: mediaSessionCommandsForTesting,
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
