import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/player_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);

  await windowManager.ensureInitialized();

  // Restore saved window geometry or use defaults.
  final savedSize = settings.rememberWindow ? settings.windowSize : null;
  final savedPos = settings.rememberWindow ? settings.windowPosition : null;

  final windowOptions = WindowOptions(
    size: savedSize ?? const Size(960, 600),
    minimumSize: const Size(480, 320),
    center: savedPos == null,
    title: 'DACX',
    titleBarStyle: Platform.isWindows || Platform.isMacOS
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (savedPos != null) {
      await windowManager.setPosition(savedPos);
    }
    await windowManager.setAlwaysOnTop(settings.alwaysOnTop);
    await windowManager.show();
    await windowManager.focus();
  });

  // Collect CLI file argument (first non-flag arg).
  final cliFile = Platform.resolvedExecutable.isNotEmpty
      ? _parseCliFilePath()
      : null;

  runApp(DACXApp(settings: settings, initialFile: cliFile));
}

/// Extracts the first CLI argument that looks like a file path.
String? _parseCliFilePath() {
  final args = Platform.executableArguments.isEmpty
      ? <String>[]
      : Platform.executableArguments;
  // In release mode, args are often empty — use the raw arguments from env.
  final raw = args.isEmpty
      ? _rawArgs()
      : args;
  for (final arg in raw) {
    if (!arg.startsWith('-') && File(arg).existsSync()) return arg;
  }
  return null;
}

List<String> _rawArgs() {
  // Platform.executableArguments may omit user args in AOT builds.
  // Dart passes user args after a '--' sentinel or as positional args.
  // We fall back to the command-line string parsing on Windows.
  try {
    // ignore: unnecessary_null_comparison
    if (Platform.executable != null) {
      return Platform.executableArguments;
    }
  } catch (_) {}
  return [];
}

class DACXApp extends StatefulWidget {
  final SettingsService settings;
  final String? initialFile;

  const DACXApp({super.key, required this.settings, this.initialFile});

  @override
  State<DACXApp> createState() => _DACXAppState();
}

class _DACXAppState extends State<DACXApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => setState(() {});

  // ── WindowListener ───────────────────────────────────────

  @override
  void onWindowResized() => _saveGeometry();

  @override
  void onWindowMoved() => _saveGeometry();

  Future<void> _saveGeometry() async {
    if (!widget.settings.rememberWindow) return;
    final size = await windowManager.getSize();
    final pos = await windowManager.getPosition();
    widget.settings.saveWindowSize(size);
    widget.settings.saveWindowPosition(pos);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final seed = s.accentColor.color;

    return MaterialApp(
      title: 'DACX',
      debugShowCheckedModeBanner: false,
      themeMode: s.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: PlayerScreen(
        settings: s,
        initialFile: widget.initialFile,
      ),
    );
  }
}
