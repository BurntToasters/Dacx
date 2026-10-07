import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
import 'package:dacx/services/path_probe.dart';
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
  static FilePickerPlatform? _previousFilePicker;

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
    PathProbe.runInline = true;
    _fullscreen = false;
    fullscreenCalls.clear();
    _windowSize = const Size(1200, 800);
    _windowPosition = Offset.zero;
    windowManagerCalls.clear();
    windowMethodsCalls.clear();
    filePickerPaths = null;
    filePickerSavePath = null;
    _previousFilePicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _HarnessFilePicker();
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
    PathProbe.runInline = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowManagerChannel, null);
    messenger.setMockMethodCallHandler(mediaSessionChannel, null);
    messenger.setMockMethodCallHandler(windowMethodsChannel, null);
    messenger.setMockMethodCallHandler(openFileMethodsChannel, null);
    messenger.setMockMethodCallHandler(filePickerChannel, null);
    messenger.setMockMethodCallHandler(bookmarkChannel, null);
    final previous = _previousFilePicker;
    if (previous != null) {
      FilePickerPlatform.instance = previous;
      _previousFilePicker = null;
    }
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

base class _HarnessPlatformFile extends PlatformFile {
  _HarnessPlatformFile(this._path)
    : name = _path
          .split(RegExp(r'[/\\]'))
          .where((part) => part.isNotEmpty)
          .last,
      uri = _uriForPath(_path);

  final String _path;

  static Uri _uriForPath(String path) {
    final windows = path.contains(r'\') || RegExp(r'^[a-zA-Z]:').hasMatch(path);
    return Uri.file(path, windows: windows);
  }

  @override
  String? get path => _path;

  @override
  final String name;

  @override
  final Uri uri;

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => 0;

  @override
  Future<int> length() async => 0;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() => const Stream.empty();
}

final class _HarnessFilePicker extends FilePickerPlatform {
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final paths = PlayerScreenHarness.filePickerPaths;
    if (paths == null || paths.isEmpty) return null;
    return _HarnessPlatformFile(paths.first);
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final paths = PlayerScreenHarness.filePickerPaths;
    if (paths == null || paths.isEmpty) return const [];
    return [for (final path in paths) _HarnessPlatformFile(path)];
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return null;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final path = PlayerScreenHarness.filePickerSavePath;
    if (path == null || path.isEmpty) return null;
    File(path).writeAsBytesSync(bytes);
    final windows = path.contains(r'\') || RegExp(r'^[a-zA-Z]:').hasMatch(path);
    return Uri.file(path, windows: windows);
  }
}
